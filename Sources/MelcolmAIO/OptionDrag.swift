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
                                              vis: CGRect(x: $0.visibleFrame.minX, y: h - $0.visibleFrame.maxY, width: $0.visibleFrame.width, height: $0.visibleFrame.height)) }
            let z = DragZone.all.map { (Prefs.d.string(forKey: "zone.\($0.rawValue)") ?? $0.defaultLayout) }
            lock.lock(); cached = c; mainH = h; slots = sl; screens = scr; zoneLayouts = z; zonesOn = Prefs.bool("dragZones"); lock.unlock() }
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
            showBadge(Prefs.bool("optionDrag") && e.flags.contains(modifier), at: e.location)
            return Unmanaged.passUnretained(e)
        case .leftMouseDown:
            guard Prefs.bool("optionDrag"), e.flags.contains(modifier), grab(at: e.location) else { break }
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
            if g != 0 { var go = CGPoint(x: o.x - 30, y: o.y - 30); _ = CGSMoveWindow(cid, g, &go) } else { pending = o; pump() }
            let hit = island(at: p)?.screen
            let z = hit == nil ? zoneRect(at: p) : nil
            if z != lastZone { lastZone = z; DispatchQueue.main.async { self.showZone(z) } }
            if hit != lastHit { lastHit = hit; DispatchQueue.main.async { self.overBar = hit; self.ghostModel?.overBar = hit != nil } }
            return nil
        case .leftMouseUp where active:
            active = false
            showBadge(e.flags.contains(modifier), at: e.location)
            let target = island(at: e.location)
            lastHit = nil; DispatchQueue.main.async { self.overBar = nil }
            let zone = lastZone; lastZone = nil
            DispatchQueue.main.async { self.showZone(nil) }
            if target == nil, let win, let zone {
                // Snapped to a zone: the window takes that spot.
                mover.async {
                    var o = zone.origin, sz = zone.size
                    if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
                    if let v = AXValueCreate(.cgSize, &sz) { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v) }
                    if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
                }
                DispatchQueue.main.async { self.fadeGhost(.settle, after: 0.22) }
            } else if target == nil, win != nil {
                pending = lastOrigin; pump()
                // The real window is there now: the copy melts away.
                DispatchQueue.main.async { self.fadeGhost(.settle, after: 0.22) }
            } else if let t = target {
                // Into the bar: the copy shrinks into the pointer and the bar announces the new Space.
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "App"
                DispatchQueue.main.async {
                    self.fadeGhost(.intoBar, after: 0.38)
                    self.onDropToBar(t.screen, name)
                }
            } else { DispatchQueue.main.async { self.hideGhost() } }
            if let target, let uuid = target.uuid, let win {
                // Back where it was, then into its own full-screen Space at the end of that display.
                let start = startPos
                let (p, w) = (pid, wid)
                let spot = barSpot(at: e.location, island: target.screen)
                DispatchQueue.main.async { [mover] in
                    let uuid = spot?.uuid ?? uuid
                    let count = spot?.index ?? target.model.displays.first { $0.id == uuid }?.spaces.filter(\.isFullscreen).count ?? 99
                    mover.async {
                        var o = start
                        if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
                        SpaceMover.move(pid: p, wid: w, display: uuid, index: count)
                        DispatchQueue.main.async { target.model.refresh() }
                    }
                }
            }
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
    private var lastZone: CGRect?
    private var slots: [CGDirectDisplayID: [(uuid: String, box: CGRect, cells: [CGFloat])]] = [:]
    private var screens: [(cg: CGRect, vis: CGRect)] = []
    private var zoneLayouts: [String] = []
    private var zonesOn = true

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

    /// The screen spot a window snaps to when dropped at `p` (near an edge or corner), top-left coords.
    private func zoneRect(at p: CGPoint) -> CGRect? {
        lock.lock(); let scr = screens; let lay = zoneLayouts; let on = zonesOn; lock.unlock()
        guard on, let s = scr.first(where: { $0.cg.contains(p) }) else { return nil }
        let v = s.vis, edge: CGFloat = 28, corner: CGFloat = 140
        let l = p.x < v.minX + edge, rt = p.x > v.maxX - edge, t = p.y < v.minY + edge, b = p.y > v.maxY - edge
        let nl = p.x < v.minX + corner, nr = p.x > v.maxX - corner, nt = p.y < v.minY + corner, nb = p.y > v.maxY - corner
        let zone: DragZone? =
            (t && nl) || (l && nt) ? .topLeft : (t && nr) || (rt && nt) ? .topRight :
            (b && nl) || (l && nb) ? .bottomLeft : (b && nr) || (rt && nb) ? .bottomRight :
            t ? .top : b ? .bottom : l ? .left : rt ? .right : nil
        guard let zone, let i = DragZone.all.firstIndex(of: zone), i < lay.count,
              let wl = WindowLayout.all.first(where: { $0.id == lay[i] }) else { return nil }
        return CGRect(x: v.minX + v.width * wl.x, y: v.minY + v.height * wl.y, width: v.width * wl.w, height: v.height * wl.h).integral
    }

    // The glowing preview of where the window will snap.
    private var zonePanel: NSPanel?
    private func showZone(_ z: CGRect?) {
        ghostModel?.dimmed = z != nil
        guard let z else {
            if let p = zonePanel { NSAnimationContext.runAnimationGroup { $0.duration = 0.12; p.animator().alphaValue = 0 } }
            return
        }
        let h = NSScreen.screens.first?.frame.height ?? 0
        let r = NSRect(x: z.minX, y: h - z.maxY, width: z.width, height: z.height).insetBy(dx: 6, dy: 6)
        let p = zonePanel ?? {
            let p = NSPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
            p.level = .floating; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.contentView = NSHostingView(rootView: ZoneView()); p.alphaValue = 0
            zonePanel = p; return p
        }()
        p.orderFrontRegardless()
        if p.alphaValue < 0.05 { p.setFrame(r, display: true) }
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.16; c.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(r, display: true); p.animator().alphaValue = 1
        }
    }
    private var lastOrigin = CGPoint.zero
    private var ghostID: UInt32 = 0
    private var ghost: NSPanel?
    private var ghostModel: GhostModel?
    /// Called when a window is dropped on a display's bar (AppDelegate shows the pop-up there).
    var onDropToBar: (CGDirectDisplayID, String) -> Void = { _, _ in }

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
            await MainActor.run { model.image = NSImage(cgImage: img, size: r.size) }
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
            if !badgeOn { badgeOn = true; DispatchQueue.main.async { self.badge.orderFrontRegardless(); var o2 = o; _ = CGSMoveWindow(self.cid, self.badgeID, &o2) } }
        } else if badgeOn { badgeOn = false; DispatchQueue.main.async { self.badge.orderOut(nil) } }
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
            if let img = m.image, !m.overBar { Image(nsImage: img).resizable() }
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

