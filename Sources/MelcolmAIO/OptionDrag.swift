import AppKit
import SwiftUI
import ScreenCaptureKit

@_silgen_name("CGSMoveWindow") private func CGSMoveWindow(_ cid: Int32, _ wid: UInt32, _ p: UnsafePointer<CGPoint>) -> Int32
@_silgen_name("_CGSDefaultConnection") private func dragConn() -> Int32

/// Hold a modifier (Option by default) and drag any window from anywhere on it, not just its title bar.
/// Drop it on the bar and it becomes its own full-screen Space on that display.
final class OptionDrag: ObservableObject {
    static let shared = OptionDrag()
    @Published var overBar: CGDirectDisplayID?      // the island the window is over (glows)
    private var active = false
    private var badgeOn = false
    private var badgeID: UInt32 = 0
    private var cid: Int32 = 0

    /// Islands' frames (AppKit coords) and their display UUIDs, refreshed by AppDelegate.
    var islands: () -> [(frame: NSRect, screen: CGDirectDisplayID, uuid: String?, model: SpacesModel)] = { [] }
    /// Snapshot of `islands()` taken on the main thread, so the drag thread never waits on it.
    private var cached: [(frame: NSRect, screen: CGDirectDisplayID, uuid: String?, model: SpacesModel)] = []
    private var mainH: CGFloat = 0

    private var tap: CFMachPort?
    private var pid: pid_t = 0
    private var wid: CGWindowID = 0
    private var win: AXUIElement?
    private var startMouse = CGPoint.zero
    private var startPos = CGPoint.zero

    var modifier: CGEventFlags {
        switch Prefs.d.string(forKey: "dragModifier") ?? "option" {
        case "shift": .maskShift
        case "control": .maskControl
        case "command": .maskCommand
        default: .maskAlternate
        }
    }

