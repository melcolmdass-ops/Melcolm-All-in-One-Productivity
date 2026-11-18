import AppKit
import SwiftUI
import ApplicationServices

/// "Split view" drop spot: the dropped window takes the left half, a pop-up asks which app takes the right half.
enum SplitView {
    struct Choice: Identifiable {
        let pid: pid_t, wid: CGWindowID, name: String, title: String
        var id: CGWindowID { wid }
        var icon: NSImage { NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)! }
    }

    private static var panel: NSPanel?
    private static var keyMonitor: Any?
    private static var clickMonitor: Any?

    /// Other apps with a visible window on this display (one entry per app, front to back).
    static func choices(excluding pid: pid_t, wid: CGWindowID) -> [Choice] {
        let me = ProcessInfo.processInfo.processIdentifier
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var seen = Set<pid_t>(), out: [Choice] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let p = w[kCGWindowOwnerPID as String] as? pid_t, p != pid, p != me, !seen.contains(p),
                  let n = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) > 200, (b["Height"] ?? 0) > 150,
                  let app = NSRunningApplication(processIdentifier: p), app.activationPolicy == .regular else { continue }
            seen.insert(p)
            out.append(Choice(pid: p, wid: n, name: app.localizedName ?? "App", title: (w[kCGWindowName as String] as? String) ?? ""))
        }
        return out
    }

    /// Shows the pop-up in the middle of the display the window was dropped on.
    static func ask(pid: pid_t, wid: CGWindowID, display: CGDirectDisplayID) {
        close()
        let list = choices(excluding: pid, wid: wid)
        let screen = NSScreen.screens.first { Island.id(of: $0) == display } ?? NSScreen.main ?? NSScreen.screens[0]
        let mine = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "this window"
        let view = SplitPicker(mine: mine, list: list, pick: { c in close(); make(left: (pid, wid), right: (c.pid, c.wid), on: screen) }, cancel: { close() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let p = IslandPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.level = .statusBar + 2
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.contentView = host
        p.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        p.alphaValue = 0; p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.16; p.animator().alphaValue = 1 }
        panel = p
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in if e.keyCode == 53 { close(); return nil }; return e }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            if let p = panel, !p.frame.contains(NSEvent.mouseLocation) { close() }
        }
    }

    static func close() {
        panel?.orderOut(nil); panel = nil
        if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
        if let c = clickMonitor { NSEvent.removeMonitor(c); clickMonitor = nil }
    }

    // MARK: making the split

    /// Looks through an app's menu bar for an item whose title starts with `prefix`.
    private static func menuItem(_ app: AXUIElement, startsWith prefix: String) -> AXUIElement? {
        func kids(_ e: AXUIElement) -> [AXUIElement] {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) == .success ? (v as? [AXUIElement]) ?? [] : []
        }
        func title(_ e: AXUIElement) -> String {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(e, kAXTitleAttribute as CFString, &v) == .success ? (v as? String) ?? "" : ""
        }
        func find(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
            if depth > 4 { return nil }
            for k in kids(e) {
                if title(k).hasPrefix(prefix) { return k }
                if let f = find(k, depth + 1) { return f }
            }
            return nil
        }
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success else { return nil }
        return find(bar as! AXUIElement, 0)
    }

    /// Presses "Tile Window to Left/Right of Screen" in the app's Window menu. False if the app has no such item.
    private static func tile(pid: pid_t, wid: CGWindowID, left: Bool) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        NSRunningApplication(processIdentifier: pid)?.activate()
        if let w = SpaceMover.window(pid: pid, wid: wid) { AXUIElementPerformAction(w, kAXRaiseAction as CFString) }
        Thread.sleep(forTimeInterval: 0.25)
        guard let item = menuItem(app, startsWith: left ? "Tile Window to Left" : "Tile Window to Right") else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// Left app goes to the left half, right app to the right half. macOS turns two tiled windows into a Split View Space;
    /// when an app has no tiling menu item, both just snap to the two halves of the screen.
    static func make(left: (pid_t, CGWindowID), right: (pid_t, CGWindowID), on screen: NSScreen) {
        openedOutside()
        DispatchQueue.global(qos: .userInitiated).async {
            let okLeft = tile(pid: left.0, wid: left.1, left: true)
            var okRight = false
            if okLeft {
                Thread.sleep(forTimeInterval: 1.1)      // let the first window finish sliding into place
                okRight = tile(pid: right.0, wid: right.1, left: false)
            }
            if !(okLeft && okRight) {
                let h = NSScreen.screens.first?.frame.height ?? 0
                let v = CGRect(x: screen.visibleFrame.minX, y: h - screen.visibleFrame.maxY, width: screen.visibleFrame.width, height: screen.visibleFrame.height)
                for (i, t) in [left, right].enumerated() {
                    guard let w = SpaceMover.window(pid: t.0, wid: t.1) else { continue }
                    OptionDrag.setFrame(w, app: AXUIElementCreateApplication(t.0),
                                        to: CGRect(x: v.minX + (i == 0 ? 0 : v.width / 2), y: v.minY, width: v.width / 2, height: v.height).integral)
                }
                NSRunningApplication(processIdentifier: right.0)?.activate()
            }
            DispatchQueue.main.async { NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil) }
        }
    }
}

/// The pop-up: "Which one goes next to Chrome?" with one big button per open app.
struct SplitPicker: View {
    let mine: String
    let list: [SplitView.Choice]
    let pick: (SplitView.Choice) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Split view").font(.system(size: 14, weight: .heavy))
                    Text("\(mine) takes the left. Which one goes on the right?").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 20)
                Button(action: cancel) { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            if list.isEmpty {
                Text("No other open app to pair with.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 10)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(104), spacing: 8), count: min(4, max(1, list.count))), spacing: 8) {
                    ForEach(list.prefix(12)) { c in
                        Button { pick(c) } label: {
                            VStack(spacing: 5) {
                                Image(nsImage: c.icon).resizable().frame(width: 40, height: 40)
                                Text(c.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                if !c.title.isEmpty { Text(c.title).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            .frame(width: 104).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                            .contentShape(Rectangle())
                        }.buttonStyle(PressStyle())
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.09))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(accent.opacity(0.7), lineWidth: 1.5)))
        .padding(8)
        .preferredColorScheme(.dark)
    }
}
