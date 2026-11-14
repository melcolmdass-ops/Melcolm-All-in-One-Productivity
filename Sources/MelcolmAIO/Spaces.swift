import AppKit

// Private CGS APIs (same ones WhichSpace uses; there is no public alternative).
@_silgen_name("_CGSDefaultConnection") private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ conn: Int32) -> Unmanaged<CFArray>?
@_silgen_name("CGSGetSymbolicHotKeyValue") private func CGSGetSymbolicHotKeyValue(
    _ hotKey: Int32, _ char: UnsafeMutablePointer<UInt16>?, _ keyCode: UnsafeMutablePointer<UInt16>?, _ flags: UnsafeMutablePointer<UInt32>?
) -> Int32
@_silgen_name("CGSIsSymbolicHotKeyEnabled") private func CGSIsSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool
@_silgen_name("CGSSetSymbolicHotKeyEnabled") private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> Int32

struct SpaceItem: Identifiable, Equatable {
    let id: Int
    let number: Int        // 1-based position on this display
    let isFullscreen: Bool
}

final class SpacesModel: ObservableObject {
    @Published var spaces: [SpaceItem] = []
    @Published var currentID: Int = 0

    init() {
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
        guard let raw = CGSCopyManagedDisplaySpaces(_CGSDefaultConnection())?.takeRetainedValue() as? [NSDictionary],
              !raw.isEmpty else { return }
        let wanted = Self.uuid(of: NSScreen.screens.first)
        let display = raw.first { ($0["Display Identifier"] as? String) == wanted }
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
    }

    /// Steps left/right with the "Move left/right a space" shortcuts, which is
    /// the route WhichSpace uses on macOS 27. Needs Accessibility permission.
    func switchTo(_ space: SpaceItem) {
        guard let from = currentIndex, let to = spaces.firstIndex(of: space), from != to else { return }
        guard Self.ensureAccessibility() else { return }
        let right = to > from
        for _ in 0 ..< abs(to - from) { Self.postHotKey(right ? 81 : 79) }
        currentID = space.id // optimistic; refresh confirms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refresh() }
    }

    static func ensureAccessibility() -> Bool {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
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