    func start() {
        guard tap == nil, AXIsProcessTrusted() else {
            // Accessibility can be granted later; try again shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.start() }
            return
        }
        // Everything below runs on its own thread: the mouse never waits for the rest of the app.
        _ = badge; badgeID = UInt32(badge.windowNumber); cid = dragConn()
        let snap = { [weak self] in guard let self else { return }; let c = islands(); let h = NSScreen.screens.first?.frame.height ?? 0
            let sl = Self.barSlots(c, mainH: h)
            let scr = NSScreen.screens.map { (cg: CGRect(x: $0.frame.minX, y: h - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height),
                                              vis: CGRect(x: $0.visibleFrame.minX, y: h - $0.visibleFrame.maxY, width: $0.visibleFrame.width, height: $0.visibleFrame.height),
                                              uuid: SpacesModel.uuid(of: $0), id: Island.id(of: $0)) }
            let z = DragZone.all.map { (Prefs.d.string(forKey: "zone.\($0.rawValue)") ?? $0.defaultLayout) }
            let fs = Self.fullScreenDisplays(c)
            lock.lock(); cached = c; mainH = h; slots = sl; screens = scr; zoneLayouts = z; zonesOn = Prefs.bool("dragZones"); fullScreens = fs; lock.unlock() }
        snap(); Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in snap() }
        let mask = (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask), callback: { _, type, e, ctx in
            let s = Unmanaged<OptionDrag>.fromOpaque(ctx!).takeUnretainedValue()
            return s.handle(type, e)
        }, userInfo: me)
        guard let tap else { return }
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        let t = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        t.qualityOfService = .userInteractive; t.name = "melcolm.optiondrag.tap"; t.start()
    }

    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        switch type {
        case .flagsChanged, .mouseMoved:
            showBadge(Prefs.bool("optionDrag") && e.flags.contains(modifier) && !inFullScreen(at: e.location), at: e.location)
            return Unmanaged.passUnretained(e)
        case .leftMouseDown:
            guard Prefs.bool("optionDrag"), e.flags.contains(modifier), !inFullScreen(at: e.location), grab(at: e.location) else { break }
            active = true
            return nil
        case .leftMouseDragged where active:
            let p = e.location
            showBadge(true, at: p)
            // A see-through copy of the window rides the pointer (moved by the window server, instant);
            // the real window jumps there once, when you let go.
            var o = CGPoint(x: startPos.x + p.x - startMouse.x, y: startPos.y + p.y - startMouse.y)
            lastOrigin = o
            lock.lock(); let g = ghostID; lock.unlock()
            if g != 0 { var go = CGPoint(x: o.x - 30, y: o.y - 30); _ = CGSMoveWindow(cid, g, &go) }   // until the copy appears, the window stays put (no jump)
            let hit = island(at: p)?.screen
            let z = hit == nil ? zoneRect(at: p) : nil
            if z != lastZone { lastZone = z; DispatchQueue.main.async { self.showZone(z); self.dots.active = z?.zone ?? ""; self.dots.screen = z?.display ?? 0 } }
            if hit != lastHit { lastHit = hit; DispatchQueue.main.async { self.overBar = hit; self.ghostModel?.overBar = hit != nil } }
            return nil
        case .leftMouseUp where active:
            active = false
            showBadge(e.flags.contains(modifier), at: e.location)
            let target = island(at: e.location)
            lastHit = nil; DispatchQueue.main.async { self.overBar = nil }
            let zone = lastZone; lastZone = nil
            DispatchQueue.main.async { self.showZone(nil) }
            // Into the bar, or onto the top-middle "New Space" spot: always the LAST Space on that display.
            // (Inserting between apps would make macOS re-enter every app after it, one by one.)
            let newSpace: (uuid: String, display: CGDirectDisplayID)? =
                target.flatMap { t in t.uuid.map { ($0, t.screen) } } ?? zone?.space.map { ($0, zone!.display) }
            if let ns = newSpace, let win {
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "App"
                let (p, w) = (pid, wid)
                DispatchQueue.main.async { [mover] in
                    self.fadeGhost(.intoBar, after: 0.38)
                    self.onDropToBar(ns.display, name)
                    mover.async {
                        SpaceMover.move(pid: p, wid: w, display: ns.uuid, index: 999)
                        DispatchQueue.main.async { for i in self.islands() { i.model.refresh() } }
                    }
                }
            } else if target == nil, win != nil, zone?.id == "hide" {
                // Hide the app, exactly like Cmd-H.
                let p = pid
                DispatchQueue.main.async {
                    self.fadeGhost(.settle, after: 0)
                    NSRunningApplication(processIdentifier: p)?.hide()
                }
            } else if target == nil, let win, let snap = zone {
                let zone = snap.rect
                // Snapped to a zone: the copy glides into the spot while the window takes it.
                mover.async {
                    var o = zone.origin, sz = zone.size
                    if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
                    if let v = AXValueCreate(.cgSize, &sz) { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v) }
                    if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
                }
                DispatchQueue.main.async { self.flyGhost(to: zone) }
            } else if target == nil, win != nil {
                pending = lastOrigin; pump()
                // The real window is there now: the copy melts away.
                DispatchQueue.main.async { self.fadeGhost(.settle, after: 0.22) }
            } else { DispatchQueue.main.async { self.hideGhost() } }
            win = nil
            return nil
        default: break
        }
        return Unmanaged.passUnretained(e)
    }

    // MARK: fast window moves

    private let mover = DispatchQueue(label: "melcolm.optiondrag", qos: .userInteractive)
    private let lock = NSLock()
    private var _pending: CGPoint?
    private var pending: CGPoint? { get { lock.lock(); defer { lock.unlock() }; return _pending } set { lock.lock(); _pending = newValue; lock.unlock() } }
    private var pumping = false
    private var lastHit: CGDirectDisplayID?
    private var lastZone: Snap?
    struct Snap: Equatable { let rect: CGRect; let title: String; let id: String; var zone = ""; var space: String? = nil; var display: CGDirectDisplayID = 0 }
    private var slots: [CGDirectDisplayID: [(uuid: String, box: CGRect, cells: [CGFloat])]] = [:]
    private var screens: [(cg: CGRect, vis: CGRect, uuid: String?, id: CGDirectDisplayID)] = []
    private var zoneLayouts: [String] = []
    private var zonesOn = true
    /// Displays whose current Space is a full-screen app. MASTER RULE: no snap spots there.
    private var fullScreens = Set<String>()
    private var anyFullScreen = false

    /// UUIDs of the displays showing a full-screen app right now ("*" = every display, when
    /// macOS shares one set of Spaces across all of them).
    static func fullScreenDisplays(_ c: [(frame: NSRect, screen: CGDirectDisplayID, uuid: String?, model: SpacesModel)]) -> Set<String> {
        var out = Set<String>()
        for g in c.first?.model.displays ?? [] where g.spaces.first(where: { $0.id == g.currentID })?.isFullscreen == true {
            out.insert(g.id.count < 10 ? "*" : g.id.uppercased())
        }
        return out
    }
    private func isFullScreen(_ uuid: String?) -> Bool {
        lock.lock(); let fs = fullScreens; lock.unlock()
        return fs.contains("*") || (uuid.map { fs.contains($0.uppercased()) } ?? false)
    }
    /// True when the pointer is on a display that's showing a full-screen app.
    private func inFullScreen(at p: CGPoint) -> Bool {
        lock.lock(); let scr = screens; lock.unlock()
        return isFullScreen(scr.first { $0.cg.contains(p) }?.uuid)
    }

    /// Where each display's box and full-screen apps sit on each bar, in top-left screen coords.
    static func barSlots(_ list: [(frame: NSRect, screen: CGDirectDisplayID, uuid: String?, model: SpacesModel)], mainH: CGFloat) -> [CGDirectDisplayID: [(uuid: String, box: CGRect, cells: [CGFloat])]] {
        let f = SpaceDragModel.shared.frames
        var out: [CGDirectDisplayID: [(uuid: String, box: CGRect, cells: [CGFloat])]] = [:]
        for i in list {
            let ox = i.frame.minX, oy = mainH - i.frame.maxY
            out[i.screen] = i.model.displays.compactMap { g in
                guard let b = f["box-\(g.id)"] else { return nil }
                let cells = g.spaces.filter(\.isFullscreen).compactMap { f["app-\($0.id)"] }.map { ox + $0.midX }
                return (g.id, b.offsetBy(dx: ox, dy: oy), cells)
            }
        }
        return out
    }

    /// The display and position on the bar under the pointer.
    private func barSpot(at p: CGPoint, island: CGDirectDisplayID) -> (uuid: String, index: Int)? {
        lock.lock(); let list = slots[island] ?? []; lock.unlock()
        guard let g = list.min(by: { abs($0.box.midX - p.x) - $0.box.width / 2 < abs($1.box.midX - p.x) - $1.box.width / 2 }) else { return nil }
        return (g.uuid, g.cells.filter { $0 < p.x }.count)
    }

    /// The screen spot a window snaps to when dropped at `p`, top-left coords. You only snap
    /// inside one of the dashed circles you can see; anywhere else the window just moves.
    private func zoneRect(at p: CGPoint) -> Snap? {
        lock.lock(); let scr = screens; let lay = zoneLayouts; let on = zonesOn; lock.unlock()
        guard on, let s = scr.first(where: { $0.cg.contains(p) }), !isFullScreen(s.uuid) else { return nil }
        let v = s.vis
        // Once inside a circle you have to move a little further out to leave it (no flicker on the rim).
        let reach = DragZone.radius + (lastZone == nil ? 0 : 18)
        let zone = DragZone.all.first { z in
            let c = z.center(in: v.size)
            return hypot(p.x - (v.minX + c.x), p.y - (v.minY + c.y)) <= reach
        }
        guard let zone else { return nil }
        // Top middle is always "New Space": the window becomes its own Space, last on this display.
        if zone == .top, let u = s.uuid {
            return Snap(rect: CGRect(x: v.midX - v.width * 0.18, y: v.minY + 12, width: v.width * 0.36, height: v.height * 0.26).integral,
                        title: "New Space", id: "space", zone: "top", space: u, display: s.id)
        }
        guard let i = DragZone.all.firstIndex(of: zone), i < lay.count else { return nil }
        // "Hide": drop here and the app hides (like Cmd-H). The box shows around the circle.
        if lay[i] == "hide" {
            let c = zone.center(in: v.size), r = DragZone.radius + 30
            return Snap(rect: CGRect(x: v.minX + c.x - r, y: v.minY + c.y - r, width: 2 * r, height: 2 * r).integral,
                        title: "Hide", id: "hide", zone: zone.rawValue, display: s.id)
        }
        guard let wl = WindowLayout.all.first(where: { $0.id == lay[i] }) else { return nil }
        return Snap(rect: CGRect(x: v.minX + v.width * wl.x, y: v.minY + v.height * wl.y, width: v.width * wl.w, height: v.height * wl.h).integral, title: wl.title, id: wl.id, zone: zone.rawValue, display: s.id)
    }

    // The glowing preview of where the window will snap.
    private var zonePanel: NSPanel?
    private let zoneModel = ZoneModel()
    private var zoneToken = 0

    // The snap dots shown on every screen while the key is held.
    let dots = DotsModel()
    private var dotPanels: [NSPanel] = []
    private var dotsToken = 0
    private func showDots(_ on: Bool) {
        dotsToken += 1; let token = dotsToken
        guard on, Prefs.bool("dragZones") else {
            // Fade out; only hide if nothing asked to show them again meanwhile (no flicker on quick taps).
            dotPanels.forEach { p in NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; p.animator().alphaValue = 0 },
                                                                         completionHandler: { [weak self] in if self?.dotsToken == token { p.orderOut(nil) } }) }
            return
        }
        dots.objectWillChange.send()
        dots.layouts = Dictionary(uniqueKeysWithValues: DragZone.all.map { ($0.rawValue, Prefs.d.string(forKey: "zone.\($0.rawValue)") ?? $0.defaultLayout) })
        let scr = NSScreen.screens
        while dotPanels.count < scr.count {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
            p.level = .floating; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            dotPanels.append(p)
        }
        for (i, sc) in scr.enumerated() {
            let p = dotPanels[i]
            let sid = Island.id(of: sc)
            if isFullScreen(SpacesModel.uuid(of: sc)) { p.orderOut(nil); continue }   // nothing to snap in a full-screen app
            if p.frame != sc.visibleFrame { p.setFrame(sc.visibleFrame, display: false) }
            // Build the dots once per screen and keep them; only fade in/out after that.
            if (p.contentView as? NSHostingView<DotsView>)?.rootView.screen != sid {
                p.contentView = NSHostingView(rootView: DotsView(m: dots, screen: sid))
            }
            if !p.isVisible { p.alphaValue = 0 }
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
        }
    }
    private func showZone(_ snap: Snap?) {
        ghostModel?.dimmed = snap != nil
        if let snap { zoneModel.title = snap.title; zoneModel.id = snap.id }
        guard let z = snap?.rect else {
            zoneToken += 1; let t = zoneToken
            if let p = zonePanel { NSAnimationContext.runAnimationGroup({ $0.duration = 0.14; p.animator().alphaValue = 0 },
                                                                      completionHandler: { [weak self] in if self?.zoneToken == t { p.orderOut(nil) } }) }
            return
        }
        let h = NSScreen.screens.first?.frame.height ?? 0
        let r = NSRect(x: z.minX, y: h - z.maxY, width: z.width, height: z.height).insetBy(dx: 6, dy: 6)
        let p = zonePanel ?? {
            let p = NSPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
            p.level = .floating; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.contentView = NSHostingView(rootView: ZoneView(m: zoneModel)); p.alphaValue = 0
            zonePanel = p; return p
        }()
        zoneToken += 1
        if !p.isVisible || p.alphaValue < 0.05 { p.setFrame(r, display: true) }
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.2; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            p.animator().setFrame(r, display: true); p.animator().alphaValue = 1
        }
    }
    private var lastOrigin = CGPoint.zero
    private var ghostID: UInt32 = 0
    private var ghost: NSPanel?
    private var ghostModel: GhostModel?
    /// Called when a window is dropped on a display's bar (AppDelegate shows the pop-up there).
    var onDropToBar: (CGDirectDisplayID, String) -> Void = { _, _ in }

    /// Snap drop: the copy glides into the spot and fades as the real window appears there.
    private func flyGhost(to z: CGRect) {
        guard let g = ghost, let m = ghostModel else { return }
        lock.lock(); ghostID = 0; lock.unlock()
        let h = NSScreen.screens.first?.frame.height ?? 0
        let r = NSRect(x: z.minX - 30, y: h - z.maxY - 30, width: z.width + 60, height: z.height + 60)
        withAnimation(.easeOut(duration: 0.15)) { m.dimmed = false }
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.2; c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            g.animator().setFrame(r, display: true)
        }, completionHandler: { [weak self] in self?.fadeGhost(.settle, after: 0.2) })
    }

    private func fadeGhost(_ how: GhostModel.End, after t: Double) {
        guard let m = ghostModel, let g = ghost else { hideGhost(); return }
        lock.lock(); ghostID = 0; lock.unlock()        // stop following the pointer
        withAnimation(how == .intoBar ? .spring(response: 0.34, dampingFraction: 0.8) : .easeOut(duration: 0.2)) { m.end = how }
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
            g.orderOut(nil)
            if self?.ghost === g { self?.ghost = nil; self?.ghostModel = nil }
        }
    }

    /// The copy of the window that follows the pointer: a picture of it when Screen Recording is allowed, else a glowing outline.
    private func makeGhost(_ r: CGRect, wid: CGWindowID, pid: pid_t) {
        hideGhost()
        guard active else { return }
        let h = NSScreen.screens.first?.frame.height ?? 0
        let p = NSPanel(contentRect: NSRect(x: r.minX - 30, y: h - r.maxY - 30, width: r.width + 60, height: r.height + 60),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.ignoresMouseEvents = true
        p.level = .floating; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let model = GhostModel(); model.icon = NSRunningApplication(processIdentifier: pid)?.icon
        model.grip = UnitPoint(x: (startMouse.x - r.minX) / max(1, r.width), y: (startMouse.y - r.minY) / max(1, r.height))
        ghostModel = model
        p.contentView = NSHostingView(rootView: GhostView(m: model))
        // Put it exactly where the pointer has already got to.
        let at = lastOrigin == .zero ? r.origin : lastOrigin
        var o = CGPoint(x: at.x - 30, y: at.y - 30)
        p.orderFrontRegardless()
        DispatchQueue.main.async { withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { model.lifted = true } }
        ghost = p
        lock.lock(); ghostID = UInt32(p.windowNumber); lock.unlock()
        _ = CGSMoveWindow(cid, UInt32(p.windowNumber), &o)
        guard CGPreflightScreenCaptureAccess() else { return }
        Task {
            guard let all = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let w = all.windows.first(where: { $0.windowID == wid }) else { return }
            let cfg = SCStreamConfiguration()
            cfg.width = Int(r.width * 2); cfg.height = Int(r.height * 2); cfg.showsCursor = false
            guard let img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg) else { return }
            await MainActor.run { withAnimation(.easeOut(duration: 0.15)) { model.image = NSImage(cgImage: img, size: r.size) } }
        }
    }

    private func hideGhost() {
        lock.lock(); ghostID = 0; lock.unlock()
        ghost?.orderOut(nil); ghost = nil; ghostModel = nil
    }

    /// One move in flight at a time, always to the latest pointer spot (skips stale ones). Never touches the main thread.
    private func pump() {
        guard let win else { return }
        lock.lock(); if pumping { lock.unlock(); return }; pumping = true; lock.unlock()
        mover.async { [weak self] in
            guard let self else { return }
            while true {
                lock.lock()
                guard var o = _pending else { pumping = false; lock.unlock(); return }
                _pending = nil; lock.unlock()
                if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
            }
        }
    }

    // MARK: the ⌥ badge beside the pointer

    private lazy var badge: NSPanel = {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 26, height: 22), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.ignoresMouseEvents = true
        p.level = .screenSaver; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: BadgeView())
        return p
    }()

    /// `p` is the pointer in top-left screen coords. Moving is done straight by the window server, so it sticks to the pointer.
    private func showBadge(_ on: Bool, at p: CGPoint) {
        if on {
            var o = CGPoint(x: p.x + 14, y: p.y + 10)
            _ = CGSMoveWindow(cid, badgeID, &o)
            if !badgeOn { badgeOn = true; DispatchQueue.main.async { self.showDots(true); self.badge.orderFrontRegardless(); var o2 = o; _ = CGSMoveWindow(self.cid, self.badgeID, &o2) } }
        } else if badgeOn { badgeOn = false; DispatchQueue.main.async { self.showDots(false); self.badge.orderOut(nil) } }
    }

    private func island(at p: CGPoint) -> (frame: NSRect, screen: CGDirectDisplayID, uuid: String?, model: SpacesModel)? {
        lock.lock(); let list = cached; let h = mainH; lock.unlock()
        let q = NSPoint(x: p.x, y: h - p.y)   // to AppKit's bottom-left coords
        return list.first { $0.frame.insetBy(dx: -8, dy: -8).contains(q) }
    }

    /// The top normal window under the pointer (CG top-left coords).
    private func grab(at p: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let wid = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? [String: Double] else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard r.contains(p) else { continue }
            guard pid != me else { return false }
            let app = AXUIElementCreateApplication(pid)
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v)
            guard let ax = (v as? [AXUIElement])?.first(where: { var n: CGWindowID = 0; _ = axWindowID($0, &n); return n == wid }),
                  !SpaceMover.isFull(ax) else { return false }
            self.pid = pid; self.wid = wid; win = ax
            startMouse = p; startPos = r.origin; lastOrigin = r.origin
            active = true
            DispatchQueue.main.async { self.makeGhost(r, wid: wid, pid: pid) }
            AXUIElementSetMessagingTimeout(ax, 0.25)
            NSRunningApplication(processIdentifier: pid)?.activate()
            AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
            return true
        }
        return false
    }
}

