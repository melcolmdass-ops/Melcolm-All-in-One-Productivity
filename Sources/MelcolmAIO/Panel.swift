import CoreAudio
import SwiftUI

/// Every page the panel can show. `home` is the grid of buttons; the rest open from it.
enum PanelPage: String, CaseIterable {
    case home, nowPlaying, sound, mic, brightness, wifi, bluetooth, awake, dark, timer, layouts, settings

    static var listed: [PanelPage] { allCases.filter { $0 != .home && $0 != .settings } }

    var title: String {
        switch self {
        case .home: "Melcolm"; case .nowPlaying: "Now Playing"; case .sound: "Sound"; case .mic: "Microphone"; case .brightness: "Brightness"
        case .wifi: "Wi-Fi"; case .bluetooth: "Bluetooth"; case .awake: "Keep Awake"; case .dark: "Dark Mode"
        case .timer: "Timer"; case .layouts: "Layouts"; case .settings: "Settings"
        }
    }
    var icon: String {
        switch self {
        case .home: "house"; case .nowPlaying: "music.note"; case .sound: "speaker.wave.2.fill"; case .mic: "mic.fill"; case .brightness: "sun.max.fill"
        case .wifi: "wifi"; case .bluetooth: "dot.radiowaves.left.and.right"; case .awake: "cup.and.saucer.fill"
        case .dark: "circle.lefthalf.filled"; case .timer: "timer"; case .layouts: "rectangle.split.2x2.fill"; case .settings: "gearshape.fill"
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
        case .mic: return [c(1.0, 0.40, 0.55), c(1.0, 0.26, 0.34)]
        case .brightness: return [c(1.0, 0.82, 0.28), c(1.0, 0.55, 0.20)]
        case .wifi: return [c(0.25, 0.85, 1.0), c(0.30, 0.55, 1.0)]
        case .bluetooth: return [c(0.32, 0.62, 1.0), c(0.26, 0.40, 1.0)]
        case .awake: return [c(1.0, 0.62, 0.22), c(1.0, 0.40, 0.28)]
        case .dark: return [c(0.52, 0.46, 1.0), c(0.72, 0.36, 0.95)]
        case .timer: return [c(0.32, 0.92, 0.58), c(0.20, 0.74, 0.82)]
        case .layouts: return [c(0.26, 0.82, 0.82), c(0.30, 0.55, 1.0)]
        default: return [accent, accent2]
        }
    }
}

/// The panel that slides out of the island: a home grid, and one clean page per button.
struct PanelView: View {
    @EnvironmentObject var state: IslandState

