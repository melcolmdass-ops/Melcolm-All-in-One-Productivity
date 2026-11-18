import CoreAudio
import SwiftUI

/// Every page the panel can show. `home` is the grid of buttons; the rest open from it.
enum PanelPage: String, CaseIterable {
    case home, nowPlaying, sound, brightness, network, batteries, awake, dark, timer, layouts, focus, notifications, settings

    /// Every page in your chosen order (Settings ▸ Pages, drag to reorder).
    static var listed: [PanelPage] {
        let all = allCases.filter { $0 != .home && $0 != .settings }
        var l = (Prefs.d.string(forKey: "pageOrder") ?? "").split(separator: ",").compactMap { PanelPage(rawValue: String($0)) }.filter(all.contains)
        for p in all where !l.contains(p) { l.append(p) }
        return l
    }
    static let maxPinned = 3
    static func pinned(_ raw: String) -> [PanelPage] {
        let set = Set(raw.split(separator: ",").compactMap { PanelPage(rawValue: String($0)) })
        return Array(listed.filter(set.contains).prefix(maxPinned))   // shown in your page order
    }
    /// What's on the utility bar at the bottom of Home (Settings ▸ Utility Bar).
    static func utility(_ raw: String) -> [PanelPage] {
        let set = Set(raw.split(separator: ",").compactMap { PanelPage(rawValue: String($0)) })
        return listed.filter(set.contains)
    }

    var title: String {
        switch self {
        case .home: "Melcolm"; case .nowPlaying: "Now Playing"; case .sound: "Sound & Microphone"; case .brightness: "Brightness"
        case .network: "Wi-Fi & Bluetooth"; case .batteries: "Batteries"; case .awake: "Keep Awake"; case .dark: "Dark Mode"
        case .timer: "Clock"; case .layouts: "Layouts"; case .focus: "Focus Workflows"; case .notifications: "Notifications"; case .settings: "Settings"
        }
    }
    var icon: String {
        switch self {
        case .home: "house"; case .nowPlaying: "music.note"; case .sound: "speaker.wave.2.fill"; case .brightness: "sun.max.fill"
        case .network: "wifi"; case .batteries: "battery.75percent"; case .awake: "cup.and.saucer.fill"
        case .dark: "circle.lefthalf.filled"; case .timer: "timer"; case .layouts: "rectangle.split.2x2.fill"; case .focus: "moon.fill"; case .notifications: "bell.badge.fill"; case .settings: "gearshape.fill"
        }
    }
}

extension PanelPage {
    /// Each page has its own colour, so the home grid reads at a glance.
    var tint: [Color] {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch self {
        case .nowPlaying: return [c(1.0, 0.36, 0.62), c(0.78, 0.34, 1.0)]
        case .sound: return [c(0.36, 0.60, 1.0), c(0.58, 0.42, 1.0)]
        case .brightness: return [c(1.0, 0.82, 0.28), c(1.0, 0.55, 0.20)]
        case .network: return [c(0.25, 0.85, 1.0), c(0.30, 0.55, 1.0)]
        case .batteries: return [c(0.25, 0.95, 0.45), c(0.20, 0.74, 0.50)]
        case .awake: return [c(1.0, 0.62, 0.22), c(1.0, 0.40, 0.28)]
        case .dark: return [c(0.52, 0.46, 1.0), c(0.72, 0.36, 0.95)]
        case .timer: return [c(0.32, 0.92, 0.58), c(0.20, 0.74, 0.82)]
        case .layouts: return [c(0.26, 0.82, 0.82), c(0.30, 0.55, 1.0)]
        case .focus: return [c(0.62, 0.40, 1.0), c(0.36, 0.30, 0.95)]
        case .notifications: return [c(1.0, 0.36, 0.40), c(1.0, 0.58, 0.30)]
        default: return [accent, accent2]
        }
    }
}

/// The panel that slides out of the island: a home grid, and one clean page per button.
struct PanelView: View {
    @EnvironmentObject var state: IslandState
    @AppStorage("settingsPage") var settingsPage = "General"