final class GhostModel: ObservableObject {
    enum End { case none, settle, intoBar }
    @Published var image: NSImage?
    @Published var lifted = false          // pops up off the screen when grabbed
    @Published var overBar = false         // over the bar: shrinks to a Space-sized tile
    @Published var end: End = .none
    @Published var dimmed = false          // over a snap zone: the zone preview takes over
    var icon: NSImage?
    var grip: UnitPoint = .center          // where the pointer holds it, so it shrinks into the pointer
}

struct GhostView: View {
    @ObservedObject var m: GhostModel
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: m.overBar ? 22 : 12, style: .continuous)
        let tint = m.overBar ? Color(red: 0.25, green: 0.88, blue: 1.0) : accent
        let scale: CGFloat = m.end == .intoBar ? 0.02 : m.overBar ? 0.3 : m.end == .settle ? 1.0 : m.lifted ? 1.02 : 0.97
        ZStack {
            if let img = m.image, !m.overBar { Image(nsImage: img).resizable().transition(.opacity) }
            else {
                shape.fill(tint.opacity(m.overBar ? 0.55 : 0.22))
                if let i = m.icon { Image(nsImage: i).resizable().frame(width: m.overBar ? 200 : 72, height: m.overBar ? 200 : 72) }
            }
            if m.overBar {
                VStack {
                    Spacer()
                    Label("New Space", systemImage: "plus.rectangle.on.rectangle")
                        .font(.system(size: 56, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 40).padding(.vertical, 18)
                        .background(Capsule().fill(tint))
                        .padding(.bottom, 60)
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(tint, lineWidth: m.overBar ? 8 : 2.5))
        .shadow(color: tint.opacity(m.lifted ? 0.55 : 0), radius: m.overBar ? 40 : 18)
        .scaleEffect(scale, anchor: m.grip)
        .opacity(m.end == .none ? (m.dimmed ? 0.35 : m.lifted ? 0.94 : 0.6) : 0)
        .animation(.easeOut(duration: 0.15), value: m.dimmed)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: m.overBar)
        .padding(30)   // room for the glow
    }
}

