import AppKit
import SwiftUI
import ApplicationServices

/// Where a window goes, as fractions of the screen (x, y from the top-left, width, height).
struct WindowLayout: Identifiable {
    let id: String
    let title: String
    let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat

    static let halves = [
        WindowLayout(id: "left", title: "Left half", x: 0, y: 0, w: 0.5, h: 1),
        WindowLayout(id: "right", title: "Right half", x: 0.5, y: 0, w: 0.5, h: 1),
        WindowLayout(id: "top", title: "Top half", x: 0, y: 0, w: 1, h: 0.5),
        WindowLayout(id: "bottom", title: "Bottom half", x: 0, y: 0.5, w: 1, h: 0.5),
    ]
    static let thirds = [
        WindowLayout(id: "t1", title: "Left third", x: 0, y: 0, w: 1 / 3, h: 1),
        WindowLayout(id: "t2", title: "Middle third", x: 1 / 3, y: 0, w: 1 / 3, h: 1),
        WindowLayout(id: "t3", title: "Right third", x: 2 / 3, y: 0, w: 1 / 3, h: 1),
        WindowLayout(id: "tl2", title: "Left two thirds", x: 0, y: 0, w: 2 / 3, h: 1),
        WindowLayout(id: "tr2", title: "Right two thirds", x: 1 / 3, y: 0, w: 2 / 3, h: 1),
    ]
    static let corners = [
        WindowLayout(id: "tl", title: "Top left", x: 0, y: 0, w: 0.5, h: 0.5),
        WindowLayout(id: "tr", title: "Top right", x: 0.5, y: 0, w: 0.5, h: 0.5),
        WindowLayout(id: "bl", title: "Bottom left", x: 0, y: 0.5, w: 0.5, h: 0.5),
        WindowLayout(id: "br", title: "Bottom right", x: 0.5, y: 0.5, w: 0.5, h: 0.5),
    ]
    static let other = [
        WindowLayout(id: "full", title: "Full screen", x: 0, y: 0, w: 1, h: 1),
        WindowLayout(id: "center", title: "Centre", x: 0.15, y: 0.1, w: 0.7, h: 0.8),
    ]
    static let all = halves + thirds + corners + other
}

/// Moves and resizes other apps' windows through Accessibility (the same way Rectangle does).
enum Tiler {
    private static var lastApp: NSRunningApplication?
    private static var observer: NSObjectProtocol?

    /// Remember the last app you used, since opening the island must not steal focus from it.
    static func watch() {
        guard observer == nil else { return }
        lastApp = NSWorkspace.shared.frontmostApplication
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            if let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               a.processIdentifier != ProcessInfo.processInfo.processIdentifier, a.activationPolicy == .regular { lastApp = a }
        }
    }

    static var trusted: Bool { AXIsProcessTrusted() }

    /// Top-left-origin screen rect (what Accessibility uses) for a fraction of a screen's usable area.
    private static func rect(_ l: WindowLayout, on screen: NSScreen) -> CGRect {
        let v = screen.visibleFrame
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let top = primaryH - v.maxY
        let gap: CGFloat = 0
        return CGRect(x: v.minX + v.width * l.x + gap, y: top + v.height * l.y + gap, width: v.width * l.w - gap * 2, height: v.height * l.h - gap * 2).integral
    }

    private static func focusedWindow() -> AXUIElement? {
        guard let app = lastApp, !app.isTerminated else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &v) == .success { return (v as! AXUIElement) }
        if AXUIElementCopyAttributeValue(el, kAXMainWindowAttribute as CFString, &v) == .success { return (v as! AXUIElement) }
        return nil
    }

    private static func frame(of w: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    private static func set(_ w: AXUIElement, _ r: CGRect) {
        var pos = r.origin, size = r.size
        // Size, position, size again: some apps clamp the first resize when the window moves screens.
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s) }
        if let p = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p) }
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s) }
    }

    /// The screen a window mostly sits on.
    private static func screen(for frame: CGRect) -> NSScreen {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let center = CGPoint(x: frame.midX, y: primaryH - frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Snap the window you were just using.
    @discardableResult
    static func apply(_ l: WindowLayout) -> Bool {
        guard trusted, let w = focusedWindow(), let f = frame(of: w) else { return false }
        set(w, rect(l, on: screen(for: f)))
        lastApp?.activate()
        return true
    }

    /// Tidy every open window on the screen the mouse is on into an even grid.
    @discardableResult
    static func autoArrange() -> Int {
        guard trusted else { return 0 }
        let mouse = NSEvent.mouseLocation
        let target = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let me = ProcessInfo.processInfo.processIdentifier
        // Apps that currently have a normal on-screen window.
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var pids: [pid_t] = []
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me, !pids.contains(pid),
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { continue }
            pids.append(pid)
        }
        var windows: [AXUIElement] = []
        for pid in pids {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &v) == .success,
                  let list = v as? [AXUIElement] else { continue }
            for w in list {
                var mini: CFTypeRef?
                AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &mini)
                guard (mini as? Bool) != true, let f = frame(of: w), f.width > 120, f.height > 80,
                      screen(for: f) == target else { continue }
                windows.append(w)
            }
        }
        guard !windows.isEmpty else { return 0 }
        let n = windows.count
        let cols = Int(ceil(Double(n).squareRoot()))
        let rows = Int(ceil(Double(n) / Double(cols)))
        for (i, w) in windows.enumerated() {
            let r = i / cols, c = i % cols
            // The last row shares the full width evenly.
            let inRow = (r == rows - 1) ? n - r * cols : cols
            let l = WindowLayout(id: "auto", title: "", x: CGFloat(c) / CGFloat(inRow), y: CGFloat(r) / CGFloat(rows), w: 1 / CGFloat(inRow), h: 1 / CGFloat(rows))
            set(w, rect(l, on: target))
        }
        return n
    }
}

