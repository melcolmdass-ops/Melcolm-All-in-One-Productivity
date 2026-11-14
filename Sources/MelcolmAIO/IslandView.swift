import SwiftUI

private let accent = Color(red: 0.45, green: 0.62, blue: 1.0)

struct IslandView: View {
    @EnvironmentObject var state: IslandState
    let toggle: () -> Void

    var body: some View {
        let wing = AppDelegate.collapsedWing
        let collapsedW = state.notchWidth + 2 * wing
        let w = state.expanded ? max(AppDelegate.expandedSize.width, collapsedW) : collapsedW
        let h = state.expanded ? AppDelegate.expandedSize.height : state.barHeight
        let radius: CGFloat = state.expanded ? 26 : state.barHeight / 2.2

        VStack(spacing: 0) {
            TopBar(toggle: toggle)
                .frame(height: state.barHeight)
            if state.expanded {
                ExpandedContent()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: w, height: h, alignment: .top)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                .fill(.black)
                .shadow(color: .black.opacity(state.expanded ? 0.5 : 0), radius: 18, y: 8)
        )
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusEffectDisabled()
        .preferredColorScheme(.dark)
    }
}

// MARK: - Top bar (always visible): spaces | notch | live status + chevron

struct TopBar: View {
    @EnvironmentObject var state: IslandState
    @EnvironmentObject var timer: TimerModel
    @EnvironmentObject var playing: NowPlayingModel
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SpacesStrip()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
            if state.notchWidth > 0 { Color.clear.frame(width: state.notchWidth) }
            HStack(spacing: 8) {
                if timer.isActive {
                    Label(timer.display, systemImage: timer.mode == .timer ? "timer" : "stopwatch")
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.finished ? .orange : accent)
                        .lineLimit(1)
                } else if playing.playing {
                    Image(systemName: "waveform").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent).symbolEffect(.variableColor.iterative, isActive: true)
                }
                Spacer(minLength: 0)
                Button(action: toggle) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(state.expanded ? 180 : 0))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Melcolm")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)
        }
    }
}

