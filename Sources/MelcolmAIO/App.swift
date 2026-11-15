import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var page: PanelPage = .home
    @Published var notchWidth: CGFloat = 0     // 0 = this screen has no notch
    @Published var barHeight: CGFloat = 32
    @Published var leftWing: CGFloat = 130
    @Published var rightWing: CGFloat = 130
    @Published var peek: Peek?
    @Published var peekExtra: CGFloat = 0     // room added on each side for the hover bar; the top bar never moves
    @Published var iconSize: CGFloat = 20
    /// True when the app's menus reach the notch: the Spaces strip moves right of the notch so no menu is covered.
    @Published var stripRight = false
    /// Collapsed, the island sits beside the notch instead of wrapping around it, so it is as short as on any other screen.
    var collapsedWidth: CGFloat { leftWing + rightWing }
    /// The open panel is centred, so on a notched screen it is symmetric around the notch.
    var expandedWidth: CGFloat {
        max(AppDelegate.expandedSize.width, notchWidth > 0 ? 2 * max(leftWing, rightWing) + notchWidth : collapsedWidth)
    }

    struct Peek: Equatable {
        var text: String
        var icon: String
        var value: Double? = nil
        var image: NSImage? = nil
        var kind: Kind = .text
        enum Kind { case text, volumeBrightness, shortcuts, media }
        var height: CGFloat { kind == .text ? AppDelegate.peekHeight : 40 }
    }
}

