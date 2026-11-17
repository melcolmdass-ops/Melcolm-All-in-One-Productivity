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
    /// How many display boxes sit left of the notch (the rest go right). 0 when menus would be covered.
    @Published var leftDisplays = 1
    /// Collapsed, the island sits beside the notch instead of wrapping around it, so it is as short as on any other screen.
    var displayID: CGDirectDisplayID = 0
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
        if UserDefaults.standard.bool(forKey: "debugToggle") {
            for (i, t) in [8.0, 14.0, 20.0].enumerated() { DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                BrowserMedia.log("debugToggle \(i) app=\(self.playing.app) playing=\(self.playing.playing) main=\(String(describing: self.playing.mainResult))")
                self.playing.playPause()
            } }
        }
        if UserDefaults.standard.bool(forKey: "debugSpacesDry") { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Tiler.minimizeSpaces(dry: true) } }
        Prefs.register()
        Tiler.watch()
        NSApp.setActivationPolicy(.accessory)
        rebuildIslands()
        OptionDrag.shared.islands = { [weak self] in
            (self?.islands ?? []).compactMap { i in i.panel.map { ($0.frame, i.screenID, SpacesModel.uuid(of: i.screen), i.spaces) } }
        }
        OptionDrag.shared.onDropToBar = { [weak self] screen, name in
            guard let i = self?.islands.first(where: { $0.screenID == screen }) ?? self?.islands.first else { return }
            i.peek(.init(text: "\(name) → new Space", icon: "plus.rectangle.on.rectangle"), for: 2.2)
        }
        SpaceDragModel.shared.onHint = { [weak self] screen, text in
            guard let i = self?.islands.first(where: { $0.screenID == screen }) ?? self?.islands.first else { return }
            if let text { i.peek(.init(text: text, icon: "macwindow.and.arrow.down"), for: 0) } else { i.endPeek() }
        }
        OptionDrag.shared.start()
        Installed.loadShortcuts()
        // For testing: `-debugFocusOverlay YES` shows the focus feedback with what's running now.
        if UserDefaults.standard.bool(forKey: "debugFocusOverlay") {
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.prefix(6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                FocusOverlay.show(title: "Focus. Let's go, Melcolm.", icon: "brain.head.profile", steps: [
                    .init(icon: "eye.slash.fill", tint: .orange, verb: "Hid", all: "all other apps", apps: Array(apps)),
                    .init(icon: "cup.and.saucer.fill", tint: .yellow, verb: "Keeping", all: "the screen awake"),
                    .init(icon: "timer", tint: .cyan, verb: "Started", all: "a 50 min timer")], showApps: true)
                if let m = self.focus.modes.first { self.focus.active = m.id; DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.focus.active = nil } }
                FocusDone.show("Deep Work workflow completed", icon: "brain.head.profile")
            }
        }
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
            // A focus with a timer ends by itself when the time is up.
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
            guard let m = focus.modes.first(where: { $0.id == id }) else { return }   // flows end with their own "completed" pop-up
            islands.forEach { $0.peek(.init(text: "Running \(m.name)…", icon: m.icon)) }
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
        // For testing: `--args -debugPressTest YES -debugLog YES` presses Play/Pause once, then again to put it back.
        if UserDefaults.standard.bool(forKey: "debugPressTest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, let r = playing.others.first(where: { $0.url.contains("music.youtube") }) ?? playing.mainResult else { return }
                BrowserMedia.log("TEST press 1 shown=\(playing.isPlaying(r))")
                playing.toggle(r)
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    let now = self.playing.others.first { $0.id == r.id }
                    BrowserMedia.log("TEST after 6s shown=\(now.map { self.playing.isPlaying($0) } ?? false)")
                    if let now { BrowserMedia.log("TEST press 2"); self.playing.toggle(now) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                        BrowserMedia.log("TEST end shown=\(self.playing.others.first { $0.id == r.id }.map { self.playing.isPlaying($0) } ?? false)")
                    }
                }
            }
        }
        // For testing a drag move: `--args -debugMove "<space id>:<slot or -1 for desktop>:<display uuid>"`.
        if let t = UserDefaults.standard.string(forKey: "debugMove"), let i = islands.first {
            let p = t.split(separator: ":").map(String.init)
            if p.count == 3, let id = Int(p[0]), let k = Int(p[1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    BrowserMedia.log("TEST move \(t)")
                    SpaceMover.start(space: id, to: k < 0 ? .desktop(p[2]) : .slot(p[2], k), model: i.spaces)
                }
            }
        }
        // For testing: `-debugDragPreview "<space id>:<slot>:<display uuid>"` holds a pretend drag so the slide can be seen.
        if let t = UserDefaults.standard.string(forKey: "debugDragPreview"), let i = islands.first {
            let p = t.split(separator: ":").map(String.init)
            if p.count >= 3, let id = Int(p[0]), let k = Int(p[1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    let d = SpaceDragModel.shared
                    d.begin(id, model: i.spaces)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { d.offset = CGSize(width: -30, height: 4); d.target = k < 0 ? .desktop(p[2]) : .slot(p[2], k) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + (p.count < 4 ? 4 : 1.2)) { if p.count < 4 { d.target = nil }; d.end(model: i.spaces) }
                }
            }
        }
        // For testing: `-debugRenderDrag <png path>` saves a picture of the Dragging box in Settings.
        if let path = UserDefaults.standard.string(forKey: "debugRenderDrag") {
            let r = ImageRenderer(content: DragZonesCard().frame(width: 430).padding(12).background(Color(white: 0.06))
                .toggleStyle(.switch).controlSize(.small).environment(\.colorScheme, .dark))
            r.scale = 2
            if let t = r.nsImage?.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
        }
        // For testing: `-debugFullWindow "<pid>:<window id>"` puts that window back into full screen.
        if let t = UserDefaults.standard.string(forKey: "debugFullWindow") {
            let p = t.split(separator: ":").compactMap { Int($0) }
            if p.count == 2 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    if let w = SpaceMover.window(pid: pid_t(p[0]), wid: CGWindowID(p[1])) { SpaceMover.setFull(w, true, pid: pid_t(p[0])) }
                    else { BrowserMedia.log("spacemove no window \(t)") }
                }
            }
        }
        // For testing: `open … --args -debugOpen Settings` opens the panel on launch (not saved).
        if let t = UserDefaults.standard.string(forKey: "debugOpen"), let i = islands.first {
            i.state.page = PanelPage.allCases.first { $0.rawValue.lowercased() == t.lowercased() } ?? .home; i.setExpanded(true)
        }
        // For testing: `-debugClicks "x,y;x,y"` (screen points, top-left origin) clicks inside the panel
        // itself, one every 0.9 s, and writes what Settings page is showing after each to /tmp/melcolm-clicks.log.
        if let list = UserDefaults.standard.string(forKey: "debugClicks"), let i = islands.first {
            let pts = list.split(separator: ";").compactMap { s -> CGPoint? in
                let v = s.split(separator: ",").compactMap { Double($0) }; return v.count == 2 ? CGPoint(x: v[0], y: v[1]) : nil }
            let logURL = URL(fileURLWithPath: "/tmp/melcolm-clicks.log"); try? "".write(to: logURL, atomically: true, encoding: .utf8)
            for (k, p) in pts.enumerated() {
                let delay: Double = 1.5 + Double(k) * 0.9
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.debugClick(i, p, logURL) }
            }
        }
    }

    private func debugClick(_ i: Island, _ p: CGPoint, _ logURL: URL) {
        let w: NSPanel = i.panel
        let top: CGFloat = NSScreen.screens[0].frame.maxY
        let local = NSPoint(x: p.x - w.frame.minX, y: top - p.y - w.frame.minY)
        let now: TimeInterval = ProcessInfo.processInfo.systemUptime
        for t: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: t, location: local, modifierFlags: [], timestamp: now, windowNumber: w.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { w.sendEvent(e) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let pg: String = UserDefaults.standard.string(forKey: "settingsPage") ?? "-"
            let line: String = "\(Int(p.x)),\(Int(p.y)) page=\(pg) open=\(i.state.expanded)\n"
            if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
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
        // Master Rule: while typing in one of our text boxes, only the open/close hotkey works.
        let g = { (f: @escaping () -> Void) -> () -> Void in { if !Island.typing(in: NSApp.keyWindow) { f() } } }
        Hotkeys.reload(actions: [
            "toggle": { [weak self] in self?.activeIsland?.toggle() },
            "play": g { [weak self] in self?.playing.playPause() },
            "next": g { [weak self] in self?.playing.next() },
            "prev": g { [weak self] in self?.playing.previous() },
            "volUp": g { [weak self] in self?.sound.nudge(0.06) },
            "volDown": g { [weak self] in self?.sound.nudge(-0.06) },
            "mute": g { [weak self] in self?.sound.toggleMute() },
        ], jump: { [weak self] n in if !Island.typing(in: NSApp.keyWindow) { self?.activeIsland?.spaces.jump(toNumber: n) } })
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
    var closeToken = 0

    var screen: NSScreen? { NSScreen.screens.first { Island.id(of: $0) == screenID } }
    static func id(of s: NSScreen) -> CGDirectDisplayID { (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0 }

    private var spaceBag = Set<AnyCancellable>()
    init(screen: NSScreen, app: AppDelegate) {
        let sid = Island.id(of: screen)
        screenID = sid
        self.app = app
        state.displayID = sid
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
            app.focus.$active.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.relayout() }
        .store(in: &bag)
        // Master rule: opening anything outside (a link, an app, the artwork) closes the panel.
        NotificationCenter.default.publisher(for: .melcolmOpenedOutside)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if state.expanded { setExpanded(false, restoreFocus: false) }
                if state.peek != nil { endPeek() }
            }
            .store(in: &bag)
        // Always on every Space: macOS sometimes leaves an all-Spaces window off a newly made
        // full-screen / Split View Space (Claude, Premiere…). Re-show it on each switch and check every second.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .merge(with: Timer.publish(every: 1, on: .main, in: .common).autoconnect().map { _ in Notification(name: .init("tick")) })
            .receive(on: RunLoop.main)
            .sink { [weak self] n in
                guard let self, let p = panel else { return }
                if n.name.rawValue != "tick" || !p.isOnActiveSpace || !p.isVisible {
                    p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
                    p.orderFrontRegardless()
                }
            }
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
        let ic = Layout.icon(forBar: barH)
        var status: CGFloat = 40 + 12                                       // arrow + divider
        switch BarActivity.current(timerOn: timer.isActive, musicOn: playing.playing) {
        case .timer: status += 92
        case .music: status += 66                                           // music note + wave
        case nil: status -= 12
        }
        if app.sound.micInUse { status += 30 }                                  // microphone icon
        if app.focus.active != nil { status += 136 }                            // running focus workflow
        let h = Prefs.d.string(forKey: "heightMode") == "custom" ? CGFloat(Prefs.d.double(forKey: "customHeight")) : screenBar
        icon = Layout.icon(forBar: h)
        let groups = spaces.displays.map { Layout.groupWidth($0, icon: ic, m: spaces) }
        func strip(_ g: ArraySlice<CGFloat>) -> CGFloat { g.reduce(0, +) + CGFloat(max(0, g.count - 1)) * Layout.chipGap }
        if state.notchWidth > 0, let screen {
            // Display 1 left of the notch, the others right of it; both sides equally wide so it stays centred.
            func wings(_ k: Int) -> (CGFloat, CGFloat) {
                let l = k > 0 ? 24 + strip(groups.prefix(k)) + 18 : 16
                let rest = groups.dropFirst(k)
                let r = 18 + (rest.isEmpty ? 0 : strip(rest) + 8) + status + 24
                return k > 0 ? (max(l, r), max(l, r)) : (l, r)
            }
            var k = groups.isEmpty ? 0 : 1
            // If the front app's menus would run under the left side, every display goes right instead.
            if k > 0,
               let menuEnd = MenuBar.rightEdge(on: screen),
               screen.frame.midX - state.notchWidth / 2 - wings(k).0 < menuEnd + 6 { k = 0 }
            if state.leftDisplays != k { state.leftDisplays = k }
            let (l, r) = wings(k)
            set(&state.leftWing, l); set(&state.rightWing, r)
        } else {
            if state.leftDisplays != groups.count { state.leftDisplays = groups.count }
            set(&state.leftWing, 24 + strip(groups[...]) + 18); set(&state.rightWing, 24 + status + 18)
        }
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
        } else if state.expanded, f != panel.frame {
            // The bar grew/shrank while the panel is open (e.g. the stopwatch started): follow it smoothly.
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.22; c.allowsImplicitAnimation = true
                panel.animator().setFrame(f, display: true)
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
        // MASTER RULE: while you're typing in a text box, keys type. No shortcut fires (space doesn't
        // play music, numbers don't switch Spaces). Only the open/close hotkey still works (it's global).
        if Self.typing(in: e.window ?? panel) { return false }
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

    /// True when the keyboard is in a text box (a text field's editor or any text view).
    static func typing(in w: NSWindow?) -> Bool {
        guard let r = w?.firstResponder else { return false }
        if let tv = r as? NSTextView { return tv.isEditable || tv.isFieldEditor }
        return r is NSTextField || r is NSSearchField
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

    /// `restoreFocus: false` when closing because something else was just opened (it keeps the focus).
    func setExpanded(_ open: Bool, restoreFocus: Bool = true) {
        closeToken += 1; let token = closeToken
        if open {
            state.peek = nil; hoverPeek = false; hoverWatch?.invalidate()
            panel.setFrame(frame(expanded: true), display: true)
            // Animate first; the slow refreshes (browser scan etc.) wait until the panel is already moving.
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84, blendDuration: 0.1)) { state.expanded = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
                guard let self, state.expanded else { return }
                sound.refresh(); system.refresh(); playing.refresh()
            }
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, Prefs.bool("closeOnClickOutside"), !panel.frame.contains(NSEvent.mouseLocation) else { return }
                setExpanded(false)
            }
        } else {
            if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
            if panel.isKeyWindow { panel.resignKey(); if restoreFocus { previousApp?.activate() }; previousApp = nil }
            // The same motion as opening, in reverse: the panel shrinks back up into the notch.
            // The page only resets to Home once it is out of sight, so nothing swaps while it closes.
            withAnimation(.spring(response: 0.36, dampingFraction: 0.95)) { state.expanded = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { [weak self] in
                guard let self, !state.expanded, closeToken == token else { return }
                state.page = .home
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
/// How far the front app's menus (File, Edit, View…) reach on a given screen, read through Accessibility.
/// Menus sit at the same distance from each screen's left edge, so one reading works for every display.
enum MenuBar {
    private static var cache: (pid: pid_t, reach: CGFloat?, at: Date)?
    static func rightEdge(on screen: NSScreen) -> CGFloat? {
        let pid = (NSWorkspace.shared.menuBarOwningApplication ?? NSWorkspace.shared.frontmostApplication)?.processIdentifier ?? 0
        let reach: CGFloat?
        if let c = cache, c.pid == pid, Date().timeIntervalSince(c.at) < 2 { reach = c.reach }
        else { reach = read(); cache = (pid, reach, Date()) }
        return reach.map { screen.frame.minX + $0 }
    }
    /// The right end of the last menu, measured from the left edge of the screen it is on.
    private static func read() -> CGFloat? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.menuBarOwningApplication ?? NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.15)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXMenuBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let items = kids as? [AXUIElement] else { return nil }
        var lo: CGFloat?, hi: CGFloat?
        for i in items {
            var pv: CFTypeRef?, sv: CFTypeRef?
            guard AXUIElementCopyAttributeValue(i, kAXPositionAttribute as CFString, &pv) == .success,
                  AXUIElementCopyAttributeValue(i, kAXSizeAttribute as CFString, &sv) == .success else { continue }
            var p = CGPoint.zero, sz = CGSize.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &sz)
            guard sz.width > 0, sz.height > 0 else { continue }
            lo = min(lo ?? p.x, p.x); hi = max(hi ?? 0, p.x + sz.width)
        }
        guard let lo, let hi else { return nil }
        let host = NSScreen.screens.first { lo >= $0.frame.minX && lo < $0.frame.maxX } ?? NSScreen.screens[0]
        return hi - host.frame.minX
    }
}
