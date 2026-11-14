import AppKit
import ServiceManagement
import SwiftUI

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var tab: Tab = .sound
    @Published var notchWidth: CGFloat = 0     // 0 = this screen has no notch
    @Published var barHeight: CGFloat = 32

    enum Tab: String, CaseIterable, Identifiable {
        case sound = "Sound", playing = "Playing", timer = "Timer", status = "Status", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .sound: "speaker.wave.2.fill"
            case .playing: "music.note"
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

    static let collapsedWing: CGFloat = 130
    static let expandedSize = CGSize(width: 470, height: 330)

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false

        let root = IslandView(toggle: { [weak self] in self?.setExpanded(!(self?.state.expanded ?? false)) })
            .environmentObject(state).environmentObject(spaces).environmentObject(sound)
            .environmentObject(playing).environmentObject(timer).environmentObject(system)
        let host = FirstClickHostingView(rootView: root)
        panel.contentView = host
        measureScreen()
        panel.setFrame(frame(expanded: false), display: true)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            measureScreen()
            panel.setFrame(frame(expanded: state.expanded), display: true)
        }
        // Light polling for the bits macOS doesn't notify about.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.playing.refresh()
            if self?.state.expanded == true { self?.system.refresh(); self?.sound.refresh() }
        }
        playing.refresh()
        _ = SpacesModel.ensureAccessibility()
    }

    func measureScreen() {
        guard let screen = NSScreen.screens.first else { return }
        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            state.notchWidth = screen.frame.width - l.width - r.width
            state.barHeight = top
        } else {
            state.notchWidth = 0
            state.barHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        }
    }

    func frame(expanded: Bool) -> NSRect {
        guard let screen = NSScreen.screens.first else { return .zero }
        let size = expanded
            ? CGSize(width: max(Self.expandedSize.width, state.notchWidth + 2 * Self.collapsedWing), height: Self.expandedSize.height)
            : CGSize(width: state.notchWidth + 2 * Self.collapsedWing, height: state.barHeight)
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    func setExpanded(_ open: Bool) {
        if open {
            sound.refresh(); system.refresh(); playing.refresh()
            panel.setFrame(frame(expanded: true), display: true)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { state.expanded = true }
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, !panel.frame.contains(NSEvent.mouseLocation) else { return }
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