final class DotsModel: ObservableObject {
    @Published var active = ""                      // zone being hovered while dragging
    @Published var screen: CGDirectDisplayID = 0
    var layouts: [String: String] = [:]
}

/// The 8 spots drawn on the real screen while the drag key is held: each one a dashed circle
/// (the exact area that snaps), a dot and its name.
struct DotsView: View {
    @ObservedObject var m: DotsModel
    let screen: CGDirectDisplayID
    var body: some View {
        GeometryReader { g in
            ForEach(DragZone.all, id: \.self) { z in
                let isSpace = z == .top
                let lay = m.layouts[z.rawValue] ?? "none"
                if isSpace || lay != "none" {
                    let on = m.active == z.rawValue && m.screen == screen
                    let title = isSpace ? "New Space" : lay == "hide" ? "Hide" : WindowLayout.all.first { $0.id == lay }?.title ?? ""
                    let tint = isSpace ? Color(red: 0.25, green: 0.88, blue: 1.0) : accent
                    let d = DragZone.radius * 2
                    ZStack {
                        Circle().fill(tint.opacity(on ? 0.34 : 0.14))
                        Circle().strokeBorder(tint.opacity(on ? 1 : 0.75),
                                              style: StrokeStyle(lineWidth: on ? 2.5 : 1.8, lineCap: .round, dash: on ? [] : [7, 6]))
                        VStack(spacing: 7) {
                            Circle().fill(on ? tint : Color.white.opacity(0.95))
                                .frame(width: on ? 22 : 15, height: on ? 22 : 15)
                                .overlay(Circle().strokeBorder(tint, lineWidth: on ? 3 : 2))
                                .shadow(color: tint.opacity(0.9), radius: on ? 10 : 5)
                            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.72)))
                        }
                    }
                    .frame(width: d, height: d)
                    .shadow(color: tint.opacity(on ? 0.55 : 0.2), radius: on ? 16 : 8)
                    .scaleEffect(on ? 1.06 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: on)
                    .position(z.center(in: g.size))
                }
            }
        }
    }
}