struct SpacesStrip: View {
    @EnvironmentObject var spaces: SpacesModel
    @AppStorage("indicatorStyle") var style = "glow"   // "glow" or "box"
    @AppStorage("showNumbers") var showNumbers = true
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(spaces.spaces) { s in
                let on = s.id == spaces.currentID
                Button { spaces.switchTo(s) } label: {
                    ZStack {
                        if showNumbers {
                            Text(s.isFullscreen ? "F" : "\(s.number)")
                                .font(.system(size: 11, weight: on ? .bold : .medium, design: .rounded))
                                .foregroundStyle(on ? .white : .white.opacity(0.45))
                        } else {
                            Circle().fill(on ? .white : .white.opacity(0.35)).frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .background {
                        if on && style == "box" {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(accent, lineWidth: 1.3)
                                .background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.18)))
                                .matchedGeometryEffect(id: "sel", in: ns)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if on && style == "glow" {
                            Capsule().fill(accent).frame(width: 12, height: 2.5)
                                .shadow(color: accent, radius: 4)
                                .offset(y: 2)
                                .matchedGeometryEffect(id: "sel", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(s.isFullscreen ? "Full-screen space" : "Desktop \(s.number)")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: spaces.currentID)
    }
}

// MARK: - Expanded

struct ExpandedContent: View {
    @EnvironmentObject var state: IslandState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(IslandState.Tab.allCases) { t in
                    Button { state.tab = t } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.icon).font(.system(size: 13, weight: .semibold))
                            Text(t.rawValue).font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(state.tab == t ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(state.tab == t ? Color.white.opacity(0.12) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Group {
                switch state.tab {
                case .sound: SoundTab()
                case .playing: PlayingTab()
                case .timer: TimerTab()
                case .status: StatusTab()
                case .settings: SettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
    }
}

struct SoundTab: View {
    @EnvironmentObject var sound: SoundModel
    var body: some View {
        VStack(spacing: 10) {
            Card {
                HStack(spacing: 10) {
                    Button { sound.toggleMute() } label: {
                        Image(systemName: sound.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 20)
                    }.buttonStyle(.plain)
                    Slider(value: Binding(get: { sound.volume }, set: { sound.setVolume($0) }), in: 0 ... 1)
                        .tint(accent)
                    Text("\(Int(sound.volume * 100))%").font(.caption.monospacedDigit()).frame(width: 34)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OUTPUT").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(sound.devices) { d in
                                Button { sound.select(d) } label: {
                                    HStack {
                                        Image(systemName: d.id == sound.currentDevice ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(d.id == sound.currentDevice ? accent : .secondary)
                                        Text(d.name).lineLimit(1)
                                        Spacer()
                                    }
                                    .font(.system(size: 12)).padding(.vertical, 4).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxHeight: 110)
                }
            }
            HStack { Spacer(); LinkButton("Sound Settings…") { SystemModel.open("com.apple.Sound-Settings.extension") } }
        }
    }
}

struct PlayingTab: View {
    @EnvironmentObject var playing: NowPlayingModel
    var body: some View {
        VStack(spacing: 14) {
            Card {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.25)).frame(width: 52, height: 52)
                        .overlay(Image(systemName: "music.note").font(.title2))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playing.title.isEmpty ? "Nothing detected" : playing.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(playing.title.isEmpty ? "Controls still work for any player, including YouTube" : "\(playing.artist) · \(playing.app)")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                }
            }
            HStack(spacing: 34) {
                ctl("backward.fill") { playing.previous() }
                ctl(playing.playing ? "pause.fill" : "play.fill", big: true) { playing.playPause() }
                ctl("forward.fill") { playing.next() }
            }
            if !playing.app.isEmpty { LinkButton("Open \(playing.app)") { playing.openApp() } }
        }
    }

    func ctl(_ icon: String, big: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: big ? 22 : 16, weight: .semibold))
                .frame(width: big ? 50 : 36, height: big ? 50 : 36)
                .background(Circle().fill(.white.opacity(big ? 0.14 : 0.06)))
        }.buttonStyle(.plain)
    }
}

struct TimerTab: View {
    @EnvironmentObject var timer: TimerModel
    var body: some View {
        VStack(spacing: 12) {
            Text(timer.isActive ? timer.display : "00:00")
                .font(.system(size: 48, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(timer.finished ? .orange : .white)
            if timer.isActive {
                HStack(spacing: 10) {
                    Pill(timer.running ? "Pause" : "Resume", filled: true) { timer.running ? timer.pause() : timer.resume() }
                    Pill("Reset") { timer.reset() }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach([1, 5, 10, 25, 45], id: \.self) { m in Pill("\(m)m") { timer.start(minutes: Double(m)) } }
                }
                Pill("Stopwatch", filled: true) { timer.startStopwatch() }
            }
            Spacer(minLength: 0)
            LinkButton("Open Clock app") { timer.openClock() }
        }
    }
}

struct StatusTab: View {
    @EnvironmentObject var system: SystemModel
    var body: some View {
        VStack(spacing: 10) {
            row(icon: system.charging ? "battery.100percent.bolt" : "battery.75percent", title: "Battery",
                detail: system.battery.map { "\($0)%\(system.charging ? " · charging" : "")" } ?? "No battery",
                pane: "com.apple.Battery-Settings.extension")
            row(icon: system.wifiOn ? "wifi" : "wifi.slash", title: "Wi-Fi",
                detail: system.wifiOn ? (system.wifiName ?? "On") : "Off",
                pane: "com.apple.wifi-settings-extension", toggle: { system.toggleWifi() }, isOn: system.wifiOn)
            row(icon: "dot.radiowaves.left.and.right", title: "Bluetooth",
                detail: system.bluetoothOn ? "On" : "Off", pane: "com.apple.BluetoothSettings")
        }
    }

    func row(icon: String, title: String, detail: String, pane: String, toggle: (() -> Void)? = nil, isOn: Bool = false) -> some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if let toggle {
                    Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() })).toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                Button { SystemModel.open(pane) } label: { Image(systemName: "chevron.right").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
    }
}

struct SettingsTab: View {
    @AppStorage("indicatorStyle") var style = "glow"
    @AppStorage("showNumbers") var showNumbers = true

    var body: some View {
        VStack(spacing: 10) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SPACES").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    Picker("Current space", selection: $style) {
                        Text("Glow underline").tag("glow"); Text("Box").tag("box")
                    }.pickerStyle(.segmented)
                    Toggle("Show numbers (off = dots)", isOn: $showNumbers)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Open at login", isOn: Binding(get: { LaunchAtLogin.isOn }, set: { LaunchAtLogin.set($0) }))
                    HStack {
                        LinkButton("Accessibility access…") {
                            SystemModel.open("com.apple.preference.security?Privacy_Accessibility")
                        }
                        Spacer()
                        LinkButton("Quit") { NSApp.terminate(nil) }
                    }
                }
            }
            Text("Melcolm All-in-One Productivity · v1.0").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
    }
}

struct Pill: View {
    let title: String; var filled = false; let action: () -> Void
    init(_ title: String, filled: Bool = false, action: @escaping () -> Void) { self.title = title; self.filled = filled; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(filled ? accent : .white.opacity(0.1)))
                .foregroundStyle(filled ? .black : .white)
        }.buttonStyle(.plain)
    }
}

struct LinkButton: View {
    let title: String; let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) { Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(accent) }.buttonStyle(.plain)
    }
}