    var body: some View {
        VStack(spacing: 6) {
        if state.page == .home && !state.byHover { spaceHint }
        ZStack(alignment: .top) {
            if state.page == .home {
                HomePage().transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Button { state.page = .home } label: {
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                                .frame(width: 26, height: 26).background(Circle().fill(.white.opacity(0.08)))
                        }.buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.85)).frame(width: 64, alignment: .leading)
                        .help("Back (Esc)")
                        Spacer()
                        Text(state.page.title).font(.system(size: 15, weight: .heavy))
                        Spacer()
                        Color.clear.frame(width: 64, height: 1)
                    }
                    Hairline()
                    ScrollView(showsIndicators: false) { content.frame(maxWidth: .infinity) }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.snappy(duration: 0.25), value: state.page)
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A short reminder under the bar (only when you open it yourself, not on hover): the arrows change Space and wrap around.
    var spaceHint: some View {
        func key(_ t: String) -> some View {
            Text(t).font(.system(size: 10, weight: .heavy, design: .rounded)).frame(minWidth: 18, minHeight: 16).padding(.horizontal, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.12)))
        }
        func hotkey(_ id: String, _ arrow: String) -> String? {
            guard Prefs.bool(Hotkeys.onKey(id)), let c = Hotkeys.commands.first(where: { $0.id == id }) else { return nil }
            let mods = Hotkeys.modifierChoices.first { $0.id == (Prefs.d.string(forKey: "cmdMods") ?? "ctrlOpt") }?.label ?? "⌃⌥"
            return mods + (Prefs.d.string(forKey: "cmd.\(id).key") ?? c.key)
        }
        let dbl = ["spacePrev", "spaceNext"].compactMap { Prefs.d.string(forKey: DoubleTap.prefKey($0)) }.filter { $0 != "Off" }
        return HStack(spacing: 6) {
            key("←"); key("→")
            Text("switch Space · wraps around").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            if let a = hotkey("spacePrev", "←"), let b = hotkey("spaceNext", "→") {
                Text("· anywhere: \(a) \(b)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            } else if !dbl.isEmpty {
                Text("· anywhere: double-tap \(dbl.joined(separator: " / "))").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Button { settingsPage = SettingsTab.Page.commands.rawValue; state.page = .settings } label: {
                HStack(spacing: 3) { Text("Change keys").font(.system(size: 10.5, weight: .semibold)); Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)) }
                    .foregroundStyle(accent)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 2).frame(height: 20)
        .transition(.opacity)
    }

    @ViewBuilder var content: some View { Self.pageContent(state.page) }

    @ViewBuilder static func pageContent(_ page: PanelPage) -> some View {
        switch page {
        case .nowPlaying: NowPlayingPage()
        case .sound: CompactStack { SoundPage(); sectionLabel("Microphone"); MicPage() }
        case .network: NetworkPage()
        case .batteries: BatteriesPage()
        case .brightness: BrightnessPage()
        case .awake: AwakePage()
        case .dark: DarkPage()
        case .timer: TimerPage()
        case .layouts: LayoutsPage()
        case .focus: FocusPage()
        case .notifications: NotificationsPage()
        case .settings: SettingsTab()
        case .home: EmptyView()
        }
    }
}

// MARK: - Home: one button per page

struct HomePage: View {
    @EnvironmentObject var state: IslandState
    @EnvironmentObject var system: SystemModel
    @EnvironmentObject var sound: SoundModel
    @EnvironmentObject var playing: NowPlayingModel
    @EnvironmentObject var focus: FocusModel
    @EnvironmentObject var timer: TimerModel
    @AppStorage("hiddenTiles") var hidden = ""
    @AppStorage("homePinned") var pinnedRaw = ""
    @AppStorage("utilityBar") var utilityBar = true
    @AppStorage("utilityItems") var utilityRaw = "sound,network,brightness,batteries"
    @AppStorage("pageOrder") var order = ""

