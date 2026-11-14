import CoreAudio
import SwiftUI

private let accent = Color(red: 0.45, green: 0.62, blue: 1.0)

struct IslandView: View {
    @EnvironmentObject var state: IslandState
    let toggle: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        let collapsedW = state.collapsedWidth
        let w = state.expanded ? max(AppDelegate.expandedSize.width, collapsedW) : collapsedW
        let h = state.expanded ? AppDelegate.expandedSize.height : state.barHeight
        let radius: CGFloat = state.expanded ? 26 : min(14, state.barHeight / 2.2)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)

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
            shape.fill(.black)
                .overlay(shape.stroke(LinearGradient(colors: [.clear, .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(state.expanded ? 0.5 : 0), radius: 18, y: 8)
        )
        .clipShape(shape)
        .onHover(perform: hover)
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
    @AppStorage("barShowTimer") var showTimer = true
    @AppStorage("barShowMusic") var showMusic = true
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SpacesStrip()
                .padding(.leading, 14)
                .frame(width: state.leftWing, alignment: .leading)
            if state.notchWidth > 0 { Color.clear.frame(width: state.notchWidth) }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if timer.isActive && showTimer {
                    Label(timer.display, systemImage: timer.mode == .timer ? "timer" : "stopwatch")
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.finished ? .orange : accent)
                        .lineLimit(1)
                } else if playing.playing && showMusic {
                    Image(systemName: "waveform").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent).symbolEffect(.variableColor.iterative, isActive: true)
                }
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
                .help("Open Melcolm (⌃⌥Space)")
            }
            .padding(.trailing, 10)
        }
    }
}

/// One rounded box per Space: number on the left, then the icons of the apps on it.
struct SpacesStrip: View {
    @EnvironmentObject var spaces: SpacesModel
    @AppStorage("indicatorStyle") var style = "glow"
    @AppStorage("showNumbers") var showNumbers = true
    @AppStorage("showAppIcons") var showIcons = true
    @AppStorage("maxIcons") var maxIcons = 4
    @AppStorage("iconClick") var iconClick = "app"
    @AppStorage("islandSize") var size = "medium"
    @Namespace private var ns

