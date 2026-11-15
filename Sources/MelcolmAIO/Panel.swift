import CoreAudio
import SwiftUI

/// Every page the panel can show. `home` is the grid of buttons; the rest open from it.
enum PanelPage: String, CaseIterable {
    case home, sound, mic, brightness, wifi, bluetooth, awake, dark, timer, layouts, settings

    static var listed: [PanelPage] { allCases.filter { $0 != .home && $0 != .settings } }

    var title: String {
        switch self {
        case .home: "Melcolm"; case .sound: "Sound"; case .mic: "Microphone"; case .brightness: "Brightness"
        case .wifi: "Wi-Fi"; case .bluetooth: "Bluetooth"; case .awake: "Keep Awake"; case .dark: "Dark Mode"
        case .timer: "Timer"; case .layouts: "Layouts"; case .settings: "Settings"
        }
    }
    var icon: String {
        switch self {
        case .home: "house"; case .sound: "speaker.wave.2.fill"; case .mic: "mic.fill"; case .brightness: "sun.max.fill"
        case .wifi: "wifi"; case .bluetooth: "dot.radiowaves.left.and.right"; case .awake: "cup.and.saucer.fill"
        case .dark: "circle.lefthalf.filled"; case .timer: "timer"; case .layouts: "rectangle.split.2x2.fill"; case .settings: "gearshape.fill"
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
    @AppStorage("hiddenTiles") var hidden = ""

    var body: some View {
        let pages = PanelPage.listed.filter { !hidden.split(separator: ",").contains(Substring($0.rawValue)) }
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(pages, id: \.self) { p in
                    let (sub, on) = status(p)
                    Button { state.page = p } label: {
                        HStack(spacing: 12) {
                            Image(systemName: p.icon).font(.system(size: 15, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(on ? accent : .white.opacity(0.1)))
                                .foregroundStyle(on ? .black : .white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                Text(sub).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.07)))
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
        case .sound: return ("\(sound.muted ? "Muted" : "\(Int(sound.volume * 100))%") · \(sound.outputName)", !sound.muted)
        case .mic: return (sound.inputMuted ? "Muted" : "\(Int(sound.inputVolume * 100))%", !sound.inputMuted)
        case .brightness: return (system.brightness.map { "\(Int($0 * 100))%" } ?? "External screen", system.brightness != nil)
        case .wifi: return (system.wifiOn ? (system.wifiName ?? "On") : "Off", system.wifiOn)
        case .bluetooth: return (system.bluetoothOn ? "On" : "Off", system.bluetoothOn)
        case .awake: return (system.awake ? "On" : "Off", system.awake)
        case .dark: return (system.dark ? "Dark" : "Light", system.dark)
        case .timer: return (timer.isActive ? timer.display : "Ready", timer.isActive)
        case .layouts: return ("Snap windows", false)
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
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(accent).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { on }, set: { _ in action() })).toggleStyle(.switch).labelsHidden()
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
            NowPlayingCard()
            if playing.app == "Browser" && playing.jsHint {
                Text("Want the artist and cover art too? In Chrome: View ▸ Developer ▸ Allow JavaScript from Apple Events (Safari: Develop menu).")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
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
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.09)))
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
    Text(t).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
}

// MARK: - Now playing

struct NowPlayingCard: View {
    @EnvironmentObject var playing: NowPlayingModel

    var body: some View {
        Card {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    Group {
                        if let art = playing.artwork { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) }
                        else if let icon = playing.appIcon { Image(nsImage: icon).resizable().padding(14) }
                        else { Image(systemName: "music.note").font(.system(size: 26, weight: .semibold)).foregroundStyle(accent) }
                    }
                    .frame(width: 84, height: 84)
                    .background(accent.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                    .onTapGesture { playing.openApp() }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(playing.title.isEmpty ? "Not playing" : playing.title)
                            .font(.system(size: 15, weight: .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(playing.title.isEmpty ? "Controls work with any player, including YouTube" : playing.artist)
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        if playing.duration > 0 {
                            HStack(spacing: 6) {
                                Text(TimerModel.format(playing.position))
                                GeometryReader { g in
                                    Capsule().fill(.white.opacity(0.14))
                                        .overlay(alignment: .leading) {
                                            Capsule().fill(accent).frame(width: g.size.width * min(1, playing.position / playing.duration))
                                        }
                                }.frame(height: 3)
                                Text(TimerModel.format(playing.duration))
                            }
                            .font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(.secondary).padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 30) {
                    MediaButton(icon: "backward.fill") { playing.previous() }
                    MediaButton(icon: playing.playing ? "pause.fill" : "play.fill", big: true) { playing.playPause() }
                    MediaButton(icon: "forward.fill") { playing.next() }
                }
            }
        }
    }
}

struct MediaButton: View {
    let icon: String; var big = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: big ? 15 : 11, weight: .semibold))
                .frame(width: big ? 36 : 28, height: big ? 36 : 28)
                .background(Circle().fill(.white.opacity(big ? 0.16 : 0.06)))
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