    var body: some View {
        let pages = PanelPage.listed.filter { !hidden.split(separator: ",").contains(Substring($0.rawValue)) }
        let pinned = PanelPage.pinned(pinnedRaw)
        let _ = order
        VStack(spacing: 14) {
          ScrollView(showsIndicators: true) {
           VStack(spacing: 14) {
            // Pages you chose to see open right here (Settings ▸ Pages, up to 3).
            ForEach(pinned, id: \.self) { p in
                VStack(spacing: 10) {
                    Button { state.page = p } label: {
                        HStack(spacing: 6) {
                            Circle().fill(p.tint[0]).frame(width: 6, height: 6)
                            Text(p.title.uppercased()).font(.system(size: 10, weight: .bold)).kerning(0.8)
                            Spacer()
                            Text("Open").font(.system(size: 10, weight: .semibold))
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                        }.foregroundStyle(.white.opacity(0.45)).padding(.horizontal, 2).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    PanelView.pageContent(p).environment(\.lightPage, true)
                    Hairline().padding(.top, 4)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(pages, id: \.self) { p in
                    let (sub, on) = status(p)
                    Button { state.page = p } label: {
                        HStack(spacing: 12) {
                            Image(systemName: p.icon).font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(on ? AnyShapeStyle(p.tint[0]) : AnyShapeStyle(.white.opacity(0.08)))
                                )
                                .foregroundStyle(on ? .white : .white.opacity(0.6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                                Text(sub).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.105))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                        )
                        .contentShape(Rectangle())
                    }.buttonStyle(PressStyle())
                }
            }
           }.padding(.trailing, 2)
          }
          .scrollIndicators(.visible)
            Hairline()
            HStack(spacing: 10) {
                if utilityBar { UtilityBar(items: PanelPage.utility(utilityRaw)) } else {
                    Spacer()
                    Text("⌃⌥Space").foregroundStyle(.tertiary)
                }
                Button { state.page = .settings } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 12))
                        .frame(width: 28, height: 28).background(Circle().fill(.white.opacity(0.08)))
                }.buttonStyle(PressStyle()).help("Settings")
            }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    /// The little status line under each button, and whether it is "on" (lit).
    func status(_ p: PanelPage) -> (String, Bool) {
        switch p {
        case .nowPlaying: return (playing.title.isEmpty ? "Nothing playing" : playing.title, true)
        case .sound: return ("\(sound.muted ? "Muted" : "\(Int(sound.volume * 100))%") · \(sound.outputName)", !sound.muted)
        case .batteries: return (system.battery.map { "Mac \($0)%" } ?? "Batteries", true)
        case .brightness: return (system.brightness.map { "\(Int($0 * 100))%" } ?? "External screen", system.brightness != nil)
        case .network: return ("\(system.wifiOn ? (system.wifiName ?? "Wi-Fi on") : "Wi-Fi off") · BT \(system.bluetoothOn ? "on" : "off")", system.wifiOn || system.bluetoothOn)
        case .awake: return (system.awake ? "On" : "Off", system.awake)
        case .dark: return (system.dark ? "Dark" : "Light", system.dark)
        case .timer: return (timer.isActive ? timer.display : "Ready", timer.isActive)
        case .layouts: return ("Snap windows", true)
        case .notifications: return ("See your Mac's alerts", true)
        case .focus: return (focus.active.flatMap { id in focus.modes.first { $0.id == id }?.name } ?? "Off", focus.active != nil)
        default: return ("", false)
        }
    }
}

// MARK: - Pages

struct ToggleRow: View {
    let icon: String; let title: String; let subtitle: String; let on: Bool; let action: () -> Void
    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white).frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .bold))
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { on }, set: { _ in action() })).toggleStyle(.switch).labelsHidden().tint(accent)
            }
            .padding(.vertical, 6)
        }
    }
}