/// Lets the very first click land on a button instead of just focusing the panel.
final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let sound = SoundModel()
    let playing = NowPlayingModel()
    let timer = TimerModel()
    let system = SystemModel()
    let levels = AudioLevels()
    let batteries = BatteryModel()
    let network = NetworkModel()
    let focus = FocusModel()
    var islands: [Island] = []
    var bag = Set<AnyCancellable>()
    static let expandedSize = CGSize(width: 480, height: 480)
    static let peekHeight: CGFloat = 28

    func applicationDidFinishLaunching(_ note: Notification) {
        let ds = UserDefaults.standard.double(forKey: "debugSeek")
        if ds > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.playing.seek(ds) } }
        if UserDefaults.standard.bool(forKey: "debugSpacesDry") { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Tiler.minimizeSpaces(dry: true) } }
        Prefs.register()
        Tiler.watch()
        NSApp.setActivationPolicy(.accessory)
        rebuildIslands()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildIslands()
        }
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reloadHotkeys(); self?.rebuildIslands() }
            .store(in: &bag)
        reloadHotkeys()
        // Only listen to the sound while music is playing and the wave is on.
        playing.$playing.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] on in
            guard let self else { return }
            on && Prefs.bool("barShowMusic") ? levels.start() : levels.stop()
        }.store(in: &bag)

        // Live activities: a short pop-up under the bar when something changes.
        playing.onTrackChange = { [weak self] title, artist in
            guard let self, Prefs.bool("liveActivities"), Prefs.bool("popSong") else { return }
            islands.forEach { $0.peek(.init(text: artist.isEmpty ? title : "\(title) · \(artist)", icon: "music.note", image: self.playing.artwork)) }
        }
        sound.onDeviceChange = { [weak self] name in
            guard let self, Prefs.bool("liveActivities"), Prefs.bool("popOutput") else { return }
            islands.forEach { $0.peek(.init(text: "Sound now on \(name)", icon: name.localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "speaker.wave.2.fill")) }
        }
        timer.onFinish = { [weak self] in
            guard Prefs.bool("liveActivities"), Prefs.bool("popTimer") else { return }
            self?.islands.forEach { $0.peek(.init(text: "Timer done", icon: "bell.fill")) }
        }
        // Charging plugged in / unplugged, and a low-battery warning at 20% and 10%.
        var lastCharging: Bool?; var warned = 100
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, Prefs.bool("liveActivities") else { return }
            system.refreshPower()
            let c = system.charging, b = system.battery ?? 100
            if let l = lastCharging, l != c, Prefs.bool("popCharge") {
                islands.forEach { $0.peek(.init(text: c ? "Charging · \(b)%" : "On battery · \(b)%", icon: c ? "battery.100percent.bolt" : "battery.75percent")) }
            }
            lastCharging = c
            if c { warned = 100 }
            else if Prefs.bool("popBattery"), let level = [20, 10].first(where: { b <= $0 && warned > $0 }) {
                warned = level
                islands.forEach { $0.peek(.init(text: "Battery low · \(b)%", icon: "battery.25percent"), for: 5) }
            }
        }
        // Focus started / ended.
        focus.$active.removeDuplicates().dropFirst().receive(on: RunLoop.main).sink { [weak self] id in
            guard let self, Prefs.bool("liveActivities"), Prefs.bool("popFocus") else { return }
            let m = focus.modes.first { $0.id == id }
            islands.forEach { $0.peek(.init(text: m.map { "\($0.name) on" } ?? "Focus off", icon: m?.icon ?? "moon")) }
        }.store(in: &bag)

        // Keyboard control while a panel is open from ⌃⌥Space.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let open = self?.islands.first(where: { $0.state.expanded }) else { return e }
            return open.handleKey(e) ? nil : e
        }
        // Scrolling over an island: left = Spaces, right = volume.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            self?.islands.first { $0.panel.frame.contains(NSEvent.mouseLocation) }?.scrolled(e); return e
        }
        // Light polling for the bits macOS doesn't notify about.
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.sound.refreshMic() }
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            playing.refresh()
            if islands.contains(where: { $0.state.expanded }) { system.refresh(); sound.refresh() }
        }
        playing.refresh()
        // For testing: `open … --args -debugOpen Settings` opens the panel on launch (not saved).
        if let t = UserDefaults.standard.string(forKey: "debugOpen"), let i = islands.first {
            i.state.page = PanelPage.allCases.first { $0.rawValue.lowercased() == t.lowercased() } ?? .home; i.setExpanded(true)
        }
    }

    /// One island on the main display, or one on every display if that setting is on.
    func rebuildIslands() {
        let wanted = Prefs.bool("allDisplays") ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        let ids = wanted.map(Island.id(of:))
        islands.filter { !ids.contains($0.screenID) }.forEach { $0.close() }
        islands.removeAll { !ids.contains($0.screenID) }
        for s in wanted where !islands.contains(where: { $0.screenID == Island.id(of: s) }) {
            islands.append(Island(screen: s, app: self))
        }
        islands.forEach { $0.measureScreen(); $0.relayout() }
        BrowserMedia.log("islands=\(islands.count) frames=\(islands.map { $0.panel.frame }) visible=\(islands.map { $0.panel.isVisible }) screens=\(NSScreen.screens.map { $0.frame })")
    }

    func closeOthers(except keep: Island) { islands.filter { $0 !== keep && $0.state.expanded }.forEach { $0.setExpanded(false) } }

    /// The island on the screen the mouse is on (for ⌃⌥ shortcuts).
    var activeIsland: Island? {
        let m = NSEvent.mouseLocation
        return islands.first { $0.screen?.frame.contains(m) == true } ?? islands.first
    }

    func reloadHotkeys() {
        Hotkeys.reload(actions: [
            "toggle": { [weak self] in self?.activeIsland?.toggle() },
            "play": { [weak self] in self?.playing.playPause() },
            "next": { [weak self] in self?.playing.next() },
            "prev": { [weak self] in self?.playing.previous() },
            "volUp": { [weak self] in self?.sound.nudge(0.06) },
            "volDown": { [weak self] in self?.sound.nudge(-0.06) },
            "mute": { [weak self] in self?.sound.toggleMute() },
        ], jump: { [weak self] n in self?.activeIsland?.spaces.jump(toNumber: n) })
    }
}

/// One island on one display. Sound, music, timer and status are shared; Spaces are per display.
final class Island: NSObject {
    let screenID: CGDirectDisplayID
    let state = IslandState()
    let spaces: SpacesModel
    unowned let app: AppDelegate
    var sound: SoundModel { app.sound }
    var playing: NowPlayingModel { app.playing }
    var timer: TimerModel { app.timer }
    var system: SystemModel { app.system }
    var panel: IslandPanel!
    var clickMonitor: Any?

    var screenBar: CGFloat = 24
    var openedByHover = false
    var hovering = false
    var scrollAccum: CGFloat = 0
    var lastScrollSwitch = Date.distantPast
    var bag = Set<AnyCancellable>()

    static var expandedSize: CGSize { AppDelegate.expandedSize }
    var peekToken = 0
    var hoverPeek = false
    var hoverWatch: Timer?
    var previousApp: NSRunningApplication?