    var body: some View {
        let icon = Layout.iconSize(size)
        HStack(spacing: Layout.chipGap) {
            ForEach(spaces.spaces) { s in
                let on = s.id == spaces.currentID
                let apps = spaces.apps[s.id] ?? []
                let shown = showIcons ? Array(apps.prefix(maxIcons)) : []
                Button { spaces.switchTo(s) } label: {
                    HStack(spacing: 4) {
                        if !s.isFullscreen || shown.isEmpty {
                            Group {
                                if showNumbers {
                                    Text("\(s.number)")
                                        .font(.system(size: icon * 0.6, weight: .bold, design: .rounded))
                                        .foregroundStyle(on ? .white : .white.opacity(0.5))
                                } else {
                                    Circle().fill(on ? .white : .white.opacity(0.4)).frame(width: 6, height: 6)
                                }
                            }
                            .frame(width: showNumbers ? Layout.numberWidth : 6)
                        }
                        ForEach(shown) { app in
                            Image(nsImage: app.icon).resizable().interpolation(.high)
                                .frame(width: icon, height: icon)
                                .opacity(on ? 1 : 0.6)
                                .saturation(on ? 1 : 0.6)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if iconClick == "app" { spaces.focus(app, on: s) } else { spaces.switchTo(s) }
                                }
                                .help(app.name)
                        }
                        if showIcons && apps.count > shown.count {
                            Text("+\(apps.count - shown.count)")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: Layout.overflowWidth)
                        }
                    }
                    .frame(width: Layout.chipWidth(s, apps: apps.count), height: icon + 6)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(on ? accent.opacity(style == "box" ? 0.22 : 0.12) : .white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(on && style == "box" ? accent : .white.opacity(on ? 0.18 : 0.08), lineWidth: on && style == "box" ? 1.3 : 0.6)
                    }
                    .overlay(alignment: .bottom) {
                        if on && style == "glow" {
                            Capsule().fill(accent).frame(width: 16, height: 2.5)
                                .shadow(color: accent, radius: 5)
                                .offset(y: 2)
                                .matchedGeometryEffect(id: "sel", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(s.isFullscreen ? "Full-screen: \(apps.first?.name ?? "app")" : "Desktop \(s.number)")
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
    @EnvironmentObject var playing: NowPlayingModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                // Now playing + controls
                Card {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 9).fill(accent.opacity(0.25)).frame(width: 40, height: 40)
                            .overlay(Image(systemName: "music.note").font(.system(size: 16, weight: .semibold)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playing.title.isEmpty ? "Media controls" : playing.title)
                                .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(playing.title.isEmpty ? "Works with any player, including YouTube" : "\(playing.artist) · \(playing.app)")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        ctl("backward.fill") { playing.previous() }
                        ctl(playing.playing ? "pause.fill" : "play.fill", big: true) { playing.playPause() }
                        ctl("forward.fill") { playing.next() }
                    }
                }
                deviceCard(title: "OUTPUT", icon: sound.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           volume: Binding(get: { sound.volume }, set: { sound.setVolume($0) }),
                           adjustable: true, mute: sound.toggleMute,
                           devices: sound.devices, current: sound.currentDevice, pick: sound.select)
                deviceCard(title: "INPUT", icon: sound.inputMuted ? "mic.slash.fill" : "mic.fill",
                           volume: Binding(get: { sound.inputVolume }, set: { sound.setInputVolume($0) }),
                           adjustable: sound.inputAdjustable, mute: sound.toggleInputMute,
                           devices: sound.inputs, current: sound.currentInput, pick: sound.selectInput)
                HStack { Spacer(); LinkButton("Sound Settings…") { SystemModel.open("com.apple.Sound-Settings.extension") } }
            }
        }
    }

    func deviceCard(title: String, icon: String, volume: Binding<Double>, adjustable: Bool, mute: @escaping () -> Void,
                    devices: [OutputDevice], current: AudioDeviceID, pick: @escaping (OutputDevice) -> Void) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(action: mute) { Image(systemName: icon).frame(width: 20) }.buttonStyle(.plain)
                    if adjustable {
                        Slider(value: volume, in: 0 ... 1).tint(accent)
                        Text("\(Int(volume.wrappedValue * 100))%").font(.caption.monospacedDigit()).frame(width: 34)
                    } else {
                        Text("This device has no volume control").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                Divider().opacity(0.4)
                ForEach(devices) { d in
                    Button { pick(d) } label: {
                        HStack {
                            Image(systemName: d.id == current ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(d.id == current ? accent : .secondary)
                            Text(d.name).lineLimit(1)
                            Spacer()
                        }
                        .font(.system(size: 12)).padding(.vertical, 2).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    func ctl(_ icon: String, big: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: big ? 15 : 11, weight: .semibold))
                .frame(width: big ? 34 : 26, height: big ? 34 : 26)
                .background(Circle().fill(.white.opacity(big ? 0.16 : 0.06)))
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
    enum Page: String, CaseIterable { case general = "General", bar = "Menu Bar", spaces = "Spaces", mouse = "Mouse", keyboard = "Keyboard" }
    @AppStorage("settingsPage") var page = Page.general.rawValue
    @AppStorage("islandSize") var size = "medium"
    @AppStorage("barShowTimer") var barTimer = true
    @AppStorage("barShowMusic") var barMusic = true
    @AppStorage("indicatorStyle") var style = "glow"
    @AppStorage("showNumbers") var showNumbers = true
    @AppStorage("showAppIcons") var showIcons = true
    @AppStorage("maxIcons") var maxIcons = 4
    @AppStorage("iconClick") var iconClick = "app"
    @AppStorage("hoverToOpen") var hoverOpen = false
    @AppStorage("scrollSwitches") var scrollSwitch = true
    @AppStorage("closeOnClickOutside") var closeOutside = true
    @AppStorage("hotkeyToggle") var hkToggle = true
    @AppStorage("hotkeyNumbers") var hkNumbers = true

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Page.allCases, id: \.self) { p in
                    Button { page = p.rawValue } label: {
                        Text(p.rawValue).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(page == p.rawValue ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(page == p.rawValue ? accent : .white.opacity(0.07)))
                    }.buttonStyle(.plain)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 11) {
                    switch Page(rawValue: page) ?? .general {
                    case .general: general
                    case .bar: bar
                    case .spaces: spacesPage
                    case .mouse: mouse
                    case .keyboard: keyboard
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Melcolm All-in-One Productivity · v1.1").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
        .toggleStyle(.switch).controlSize(.small)
    }

    @ViewBuilder var general: some View {
        row("Open at login") { Toggle("", isOn: Binding(get: { LaunchAtLogin.isOn }, set: { LaunchAtLogin.set($0) })).labelsHidden() }
        row("Accessibility (needed to switch Spaces)") {
            if AXIsProcessTrusted() { Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            else { LinkButton("Allow…") { SystemModel.open("com.apple.preference.security?Privacy_Accessibility") } }
        }
        row("Reset all settings") { LinkButton("Reset") { Prefs.reset() } }
        row("Quit Melcolm") { LinkButton("Quit") { NSApp.terminate(nil) } }
    }

    @ViewBuilder var bar: some View {
        row("Island size") {
            Picker("", selection: $size) { Text("Small").tag("small"); Text("Medium").tag("medium"); Text("Large").tag("large") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
        row("Show running timer in the bar") { Toggle("", isOn: $barTimer).labelsHidden() }
        row("Show music wave while playing") { Toggle("", isOn: $barMusic).labelsHidden() }
    }

    @ViewBuilder var spacesPage: some View {
        row("Current Space") {
            Picker("", selection: $style) { Text("Glow").tag("glow"); Text("Box").tag("box") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
        }
        row("Show numbers (off = dots)") { Toggle("", isOn: $showNumbers).labelsHidden() }
        row("Show app icons") { Toggle("", isOn: $showIcons).labelsHidden() }
        row("Icons per Space: \(maxIcons)") { Stepper("", value: $maxIcons, in: 1 ... 10).labelsHidden() }
        row("Clicking an app icon") {
            Picker("", selection: $iconClick) { Text("Opens the app").tag("app"); Text("Goes to Space").tag("space") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
    }

    @ViewBuilder var mouse: some View {
        row("Open the island on hover") { Toggle("", isOn: $hoverOpen).labelsHidden() }
        row("Scroll on the island to change Space") { Toggle("", isOn: $scrollSwitch).labelsHidden() }
        row("Close when clicking elsewhere") { Toggle("", isOn: $closeOutside).labelsHidden() }
    }

    @ViewBuilder var keyboard: some View {
        row("⌃⌥Space opens and closes the island") { Toggle("", isOn: $hkToggle).labelsHidden() }
        row("⌃⌥1…9 jumps to that Space") { Toggle("", isOn: $hkNumbers).labelsHidden() }
        row("Mission Control shortcuts") { LinkButton("Keyboard Shortcuts…") { SystemModel.open("com.apple.Keyboard-Settings.extension") } }
    }

    func row<C: View>(_ title: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack { Text(title); Spacer(); control() }.frame(minHeight: 22)
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