struct DeviceList: View {
    let devices: [OutputDevice]; let current: AudioDeviceID; let pick: (OutputDevice) -> Void
    @Environment(\.compactPage) var compact
    var body: some View {
        Card {
            VStack(spacing: 0) {
                ForEach(devices) { d in
                    if d.id != devices.first?.id { Hairline() }
                    Button { pick(d) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: d.id == current ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(d.id == current ? accent : .secondary)
                            Text(d.name).lineLimit(1)
                            Spacer()
                        }
                        .font(.system(size: 13, weight: d.id == current ? .semibold : .regular)).padding(.vertical, compact ? 5 : 9).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct BigSlider: View {
    let icon: String; let value: Binding<Double>; var tap: (() -> Void)?
    @Environment(\.compactPage) var compact
    var body: some View {
        Card {
            HStack(spacing: 12) {
                Button { tap?() } label: { Image(systemName: icon).font(.system(size: 16, weight: .semibold)).frame(width: 26) }
                    .buttonStyle(.plain).disabled(tap == nil)
                Slider(value: value, in: 0 ... 1).tint(accent)
                Text("\(Int(value.wrappedValue * 100))%").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(compact ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary)).frame(width: 40, alignment: .trailing)
            }
            .padding(.vertical, compact ? 0 : 6)
        }
    }
}

struct SoundPage: View {
    @EnvironmentObject var sound: SoundModel
    @EnvironmentObject var playing: NowPlayingModel
    var body: some View {
        CompactStack {
            BigSlider(icon: sound.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                      value: Binding(get: { sound.volume }, set: { sound.setVolume($0) }), tap: sound.toggleMute)
            sectionLabel("OUTPUT")
            DeviceList(devices: sound.devices, current: sound.currentDevice, pick: sound.select)
            SettingsLink(title: "Sound Settings", pane: "com.apple.Sound-Settings.extension")
        }
    }
}

struct MicPage: View {
    @EnvironmentObject var sound: SoundModel
    var body: some View {
        CompactStack {
            if sound.inputAdjustable {
                BigSlider(icon: sound.inputMuted ? "mic.slash.fill" : "mic.fill",
                          value: Binding(get: { sound.inputVolume }, set: { sound.setInputVolume($0) }), tap: sound.toggleInputMute)
            } else {
                ToggleRow(icon: sound.inputMuted ? "mic.slash.fill" : "mic.fill", title: "Mute microphone",
                          subtitle: "This device has no volume control", on: sound.inputMuted, action: sound.toggleInputMute)
            }
            sectionLabel("INPUT")
            DeviceList(devices: sound.inputs, current: sound.currentInput, pick: sound.selectInput)
            SettingsLink(title: "Microphone Settings", pane: "com.apple.Sound-Settings.extension?input")
        }
    }
}

struct BrightnessPage: View {
    @EnvironmentObject var system: SystemModel
    var body: some View {
        CompactStack {
            if let b = system.brightness {
                BigSlider(icon: "sun.max.fill", value: Binding(get: { b }, set: { system.setBrightness($0) }))
            } else {
                Card { Text("Brightness can only be changed here for the MacBook's built-in screen.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary) }
            }
            SettingsLink(title: "Display Settings", pane: "com.apple.Displays-Settings.extension")
        }
    }
}

struct AwakePage: View {
    @EnvironmentObject var system: SystemModel
    var body: some View {
        CompactStack {
            ToggleRow(icon: "cup.and.saucer.fill", title: "Keep Awake",
                      subtitle: "Stops the screen from sleeping until you turn this off.", on: system.awake, action: system.toggleAwake)
            SettingsLink(title: "Lock Screen Settings", pane: "com.apple.Lock-Screen-Settings.extension")
        }
    }
}

struct DarkPage: View {
    @EnvironmentObject var system: SystemModel
    var body: some View {
        CompactStack {
            ToggleRow(icon: "circle.lefthalf.filled", title: "Dark Mode",
                      subtitle: system.dark ? "The Mac is using the dark look." : "The Mac is using the light look.", on: system.dark, action: system.toggleDark)
            SettingsLink(title: "Appearance Settings", pane: "com.apple.Appearance-Settings.extension")
        }
    }
}

struct TimerPage: View {
    @EnvironmentObject var timer: TimerModel
    var body: some View {
        VStack(spacing: 16) {
            Picker("", selection: Binding(get: { timer.mode }, set: { if !timer.isActive { timer.mode = $0 } })) {
                Text("Timer").tag(TimerModel.Mode.timer)
                Text("Stopwatch").tag(TimerModel.Mode.stopwatch)
            }.pickerStyle(.segmented).labelsHidden().disabled(timer.isActive)

            Text(timer.isActive ? timer.display : "00:00")
                .font(.system(size: 54, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(timer.finished ? .orange : .white).padding(.vertical, 4)

            if timer.isActive {
                HStack(spacing: 12) {
                    Pill(timer.running ? "Pause" : "Resume", filled: true) { timer.running ? timer.pause() : timer.resume() }
                    Pill("Reset") { timer.reset() }
                }
            } else if timer.mode == .timer {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach([1, 5, 10, 15, 25, 45], id: \.self) { m in
                        Button { timer.start(minutes: Double(m)) } label: {
                            Text("\(m) min").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 40)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.09))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.7)))
                        }.buttonStyle(PressStyle())
                    }
                }
            } else {
                Pill("Start stopwatch", filled: true) { timer.startStopwatch() }
            }
            SettingsLink(title: "Open Clock app", action: { timer.openClock() })
        }
    }
}

func sectionLabel(_ t: String) -> some View {
    Text(t.uppercased()).font(.system(size: 10, weight: .bold)).kerning(0.8).foregroundStyle(.white.opacity(0.45))
        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 2).padding(.top, 4)
}

