import CoreAudio
import SwiftUI

let accent = Color(red: 0.45, green: 0.62, blue: 1.0)

struct IslandView: View {
    @EnvironmentObject var state: IslandState
    let toggle: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        let collapsedW = state.collapsedWidth
        let w = state.expanded ? max(AppDelegate.expandedSize.width, collapsedW) : collapsedW
        let h = state.expanded ? AppDelegate.expandedSize.height : state.barHeight + (state.peek != nil ? AppDelegate.peekHeight : 0)
        let radius: CGFloat = state.expanded ? 26 : state.peek != nil ? 16 : min(14, state.barHeight / 2.2)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)

        VStack(spacing: 0) {
            TopBar(toggle: toggle)
                .frame(height: state.barHeight)
            if state.expanded {
                PanelView()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                                            removal: .opacity))
            } else if let p = state.peek {
                PeekRow(peek: p).frame(height: AppDelegate.peekHeight)
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
                if !playing.title.isEmpty && !state.expanded {
                    Button { playing.playPause() } label: {
                        Image(systemName: playing.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 9, weight: .bold)).frame(width: 20, height: 20)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }.buttonStyle(PressStyle()).help(playing.title)
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

/// One rounded box per display: its number, then each of its Spaces as a group of app icons.
/// The Space showing on that display is lit; the app you're using is underlined.
struct SpacesStrip: View {
    @EnvironmentObject var spaces: SpacesModel
    @EnvironmentObject var state: IslandState
    @AppStorage("indicatorStyle") var style = "glow"
    @AppStorage("showNumbers") var showNumbers = true
    @AppStorage("showAppIcons") var showIcons = true
    @AppStorage("maxIcons") var maxIcons = 4
    @AppStorage("iconClick") var iconClick = "app"
    @AppStorage("dimOthers") var dimOthers = false

    var body: some View {
        let icon = state.iconSize
        let h = min(icon + 6, state.barHeight - 2)
        HStack(spacing: Layout.chipGap) {
            ForEach(spaces.displays) { g in
                HStack(spacing: 0) {
                    Group {
                        if showNumbers {
                            Text("\(g.number)")
                                .font(.system(size: max(10, icon * 0.55), weight: .heavy, design: .rounded))
                                .foregroundStyle(accent)
                        } else {
                            Circle().fill(accent).frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: showNumbers ? Layout.numberWidth : 6)
                    .padding(.leading, 10).padding(.trailing, 6)
                    ForEach(Array(g.spaces.enumerated()), id: \.element.id) { i, s in
                        if i > 0 {
                            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: icon * 0.7)
                                .frame(width: Layout.dividerGap)
                        }
                        segment(s, current: s.id == g.currentID, icon: icon, h: h - 4)
                    }
                }
                .padding(.trailing, 6)
                .frame(width: Layout.groupWidth(g, spaces, icon: icon), height: h, alignment: .leading)
                .background {
                    let r = RoundedRectangle(cornerRadius: 9, style: .continuous)
                    r.fill(.white.opacity(0.06))
                    r.strokeBorder(.white.opacity(0.1), lineWidth: 0.7)
                }
                .help("Display \(g.number) · \(g.spaces.count) Space\(g.spaces.count == 1 ? "" : "s")")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: spaces.displays)
        .animation(.easeOut(duration: 0.15), value: spaces.frontPID)
    }

    func segment(_ s: SpaceItem, current: Bool, icon: CGFloat, h: CGFloat) -> some View {
        let apps = spaces.apps[s.id] ?? []
        let shown = showIcons ? Array(apps.prefix(maxIcons)) : []
        let dim = dimOthers && !current
        return Button { spaces.switchTo(s) } label: {
            HStack(spacing: Layout.iconGap) {
                if shown.isEmpty {
                    Circle().fill(.white.opacity(current ? 0.9 : 0.35)).frame(width: 6, height: 6)
                }
                ForEach(shown) { app in
                    let front = app.pid == spaces.frontPID && current
                    Image(nsImage: app.icon).resizable().interpolation(.high)
                        .frame(width: icon, height: icon)
                        .opacity(dim ? 0.5 : 1)
                        .saturation(dim ? 0.4 : 1)
                        .overlay(alignment: .bottom) {
                            if front {
                                Capsule().fill(accent).frame(width: icon * 0.7, height: 2.5)
                                    .shadow(color: accent, radius: 3)
                                    .offset(y: 4)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if iconClick == "app" { spaces.focus(app, on: s) } else { spaces.switchTo(s) }
                        }
                        .help(app.name)
                }
                if showIcons && apps.count > shown.count {
                    Text("+\(apps.count - shown.count)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: Layout.overflowWidth)
                }
            }
            .frame(width: Layout.segmentWidth(apps: apps.count, icon: icon), height: h)
            .background {
                if current {
                    let r = RoundedRectangle(cornerRadius: 7, style: .continuous)
                    r.fill(accent.opacity(style == "box" ? 0.28 : 0.14))
                    if style == "box" { r.strokeBorder(accent, lineWidth: 1.1) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(s.isFullscreen ? "Full screen · \(apps.first?.name ?? "")" : "Desktop \(s.number)")
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
    }
}

struct SettingsTab: View {
    enum Page: String, CaseIterable { case general = "General", bar = "Bar", panel = "Panel", spaces = "Spaces", mouse = "Mouse", keyboard = "Keyboard" }
    @AppStorage("settingsPage") var page = Page.general.rawValue
    @AppStorage("islandSize") var size = "large"
    @AppStorage("heightMode") var heightMode = "menu"
    @AppStorage("customHeight") var customHeight = 34.0
    @AppStorage("allDisplays") var allDisplays = false
    @AppStorage("barShowTimer") var barTimer = true
    @AppStorage("barShowMusic") var barMusic = true
    @AppStorage("indicatorStyle") var style = "glow"
    @AppStorage("showNumbers") var showNumbers = true
    @AppStorage("showAppIcons") var showIcons = true
    @AppStorage("maxIcons") var maxIcons = 4
    @AppStorage("iconClick") var iconClick = "app"
    @AppStorage("dimOthers") var dimOthers = false
    @AppStorage("hoverToOpen") var hoverOpen = false
    @AppStorage("hoverPeek") var hoverPeek = true
    @AppStorage("scrollVolume") var scrollVolume = true
    @AppStorage("liveActivities") var live = true
    @AppStorage("hiddenTiles") var hiddenTiles = ""
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
                    case .panel: panelPage
                    case .spaces: spacesPage
                    case .mouse: mouse
                    case .keyboard: keyboard
                    }
                }
            }
            Text("Melcolm All-in-One Productivity · v1.2").font(.system(size: 10)).foregroundStyle(.tertiary)
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
        row("Show on every display") { Toggle("", isOn: $allDisplays).labelsHidden() }
        row("Height") {
            Picker("", selection: $heightMode) { Text("Match menu bar").tag("menu"); Text("Custom").tag("custom") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
        if heightMode == "custom" {
            row("Custom height: \(Int(customHeight)) pt") { Slider(value: $customHeight, in: 22 ... 48, step: 1).frame(width: 200).tint(accent) }
        }
        row("Icon size") {
            Picker("", selection: $size) { Text("Small").tag("small"); Text("Medium").tag("medium"); Text("Large").tag("large") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
        row("Show running timer in the bar") { Toggle("", isOn: $barTimer).labelsHidden() }
        row("Show music wave while playing") { Toggle("", isOn: $barMusic).labelsHidden() }
        row("Pop-ups for song, output and timer") { Toggle("", isOn: $live).labelsHidden() }
    }

    @ViewBuilder var panelPage: some View {
        Text("Quick buttons to show").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
        ForEach(TileKind.allCases, id: \.self) { t in
            row(t.title) {
                Toggle("", isOn: Binding(
                    get: { !hiddenTiles.split(separator: ",").contains(Substring(t.rawValue)) },
                    set: { show in
                        var set = Set(hiddenTiles.split(separator: ",").map(String.init))
                        if show { set.remove(t.rawValue) } else { set.insert(t.rawValue) }
                        hiddenTiles = set.sorted().joined(separator: ",")
                    })).labelsHidden()
            }
        }
    }

    @ViewBuilder var spacesPage: some View {
        row("Space on screen") {
            Picker("", selection: $style) { Text("Glow").tag("glow"); Text("Box").tag("box") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
        }
        row("Show display numbers (off = dots)") { Toggle("", isOn: $showNumbers).labelsHidden() }
        row("Show app icons") { Toggle("", isOn: $showIcons).labelsHidden() }
        row("Icons") {
            Picker("", selection: $dimOthers) { Text("All bright").tag(false); Text("Dim other Spaces").tag(true) }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
        row("Icons per Space: \(maxIcons)") { Stepper("", value: $maxIcons, in: 1 ... 10).labelsHidden() }
        row("Clicking an app icon") {
            Picker("", selection: $iconClick) { Text("Opens the app").tag("app"); Text("Goes to Space").tag("space") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
    }

    @ViewBuilder var mouse: some View {
        row("Open the whole panel on hover") { Toggle("", isOn: $hoverOpen).labelsHidden() }
        row("Rest on the island for a quick summary") { Toggle("", isOn: $hoverPeek).labelsHidden() }
        row("Scroll on the right side to change volume") { Toggle("", isOn: $scrollVolume).labelsHidden() }
        row("Scroll on the island to change Space") { Toggle("", isOn: $scrollSwitch).labelsHidden() }
        row("Close when clicking elsewhere") { Toggle("", isOn: $closeOutside).labelsHidden() }
    }

    @ViewBuilder var keyboard: some View {
        row("⌃⌥Space opens and closes the island") { Toggle("", isOn: $hkToggle).labelsHidden() }
        row("⌃⌥1…9 jumps to that Space") { Toggle("", isOn: $hkNumbers).labelsHidden() }
        Text("While the panel is open: Esc closes · Space plays/pauses · ↑↓ volume · ←→ or 1–9 Spaces · , Settings")
            .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

/// The little row that drops under the bar for a moment: song change, volume, new output, hover summary.
struct PeekRow: View {
    let peek: IslandState.Peek
    var body: some View {
        HStack(spacing: 8) {
            if let art = peek.image {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: peek.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent).frame(width: 18)
            }
            if let v = peek.value {
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.15)).overlay(alignment: .leading) {
                        Capsule().fill(accent).frame(width: g.size.width * v)
                    }
                }.frame(height: 4)
                Text("\(Int(v * 100))%").font(.system(size: 10, weight: .semibold).monospacedDigit()).frame(width: 32)
            } else {
                Text(peek.text).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .foregroundStyle(.white.opacity(0.9))
    }
}
