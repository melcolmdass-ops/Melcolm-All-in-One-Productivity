import AppKit

// Private CGS APIs (same ones WhichSpace uses; there is no public alternative).
@_silgen_name("_CGSDefaultConnection") private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ conn: Int32) -> Unmanaged<CFArray>?
@_silgen_name("CGSGetSymbolicHotKeyValue") private func CGSGetSymbolicHotKeyValue(
    _ hotKey: Int32, _ char: UnsafeMutablePointer<UInt16>?, _ keyCode: UnsafeMutablePointer<UInt16>?, _ flags: UnsafeMutablePointer<UInt32>?
) -> Int32
@_silgen_name("CGSCopySpacesForWindows") private func CGSCopySpacesForWindows(_ conn: Int32, _ mask: Int32, _ wids: CFArray) -> Unmanaged<CFArray>?
@_silgen_name("CGSIsSymbolicHotKeyEnabled") private func CGSIsSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool
@_silgen_name("CGSSetSymbolicHotKeyEnabled") private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> Int32

/// An app with at least one window on a Space.
struct SpaceApp: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    var id: pid_t { pid }
    var icon: NSImage { NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage(named: NSImage.applicationIconName)! }
}

struct SpaceItem: Identifiable, Equatable {
    let id: Int
    let number: Int        // 1-based position on this display
    let isFullscreen: Bool
    var window: Int = 0    // the full-screen window: stays the same when macOS gives the app a new Space
    /// Stable identity for the bar, so a moved app glides instead of being redrawn.
    var cellKey: Int { window != 0 ? window : id }
}

/// A display and its Spaces, numbered left to right like the screens are arranged.
struct DisplayGroup: Identifiable, Equatable {
    let id: String
    let number: Int
    let spaces: [SpaceItem]
    let currentID: Int
}

final class SpacesModel: ObservableObject {
    @Published var displays: [DisplayGroup] = []
    @Published var spaces: [SpaceItem] = []
    @Published var currentID: Int = 0
    @Published var apps: [Int: [SpaceApp]] = [:]   // space id -> apps, front-most first

    @Published var frontPID: pid_t = 0
    @Published var split: Set<Int> = []           // Split View Spaces (two apps side by side)
    let screen: () -> NSScreen?

    init(screen: @escaping () -> NSScreen? = { NSScreen.screens.first }) {
        self.screen = screen
        frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            let pid = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier ?? 0
            if pid != ProcessInfo.processInfo.processIdentifier { self?.frontPID = pid }
        }
        refresh()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        // Spaces can be added/removed in Mission Control without a switch.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    var currentIndex: Int? { spaces.firstIndex { $0.id == currentID } }

    /// Reads the spaces of the display the island sits on (the menu-bar screen).
    func refresh() {
        if holding { return }   // a drag move is running; keep showing where it's going
        guard let raw = CGSCopyManagedDisplaySpaces(_CGSDefaultConnection())?.takeRetainedValue() as? [NSDictionary],
              !raw.isEmpty else { return }
        let wanted = Self.uuid(of: screen())
        let display = raw.first { ($0["Display Identifier"] as? String) == wanted }
            ?? raw.first { ($0["Display Identifier"] as? String) == "Main" && screen() == NSScreen.screens.first }
            ?? raw.first { ($0["Display Identifier"] as? String) == "Main" }
            ?? raw[0]
        let list = (display["Spaces"] as? [NSDictionary]) ?? []
        var items: [SpaceItem] = []
        var n = 0
        for s in list {
            guard let id = (s["ManagedSpaceID"] as? Int) ?? (s["id64"] as? Int) else { continue }
            let full = (s["type"] as? Int) == 4
            n += 1
            items.append(SpaceItem(id: id, number: n, isFullscreen: full))
        }
        let cur = ((display["Current Space"] as? NSDictionary)?["ManagedSpaceID"] as? Int) ?? 0
        if items != spaces { spaces = items }
        if cur != currentID { currentID = cur }
        // Every display, ordered left to right.
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        let order = screens.compactMap { Self.uuid(of: $0) }
        var groups: [DisplayGroup] = []
        var allIDs = Set<Int>()
        let sorted = raw.sorted {
            (order.firstIndex(of: ($0["Display Identifier"] as? String) ?? "") ?? 99) < (order.firstIndex(of: ($1["Display Identifier"] as? String) ?? "") ?? 99)
        }
        for (i, d) in sorted.enumerated() {
            var list: [SpaceItem] = []
            for (j, sp) in ((d["Spaces"] as? [NSDictionary]) ?? []).enumerated() {
                guard let id = (sp["ManagedSpaceID"] as? Int) ?? (sp["id64"] as? Int) else { continue }
                list.append(SpaceItem(id: id, number: j + 1, isFullscreen: (sp["type"] as? Int) == 4, window: SpaceMover.wid(sp)))
                allIDs.insert(id)
            }
            let c = ((d["Current Space"] as? NSDictionary)?["ManagedSpaceID"] as? Int) ?? 0
            groups.append(DisplayGroup(id: (d["Display Identifier"] as? String) ?? "\(i)", number: i + 1, spaces: list, currentID: c))
        }
        if groups != displays { displays = groups }
        let sp = SpaceMover.splitIDs()
        if sp != split { split = sp }
        let a = Self.appsBySpace(allIDs, split: sp)
        if a != apps { apps = a }
    }