/// The one divider used across the app: a single soft line.
struct Hairline: View {
    var body: some View { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
}

// MARK: - Now playing

struct NowPlayingPage: View {
    @EnvironmentObject var playing: NowPlayingModel
    @Environment(\.lightPage) var light
    var body: some View {
        let browserMain = playing.app == "Browser"
        let list = playing.others
        VStack(spacing: 8) {
            if !browserMain {
                PlayerRow(title: playing.title, artist: playing.artist, art: playing.artwork, icon: playing.appIcon,
                          playing: playing.playing, position: playing.position, duration: playing.duration,
                          open: playing.openApp, prev: playing.previous, play: playing.playPause, next: playing.next,
                          seek: playing.seek)
            }
            ForEach(list, id: \.id) { r in
                PlayerRow(title: r.title, artist: r.artist.isEmpty ? r.browser : r.artist,
                          art: playing.thumbs[r.artwork] ?? (r.id == playing.mainResult?.id ? playing.artwork : nil), icon: nil,
                          playing: playing.isPlaying(r), position: r.position, duration: r.duration,
                          open: { playing.show(r) }, prev: { playing.skip(r, forward: false) },
                          play: { playing.toggle(r) }, next: { playing.skip(r, forward: true) },
                          seek: { playing.seek(r, to: $0) })
            }
            if false, playing.seekBlocked {
                Label("Chrome blocked the jump. In that Chrome window, choose View ▸ Developer ▸ Allow JavaScript from Apple Events (once per Chrome profile).", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
            if !light {
            Label("Click the artwork to open it where it's playing", systemImage: "hand.point.up.left.fill")
                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 2)
            }
            SettingsLink(title: "Sound Settings", pane: "com.apple.Sound-Settings.extension")
        }
    }
}

/// One player, compact: artwork, title, artist, then Previous / Play / Next. Every player looks the same.
struct PlayerRow: View {
    let title: String; let artist: String; let art: NSImage?; let icon: NSImage?
    let playing: Bool; let position: Double; let duration: Double
    let open: () -> Void; let prev: () -> Void; let play: () -> Void; let next: () -> Void
    var seek: ((Double) -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 11) {
                Button(action: open) {
                    Group {
                        if let art { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) }
                        else if let icon { Image(nsImage: icon).resizable().padding(6) }
                        else { Image(systemName: "music.note").font(.system(size: 16, weight: .semibold)).foregroundStyle(accent) }
                    }
                    .frame(width: 46, height: 46).background(Color(white: 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }.buttonStyle(PressStyle()).help("Open it")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? "Not playing" : title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Text(title.isEmpty ? "Play something in any app or tab" : artist)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    MediaButton(icon: "backward.fill", small: true, action: prev)
                    MediaButton(icon: playing ? "pause.fill" : "play.fill", big: true, small: true, action: play)
                    MediaButton(icon: "forward.fill", small: true, action: next)
                }
            }
            Scrubber(position: position, duration: duration, seek: seek)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.105))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1)))
    }
}

/// The play bar: drag or click anywhere on it to jump. Times on each side.
/// The one play bar being dragged right now, so the knob follows your finger before the jump.
final class ScrubDrag: ObservableObject {
    static let shared = ScrubDrag()
    @Published var key: Double?      // the duration of the bar being dragged (identifies it)
    @Published var f: Double = 0
}