    var body: some View {
        ZStack(alignment: .top) {
            if state.page == .home {
                HomePage().transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                VStack(spacing: 16) {
                    HStack {
                        Button { state.page = .home } label: {
                            Label("Back", systemImage: "chevron.left").font(.system(size: 12, weight: .semibold))
                        }.buttonStyle(.plain).foregroundStyle(accent).frame(width: 64, alignment: .leading)
                        Spacer()
                        Text(state.page.title).font(.system(size: 14, weight: .bold))
                        Spacer()
                        Color.clear.frame(width: 64, height: 1)
                    }
                    ScrollView(showsIndicators: false) { content.frame(maxWidth: .infinity) }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.snappy(duration: 0.25), value: state.page)
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder var content: some View {
        switch state.page {
        case .nowPlaying: NowPlayingPage()
        case .sound: SoundPage()
        case .mic: MicPage()
        case .brightness: BrightnessPage()
        case .wifi: WifiPage()
        case .bluetooth: BluetoothPage()
        case .awake: AwakePage()
        case .dark: DarkPage()
        case .timer: TimerPage()
        case .layouts: LayoutsPage()
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
    @EnvironmentObject var timer: TimerModel
    @EnvironmentObject var playing: NowPlayingModel
    @AppStorage("hiddenTiles") var hidden = ""

    var body: some View {
        let pages = PanelPage.listed.filter { !hidden.split(separator: ",").contains(Substring($0.rawValue)) }
        VStack(spacing: 14) {
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
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button { SystemModel.open("com.apple.Battery-Settings.extension") } label: {
                    Label(system.battery.map { "\($0)%" } ?? "AC", systemImage: system.charging ? "battery.100percent.bolt" : "battery.75percent")
                }.buttonStyle(.plain)
                Spacer()
                Text("⌃⌥Space").foregroundStyle(.tertiary)
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
        case .nowPlaying: return (playing.title.isEmpty ? "Nothing playing" : playing.title, playing.playing)
        case .sound: return ("\(sound.muted ? "Muted" : "\(Int(sound.volume * 100))%") · \(sound.outputName)", !sound.muted)
        case .mic: return (sound.inputMuted ? "Muted" : "\(Int(sound.inputVolume * 100))%", !sound.inputMuted)
        case .brightness: return (system.brightness.map { "\(Int($0 * 100))%" } ?? "External screen", system.brightness != nil)
        case .wifi: return (system.wifiOn ? (system.wifiName ?? "On") : "Off", system.wifiOn)
        case .bluetooth: return (system.bluetoothOn ? "On" : "Off", system.bluetoothOn)
        case .awake: return (system.awake ? "On" : "Off", system.awake)
        case .dark: return (system.dark ? "Dark" : "Light", system.dark)
        case .timer: return (timer.isActive ? timer.display : "Ready", timer.isActive)
        case .layouts: return ("Snap windows", true)
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
    var body: some View {
        Card {
            VStack(spacing: 2) {
                ForEach(devices) { d in
                    Button { pick(d) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: d.id == current ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(d.id == current ? accent : .secondary)
                            Text(d.name).lineLimit(1)
                            Spacer()
                        }
                        .font(.system(size: 13)).padding(.vertical, 7).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct BigSlider: View {
    let icon: String; let value: Binding<Double>; var tap: (() -> Void)?
    var body: some View {
        Card {
            HStack(spacing: 12) {
                Button { tap?() } label: { Image(systemName: icon).font(.system(size: 16, weight: .semibold)).frame(width: 26) }
                    .buttonStyle(.plain).disabled(tap == nil)
                Slider(value: value, in: 0 ... 1).tint(accent)
                Text("\(Int(value.wrappedValue * 100))%").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            }
            .padding(.vertical, 6)
        }
    }
}

struct SoundPage: View {
    @EnvironmentObject var sound: SoundModel
    @EnvironmentObject var playing: NowPlayingModel
    var body: some View {
        VStack(spacing: 14) {
            BigSlider(icon: sound.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                      value: Binding(get: { sound.volume }, set: { sound.setVolume($0) }), tap: sound.toggleMute)
            sectionLabel("OUTPUT")
            DeviceList(devices: sound.devices, current: sound.currentDevice, pick: sound.select)
            HStack { Spacer(); LinkButton("Sound Settings…") { SystemModel.open("com.apple.Sound-Settings.extension") } }
        }
    }
}

struct MicPage: View {
    @EnvironmentObject var sound: SoundModel
    var body: some View {
        VStack(spacing: 14) {
            if sound.inputAdjustable {
                BigSlider(icon: sound.inputMuted ? "mic.slash.fill" : "mic.fill",
                          value: Binding(get: { sound.inputVolume }, set: { sound.setInputVolume($0) }), tap: sound.toggleInputMute)
            } else {
                ToggleRow(icon: sound.inputMuted ? "mic.slash.fill" : "mic.fill", title: "Mute microphone",
                          subtitle: "This device has no volume control", on: sound.inputMuted, action: sound.toggleInputMute)
            }
            sectionLabel("INPUT")
            DeviceList(devices: sound.inputs, current: sound.currentInput, pick: sound.selectInput)
        }
    }
}

struct BrightnessPage: View {
    @EnvironmentObject var system: SystemModel
    var body: some View {
        VStack(spacing: 14) {
            if let b = system.brightness {
                BigSlider(icon: "sun.max.fill", value: Binding(get: { b }, set: { system.setBrightness($0) }))
            } else {
                Card { Text("Brightness can only be changed here for the MacBook's built-in screen.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary) }
            }
            HStack { Spacer(); LinkButton("Display Settings…") { SystemModel.open("com.apple.Displays-Settings.extension") } }
        }
    }
}

struct WifiPage: View {
    @EnvironmentObject var system: SystemModel
    var body: some View {
        VStack(spacing: 14) {
            ToggleRow(icon: system.wifiOn ? "wifi" : "wifi.slash", title: "Wi-Fi",
                      subtitle: system.wifiOn ? (system.wifiName ?? "On") : "Off", on: system.wifiOn, action: system.toggleWifi)
            HStack { Spacer(); LinkButton("Wi-Fi Settings…") { SystemModel.open("com.apple.wifi-settings-extension") } }
        }
    }
}

struct BluetoothPage: View {
    @EnvironmentObject var system: SystemModel
    var body: some View {
        VStack(spacing: 14) {
            ToggleRow(icon: "dot.radiowaves.left.and.right", title: "Bluetooth",
                      subtitle: system.bluetoothOn ? "On" : "Off", on: system.bluetoothOn, action: system.toggleBluetooth)
            HStack { Spacer(); LinkButton("Bluetooth Settings…") { SystemModel.open("com.apple.BluetoothSettings") } }
        }
    }
}

struct AwakePage: View {
    @EnvironmentObject var system: SystemModel
    var body: some View {
        ToggleRow(icon: "cup.and.saucer.fill", title: "Keep Awake",
                  subtitle: "Stops the screen from sleeping until you turn this off.", on: system.awake, action: system.toggleAwake)
    }
}

struct DarkPage: View {
    @EnvironmentObject var system: SystemModel
    var body: some View {
        ToggleRow(icon: "circle.lefthalf.filled", title: "Dark Mode",
                  subtitle: system.dark ? "The Mac is using the dark look." : "The Mac is using the light look.", on: system.dark, action: system.toggleDark)
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
            LinkButton("Open Clock app") { timer.openClock() }
        }
    }
}

func sectionLabel(_ t: String) -> some View {
    Text(t).font(.system(size: 10, weight: .heavy)).kerning(0.6).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
}

// MARK: - Now playing

struct NowPlayingPage: View {
    @EnvironmentObject var playing: NowPlayingModel
    var body: some View {
        let rest = playing.others.filter { !(playing.app == "Browser" && $0.title == playing.title) }
        VStack(spacing: 12) {
            PlayerCard(title: playing.title, artist: playing.artist, art: playing.artwork, icon: playing.appIcon,
                       playing: playing.playing, position: playing.position, duration: playing.duration,
                       open: playing.openApp, prev: playing.previous, play: playing.playPause, next: playing.next)
            ForEach(rest, id: \.id) { r in
                PlayerCard(title: r.title, artist: r.artist.isEmpty ? r.browser : r.artist, art: playing.thumbs[r.artwork], icon: nil,
                           playing: r.playing, position: r.position, duration: r.duration,
                           open: { playing.show(r) }, prev: { playing.skip(r, forward: false) },
                           play: { playing.toggle(r) }, next: { playing.skip(r, forward: true) })
            }
            if playing.jsHint {
                Text("For exact play/pause on each tab and a progress bar: in Chrome, View ▸ Developer ▸ Allow JavaScript from Apple Events (Safari: Develop menu).")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
        }
    }
}

/// One player: artwork, title, artist, progress, and Previous / Play / Next. Every player looks the same.
struct PlayerCard: View {
    let title: String; let artist: String; let art: NSImage?; let icon: NSImage?
    let playing: Bool; let position: Double; let duration: Double
    let open: () -> Void; let prev: () -> Void; let play: () -> Void; let next: () -> Void

    var body: some View {
        Card {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    Group {
                        if let art { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) }
                        else if let icon { Image(nsImage: icon).resizable().padding(14) }
                        else { Image(systemName: "music.note").font(.system(size: 26, weight: .semibold)).foregroundStyle(accent) }
                    }
                    .frame(width: 76, height: 76)
                    .background(Color(white: 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture(perform: open)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.isEmpty ? "Not playing" : title)
                            .font(.system(size: 15, weight: .heavy)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(title.isEmpty ? "Controls work with any player, including YouTube" : artist)
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        if duration > 0 {
                            HStack(spacing: 6) {
                                Text(TimerModel.format(position))
                                GeometryReader { g in
                                    Capsule().fill(.white.opacity(0.14))
                                        .overlay(alignment: .leading) {
                                            Capsule().fill(accent).frame(width: g.size.width * min(1, position / duration))
                                        }
                                }.frame(height: 3)
                                Text(TimerModel.format(duration))
                            }
                            .font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(.secondary).padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 34) {
                    MediaButton(icon: "backward.fill", action: prev)
                    MediaButton(icon: playing ? "pause.fill" : "play.fill", big: true, action: play)
                    MediaButton(icon: "forward.fill", action: next)
                }
            }
        }
    }
}

struct MediaButton: View {
    let icon: String; var big = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: big ? 16 : 14, weight: .bold))
                .frame(width: big ? 40 : 32, height: big ? 40 : 32)
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
