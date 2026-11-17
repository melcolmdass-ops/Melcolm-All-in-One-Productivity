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
        "liveActivities": true,
        "barOrder": "timer,music",     // which live thing the bar shows first (only one fits)
        "batteriesBar": true,          // the batteries row at the bottom of Home
        "batteryHidden": "",        // song / output / timer pop-ups under the bar
        // Spaces
        "indicatorStyle": "glow",      // glow / box
        "boxStyle": "soft",
        "focusDonePopup": true,        // "… flow completed" pop-up when a focus flow finishes
        "focusStopClock": true,        // stopping a focus stops its stopwatch
        "focusShowApps": true,         // stopping a focus shows the apps it hid            // bar boxes: outlined / soft (faint fill) / minimal (nothing)
        "showNumbers": true,
        "showAppIcons": true,
        "optionDrag": true,            // hold a key and drag any window from anywhere; drop on the bar = own Space
        "dragModifier": "option",
        "dragZones": true,             // drop a dragged window on a screen edge/corner to snap it
        "dragSpaces": true,            // drag full-screen apps on the bar to move them
        "dimOthers": false,            // false = every icon bright, the app in use underlined
        "maxIcons": 4,
        "classicSwitching": false,     // false = instant (fast) switching, true = Ctrl-arrow shortcuts with animation
        "iconClick": "app",            // app = open that app, space = only go to the Space
        // Mouse
        "hoverToOpen": false,
        "hoverPeek": true,             // rest on the island to open the hover bar
        "hoverBarMode": "smart",       // smart / summary / volumeBrightness / shortcuts / media
        // Pop-ups under the island when something happens
        "popSong": true, "popOutput": true, "popTimer": true, "popCharge": true, "popBattery": true, "popFocus": true, "popSpace": false,
        "shortcuts": "Google|https://google.com\nChatGPT|https://chatgpt.com\nYouTube|https://youtube.com",
        "scrollVolume": true,          // scroll on the right half = volume
        "scrollSwitches": true,
        "closeOnClickOutside": true,
        // Keyboard
        "cmdMods": "ctrlOpt",          // modifier keys used by every command
        "cmd.play.on": false, "cmd.next.on": false, "cmd.prev.on": false,
        "cmd.volUp.on": false, "cmd.volDown.on": false, "cmd.mute.on": false,
        "hotkeyToggle": true,          // opens/closes the island
        "hotkeyNumbers": true,         // ⌃⌥1…9 jumps to that Space
    ]

    static func register() { UserDefaults.standard.register(defaults: defaults) }
    static func reset() { defaults.keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    static var d: UserDefaults { .standard }
    static func bool(_ k: String) -> Bool { d.bool(forKey: k) }
}

/// The one live thing shown in the bar beside the chevron, picked by your priority order.
enum BarActivity: String, CaseIterable {
    case timer, music
    var title: String { self == .timer ? "Clock (timer / stopwatch)" : "Music" }
    var icon: String { self == .timer ? "timer" : "music.note" }
    var page: PanelPage { self == .timer ? .timer : .nowPlaying }
    var showKey: String { self == .timer ? "barShowTimer" : "barShowMusic" }
    static var order: [BarActivity] {
        var l = (Prefs.d.string(forKey: "barOrder") ?? "").split(separator: ",").compactMap { BarActivity(rawValue: String($0)) }
        for a in allCases where !l.contains(a) { l.append(a) }
        return l
    }
    static func current(timerOn: Bool, musicOn: Bool) -> BarActivity? {
        order.first { Prefs.bool($0.showKey) && ($0 == .timer ? timerOn : musicOn) }
    }
}

/// Sizes shared by the view and the window, so the window always fits the strip exactly.
enum Layout {
    static func iconSize(_ size: String) -> CGFloat { size == "small" ? 20 : size == "large" ? 32 : 26 }
    /// The chosen icon size, shrunk if needed so it fits inside the bar.
    static func icon(forBar h: CGFloat) -> CGFloat {
        min(iconSize(Prefs.d.string(forKey: "islandSize") ?? "large"), max(14, h - 5))
    }
    static let chipGap: CGFloat = 8
    static let cellPad: CGFloat = 5       // room around each icon for its glow outline