// MARK: - Page

struct LayoutsPage: View {
    @EnvironmentObject var state: IslandState
    @Environment(\.lightPage) var light
    @AppStorage("layoutsHidden") var hiddenRaw = "top,bottom"
    @AppStorage("layoutsEditing") var editing = false
    var body: some View {
        VStack(spacing: 12) {
            if !Tiler.trusted {
                Card {
                    HStack {
                        Text("Needs Accessibility to move windows.").font(.system(size: 12)).foregroundStyle(.orange)
                        Spacer()
                        LinkButton("Allow…") { SystemModel.open("com.apple.preference.security?Privacy_Accessibility") }
                    }
                }
            }
            Button { _ = Tiler.autoArrange() } label: {
                Label("Auto-arrange all windows", systemImage: "sparkles.rectangle.stack")
                    .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent))
                    .foregroundStyle(.white)
            }.buttonStyle(PressStyle())
            if !light {
                let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
                let shown = WindowLayout.all.filter { !hidden.contains($0.id) }
                let gone = WindowLayout.all.filter { hidden.contains($0.id) }
                HStack {
                    sectionLabel("SNAP")
                    LinkButton(editing ? "Done" : "Edit") { withAnimation(.easeOut(duration: 0.2)) { editing.toggle() } }
                }
                grid(shown, hide: true)
                if editing {
                    sectionLabel("HIDDEN")
                    if gone.isEmpty {
                        Text("Click a layout above to hide it.").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else { grid(gone, hide: false) }
                }
                Text(editing ? "Click a layout to move it between shown and hidden." : "Snaps the window you were just using. Auto-arrange tidies every window on this screen into a grid.")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                SettingsLink(title: "Desktop & Dock Settings", pane: "com.apple.Desktop-Settings.extension")
            }
        }
    }

    func flip(_ id: String) {
        var h = hiddenRaw.split(separator: ",").map(String.init)
        if let i = h.firstIndex(of: id) { h.remove(at: i) } else { h.append(id) }
        hiddenRaw = h.joined(separator: ",")
    }

    /// Everything shown fits in two rows.
    func grid(_ items: [WindowLayout], hide: Bool) -> some View {
        let cols = max(4, Int(ceil(Double(items.count) / 2)))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols), spacing: 6) {
            ForEach(items) { l in
                Button { editing ? flip(l.id) : { _ = Tiler.apply(l) }() } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.1))
                            GeometryReader { g in
                                RoundedRectangle(cornerRadius: 2).fill(accentGradient)
                                    .frame(width: g.size.width * l.w - 3, height: g.size.height * l.h - 3)
                                    .offset(x: g.size.width * l.x + 1.5, y: g.size.height * l.y + 1.5)
                            }
                        }
                        .frame(height: 24)
                        Text(l.title).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(5).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.06)))
                    .overlay(alignment: .topTrailing) {
                        if editing {
                            Image(systemName: hide ? "minus.circle.fill" : "plus.circle.fill")
                                .font(.system(size: 11)).foregroundStyle(hide ? .red : .green).offset(x: 3, y: -3)
                        }
                    }
                    .opacity(hide ? 1 : 0.6)
                    .contentShape(Rectangle())
                }.buttonStyle(PressStyle()).help(l.title)
            }
        }
    }
}