struct Scrubber: View {
    let position: Double; let duration: Double; let seek: ((Double) -> Void)?
    @ObservedObject var drag = ScrubDrag.shared
    var body: some View {
        let known = duration > 0
        let dragging = drag.key == duration && known
        HStack(spacing: 8) {
            Text(known ? TimerModel.format(dragging ? drag.f * duration : position) : "--:--")
            GeometryReader { g in
                let f = dragging ? drag.f : known ? min(1, max(0, position / duration)) : 0
                ZStack(alignment: .leading) {
                    // Thick red bar (like YouTube), used on Quick View and the Now Playing page alike.
                    let red = Color(red: 1.0, green: 0.16, blue: 0.2)
                    Capsule().fill(.white.opacity(0.16)).frame(height: 7)
                    Capsule().fill(LinearGradient(colors: [Color(red: 1.0, green: 0.3, blue: 0.3), red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(7, g.size.width * f), height: 7)
                        .shadow(color: red.opacity(0.55), radius: 4)
                    if known && seek != nil {
                        Circle().fill(red).frame(width: 15, height: 15)
                            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                            .shadow(color: red.opacity(0.7), radius: 4)
                            .offset(x: g.size.width * f - 7.5)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard known, seek != nil else { return }
                        drag.key = duration; drag.f = min(1, max(0, v.location.x / g.size.width))
                    }
                    .onEnded { v in
                        guard known, let seek else { return }
                        let to = min(1, max(0, v.location.x / g.size.width)) * duration
                        seek(to)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if drag.key == duration { drag.key = nil } }
                    })
            }.frame(height: 18)
            Text(known ? TimerModel.format(duration) : "--:--")
        }
        .font(.system(size: 9.5, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
        .opacity(known ? 1 : 0.5)
        .help(known ? "Click or drag to jump" : "The browser isn't sharing the time yet (see the tip below)")
    }
}

/// A clean "go to the real settings" row at the bottom of a page.
struct SettingsLink: View {
    let title: String; var pane: String? = nil; var action: (() -> Void)? = nil
    @Environment(\.lightPage) var light
    var body: some View {
        if !light { full }
    }
    var full: some View {
        Button { if let action { action() } else if let pane { SystemModel.open(pane) } } label: {
            HStack {
                Image(systemName: "gearshape").font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 12).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }
}

struct MediaButton: View {
    let icon: String; var big = false; var small = false; let action: () -> Void
    var body: some View {
        let d: CGFloat = small ? (big ? 30 : 26) : (big ? 40 : 32)
        Button(action: action) {
            Image(systemName: icon).font(.system(size: small ? (big ? 12 : 11) : (big ? 16 : 14), weight: .bold))
                .frame(width: d, height: d)
                .background(Circle().fill(big ? AnyShapeStyle(.white) : AnyShapeStyle(.clear)))
                .foregroundStyle(big ? .black : .white.opacity(0.9))
                .contentShape(Circle())
        }.buttonStyle(PressStyle())
    }
}

/// Gentle shrink when pressed, so every click feels answered.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Batteries bar (bottom of Home)

struct BatteriesBar: View {
    @EnvironmentObject var system: SystemModel
    @EnvironmentObject var batteries: BatteryModel
    @AppStorage("batteryHidden") var hiddenRaw = ""
    @AppStorage("batteryPicking") var picking = false
    @Environment(\.compactPage) var compact

    static func color(_ p: Int) -> Color {
        p <= 10 ? Color(red: 1, green: 0.27, blue: 0.27) : p <= 20 ? Color(red: 1, green: 0.62, blue: 0.2)
            : p <= 35 ? Color(red: 1, green: 0.85, blue: 0.25) : Color(red: 0.25, green: 0.95, blue: 0.45)
    }
    var all: [BatteryItem] {
        let mac = system.battery.map { [BatteryItem(id: "mac", name: "This Mac", icon: "laptopcomputer", percent: $0, charging: system.charging)] } ?? []
        return mac + batteries.devices
    }
    var hidden: Set<String> { Set(hiddenRaw.split(separator: "\n").map(String.init)) }

    var body: some View {
        let shown = all.filter { !hidden.contains($0.id) }
        HStack(alignment: .top, spacing: 6) {
            // Four per row; the fifth starts a new row, so nothing is ever cut off.
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(compact ? 84 : 86), spacing: 5), count: compact ? 3 : 4), alignment: .leading, spacing: 5) {
                ForEach(shown) { chip($0) }
            }
            if shown.isEmpty { Text("No batteries shown").foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading) }
            Button { picking.toggle() } label: {
                Image(systemName: picking ? "eye.fill" : "eye").font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 26).background(Circle().fill(.white.opacity(picking ? 0.16 : 0.08)))
            }.buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.85)).help("Hide or show batteries")
            .popover(isPresented: Binding(get: { picking }, set: { picking = $0 }), arrowEdge: .top) { pickerList }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "L", "R" or "Case" for AirPods pieces, so left and right read apart.
    static func side(_ b: BatteryItem) -> String? {
        switch b.id.split(separator: "|").last.map(String.init) ?? "" {
        case "Left": "L"; case "Right": "R"; case "Case": "Case"; default: nil
        }
    }

    func chip(_ b: BatteryItem) -> some View {
        let c = Self.color(b.percent)
        return HStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: b.icon).font(.system(size: 12.5, weight: .semibold)).frame(width: 18, height: 16)
                    .foregroundStyle(.white.opacity(0.95))
                if let s = Self.side(b), s != "Case" {
                    Text(s).font(.system(size: 7.5, weight: .black)).foregroundStyle(.black)
                        .frame(width: 10, height: 10).background(Circle().fill(.white)).offset(x: 4, y: 3)
                }
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(c.opacity(0.7), lineWidth: 1).frame(width: 18, height: 10)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(c.gradient)
                    .frame(width: max(2, 14 * CGFloat(b.percent) / 100), height: 6).padding(.leading, 2)
                    .shadow(color: c.opacity(0.7), radius: 2)
                if b.charging { Image(systemName: "bolt.fill").font(.system(size: 6, weight: .black)).foregroundStyle(.black).frame(width: 18) }
            }
            Text("\(b.percent)%").font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(c)
                .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 26)
        .background(Capsule().fill(c.opacity(0.10)).overlay(Capsule().strokeBorder(c.opacity(0.22), lineWidth: 1)))
        .help(b.name)
    }

    var pickerList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SHOW IN THE BATTERIES BAR").font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary)
            ForEach(all) { b in
                Toggle(isOn: Binding(get: { !hidden.contains(b.id) }, set: { on in
                    var h = hidden; if on { h.remove(b.id) } else { h.insert(b.id) }
                    hiddenRaw = h.sorted().joined(separator: "\n")
                })) {
                    HStack(spacing: 8) {
                        Image(systemName: b.icon).frame(width: 20)
                        Text(b.name).lineLimit(1)
                        Spacer()
                        Text("\(b.percent)%").foregroundStyle(Self.color(b.percent)).monospacedDigit()
                    }.frame(width: 230)
                }.toggleStyle(.checkbox)
            }
            if all.isEmpty { Text("Nothing with a battery is connected.").foregroundStyle(.secondary) }
            Hairline()
            Button("Battery Settings…") { SystemModel.open("com.apple.Battery-Settings.extension") }.buttonStyle(.link)
        }
        .font(.system(size: 12)).padding(14)
    }
}

