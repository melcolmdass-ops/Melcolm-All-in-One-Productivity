import AppKit
import Carbon

/// Every setting in one place. Stored in UserDefaults; views read them with @AppStorage.
enum Prefs {
    static let defaults: [String: Any] = [
        // Menu bar
        "islandSize": "large",         // icon size: small / medium / large (capped by the bar height)
        "heightMode": "menu",          // menu = match the menu bar, custom = customHeight
        "customHeight": 34.0,
        "allDisplays": false,          // one island on every display
        "barShowTimer": true,
        "barShowMusic": true,
        "liveActivities": true,        // song / output / timer pop-ups under the bar
        // Spaces
        "indicatorStyle": "glow",      // glow / box
        "showNumbers": true,
        "showAppIcons": true,
        "dimOthers": false,            // false = every icon bright, the app in use underlined
        "maxIcons": 4,
        "iconClick": "app",            // app = open that app, space = only go to the Space
        // Mouse
        "hoverToOpen": false,
        "hoverPeek": true,             // rest on the island to see a one-line summary
        "scrollVolume": true,          // scroll on the right half = volume
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
    static func iconSize(_ size: String) -> CGFloat { size == "small" ? 16 : size == "large" ? 24 : 20 }
    /// The chosen icon size, shrunk if needed so it fits inside the bar.
    static func icon(forBar h: CGFloat) -> CGFloat {
        min(iconSize(Prefs.d.string(forKey: "islandSize") ?? "large"), max(14, h - 5))
    }
    static let chipGap: CGFloat = 8
    static let iconGap: CGFloat = 7
    static let numberWidth: CGFloat = 12
    static let overflowWidth: CGFloat = 18

    static let dividerGap: CGFloat = 9

    static func shownCount(_ apps: Int) -> Int {
        Prefs.bool("showAppIcons") ? min(apps, Prefs.d.integer(forKey: "maxIcons")) : 0
    }

    /// One Space inside a display box: its icons (or a dot if empty), plus +n.
    static func segmentWidth(apps: Int, icon: CGFloat) -> CGFloat {
        let n = shownCount(apps)
        var w = n == 0 ? 8 : CGFloat(n) * icon + CGFloat(n - 1) * iconGap
        if Prefs.bool("showAppIcons") && apps > n { w += iconGap + overflowWidth }
        return w + 10
    }

    /// One display box: number, then each Space separated by a thin divider.
    static func groupWidth(_ g: DisplayGroup, _ m: SpacesModel, icon: CGFloat) -> CGFloat {
        let segs = g.spaces.map { segmentWidth(apps: m.apps[$0.id]?.count ?? 0, icon: icon) }
        let num = Prefs.bool("showNumbers") ? numberWidth : 6
        return 10 + num + 6 + segs.reduce(0, +) + CGFloat(max(0, segs.count - 1)) * dividerGap + 6
    }

    static func stripWidth(_ m: SpacesModel, icon: CGFloat) -> CGFloat {
        let w = m.displays.map { groupWidth($0, m, icon: icon) }
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
