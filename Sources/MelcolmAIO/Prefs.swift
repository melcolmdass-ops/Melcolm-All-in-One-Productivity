import AppKit
import Carbon

/// Every setting in one place. Stored in UserDefaults; views read them with @AppStorage.
enum Prefs {
    static let defaults: [String: Any] = [
        // Menu bar
        "islandSize": "medium",        // small / medium / large
        "barShowTimer": true,
        "barShowMusic": true,
        // Spaces
        "indicatorStyle": "glow",      // glow / box
        "showNumbers": true,
        "showAppIcons": true,
        "maxIcons": 4,
        "iconClick": "app",            // app = open that app, space = only go to the Space
        // Mouse
        "hoverToOpen": false,
        "scrollSwitches": true,
        "closeOnClickOutside": true,
        // Keyboard
        "hotkeyToggle": true,          // ⌃⌥Space opens/closes the island
        "hotkeyNumbers": true,         // ⌃⌥1…9 jumps to that Space
    ]

    static func register() { UserDefaults.standard.register(defaults: defaults) }
    static func reset() { defaults.keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    static var d: UserDefaults { .standard }
    static func bool(_ k: String) -> Bool { d.bool(forKey: k) }
}

/// Sizes shared by the view and the window, so the window always fits the strip exactly.
enum Layout {
    static func iconSize(_ size: String) -> CGFloat { size == "small" ? 16 : size == "large" ? 26 : 20 }
    static var icon: CGFloat { iconSize(Prefs.d.string(forKey: "islandSize") ?? "medium") }
    static let chipGap: CGFloat = 5
    static let numberWidth: CGFloat = 12
    static let overflowWidth: CGFloat = 18

    /// Width of one Space box: [number] [icons…] [+n]
    static func chipWidth(_ space: SpaceItem, apps: Int) -> CGFloat {
        let showIcons = Prefs.bool("showAppIcons")
        let shown = showIcons ? min(apps, Prefs.d.integer(forKey: "maxIcons")) : 0
        let overflow = showIcons && apps > shown
        var parts: [CGFloat] = []
        if !space.isFullscreen || shown == 0 { parts.append(Prefs.bool("showNumbers") ? numberWidth : 6) }
        parts += Array(repeating: icon, count: shown)
        if overflow { parts.append(overflowWidth) }
        let inner = parts.reduce(0, +) + CGFloat(max(0, parts.count - 1)) * 4
        return max(icon + 10, inner + 14)
    }

    static func stripWidth(_ m: SpacesModel) -> CGFloat {
        let w = m.spaces.map { chipWidth($0, apps: m.apps[$0.id]?.count ?? 0) }
        return w.reduce(0, +) + CGFloat(max(0, w.count - 1)) * chipGap
    }
}

/// System-wide shortcuts (Carbon hotkeys don't need any permission).
private var hotkeyActions: [UInt32: () -> Void] = [:]

enum Hotkeys {
    private static var refs: [EventHotKeyRef] = []
    private static var installed = false
    // Key codes for 1…9 on the top row.
    private static let digitCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    static func reload(toggle: @escaping () -> Void, jump: @escaping (Int) -> Void) {
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { hotkeyActions[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []; hotkeyActions = [:]
        let mods = UInt32(controlKey | optionKey)
        func add(_ id: UInt32, _ code: UInt32, _ action: @escaping () -> Void) {
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(code, mods, EventHotKeyID(signature: OSType(0x4D4C434D), id: id), GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref); hotkeyActions[id] = action
            }
        }
        if Prefs.bool("hotkeyToggle") { add(100, 49, toggle) }
        if Prefs.bool("hotkeyNumbers") { for (i, c) in digitCodes.enumerated() { add(UInt32(i + 1), c) { jump(i + 1) } } }
    }
}