    /// Which apps have normal windows on which Space (includes Spaces you're not on).
    static func appsBySpace(_ ids: Set<Int>, split: Set<Int> = []) -> [Int: [SpaceApp]] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        let me = ProcessInfo.processInfo.processIdentifier
        let conn = _CGSDefaultConnection()
        var out: [Int: [SpaceApp]] = [:]
        var area: [Int: [pid_t: Double]] = [:]
        var left: [Int: [pid_t: Double]] = [:]   // left edge, so a Split View shows apps in screen order
        var regular: [pid_t: NSRunningApplication?] = [:]
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let wid = w[kCGWindowNumber as String] as? Int,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? [String: Double],
                  (b["Width"] ?? 0) >= 120, (b["Height"] ?? 0) >= 80 else { continue }
            if regular[pid] == nil { regular[pid] = NSRunningApplication(processIdentifier: pid) }
            guard let app = regular[pid] ?? nil, app.activationPolicy == .regular else { continue }
            guard let sp = CGSCopySpacesForWindows(conn, 0x7, [wid] as CFArray)?.takeRetainedValue() as? [Int] else { continue }
            for s in sp where ids.contains(s) {
                left[s, default: [:]][pid] = min(left[s]?[pid] ?? .infinity, b["X"] ?? 0)
                area[s, default: [:]][pid, default: 0] = max(area[s]?[pid] ?? 0, (b["Width"] ?? 0) * (b["Height"] ?? 0))
                if out[s]?.contains(where: { $0.pid == pid }) == true { continue }
                out[s, default: []].append(SpaceApp(pid: pid, name: app.localizedName ?? "App"))
            }
        }
        for (id, apps) in out where split.contains(id) {
            out[id] = apps.sorted { (left[id]?[$0.pid] ?? 0) < (left[id]?[$1.pid] ?? 0) }
        }
        for (id, apps) in out where !(split.contains(id)) { out[id] = apps.sorted { (area[id]?[$0.pid] ?? 0) > (area[id]?[$1.pid] ?? 0) } }
        return out
    }

    /// Goes to the Space, then brings the app forward there.
    func focus(_ app: SpaceApp, on space: SpaceItem) {
        // Spaces on this island's display are stepped to; on other displays macOS follows the app.
        let moved = space.id != currentID && spaces.contains(space)
        if moved { switchTo(space) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (moved ? 0.45 : 0)) {
            NSRunningApplication(processIdentifier: app.pid)?.activate()
        }
    }

    /// While a dragged app is being moved, show it in its new place straight away.
    private var holding = false
    func preview(moving id: Int, to t: SpaceDrop) {
        guard let item = displays.flatMap(\.spaces).first(where: { $0.id == id }) else { return }
        holding = true
        var gs = displays.map { g in DisplayGroup(id: g.id, number: g.number, spaces: g.spaces.filter { $0.id != id }, currentID: g.currentID) }
        if case .slot(let d, let k) = t, let i = gs.firstIndex(where: { $0.id == d }) {
            let g = gs[i]
            var fulls = g.spaces.filter(\.isFullscreen)
            fulls.insert(item, at: min(k, fulls.count))
            gs[i] = DisplayGroup(id: g.id, number: g.number, spaces: g.spaces.filter { !$0.isFullscreen } + fulls, currentID: g.currentID)
        }
        displays = gs
    }
    func endPreview() {
        holding = false
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refresh() }
    }

    func jump(toNumber n: Int) {
        guard n >= 1, n <= spaces.count else { return }
        switchTo(spaces[n - 1])
    }

    /// One Space left or right. With `wrap`, going past the last Space comes back round to the first (and the other way).
    /// Presses arrive faster than macOS can animate a switch, and a switch posted mid-animation is dropped.
    /// So each press is counted from where the LAST press is heading (not a stale reading), presses are spaced
    /// out until the animation is done, and each one re-reads the real current Space before it switches.
    private var stepTarget: Int?
    private var busyUntil = Date.distantPast
    private static let stepGap = 0.42

    func step(_ delta: Int, wrap: Bool = false) {
        let idle = Date() >= busyUntil
        if idle { stepTarget = nil; refresh() }
        let base = stepTarget.flatMap { t in spaces.firstIndex { $0.id == t } } ?? currentIndex
        guard let i = base, !spaces.isEmpty else { refresh(); return }
        var j = i + delta
        if wrap { j = ((j % spaces.count) + spaces.count) % spaces.count }
        guard spaces.indices.contains(j) else { return }
        let target = spaces[j].id
        stepTarget = target
        let wait = max(0, busyUntil.timeIntervalSinceNow)
        busyUntil = Date().addingTimeInterval(wait + Self.stepGap)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.go(to: target, retries: 1) }
    }

    /// Switches to the Space with this id from wherever macOS really is now, then checks it arrived (retrying once).
    private func go(to id: Int, retries: Int) {
        guard stepTarget == id || stepTarget == nil else { return }   // a newer press took over; it will finish the job
        refresh()
        guard let sp = spaces.first(where: { $0.id == id }) else { return }
        if currentID != id { switchTo(sp) }
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self, self.stepTarget == id, Date() >= self.busyUntil else { return }
            self.refresh()
            if self.currentID != id { self.busyUntil = Date().addingTimeInterval(Self.stepGap); self.go(to: id, retries: retries - 1) }
        }
    }

    /// Steps left/right with the "Move left/right a space" shortcuts, which is
    /// the route WhichSpace uses on macOS 27. Needs Accessibility permission.
    func switchTo(_ space: SpaceItem) {
        if !spaces.contains(space), let app = apps[space.id]?.first {
            NSRunningApplication(processIdentifier: app.pid)?.activate(); return
        }
        guard let from = currentIndex, let to = spaces.firstIndex(of: space), from != to else { return }
        guard Self.ensureAccessibility() else { return }
        let right = to > from
        let steps = abs(to - from)
        if Prefs.bool("classicSwitching") || !FastSwitch.available {
            for _ in 0 ..< steps { Self.postHotKey(right ? 81 : 79) }
        } else {
            for _ in 0 ..< steps { FastSwitch.step(right: right, scale: Double(steps)) }
        }
        currentID = space.id // optimistic; refresh confirms
        // Move the outline now, so it slides over while macOS is still switching.
        displays = displays.map { g in g.spaces.contains(space) ? DisplayGroup(id: g.id, number: g.number, spaces: g.spaces, currentID: space.id) : g }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refresh() }
    }

    private static var prompted = false

    /// True if macOS trusts this build. Only asks (once per launch) when you actually try to switch Spaces.
    static func ensureAccessibility(prompt: Bool = true) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt && !prompted {
            prompted = true
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        return false
    }

    private static func postHotKey(_ hotKey: Int32) {
        var keyCode: UInt16 = 0
        var flags: UInt32 = 0
        guard CGSGetSymbolicHotKeyValue(hotKey, nil, &keyCode, &flags) == 0 else { return }
        let wasOff = !CGSIsSymbolicHotKeyEnabled(hotKey)
        if wasOff { _ = CGSSetSymbolicHotKeyEnabled(hotKey, true) }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        down?.flags = CGEventFlags(rawValue: UInt64(flags))
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        if wasOff {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { _ = CGSSetSymbolicHotKeyEnabled(hotKey, false) }
        }
    }

    static func uuid(of screen: NSScreen?) -> String? {
        guard let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, u) as String?
    }
}
