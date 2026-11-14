import CoreAudio
import SwiftUI

/// The one panel that slides out of the island: music, quick toggles, sliders, timer.
struct PanelView: View {
    @EnvironmentObject var state: IslandState

    var body: some View {
        ZStack(alignment: .top) {
            if state.showSettings {
                VStack(spacing: 10) {
                    HStack {
                        Button { withAnimation(.snappy) { state.showSettings = false } } label: {
                            Label("Back", systemImage: "chevron.left").font(.system(size: 12, weight: .semibold))
                        }.buttonStyle(.plain).foregroundStyle(accent)
                        Spacer()
                        Text("Settings").font(.system(size: 13, weight: .bold))
                        Spacer()
                        Color.clear.frame(width: 44, height: 1)
                    }
                    ScrollView(showsIndicators: false) { SettingsTab() }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        NowPlayingCard()
                        TileGrid()
                        SlidersCard()
                        TimerRow()
                        FooterRow()
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Now playing

struct NowPlayingCard: View {
    @EnvironmentObject var playing: NowPlayingModel

    var body: some View {
        Card {
            HStack(spacing: 12) {
                Group {
                    if let art = playing.artwork { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) }
                    else if let icon = playing.appIcon { Image(nsImage: icon).resizable().padding(6) }
                    else { Image(systemName: "music.note").font(.system(size: 20, weight: .semibold)).foregroundStyle(accent) }
                }
                .frame(width: 52, height: 52)
                .background(accent.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture { playing.openApp() }

                VStack(alignment: .leading, spacing: 4) {
                    Text(playing.title.isEmpty ? "Not playing" : playing.title)
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(playing.title.isEmpty ? "Controls work with any player, including YouTube" : playing.artist)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    if playing.duration > 0 {
                        HStack(spacing: 6) {
                            Text(TimerModel.format(playing.position))
                            GeometryReader { g in
                                Capsule().fill(.white.opacity(0.12))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(accent).frame(width: g.size.width * min(1, playing.position / playing.duration))
                                    }
                            }.frame(height: 3)
                            Text(TimerModel.format(playing.duration))
                        }
                        .font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
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

// MARK: - Quick toggles

enum TileKind: String, CaseIterable {
    case wifi, bluetooth, awake, dark, mic, screenshot
    var title: String {
        switch self {
        case .wifi: "Wi-Fi"; case .bluetooth: "Bluetooth"; case .awake: "Keep Awake"
        case .dark: "Dark Mode"; case .mic: "Mic"; case .screenshot: "Screenshot"
        }
    }
}

struct TileGrid: View {
    @EnvironmentObject var system: SystemModel
    @EnvironmentObject var sound: SoundModel
    @AppStorage("hiddenTiles") var hidden = ""

    var body: some View {
        let tiles = TileKind.allCases.filter { !hidden.split(separator: ",").contains(Substring($0.rawValue)) }
        if !tiles.isEmpty {
            HStack(spacing: 0) {
                ForEach(tiles, id: \.self) { t in tile(t).frame(maxWidth: .infinity) }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder func tile(_ t: TileKind) -> some View {
        switch t {
        case .wifi: Tile(icon: system.wifiOn ? "wifi" : "wifi.slash", title: system.wifiName ?? t.title, on: system.wifiOn,
                         action: system.toggleWifi, more: { SystemModel.open("com.apple.wifi-settings-extension") })
        case .bluetooth: Tile(icon: "dot.radiowaves.left.and.right", title: t.title, on: system.bluetoothOn,
                              action: system.toggleBluetooth, more: { SystemModel.open("com.apple.BluetoothSettings") })
        case .awake: Tile(icon: system.awake ? "cup.and.saucer.fill" : "cup.and.saucer", title: t.title, on: system.awake, action: system.toggleAwake)
        case .dark: Tile(icon: "circle.lefthalf.filled", title: t.title, on: system.dark, action: system.toggleDark)
        case .mic: Tile(icon: sound.inputMuted ? "mic.slash.fill" : "mic.fill", title: sound.inputMuted ? "Mic off" : t.title,
                        on: !sound.inputMuted, action: sound.toggleInputMute)
        case .screenshot: Tile(icon: "camera.viewfinder", title: t.title, on: false, action: SystemModel.screenshot)
        }
    }
}

struct Tile: View {
    let icon: String; let title: String; let on: Bool; let action: () -> Void
    var more: (() -> Void)?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(on ? accent : .white.opacity(0.1)))
                    .foregroundStyle(on ? .black : .white)
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .contextMenu { if let more { Button("Open Settings…", action: more) } }
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

// MARK: - Sliders + devices

struct SlidersCard: View {
    @EnvironmentObject var sound: SoundModel
    @EnvironmentObject var system: SystemModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                SliderRow(icon: sound.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", tap: sound.toggleMute,
                          value: Binding(get: { sound.volume }, set: { sound.setVolume($0) }))
                Chips(devices: sound.devices, current: sound.currentDevice, pick: sound.select)
                if let b = system.brightness {
                    SliderRow(icon: "sun.max.fill", tap: nil, value: Binding(get: { b }, set: { system.setBrightness($0) }))
                }
                if sound.inputAdjustable {
                    SliderRow(icon: sound.inputMuted ? "mic.slash.fill" : "mic.fill", tap: sound.toggleInputMute,
                              value: Binding(get: { sound.inputVolume }, set: { sound.setInputVolume($0) }))
                }
                Chips(devices: sound.inputs, current: sound.currentInput, pick: sound.selectInput)
            }
        }
    }
}

struct SliderRow: View {
    let icon: String; let tap: (() -> Void)?; let value: Binding<Double>
    var body: some View {
        HStack(spacing: 10) {
            Button { tap?() } label: { Image(systemName: icon).font(.system(size: 12, weight: .semibold)).frame(width: 20) }
                .buttonStyle(.plain).disabled(tap == nil)
            Slider(value: value, in: 0 ... 1).tint(accent).controlSize(.small)
            Text("\(Int(value.wrappedValue * 100))%").font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
        }
    }
}

/// Devices as one-click chips.
struct Chips: View {
    let devices: [OutputDevice]; let current: AudioDeviceID; let pick: (OutputDevice) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(devices) { d in
                    let on = d.id == current
                    Button { pick(d) } label: {
                        Text(d.name.replacingOccurrences(of: "’s", with: "").replacingOccurrences(of: "Melcolm ", with: ""))
                            .font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(on ? accent.opacity(0.25) : .white.opacity(0.07)))
                            .overlay(Capsule().stroke(on ? accent : .clear, lineWidth: 1))
                            .foregroundStyle(on ? .white : .white.opacity(0.7))
                    }.buttonStyle(PressStyle())
                }
            }
            .padding(.leading, 30)
        }
    }
}

// MARK: - Timer + footer

struct TimerRow: View {
    @EnvironmentObject var timer: TimerModel
    var body: some View {
        Card {
            HStack(spacing: 8) {
                Image(systemName: timer.mode == .stopwatch && timer.isActive ? "stopwatch" : "timer")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                if timer.isActive {
                    Text(timer.display).font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.finished ? .orange : .white)
                    Spacer()
                    Pill(timer.running ? "Pause" : "Resume", filled: true) { timer.running ? timer.pause() : timer.resume() }
                    Pill("Reset") { timer.reset() }
                } else {
                    ForEach([5, 15, 25, 45], id: \.self) { m in Pill("\(m)m") { timer.start(minutes: Double(m)) } }
                    Pill("Stopwatch") { timer.startStopwatch() }
                    Spacer(minLength: 0)
                    Button { timer.openClock() } label: { Image(systemName: "clock").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Open Clock app")
                }
            }
        }
    }
}

struct FooterRow: View {
    @EnvironmentObject var system: SystemModel
    @EnvironmentObject var state: IslandState
    var body: some View {
        HStack(spacing: 10) {
            Button { SystemModel.open("com.apple.Battery-Settings.extension") } label: {
                Label(system.battery.map { "\($0)%" } ?? "AC", systemImage: system.charging ? "battery.100percent.bolt" : "battery.75percent")
            }.buttonStyle(.plain)
            Spacer()
            Text("⌃⌥Space").foregroundStyle(.tertiary)
            Button { withAnimation(.snappy) { state.showSettings = true } } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 12))
                    .frame(width: 26, height: 26).background(Circle().fill(.white.opacity(0.08)))
            }.buttonStyle(PressStyle()).help("Settings")
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
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
