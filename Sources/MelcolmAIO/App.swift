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
    @Published var iconSize: CGFloat = 20
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
    var islands: [Island] = []
    var bag = Set<AnyCancellable>()
    static let expandedSize = CGSize(width: 480, height: 480)
    static let peekHeight: CGFloat = 28

    func applicationDidFinishLaunching(_ note: Notification) {
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
            guard let self, Prefs.bool("liveActivities") else { return }
            islands.forEach { $0.peek(.init(text: artist.isEmpty ? title : "\(title) · \(artist)", icon: "music.note", image: self.playing.artwork)) }
        }
        sound.onDeviceChange = { [weak self] name in
            guard let self, Prefs.bool("liveActivities") else { return }
            islands.forEach { $0.peek(.init(text: "Sound now on \(name)", icon: name.localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "speaker.wave.2.fill")) }
        }
        timer.onFinish = { [weak self] in self?.islands.forEach { $0.peek(.init(text: "Timer done", icon: "bell.fill"), for: 5) } }

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
        Hotkeys.reload(toggle: { [weak self] in self?.activeIsland?.toggle() },
                       jump: { [weak self] n in self?.activeIsland?.spaces.jump(toNumber: n) })
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
    var previousApp: NSRunningApplication?

    var screen: NSScreen? { NSScreen.screens.first { Island.id(of: $0) == screenID } }
    static func id(of s: NSScreen) -> CGDirectDisplayID { (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0 }

    init(screen: NSScreen, app: AppDelegate) {
        let sid = Island.id(of: screen)
        screenID = sid
        self.app = app
        spaces = SpacesModel(screen: { NSScreen.screens.first { Island.id(of: $0) == sid } })
        super.init()
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        let root = IslandView(toggle: { [weak self] in self?.toggle() },
                              hover: { [weak self] in self?.hover($0) })
            .environmentObject(state).environmentObject(spaces).environmentObject(app.sound)
            .environmentObject(app.playing).environmentObject(app.timer).environmentObject(app.system).environmentObject(app.levels)
        panel.contentView = FirstClickHostingView(rootView: root)
        measureScreen()
        relayout()
        panel.orderFrontRegardless()
        Publishers.MergeMany(
            spaces.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            app.timer.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            app.playing.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.relayout() }
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
        var right: CGFloat = 10 + 36 + 12                     // chevron
        if timer.isActive && Prefs.bool("barShowTimer") { right += 74 }
        else if playing.playing && Prefs.bool("barShowMusic") { right += 30 }
        if !playing.title.isEmpty { right += 28 }            // mini play button
        let h = Prefs.d.string(forKey: "heightMode") == "custom" ? CGFloat(Prefs.d.double(forKey: "customHeight")) : screenBar
        icon = Layout.icon(forBar: h)
        // Each island is only as wide as its own content, so it fits whatever screen it is on.
        set(&state.leftWing, left); set(&state.rightWing, right)
        set(&state.barHeight, h)
        let minPeek: CGFloat = state.peek?.kind == .text || state.peek == nil ? 300 : 360
        if state.peek != nil, state.notchWidth == 0, state.collapsedWidth < minPeek {
            // Give the pop-up room on screens without a notch.
            let extra = (minPeek - state.collapsedWidth) / 2
            state.leftWing += extra; state.rightWing += extra
        }
        let f = frame(expanded: state.expanded)
        if !state.expanded, f != panel.frame { panel.setFrame(f, display: true) }
    }

    private func set(_ v: inout CGFloat, _ n: CGFloat) { if abs(v - n) > 0.5 { v = n } }

    func frame(expanded: Bool) -> NSRect {
        guard let screen else { return .zero }
        let size = expanded
            ? CGSize(width: state.expandedWidth, height: AppDelegate.expandedSize.height)
            : CGSize(width: state.notchWidth > 0 ? state.collapsedWidth + state.notchWidth : max(state.collapsedWidth, state.peek == nil ? 0 : state.peek!.kind == .text ? 300 : 360),
                     height: state.barHeight + (state.peek?.height ?? 0))
        // Centred on every screen; on a notched screen it straddles the notch.
        // Collapsed on a notched screen, each side is only as wide as its content.
        let x = !expanded && state.notchWidth > 0
            ? screen.frame.midX - state.notchWidth / 2 - state.leftWing
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
    func peek(_ p: IslandState.Peek, for seconds: Double = 2.5) {
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
        switch Prefs.d.string(forKey: "hoverBarMode") ?? "summary" {
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
            // Hover to peek: rest on the island for a moment to see a one-line summary.
            DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.6 : 0.15)) { [weak self] in
                guard let self, hovering == inside, Prefs.bool("hoverPeek"), !state.expanded else { return }
                if inside { hoverPeek = true; peek(hoverBar, for: 0) }
                else if hoverPeek { hoverPeek = false; endPeek() }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.25 : 0.5)) { [weak self] in
            guard let self, hovering == inside else { return }
            if inside, !state.expanded { openedByHover = true; setExpanded(true) }
            else if !inside, state.expanded, openedByHover { openedByHover = false; setExpanded(false) }
        }
    }

    func scrolled(_ e: NSEvent) {
        guard !state.expanded, panel.frame.contains(NSEvent.mouseLocation) else { return }
        // Right half of the island = volume, left half = Spaces.
        if NSEvent.mouseLocation.x > (state.notchWidth > 0 ? (screen?.frame.midX ?? panel.frame.midX) : panel.frame.midX) {
            guard Prefs.bool("scrollVolume") else { return }
            let d = abs(e.scrollingDeltaY) >= abs(e.scrollingDeltaX) ? e.scrollingDeltaY : -e.scrollingDeltaX
            sound.nudge((e.hasPreciseScrollingDeltas ? d / 300 : d / 30) * (e.isDirectionInvertedFromDevice ? 1 : -1) * -1)
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
            state.peek = nil; hoverPeek = false
            sound.refresh(); system.refresh(); playing.refresh()
            panel.setFrame(frame(expanded: true), display: true)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { state.expanded = true }
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, Prefs.bool("closeOnClickOutside"), !panel.frame.contains(NSEvent.mouseLocation) else { return }
                setExpanded(false)
            }
        } else {
            if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
            if panel.isKeyWindow { panel.resignKey(); previousApp?.activate(); previousApp = nil }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { state.expanded = false; state.page = .home }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) { [weak self] in
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