struct ZoneView: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        shape.fill(accent.opacity(0.22)).overlay(shape.strokeBorder(accent, lineWidth: 3)).shadow(color: accent.opacity(0.6), radius: 12)
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
    /// Where the picker sits on the settings picture (0…1).
    var spot: UnitPoint {
        switch self {
        case .topLeft: .topLeading; case .top: .top; case .topRight: .topTrailing; case .right: .trailing
        case .bottomRight: .bottomTrailing; case .bottom: .bottom; case .bottomLeft: .bottomLeading; case .left: .leading
        }
    }
}

/// Settings: a picture of the screen with a picker on each edge and corner.
struct DragZonesCard: View {
    @AppStorage("dragZones") var on = true
    @AppStorage("colRev") var rev = 0
    func binding(_ z: DragZone) -> Binding<String> {
        Binding(get: { Prefs.d.string(forKey: "zone.\(z.rawValue)") ?? z.defaultLayout },
                set: { Prefs.d.set($0, forKey: "zone.\(z.rawValue)"); rev += 1 })
    }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "rectangle.3.group.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                        .frame(width: 30, height: 30).background(NeonBox(color: accent, radius: 8, strength: 0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drop on an edge to arrange").font(.system(size: 13, weight: .heavy))
                        Text("While you hold the key and drag, push the window into an edge or corner of the screen. A glowing box shows where it'll go; let go and it snaps there. Pick what each spot does, or None.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: $on).labelsHidden()
                }
                let _ = rev
                ZStack {
                    // The screen, with the bar at the top.
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.08))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1.2))
                        .overlay(alignment: .top) {
                            Capsule().fill(Color.black).overlay(Capsule().strokeBorder(BarColor.outline.color, lineWidth: 1))
                                .frame(width: 90, height: 12).padding(.top, 5)
                        }
                        .padding(14)
                    Text("Drop on the bar = new Space").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    ForEach(DragZone.all, id: \.self) { z in
                        Menu {
                            Picker("", selection: binding(z)) {
                                Text("None").tag("none")
                                ForEach(WindowLayout.all) { l in Text(l.title).tag(l.id) }
                            }.pickerStyle(.inline).labelsHidden()
                        } label: {
                            let id = binding(z).wrappedValue
                            let l = WindowLayout.all.first { $0.id == id }
                            HStack(spacing: 4) {
                                if let l { Image(nsImage: l.picture) } else { Image(systemName: "nosign").foregroundStyle(.secondary) }
                                Text(l?.title ?? "None").font(.system(size: 10, weight: .semibold)).lineLimit(1)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(l == nil ? Color.white.opacity(0.06) : accent.opacity(0.25)))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(l == nil ? .white.opacity(0.15) : accent, lineWidth: 1))
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help(z.title)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: z.spot.x < 0.3 ? .leading : z.spot.x > 0.7 ? .trailing : .center,
                                                                                               vertical: z.spot.y < 0.3 ? .top : z.spot.y > 0.7 ? .bottom : .center))
                        .padding(.top, z.spot.y < 0.3 ? 22 : 0)
                    }
                }
                .frame(height: 210)
                .opacity(on ? 1 : 0.45).disabled(!on)
            }
        }
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
