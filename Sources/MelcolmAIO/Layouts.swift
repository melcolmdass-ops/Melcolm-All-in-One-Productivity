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

    /// A small picture of the layout for menus: the screen, with the window's spot filled in.
    var picture: NSImage {
        let size = NSSize(width: 30, height: 20)
        let img = NSImage(size: size, flipped: true) { r in
            let screen = r.insetBy(dx: 1, dy: 1)
            NSColor.white.withAlphaComponent(0.55).setStroke()
            let frame = NSBezierPath(roundedRect: screen, xRadius: 3, yRadius: 3); frame.lineWidth = 1.2; frame.stroke()
            let win = NSRect(x: screen.minX + screen.width * x + 1.5, y: screen.minY + screen.height * y + 1.5,
                             width: screen.width * w - 3, height: screen.height * h - 3)
            NSColor(red: 0.45, green: 0.6, blue: 1, alpha: 1).setFill()
            NSBezierPath(roundedRect: win, xRadius: 2, yRadius: 2).fill()
            return true
        }
        return img
    }
}

/// A whole-screen arrangement: the front window takes the first spot, the next window the second, and so on.
struct Arrangement: Identifiable {
    let id: String
    let title: String
    let slots: [WindowLayout]

    private static func w(_ x: CGFloat, _ y: CGFloat, _ wd: CGFloat, _ h: CGFloat) -> WindowLayout { WindowLayout(id: "a", title: "", x: x, y: y, w: wd, h: h) }
    static let all: [Arrangement] = [
        Arrangement(id: "centre", title: "Centre (1 window)", slots: [w(0.15, 0.1, 0.7, 0.8)]),
        Arrangement(id: "full", title: "Full screen (1 window)", slots: [w(0, 0, 1, 1)]),
        Arrangement(id: "halves", title: "Half and half (2)", slots: [w(0, 0, 0.5, 1), w(0.5, 0, 0.5, 1)]),
        Arrangement(id: "twothirds", title: "Two-thirds and a third (2)", slots: [w(0, 0, 2 / 3, 1), w(2 / 3, 0, 1 / 3, 1)]),
        Arrangement(id: "stack", title: "Top and bottom (2)", slots: [w(0, 0, 1, 0.5), w(0, 0.5, 1, 0.5)]),
        Arrangement(id: "thirds", title: "Thirds (3)", slots: [w(0, 0, 1 / 3, 1), w(1 / 3, 0, 1 / 3, 1), w(2 / 3, 0, 1 / 3, 1)]),
        Arrangement(id: "halfstack", title: "Half and two stacked (3)", slots: [w(0, 0, 0.5, 1), w(0.5, 0, 0.5, 0.5), w(0.5, 0.5, 0.5, 0.5)]),
        Arrangement(id: "quarters", title: "Quarters (4)", slots: [w(0, 0, 0.5, 0.5), w(0.5, 0, 0.5, 0.5), w(0, 0.5, 0.5, 0.5), w(0.5, 0.5, 0.5, 0.5)]),
    ]

    /// A small picture: the screen with every window spot filled in.
    var picture: NSImage {
        NSImage(size: NSSize(width: 30, height: 20), flipped: true) { r in
            let screen = r.insetBy(dx: 1, dy: 1)
            NSColor.white.withAlphaComponent(0.55).setStroke()
            let frame = NSBezierPath(roundedRect: screen, xRadius: 3, yRadius: 3); frame.lineWidth = 1.2; frame.stroke()
            for (i, l) in slots.enumerated() {
                let win = NSRect(x: screen.minX + screen.width * l.x + 1.5, y: screen.minY + screen.height * l.y + 1.5,
                                 width: screen.width * l.w - 3, height: screen.height * l.h - 3)
                NSColor(red: 0.45, green: 0.6, blue: 1, alpha: i == 0 ? 1 : 0.6).setFill()
                NSBezierPath(roundedRect: win, xRadius: 2, yRadius: 2).fill()
            }
            return true
        }
    }
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