final class ZoneModel: ObservableObject {
    @Published var title = ""
    @Published var id = ""
}

struct ZoneView: View {
    @ObservedObject var m: ZoneModel
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack {
            shape.fill(accent.opacity(0.18))
            shape.strokeBorder(accent, lineWidth: 3)
            if m.id == "space" {
                Label("New Space", systemImage: "plus.rectangle.on.rectangle").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .overlay(Capsule().strokeBorder(accent, lineWidth: 1.5))
            } else if m.id == "hide" {
                Label("Hide app", systemImage: "eye.slash.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .overlay(Capsule().strokeBorder(accent, lineWidth: 1.5))
            } else if let l = WindowLayout.all.first(where: { $0.id == m.id }) {
                HStack(spacing: 8) {
                    Image(nsImage: l.picture)
                    Text(l.title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .overlay(Capsule().strokeBorder(accent, lineWidth: 1.5))
            }
        }
        .shadow(color: accent.opacity(0.6), radius: 14)
        .padding(4)
    }
}

/// The eight snap spots around the screen's edge.
enum DragZone: String, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    static let all = allCases
    var title: String {
        switch self {
        case .topLeft: "Top left"; case .top: "Top middle"; case .topRight: "Top right"; case .right: "Right middle"
        case .bottomRight: "Bottom right"; case .bottom: "Bottom middle"; case .bottomLeft: "Bottom left"; case .left: "Left middle"
        }
    }
    var defaultLayout: String {
        switch self {
        case .topLeft: "tl"; case .top: "full"; case .topRight: "tr"; case .right: "right"
        case .bottomRight: "br"; case .bottom: "bottom"; case .bottomLeft: "bl"; case .left: "left"
        }
    }
    /// Size of each snap circle (points on the real screen).
    static let radius: CGFloat = 62
    /// Centre of this spot's circle on a screen of `size` (top-left origin), kept fully on screen.
    func center(in size: CGSize) -> CGPoint {
        let r = Self.radius + 10
        return CGPoint(x: r + (size.width - 2 * r) * spot.x, y: r + (size.height - 2 * r) * spot.y)
    }
    /// Where the picker sits on the settings picture (0…1).
    var spot: UnitPoint {
        switch self {
        case .topLeft: .topLeading; case .top: .top; case .topRight: .topTrailing; case .right: .trailing
        case .bottomRight: .bottomTrailing; case .bottom: .bottom; case .bottomLeft: .bottomLeading; case .left: .leading
        }
    }
}

/// Settings: a big picture of the screen. Tap a spot, see what it does, pick a layout underneath.
struct DragZonesCard: View {
    @AppStorage("dragZones") var on = true
    @AppStorage("zoneSelected") var selRaw = DragZone.topLeft.rawValue
    @AppStorage("colRev") var rev = 0
    var sel: DragZone { DragZone(rawValue: selRaw) ?? .topLeft }