    var screen: NSScreen? { NSScreen.screens.first { Island.id(of: $0) == screenID } }
    static func id(of s: NSScreen) -> CGDirectDisplayID { (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0 }

    private var spaceBag = Set<AnyCancellable>()
    init(screen: NSScreen, app: AppDelegate) {
        let sid = Island.id(of: screen)
        screenID = sid
        self.app = app
        spaces = SpacesModel(screen: { NSScreen.screens.first { Island.id(of: $0) == sid } })
        super.init()
        // Which Space you're on, after a switch.
        spaces.$currentID.removeDuplicates().dropFirst().receive(on: RunLoop.main).sink { [weak self] (id: Int) in
            guard let self, Prefs.bool("liveActivities"), Prefs.bool("popSpace"),
                  let s = spaces.spaces.first(where: { $0.id == id }) else { return }
            let name = spaces.apps[id]?.first?.name
            peek(.init(text: s.isFullscreen ? (name ?? "Full screen") : "Desktop \(s.number)", icon: "square.on.square"), for: 1.2)
        }.store(in: &spaceBag)
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        let root = IslandView(toggle: { [weak self] in self?.toggle() },
                              hover: { [weak self] in self?.hover($0) },
                              openPage: { [weak self] p in
                                  guard let self else { return }
                                  state.page = p
                                  if !state.expanded { setExpanded(true) }
                              })
            .environmentObject(state).environmentObject(spaces).environmentObject(app.sound)
            .environmentObject(app.playing).environmentObject(app.timer).environmentObject(app.system).environmentObject(app.levels).environmentObject(app.batteries).environmentObject(app.network).environmentObject(app.focus)
        panel.contentView = FirstClickHostingView(rootView: root)
        // When the window grows for the hover bar, keep what's already drawn pinned to the top
        // and redraw during the resize, so the top bar never drops down and springs back.
        panel.contentView?.wantsLayer = true
        panel.contentView?.layerContentsPlacement = .top
        panel.contentView?.layerContentsRedrawPolicy = .duringViewResize
        measureScreen()
        relayout()
        panel.orderFrontRegardless()
        Publishers.MergeMany(
            spaces.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            app.timer.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            app.playing.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            app.sound.$micInUse.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.relayout() }
        .store(in: &bag)
        // Menus are built a moment after an app comes forward; look again then.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .delay(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &bag)
    }

    func close() { setExpanded(false); panel.orderOut(nil); bag.removeAll() }

    func measureScreen() {
        guard let screen else { return }
        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            state.notchWidth = screen.frame.width - l.width - r.width
            screenBar = top
        } else {
            state.notchWidth = 0
            screenBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        }
    }

    /// Sizes the collapsed island to fit the Spaces strip and the live bits on the right.
    var icon: CGFloat = 20
    var barH: CGFloat { Prefs.d.string(forKey: "heightMode") == "custom" ? CGFloat(Prefs.d.double(forKey: "customHeight")) : screenBar }