    static func desktops(_ g: DisplayGroup) -> [SpaceItem] { g.spaces.filter { !$0.isFullscreen } }
    static func fullscreens(_ g: DisplayGroup) -> [SpaceItem] { g.spaces.filter { $0.isFullscreen } }
    static func numberCell(_ icon: CGFloat) -> CGFloat { Prefs.bool("showNumbers") ? icon * 0.7 + 2 * cellPad : 12 + 2 * cellPad }
    static func iconCell(_ icon: CGFloat, apps: Int = 1) -> CGFloat { CGFloat(apps) * icon + CGFloat(apps - 1) * 3 + 2 * cellPad }
    /// A split-view Space holds two apps; they share one box.
    static func appCount(_ m: SpacesModel?, _ s: SpaceItem) -> Int { max(1, min(2, m?.apps[s.id]?.count ?? 1)) }

    /// One box per display: [desktop number] | [full-screen app icons…]
    static func groupWidth(_ g: DisplayGroup, icon: CGFloat, m: SpacesModel? = nil) -> CGFloat {
        let f = fullscreens(g); let n = f.count
        let cells = f.reduce(CGFloat(0)) { $0 + iconCell(icon, apps: appCount(m, $1)) }
        return 16 + numberCell(icon) + (n > 0 ? 14 : 0) + cells + CGFloat(max(0, n - 1)) * 2
    }

    static func stripWidth(_ m: SpacesModel, icon: CGFloat) -> CGFloat {
        let w = m.displays.map { groupWidth($0, icon: icon, m: m) }
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

    /// Keys you can assign to a command.
    static let keys: [(label: String, code: UInt32)] = [
        ("Space", 49), ("←", 123), ("→", 124), ("↑", 126), ("↓", 125),
        ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14), ("F", 3), ("G", 5), ("H", 4), ("I", 34), ("J", 38), ("K", 40),
        ("L", 37), ("M", 46), ("N", 45), ("O", 31), ("P", 35), ("Q", 12), ("R", 15), ("S", 1), ("T", 17), ("U", 32),
        ("V", 9), ("W", 13), ("X", 7), ("Y", 16), ("Z", 6),
    ]
    struct Command: Identifiable { let id: String; let title: String; let key: String; let on: Bool }
    /// Every command: its name, the key it starts with, and whether it starts switched on.
    static let commands: [Command] = [
        .init(id: "toggle", title: "Open or close the island", key: "Space", on: true),
        .init(id: "play", title: "Play / Pause", key: "P", on: false),
        .init(id: "next", title: "Next track", key: "N", on: false),
        .init(id: "prev", title: "Previous track", key: "B", on: false),
        .init(id: "volUp", title: "Volume up", key: "↑", on: false),
        .init(id: "volDown", title: "Volume down", key: "↓", on: false),
        .init(id: "mute", title: "Mute", key: "M", on: false),
    ]
    static let modifierChoices: [(id: String, label: String, flags: Int)] = [
        ("ctrlOpt", "⌃⌥", controlKey | optionKey), ("ctrlCmd", "⌃⌘", controlKey | cmdKey),
        ("optCmd", "⌥⌘", optionKey | cmdKey), ("ctrlShift", "⌃⇧", controlKey | shiftKey),
    ]
    static func onKey(_ id: String) -> String { id == "toggle" ? "hotkeyToggle" : "cmd.\(id).on" }

    static func reload(actions: [String: () -> Void], jump: @escaping (Int) -> Void) {
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
        let choice = Prefs.d.string(forKey: "cmdMods") ?? "ctrlOpt"
        let mods = UInt32(modifierChoices.first { $0.id == choice }?.flags ?? (controlKey | optionKey))
        func add(_ id: UInt32, _ code: UInt32, _ action: @escaping () -> Void) {
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(code, mods, EventHotKeyID(signature: OSType(0x4D4C434D), id: id), GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref); hotkeyActions[id] = action
            }
        }
        for (i, c) in commands.enumerated() where Prefs.bool(onKey(c.id)) {
            let label = Prefs.d.string(forKey: "cmd.\(c.id).key") ?? c.key
            if let code = keys.first(where: { $0.label == label })?.code, let act = actions[c.id] { add(UInt32(100 + i), code, act) }
        }
        if Prefs.bool("hotkeyNumbers") { for (i, c) in digitCodes.enumerated() { add(UInt32(i + 1), c) { jump(i + 1) } } }
    }
}

extension Notification.Name {
    /// Posted whenever the app opens something outside itself, so the panel can close (a master rule).
    static let melcolmOpenedOutside = Notification.Name("melcolmOpenedOutside")
}
func openedOutside() { NotificationCenter.default.post(name: .melcolmOpenedOutside, object: nil) }
