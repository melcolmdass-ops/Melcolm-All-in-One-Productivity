import AppKit
import SwiftUI

/// Hold a modifier (Option by default) and drag any window from anywhere on it, not just its title bar.
/// Drop it on the bar and it becomes its own full-screen Space on that display.
final class OptionDrag: ObservableObject {
    static let shared = OptionDrag()
    @Published var overBar: CGDirectDisplayID?      // the island the window is over (glows)
    @Published var active = false

    /// Islands' frames (AppKit coords) and their display UUIDs, refreshed by AppDelegate.
    var islands: () -> [(frame: NSRect, screen: CGDirectDisplayID, uuid: String?, model: SpacesModel)] = { [] }

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
        let mask = (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask), callback: { _, type, e, ctx in
            let s = Unmanaged<OptionDrag>.fromOpaque(ctx!).takeUnretainedValue()
            return s.handle(type, e)
        }, userInfo: me)
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        switch type {
        case .flagsChanged, .mouseMoved:
            showBadge(Prefs.bool("optionDrag") && e.flags.contains(modifier))
            return Unmanaged.passUnretained(e)
        case .leftMouseDown:
            guard Prefs.bool("optionDrag"), e.flags.contains(modifier), grab(at: e.location) else { break }
            active = true
            return nil
        case .leftMouseDragged where active:
            let p = e.location
            showBadge(true)
            // Never block the mouse: move the window off the event path, only to the newest spot.
            pending = CGPoint(x: startPos.x + p.x - startMouse.x, y: startPos.y + p.y - startMouse.y)
            pump()
            let hit = island(at: NSEvent.mouseLocation)?.screen
            if overBar != hit { overBar = hit }
            return nil
        case .leftMouseUp where active:
            active = false
            pending = nil
            showBadge(e.flags.contains(modifier))
            let target = island(at: NSEvent.mouseLocation)
            overBar = nil
            if let target, let uuid = target.uuid, let win {
                // Back where it was, then into its own full-screen Space at the end of that display.
                let start = startPos
                let (p, w) = (pid, wid)
                let count = target.model.displays.first { $0.id == uuid }?.spaces.filter(\.isFullscreen).count ?? 99
                mover.async {
                    var o = start
                    if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
                    SpaceMover.move(pid: p, wid: w, display: uuid, index: count)
                    DispatchQueue.main.async { target.model.refresh() }
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

    /// One move in flight at a time, always to the latest pointer spot (skips stale ones).
    private func pump() {
        guard !pumping, let win else { return }
        pumping = true
        mover.async { [weak self] in
            while let self, var o = self.pending {
                self.pending = nil
                if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
            }
            DispatchQueue.main.async { self?.pumping = false; if self?.pending != nil { self?.pump() } }
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

    private func showBadge(_ on: Bool) {
        if on {
            let m = NSEvent.mouseLocation
            badge.setFrameOrigin(NSPoint(x: m.x + 14, y: m.y - 30))
            if !badge.isVisible { badge.orderFrontRegardless() }
        } else if badge.isVisible { badge.orderOut(nil) }
    }

    private func island(at p: NSPoint) -> (frame: NSRect, screen: CGDirectDisplayID, uuid: String?, model: SpacesModel)? {
        islands().first { $0.frame.insetBy(dx: -8, dy: -8).contains(p) }
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
            startMouse = p; startPos = r.origin
            NSRunningApplication(processIdentifier: pid)?.activate()
            AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
            return true
        }
        return false
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
            DragSpacesCard()
        }
    }
}