    func layout(_ z: DragZone) -> String { let _ = rev; if z == .top { return "space" }; return Prefs.d.string(forKey: "zone.\(z.rawValue)") ?? z.defaultLayout }
    func set(_ z: DragZone, _ id: String) { Prefs.d.set(id, forKey: "zone.\(z.rawValue)"); rev += 1 }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "rectangle.3.group.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                        .frame(width: 30, height: 30).background(NeonBox(color: accent, radius: 8, strength: 0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Snap to the edges").font(.system(size: 13, weight: .heavy))
                        Text("Drag a window into one of the dashed circles. A blue box shows where it'll go; let go and it snaps there. Outside the circles it just moves. Only on a desktop, never inside a full-screen app.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: $on).labelsHidden()
                }
                Group {
                    screen
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Drop at").foregroundStyle(.secondary)
                            Text(sel.title).fontWeight(.heavy).foregroundStyle(accent)
                            Text("→").foregroundStyle(.secondary)
                            Text(sel == .top ? "New Space" : layout(sel) == "hide" ? "Hide the app" : WindowLayout.all.first { $0.id == layout(sel) }?.title ?? "Nothing").fontWeight(.heavy)
                            if sel == .top { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                        }.font(.system(size: 12))
                        if sel == .top {
                            Text("This spot is always New Space: the window becomes its own Space, added last on that display. It can't be changed.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        } else { LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                            chip("none", "None", nil)
                            chip("hide", "Hide", nil)
                            ForEach(WindowLayout.all) { l in chip(l.id, l.title, l) }
                        } }
                    }
                }
                .opacity(on ? 1 : 0.4).disabled(!on)
            }
        }
    }

    /// The screen: a dot on each spot, the chosen spot's result filled in.
    var screen: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let inner = CGRect(x: 0, y: 0, width: W, height: H).insetBy(dx: 10, dy: 10)
            let bar: CGFloat = 16
            let area = CGRect(x: inner.minX, y: inner.minY + bar, width: inner.width, height: inner.height - bar)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1.2))
                // The bar.
                Capsule().fill(Color.black).overlay(Capsule().strokeBorder(BarColor.outline.color, lineWidth: 1))
                    .frame(width: 110, height: 11).position(x: W / 2, y: inner.minY + 6)
                // What the chosen spot does.
                if sel == .top {
                    Label("New Space", systemImage: "plus.rectangle.on.rectangle").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color(red: 0.25, green: 0.88, blue: 1.0).opacity(0.35)))
                        .overlay(Capsule().strokeBorder(Color(red: 0.25, green: 0.88, blue: 1.0), lineWidth: 1.5))
                        .position(x: W / 2, y: area.minY + 52)
                } else if layout(sel) == "hide" {
                    Label("Hides the app (like ⌘H)", systemImage: "eye.slash.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(accent.opacity(0.35))).overlay(Capsule().strokeBorder(accent, lineWidth: 1.5))
                        .position(x: W / 2, y: area.midY)
                } else if let l = WindowLayout.all.first(where: { $0.id == layout(sel) }) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.28)).overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(accent, lineWidth: 2))
                        .frame(width: area.width * l.w - 6, height: area.height * l.h - 6)
                        .position(x: area.minX + area.width * (l.x + l.w / 2), y: area.minY + area.height * (l.y + l.h / 2))
                        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: layout(sel) + selRaw)
                } else {
                    Label("Does nothing", systemImage: "nosign").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .position(x: W / 2, y: area.midY)
                }
                ForEach(DragZone.all, id: \.self) { z in
                    let on = z == sel
                    let none = layout(z) == "none"
                    let cyan = Color(red: 0.25, green: 0.88, blue: 1.0)
                    let tint = z == .top ? cyan : accent
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selRaw = z.rawValue } } label: {
                        ZStack {
                            // The snap area: a dashed circle you drop the window into.
                            if !none || z == .top {
                                Circle().fill(tint.opacity(on ? 0.3 : 0.12))
                                Circle().strokeBorder(tint.opacity(on ? 1 : 0.7), style: StrokeStyle(lineWidth: on ? 1.6 : 1.2, lineCap: .round, dash: [3.5, 3]))
                            }
                            Circle().fill(z == .top ? cyan : on ? accent : none ? Color.white.opacity(0.12) : Color.white.opacity(0.85))
                                .frame(width: on ? 14 : 10, height: on ? 14 : 10)
                                .overlay(Circle().strokeBorder(.white.opacity(on ? 0.9 : 0.3), lineWidth: on ? 2 : 1))
                                .shadow(color: on ? accent : .clear, radius: 6)
                        }
                        .frame(width: 40, height: 40).contentShape(Circle())
                    }
                    .buttonStyle(PressStyle())
                    .help(z.title)
                    .position(x: area.minX + 22 + (area.width - 44) * z.spot.x, y: area.minY + 22 + (area.height - 44) * z.spot.y)
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    func chip(_ id: String, _ title: String, _ l: WindowLayout?) -> some View {
        let picked = layout(sel) == id
        return Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { set(sel, id) } } label: {
            VStack(spacing: 4) {
                if let l { Image(nsImage: l.picture) } else { Image(systemName: id == "hide" ? "eye.slash" : "nosign").font(.system(size: 14)).frame(height: 20) }
                Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(picked ? accent.opacity(0.3) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(picked ? accent : .white.opacity(0.1), lineWidth: picked ? 1.5 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }
}

struct BadgeView: View {
    @AppStorage("dragModifier") var modifier = "option"
    var body: some View {
        let k = ["shift": "⇧", "control": "⌃", "command": "⌘"][modifier] ?? "⌥"
        Text(k).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 24, height: 20)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Settings: Dragging page

struct DraggingSettings: View {
    @AppStorage("dragSpaces") var barDrag = true
    @AppStorage("optionDrag") var optionDrag = true
    @AppStorage("dragModifier") var modifier = "option"

    var body: some View {
        VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "macwindow.and.cursorarrow").font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                            .frame(width: 30, height: 30).background(NeonBox(color: accent, radius: 8, strength: 0.5))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hold a key and drag any window").font(.system(size: 13, weight: .heavy))
                            Text("Hold the key, press anywhere on a window and drag. It moves from anywhere, not just the top. Drop it on the bar to make it its own Space.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Toggle("", isOn: $optionDrag).labelsHidden()
                    }
                    HStack {
                        Text("Key to hold").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Picker("", selection: $modifier) {
                            Text("⌥ Option").tag("option")
                            Text("⇧ Shift").tag("shift")
                            Text("⌃ Control").tag("control")
                            Text("⌘ Command").tag("command")
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 300)
                    }.opacity(optionDrag ? 1 : 0.45).disabled(!optionDrag)
                }
            }
            DragZonesCard()
            DragSpacesCard()
        }
    }
}