    private static func allWindows() -> [AXUIElement] {
        let me = ProcessInfo.processInfo.processIdentifier
        var out: [AXUIElement] = []
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular && a.processIdentifier != me {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v) == .success,
               let l = v as? [AXUIElement] { out += l }
        }
        return out
    }
    private static func flag(_ w: AXUIElement, _ k: String) -> Bool {
        var v: CFTypeRef?; AXUIElementCopyAttributeValue(w, k as CFString, &v); return (v as? Bool) == true
    }

    /// Minimizes every normal window on the desktop (full-screen Spaces are left alone).
    static func minimizeDesktop() {
        guard trusted else { return }
        for w in allWindows() where !flag(w, "AXFullScreen") {
            AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    /// Closes every full-screen Space at once, on every display: each full-screen window (found on
    /// any Space, not just this one) leaves full screen, then gets minimized.
    static func minimizeSpaces(dry: Bool = false) {
        guard trusted else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
        DispatchQueue.global(qos: .userInitiated).async {
            var fulls: [AXUIElement] = []
            for a in apps {
                var v: CFTypeRef?
                var list = (AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v) == .success
                            ? v as? [AXUIElement] : nil) ?? []
                list += WebAX.windowsEverywhere(a.processIdentifier)
                for w in list where flag(w, "AXFullScreen") && !fulls.contains(where: { CFEqual($0, w) }) { fulls.append(w) }
            }
            BrowserMedia.log("minimizeSpaces found \(fulls.count): \(fulls.map { w -> String in var t: CFTypeRef?; AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t); return (t as? String ?? "?").prefix(30).description })")
            if dry { return }
            let fs = "AXFullScreen" as CFString
            for w in fulls { AXUIElementSetAttributeValue(w, fs, kCFBooleanFalse) }
            Thread.sleep(forTimeInterval: 1.5)
            // Some apps (Chrome) only leave full screen while their Space is showing: go there, then ask again.
            for w in fulls where flag(w, "AXFullScreen") {
                var pid: pid_t = 0; AXUIElementGetPid(w, &pid)
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                DispatchQueue.main.sync { NSRunningApplication(processIdentifier: pid)?.activate() }
                Thread.sleep(forTimeInterval: 1.0)
                AXUIElementSetAttributeValue(w, fs, kCFBooleanFalse)
                for _ in 0 ..< 3 where flag(w, "AXFullScreen") {
                    Thread.sleep(forTimeInterval: 1.0)
                    AXUIElementSetAttributeValue(w, fs, kCFBooleanFalse)
                }
                Thread.sleep(forTimeInterval: 1.2)
            }
            Thread.sleep(forTimeInterval: 0.6)
            for w in fulls { AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
        }
    }

    /// Every normal window on the screen the mouse is on, front-most first.
    private static func screenWindows() -> (NSScreen, [AXUIElement]) {
        let mouse = NSEvent.mouseLocation
        let target = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let me = ProcessInfo.processInfo.processIdentifier
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var axByPid: [pid_t: [(AXUIElement, CGRect)]] = [:]
        var out: [AXUIElement] = []
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular,
                  let bd = w[kCGWindowBounds as String], let cg = CGRect(dictionaryRepresentation: bd as! CFDictionary) else { continue }
            if axByPid[pid] == nil {
                var v: CFTypeRef?
                let list = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &v) == .success ? (v as? [AXUIElement] ?? []) : []
                axByPid[pid] = list.compactMap { e in
                    var mini: CFTypeRef?
                    AXUIElementCopyAttributeValue(e, kAXMinimizedAttribute as CFString, &mini)
                    guard (mini as? Bool) != true, let f = frame(of: e) else { return nil }
                    return (e, f)
                }
            }
            // The on-screen window list is front to back; match each one to its Accessibility window.
            guard let hit = axByPid[pid]?.first(where: { abs($0.1.minX - cg.minX) < 3 && abs($0.1.minY - cg.minY) < 3 && abs($0.1.width - cg.width) < 3 }),
                  hit.1.width > 120, hit.1.height > 80, screen(for: hit.1) == target,
                  !out.contains(where: { CFEqual($0, hit.0) }) else { continue }
            out.append(hit.0)
        }
        return (target, out)
    }

    /// One click: tidy every open window on the screen the mouse is on into an even grid.
    @discardableResult
    static func autoArrange() -> Int {
        guard trusted else { return 0 }
        let (target, windows) = screenWindows()
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

    /// Put the front windows into the spots of one arrangement (front-most window gets the first spot).
    @discardableResult
    static func arrange(_ a: Arrangement) -> Int {
        guard trusted else { return 0 }
        let (target, windows) = screenWindows()
        for (w, slot) in zip(windows, a.slots) { set(w, rect(slot, on: target)) }
        return min(windows.count, a.slots.count)
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
            let hiddenSet = Set(hiddenRaw.split(separator: ",").map(String.init))
            let shownList = WindowLayout.all.filter { !hiddenSet.contains($0.id) }
            HStack(spacing: 6) {
                arrangeButton
                action("Minimize all\n(desktop)", "rectangle.compress.vertical") { Tiler.minimizeDesktop() }
                action("Minimize all\n(Spaces)", "arrow.down.right.and.arrow.up.left") { Tiler.minimizeSpaces() }
                if light {
                    Menu {
                        ForEach(shownList) { l in
                            Button { _ = Tiler.apply(l) } label: {
                                Label { Text(l.title) } icon: { Image(nsImage: l.picture) }
                            }
                        }
                    } label: {
                        Label("Layouts", systemImage: "rectangle.split.2x2").font(.system(size: 11, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .padding(.horizontal, 8).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
                    .help("Snap the window you were just using")
                }
            }
            if !light {
                let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
                let shown = WindowLayout.all.filter { !hidden.contains($0.id) }
                let gone = WindowLayout.all.filter { hidden.contains($0.id) }
                sectionLabel("ARRANGE EVERY WINDOW")
                arrangeGrid
                HStack {
                    sectionLabel("SNAP ONE WINDOW")
                    LinkButton(editing ? "Done" : "Edit") { withAnimation(.easeOut(duration: 0.2)) { editing.toggle() } }
                }
                grid(shown, hide: true)
                if editing {
                    sectionLabel("HIDDEN")
                    if gone.isEmpty {
                        Text("Click a layout above to hide it.").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else { grid(gone, hide: false) }
                }
                Text(editing ? "Click a layout to move it between shown and hidden." : "Arrange lays out your front windows (front-most first). Snap moves only the window you were just using.")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                SettingsLink(title: "Desktop & Dock Settings", pane: "com.apple.Desktop-Settings.extension")
            }
        }
    }

    /// Click = arrange everything in one go. The arrow opens every arrangement as a picture to pick from.
    var arrangeButton: some View {
        Menu {
            Button { _ = Tiler.autoArrange() } label: { Label("Auto-arrange every window", systemImage: "sparkles.rectangle.stack") }
            Divider()
            ForEach(Arrangement.all) { a in
                Button { _ = Tiler.arrange(a) } label: { Label { Text(a.title) } icon: { Image(nsImage: a.picture) } }
            }
        } label: {
            Label("Auto-arrange", systemImage: "sparkles.rectangle.stack").font(.system(size: 10.5, weight: .semibold))
        } primaryAction: { _ = Tiler.autoArrange() }
        .menuStyle(.borderlessButton).fixedSize()
        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent))
        .help("Click to arrange every window. The arrow picks an arrangement.")
    }

    /// The arrangements as big pictures (full page): click one to lay out your front windows like that.
    var arrangeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(Arrangement.all) { a in
                Button { _ = Tiler.arrange(a) } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.1))
                            GeometryReader { g in
                                ForEach(Array(a.slots.enumerated()), id: \.offset) { i, l in
                                    RoundedRectangle(cornerRadius: 2).fill(accentGradient).opacity(i == 0 ? 1 : 0.6)
                                        .frame(width: g.size.width * l.w - 3, height: g.size.height * l.h - 3)
                                        .offset(x: g.size.width * l.x + 1.5, y: g.size.height * l.y + 1.5)
                                }
                            }
                        }
                        .frame(height: 24)
                        Text(a.title).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(5).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.06)))
                    .contentShape(Rectangle())
                }.buttonStyle(PressStyle()).help(a.title)
            }
        }
    }

    func action(_ title: String, _ icon: String, filled: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5) { Image(systemName: icon); Text(title).multilineTextAlignment(.leading).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                .font(.system(size: 10.5, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 36).padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(filled ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.08))))
                .foregroundStyle(.white).contentShape(Rectangle())
        }.buttonStyle(PressStyle()).help(title)
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