    func relayout() {
        state.iconSize = Layout.icon(forBar: barH)
        let left = 14 + Layout.stripWidth(spaces, icon: Layout.icon(forBar: barH)) + 12
        var right: CGFloat = 10 + 40 + 12 + 12                // chevron box + divider
        switch BarActivity.current(timerOn: timer.isActive, musicOn: playing.playing) {
        case .timer: right += 92
        case .music: right += 66                                            // music note + wave
        case nil: break
        }
        if app.sound.micInUse { right += 30 }                                   // microphone icon
        let h = Prefs.d.string(forKey: "heightMode") == "custom" ? CGFloat(Prefs.d.double(forKey: "customHeight")) : screenBar
        icon = Layout.icon(forBar: h)
        // Each island is only as wide as its own content, so it fits whatever screen it is on.
        // If the front app's menus run up to the notch, don't cover them: put the strip on the right.
        // Always centred on the middle of the screen (the notch): both sides equally wide.
        if state.stripRight { state.stripRight = false }
        let wing = state.notchWidth > 0 ? max(left, right) : 0
        if wing > 0 { set(&state.leftWing, wing); set(&state.rightWing, wing) }
        else { set(&state.leftWing, left); set(&state.rightWing, right) }
        set(&state.barHeight, h)
        let minPeek: CGFloat = state.peek?.kind == .text || state.peek == nil ? 300 : 360
        let baseW = state.collapsedWidth + state.notchWidth
        // Give the hover bar room to breathe, without moving the top bar.
        set(&state.peekExtra, state.peek != nil && baseW < minPeek ? (minPeek - baseW) / 2 : 0)
        let f = frame(expanded: state.expanded)
        if !state.expanded, f != panel.frame {
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0; c.allowsImplicitAnimation = false
                panel.setFrame(f, display: false)
                panel.contentView?.layoutSubtreeIfNeeded()
                panel.displayIfNeeded()
            }
        }
    }

    private func set(_ v: inout CGFloat, _ n: CGFloat) { if abs(v - n) > 0.5 { v = n } }

    func frame(expanded: Bool) -> NSRect {
        guard let screen else { return .zero }
        let size = expanded
            ? CGSize(width: state.expandedWidth, height: AppDelegate.expandedSize.height)
            : CGSize(width: state.collapsedWidth + state.notchWidth + 2 * state.peekExtra,
                     height: state.barHeight + (state.peek?.height ?? 0))
        // Centred on every screen; on a notched screen it straddles the notch.
        // Collapsed on a notched screen, each side is only as wide as its content.
        let x = !expanded && state.notchWidth > 0
            ? screen.frame.midX - state.notchWidth / 2 - state.leftWing - state.peekExtra
            : screen.frame.midX - size.width / 2
        return NSRect(x: x.rounded(), y: screen.frame.maxY - size.height, width: size.width.rounded(), height: size.height)
    }

    func toggle() {
        openedByHover = false
        let opening = !state.expanded
        setExpanded(opening)
        if opening { app.closeOthers(except: self); previousApp = NSWorkspace.shared.frontmostApplication; panel.makeKey() }
    }

    /// Shows a short pop-up under the bar. `for: 0` keeps it until hover ends.
    func peek(_ p: IslandState.Peek, for seconds: Double = 3) {
        guard !state.expanded else { return }
        peekToken += 1; let token = peekToken
        state.peek = p
        relayout()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { objectWillChangeIsland() }
        guard seconds > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, peekToken == token, !hoverPeek else { return }
            endPeek()
        }
    }

    func endPeek() {
        guard state.peek != nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { state.peek = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.relayout() }
    }

    private func objectWillChangeIsland() { state.objectWillChange.send() }

    /// What the island says when you rest the mouse on it.
    var summary: IslandState.Peek {
        if timer.isActive { return .init(text: "\(timer.mode.rawValue) · \(timer.display)", icon: "timer") }
        if !playing.title.isEmpty { return .init(text: "\(playing.title) · \(playing.artist)", icon: "music.note", image: playing.artwork) }
        system.refresh()
        let b = system.battery.map { "Battery \($0)%" } ?? "Power adapter"
        return .init(text: "\(b) · \(sound.outputName)", icon: system.charging ? "battery.100percent.bolt" : "battery.75percent")
    }

    /// What the hover bar shows, chosen in Settings ▸ Hover bar.
    var hoverBar: IslandState.Peek {
        var mode = Prefs.d.string(forKey: "hoverBarMode") ?? "smart"
        // Smart: music controls while a song plays, otherwise the one-line summary.
        if mode == "smart" { mode = playing.playing && !timer.isActive ? "media" : "summary" }
        switch mode {
        case "volumeBrightness": return .init(text: "", icon: "", kind: .volumeBrightness)
        case "shortcuts": return .init(text: "", icon: "", kind: .shortcuts)
        case "media": return .init(text: "", icon: "", kind: .media)
        default: return summary
        }
    }

    func handleKey(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 53: if state.page != .home { state.page = .home } else { setExpanded(false) }; return true   // esc: back, then close
        case 49: playing.playPause(); return true                       // space
        case 126: sound.nudge(0.06); return true                        // up
        case 125: sound.nudge(-0.06); return true                       // down
        case 123: spaces.step(-1); return true                          // left
        case 124: spaces.step(1); return true                           // right
        default:
            if let c = e.charactersIgnoringModifiers, let n = Int(c), n > 0 { spaces.jump(toNumber: n); return true }
            if e.charactersIgnoringModifiers == "," { state.page = state.page == .settings ? .home : .settings; return true }
            return false
        }
    }

    func hover(_ inside: Bool) {
        hovering = inside
        if !Prefs.bool("hoverToOpen") {
            // Hover bar: appears right away. It then stays for as long as the mouse is anywhere on it
            // (the timer checks the real mouse position, so gaps between things never close it).
            guard inside, Prefs.bool("hoverPeek"), !state.expanded, !hoverPeek else { return }
            hoverPeek = true; peek(hoverBar, for: 0)
            hoverWatch?.invalidate()
            hoverWatch = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] t in
                guard let self else { t.invalidate(); return }
                let m = NSEvent.mouseLocation
                if state.expanded || !hoverPeek { t.invalidate(); return }
                if !panel.frame.insetBy(dx: -2, dy: -2).contains(m) { t.invalidate(); hoverPeek = false; endPeek() }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.18 : 0.4)) { [weak self] in
            guard let self, hovering == inside else { return }
            if inside, !state.expanded { openedByHover = true; setExpanded(true) }
            else if !inside, state.expanded, openedByHover { openedByHover = false; setExpanded(false) }
        }
    }

    func scrolled(_ e: NSEvent) {
        guard !state.expanded, panel.frame.contains(NSEvent.mouseLocation) else { return }
        // The hover bar you chose stays put: scrolling on it adjusts it instead of swapping in the volume pop-up.
        let inBarRow = NSEvent.mouseLocation.y < panel.frame.maxY - state.barHeight
        if hoverPeek, let k = state.peek?.kind, k != .text, inBarRow {
            let d = abs(e.scrollingDeltaY) >= abs(e.scrollingDeltaX) ? e.scrollingDeltaY : -e.scrollingDeltaX
            let step = (e.hasPreciseScrollingDeltas ? d / 300 : d / 30) * (e.isDirectionInvertedFromDevice ? 1 : -1) * -1
            if k == .volumeBrightness, NSEvent.mouseLocation.x > panel.frame.midX, let b = system.brightness {
                system.setBrightness(min(1, max(0, b + step)))
            } else if k == .volumeBrightness || Prefs.bool("scrollVolume") { sound.nudge(step) }
            return
        }
        // Right half of the island = volume, left half = Spaces.
        if NSEvent.mouseLocation.x > (state.notchWidth > 0 ? (screen?.frame.midX ?? panel.frame.midX) : panel.frame.midX) {
            guard Prefs.bool("scrollVolume") else { return }
            let d = abs(e.scrollingDeltaY) >= abs(e.scrollingDeltaX) ? e.scrollingDeltaY : -e.scrollingDeltaX
            let step = (e.hasPreciseScrollingDeltas ? d / 300 : d / 30) * (e.isDirectionInvertedFromDevice ? 1 : -1) * -1
            sound.nudge(step)
            if hoverPeek { return }   // keep whichever hover bar is showing
            hoverPeek = false
            peek(.init(text: "", icon: sound.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", value: sound.volume), for: 1.2)
            return
        }
        guard Prefs.bool("scrollSwitches") else { return }
        let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? -e.scrollingDeltaX : -e.scrollingDeltaY
        scrollAccum += e.hasPreciseScrollingDeltas ? d : d * 10
        guard abs(scrollAccum) > 30, Date().timeIntervalSince(lastScrollSwitch) > 0.45 else { return }
        spaces.step(scrollAccum > 0 ? 1 : -1)
        scrollAccum = 0; lastScrollSwitch = Date()
    }

    func setExpanded(_ open: Bool) {
        if open {
            state.peek = nil; hoverPeek = false; hoverWatch?.invalidate()
            panel.setFrame(frame(expanded: true), display: true)
            // Animate first; the slow refreshes (browser scan etc.) wait until the panel is already moving.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { state.expanded = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                guard let self, state.expanded else { return }
                sound.refresh(); system.refresh(); playing.refresh()
            }
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, Prefs.bool("closeOnClickOutside"), !panel.frame.contains(NSEvent.mouseLocation) else { return }
                setExpanded(false)
            }
        } else {
            if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
            if panel.isKeyWindow { panel.resignKey(); previousApp?.activate(); previousApp = nil }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.94)) { state.expanded = false; state.page = .home }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                guard let self, !state.expanded else { return }
                panel.setFrame(frame(expanded: false), display: true)
            }
        }
    }
}

enum LaunchAtLogin {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

/// Where the front app's menus end, read through Accessibility (only on the menu-bar screen).
enum MenuBar {
    static func rightEdge(below limit: CGFloat) -> CGFloat? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.menuBarOwningApplication ?? NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.15)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXMenuBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let items = kids as? [AXUIElement] else { return nil }
        var end: CGFloat?
        for i in items {
            var pv: CFTypeRef?, sv: CFTypeRef?
            guard AXUIElementCopyAttributeValue(i, kAXPositionAttribute as CFString, &pv) == .success,
                  AXUIElementCopyAttributeValue(i, kAXSizeAttribute as CFString, &sv) == .success else { continue }
            var p = CGPoint.zero, sz = CGSize.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &sz)
            guard p.y < 40, p.x < limit, sz.width > 0 else { continue }
            end = max(end ?? 0, p.x + sz.width)
        }
        return end
    }
}
