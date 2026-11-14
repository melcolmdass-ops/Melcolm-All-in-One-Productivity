import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var tab: Tab = .sound
    @Published var notchWidth: CGFloat = 0     // 0 = this screen has no notch
    @Published var barHeight: CGFloat = 32
    @Published var leftWing: CGFloat = 130
    @Published var rightWing: CGFloat = 130
    var collapsedWidth: CGFloat { leftWing + notchWidth + rightWing }

    enum Tab: String, CaseIterable, Identifiable {
        case sound = "Sound", timer = "Timer", status = "Status", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .sound: "speaker.wave.2.fill"
            case .timer: "timer"
            case .status: "battery.75percent"
            case .settings: "gearshape.fill"
            }
        }
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
    let state = IslandState()
    let spaces = SpacesModel()
    let sound = SoundModel()
    let playing = NowPlayingModel()
    let timer = TimerModel()
    let system = SystemModel()
    var panel: IslandPanel!
    var clickMonitor: Any?

    var screenBar: CGFloat = 24
    var openedByHover = false
    var hovering = false
    var scrollAccum: CGFloat = 0
    var lastScrollSwitch = Date.distantPast
    var bag = Set<AnyCancellable>()

    static let expandedSize = CGSize(width: 480, height: 470)

    func applicationDidFinishLaunching(_ note: Notification) {
        Prefs.register()
        NSApp.setActivationPolicy(.accessory)
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false

        let root = IslandView(toggle: { [weak self] in self?.toggle() },
                              hover: { [weak self] in self?.hover($0) })
            .environmentObject(state).environmentObject(spaces).environmentObject(sound)
            .environmentObject(playing).environmentObject(timer).environmentObject(system)
        panel.contentView = FirstClickHostingView(rootView: root)
        measureScreen()
        relayout()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.measureScreen(); self?.relayout()
        }
        // Re-fit the island whenever what it shows changes.
        Publishers.MergeMany(
            spaces.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            timer.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            playing.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.relayout() }
        .store(in: &bag)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reloadHotkeys() }
            .store(in: &bag)
        reloadHotkeys()

        // Scroll over the island to move between Spaces.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            self?.scrolled(e); return e
        }
        // Light polling for the bits macOS doesn't notify about.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.playing.refresh()
            if self?.state.expanded == true { self?.system.refresh(); self?.sound.refresh() }
        }
        playing.refresh()
        _ = SpacesModel.ensureAccessibility()
        // For testing: `open … --args -debugOpen Settings` opens that tab on launch (not saved).
        if let t = UserDefaults.standard.string(forKey: "debugOpen"), let tab = IslandState.Tab(rawValue: t) {
            state.tab = tab; setExpanded(true)
        }
    }

    func reloadHotkeys() {
        Hotkeys.reload(toggle: { [weak self] in self?.toggle() },
                       jump: { [weak self] n in self?.spaces.jump(toNumber: n) })
    }

    func measureScreen() {
        guard let screen = NSScreen.screens.first else { return }
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
    func relayout() {
        let left = 14 + Layout.stripWidth(spaces) + 12
        var right: CGFloat = 10 + 24 + 12                     // chevron
        if timer.isActive && Prefs.bool("barShowTimer") { right += 74 }
        else if playing.playing && Prefs.bool("barShowMusic") { right += 22 }
        let h = max(screenBar, Layout.icon + 12)
        if state.notchWidth > 0 {
            let wing = max(left, right, 120)                   // symmetric around the notch
            set(&state.leftWing, wing); set(&state.rightWing, wing)
        } else {
            set(&state.leftWing, left); set(&state.rightWing, right)
        }
        set(&state.barHeight, h)
        let f = frame(expanded: state.expanded)
        if !state.expanded, f != panel.frame { panel.setFrame(f, display: true) }
    }

    private func set(_ v: inout CGFloat, _ n: CGFloat) { if abs(v - n) > 0.5 { v = n } }

    func frame(expanded: Bool) -> NSRect {
        guard let screen = NSScreen.screens.first else { return .zero }
        let size = expanded
            ? CGSize(width: max(Self.expandedSize.width, state.collapsedWidth), height: Self.expandedSize.height)
            : CGSize(width: state.collapsedWidth, height: state.barHeight)
        return NSRect(x: (screen.frame.midX - size.width / 2).rounded(), y: screen.frame.maxY - size.height,
                      width: size.width.rounded(), height: size.height)
    }

    func toggle() { openedByHover = false; setExpanded(!state.expanded) }

    func hover(_ inside: Bool) {
        hovering = inside
        guard Prefs.bool("hoverToOpen") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.25 : 0.5)) { [weak self] in
            guard let self, hovering == inside else { return }
            if inside, !state.expanded { openedByHover = true; setExpanded(true) }
            else if !inside, state.expanded, openedByHover { openedByHover = false; setExpanded(false) }
        }
    }

    func scrolled(_ e: NSEvent) {
        guard Prefs.bool("scrollSwitches"), !state.expanded, panel.frame.contains(NSEvent.mouseLocation) else { return }
        let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? -e.scrollingDeltaX : -e.scrollingDeltaY
        scrollAccum += e.hasPreciseScrollingDeltas ? d : d * 10
        guard abs(scrollAccum) > 30, Date().timeIntervalSince(lastScrollSwitch) > 0.45 else { return }
        spaces.step(scrollAccum > 0 ? 1 : -1)
        scrollAccum = 0; lastScrollSwitch = Date()
    }

    func setExpanded(_ open: Bool) {
        if open {
            sound.refresh(); system.refresh(); playing.refresh()
            panel.setFrame(frame(expanded: true), display: true)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { state.expanded = true }
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, Prefs.bool("closeOnClickOutside"), !panel.frame.contains(NSEvent.mouseLocation) else { return }
                setExpanded(false)
            }
        } else {
            if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { state.expanded = false }
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