/// Pages shown on Home are the light version: just the controls, no tips or settings links.
private struct LightPageKey: EnvironmentKey { static let defaultValue = false }
/// Pop-ups from the utility bar: same controls, tighter spacing, so text stays big in a small box.
private struct CompactPageKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var compactPage: Bool { get { self[CompactPageKey.self] } set { self[CompactPageKey.self] = newValue } }
}
extension EnvironmentValues {
    var lightPage: Bool { get { self[LightPageKey.self] } set { self[LightPageKey.self] = newValue } }
}

/// Drag a page row onto another to put it there.
struct PageDrag: ViewModifier {
    let page: PanelPage?; @Binding var order: String
    func body(content: Content) -> some View {
        if let page {
            content
                .onDrag { NSItemProvider(object: page.rawValue as NSString) }
                .onDrop(of: [.text], isTargeted: nil) { items in
                    items.first?.loadObject(ofClass: NSString.self) { s, _ in
                        guard let s = s as? String, let from = PanelPage(rawValue: s), from != page else { return }
                        DispatchQueue.main.async {
                            var l = PanelPage.listed.filter { $0 != from }
                            l.insert(from, at: l.firstIndex(of: page) ?? l.count)
                            order = l.map(\.rawValue).joined(separator: ",")
                        }
                    }
                    return true
                }
        } else { content }
    }
}

// MARK: - Batteries page and utility bar

/// Every battery, big and clear. Tick what shows with the eye button.
struct BatteriesPage: View {
    @EnvironmentObject var system: SystemModel
    @EnvironmentObject var batteries: BatteryModel
    var body: some View {
        CompactStack {
            BatteriesBar()
            LowPowerRow()
            SettingsLink(title: "Battery Settings", pane: "com.apple.Battery-Settings.extension")
        }
    }
}

/// The bar at the bottom of Home: one small button per chosen page. Click one and that page
/// opens right there as a pop-up, exactly as it looks on its own page.
struct UtilityBar: View {
    let items: [PanelPage]
    @EnvironmentObject var system: SystemModel
    @EnvironmentObject var sound: SoundModel
    @EnvironmentObject var net: NetworkModel
    @AppStorage("utilityOpen") var open = ""

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { p in
                Button { open = open == p.rawValue ? "" : p.rawValue } label: {
                    HStack(spacing: 5) {
                        if p == .network {
                            // Wi-Fi and Bluetooth side by side: tap either one to open its tab.
                            netHalf(0, system.wifiOn ? "wifi" : "wifi.slash", system.wifiOn)
                            Capsule().fill(.white.opacity(0.18)).frame(width: 1, height: 14)
                            netHalf(1, "dot.radiowaves.left.and.right", system.bluetoothOn)
                        } else {
                            Image(systemName: icon(p)).font(.system(size: 12, weight: .semibold)).symbolRenderingMode(.hierarchical)
                                .foregroundStyle(p.tint[0])
                            Text(label(p)).font(.system(size: 11, weight: .semibold).monospacedDigit()).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 9).frame(height: 28)
                    .background(Capsule().fill(.white.opacity(open == p.rawValue ? 0.16 : 0.07))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1)))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.9)).help(p.title)
                .popover(isPresented: Binding(get: { open == p.rawValue }, set: { if !$0, open == p.rawValue { open = "" } }), arrowEdge: .top) {
                    // The same page, laid out at full panel width and shrunk, so nothing is cut off.
                    ScaledDown(scale: 0.9, width: 316) {
                        VStack(spacing: 12) {
                            Text(p.title).font(.system(size: 15, weight: .heavy)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                            PanelView.pageContent(p).environment(\.lightPage, true).environment(\.compactPage, true)
                        }
                    }
                    .padding(10).preferredColorScheme(.dark)
                    // Pop-ups never become the active window, so macOS greys them out; keep them bright.
                    .environment(\.controlActiveState, .key)
                    .foregroundStyle(.white)
                }
            }
            if items.isEmpty { Text("Pick items in Settings ▸ Utility Bar").foregroundStyle(.tertiary) }
            Spacer(minLength: 0)
        }
    }

    /// One half of the Wi-Fi & Bluetooth pill. Picks its tab, opens (or switches) the pop-up.
    func netHalf(_ tab: Int, _ symbol: String, _ on: Bool) -> some View {
        let shown = open == PanelPage.network.rawValue && net.tab == tab
        return Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).symbolRenderingMode(.hierarchical)
            .foregroundStyle(on ? PanelPage.network.tint[0] : .white.opacity(0.45))
            .frame(width: 22, height: 22)
            .background(Circle().fill(.white.opacity(shown ? 0.2 : 0)))
            .contentShape(Rectangle())
            .onTapGesture {
                if shown { open = "" } else { withAnimation(.easeOut(duration: 0.15)) { net.tab = tab }; open = PanelPage.network.rawValue }
            }
            .help(tab == 0 ? "Wi-Fi" : "Bluetooth")
    }

    func icon(_ p: PanelPage) -> String {
        switch p {
        case .sound: sound.muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .batteries: system.charging ? "battery.100percent.bolt" : "battery.75percent"
        case .network: system.wifiOn ? "wifi" : "wifi.slash"
        default: p.icon
        }
    }
    func label(_ p: PanelPage) -> String {
        switch p {
        case .sound: sound.muted ? "Muted" : "\(Int(sound.volume * 100))%"
        case .brightness: system.brightness.map { "\(Int($0 * 100))%" } ?? "Bright"
        case .batteries: system.battery.map { "\($0)%" } ?? "AC"
        case .network: system.wifiOn ? "On" : "Off"
        case .awake: system.awake ? "On" : "Off"
        case .dark: system.dark ? "Dark" : "Light"
        default: p == .timer ? "Clock" : p.title
        }
    }
}

/// Lays its content out at `width`, then draws it at `scale`, taking up only the shrunk space.
struct ScaledDown<C: View>: View {
    let scale: CGFloat; let width: CGFloat; @ViewBuilder var content: C
    var body: some View {
        ScaledLayout(scale: scale, width: width) {
            content.frame(width: width).scaleEffect(scale, anchor: .topLeading)
        }
    }
}
struct ScaledLayout: SwiftUI.Layout {
    let scale: CGFloat; let width: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)) ?? .zero
        return CGSize(width: width * scale, height: s.height * scale)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
    }
}

/// A page's column: normal spacing, tighter inside utility pop-ups.
struct CompactStack<C: View>: View {
    @Environment(\.compactPage) var compact
    @ViewBuilder var content: C
    var body: some View { VStack(spacing: compact ? 7 : 14) { content } }
}

/// Low Power Mode switch: a slim row that fits the page and the small pop-up alike.
struct LowPowerRow: View {
    @EnvironmentObject var system: SystemModel
    var body: some View {
        let on = system.lowPower
        let yellow = Color(red: 1, green: 0.84, blue: 0.2)
        HStack(spacing: 10) {
            Image(systemName: on ? "bolt.badge.automatic.fill" : "bolt.badge.automatic")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(on ? .black : yellow)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? AnyShapeStyle(yellow) : AnyShapeStyle(yellow.opacity(0.14))))
            VStack(alignment: .leading, spacing: 1) {
                Text("Low Power Mode").font(.system(size: 13, weight: .bold))
                Text(system.lowPowerBusy ? "Waiting for your password (first time only)…" : on ? "On · the battery lasts longer" : "Off")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { on }, set: { system.setLowPower($0) })).toggleStyle(.switch).labelsHidden()
                .tint(yellow).disabled(system.lowPowerBusy)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.105))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? yellow.opacity(0.5) : .white.opacity(0.08), lineWidth: 1)))
        .help("Turns Low Power Mode on or off for the whole Mac. macOS asks for your password the first time only.")
    }
}
