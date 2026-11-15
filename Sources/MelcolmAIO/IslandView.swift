import CoreAudio
import SwiftUI

let accent = Color(red: 0.40, green: 0.62, blue: 1.0)
let accent2 = Color(red: 0.62, green: 0.45, blue: 1.0)
let accentGradient = LinearGradient(colors: [Color(red: 0.36, green: 0.66, blue: 1.0), Color(red: 0.58, green: 0.42, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)

struct IslandView: View {
    @EnvironmentObject var state: IslandState
    let toggle: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        // On a notched screen the collapsed island reaches into the notch so the two read as one shape.
        let attached = state.notchWidth > 0 && !state.expanded
        let collapsedW = attached ? state.collapsedWidth + state.notchWidth : state.collapsedWidth
        let w = state.expanded ? state.expandedWidth : collapsedW
        let h = state.expanded ? AppDelegate.expandedSize.height : state.barHeight + (state.peek?.height ?? 0)
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
                PeekRow(peek: p).frame(height: p.height)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: w, height: h, alignment: .top)
        .background(
            ZStack {
                shape.fill(LinearGradient(colors: [Color(white: 0.0), Color(white: 0.055)], startPoint: .top, endPoint: .bottom))
                if state.expanded {
                    // A soft glow rising from the top of the panel.
                    shape.fill(RadialGradient(colors: [accent.opacity(0.20), accent2.opacity(0.08), .clear],
                                              center: .init(x: 0.5, y: 0), startRadius: 4, endRadius: 330))
                }
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(state.expanded ? 0.22 : 0.14), accent.opacity(0.35)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: .black.opacity(state.expanded ? 0.6 : 0), radius: 22, y: 10)
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
                .frame(width: state.expanded && state.notchWidth > 0 ? max(state.leftWing, state.rightWing) : state.leftWing, alignment: .leading)
            if state.notchWidth > 0 { Color.clear.frame(width: state.notchWidth) }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if timer.isActive && showTimer {
                    Label(timer.display, systemImage: timer.mode == .timer ? "timer" : "stopwatch")
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.finished ? .orange : accent)
                        .lineLimit(1)
                } else if playing.playing && showMusic {
                    BeatWave()
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
                        .font(.system(size: 13, weight: .bold))
                        .rotationEffect(.degrees(state.expanded ? 180 : 0))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 36, height: 26)
                        .background(Capsule().fill(.white.opacity(0.1)).overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.7)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Melcolm (⌃⌥Space)")
            }
            .padding(.trailing, 10)
        }
    }
}

/// One box per display: its desktop number, then the apps open in full-screen Spaces.
/// Whatever is showing on that display gets a glowing outline.
struct SpacesStrip: View {
    @EnvironmentObject var spaces: SpacesModel
    @EnvironmentObject var state: IslandState
    @AppStorage("indicatorStyle") var style = "glow"
    @AppStorage("showNumbers") var showNumbers = true
    @AppStorage("showAppIcons") var showIcons = true
    @AppStorage("iconClick") var iconClick = "app"
    @AppStorage("dimOthers") var dimOthers = false

    var body: some View {
        let icon = state.iconSize
        let h = min(icon + 2 * Layout.cellPad, state.barHeight - 2)
        HStack(spacing: Layout.chipGap) {
            ForEach(spaces.displays) { g in
                let desktops = Layout.desktops(g)
                let home = desktops.first { $0.id == g.currentID } ?? desktops.first
                HStack(spacing: 2) {
                    if let home { numberCell(g, home, on: home.id == g.currentID, icon: icon, h: h - 4) }
                    else { Color.clear.frame(width: Layout.numberCell(icon), height: h - 4) }
                    let fulls = Layout.fullscreens(g)
                    if !fulls.isEmpty {
                        Capsule().fill(.white.opacity(0.32)).frame(width: 2, height: icon * 0.8)
                            .padding(.horizontal, 4)
                    }
                    ForEach(fulls) { s in appCell(s, on: s.id == g.currentID, icon: icon, h: h - 4) }
                }
                .padding(.horizontal, 8)
                .frame(width: Layout.groupWidth(g, icon: icon), height: h, alignment: .leading)
                .background {
                    let r = RoundedRectangle(cornerRadius: 10, style: .continuous)
                    r.fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom))
                    r.strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                }
                .help("Display \(g.number)")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: spaces.displays)
    }

    func glow(_ on: Bool) -> some View {
        let r = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            if on {
                r.fill(accentGradient.opacity(style == "box" ? 0.40 : 0.24))
                r.strokeBorder(accentGradient, lineWidth: 1.5)
                    .shadow(color: accent.opacity(0.95), radius: style == "glow" ? 7 : 0)
            }
        }
    }

    func numberCell(_ g: DisplayGroup, _ home: SpaceItem, on: Bool, icon: CGFloat, h: CGFloat) -> some View {
        Button { spaces.switchTo(home) } label: {
            Group {
                if showNumbers {
                    Text("\(g.number)").font(.system(size: icon * 0.72, weight: .heavy, design: .rounded))
                        .foregroundStyle(on ? .white : accent.opacity(0.85))
                } else {
                    Circle().fill(on ? .white : accent).frame(width: 8, height: 8)
                }
            }
            .frame(width: Layout.numberCell(icon), height: h)
            .background(glow(on))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help("Desktop \(g.number)")
    }

    func appCell(_ s: SpaceItem, on: Bool, icon: CGFloat, h: CGFloat) -> some View {
        let app = spaces.apps[s.id]?.first
        let dim = dimOthers && !on
        return Button {
            if let app, iconClick == "app" { spaces.focus(app, on: s) } else { spaces.switchTo(s) }
        } label: {
            Group {
                if showIcons, let app {
                    Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: icon, height: icon)
                } else {
                    Image(systemName: "rectangle.inset.filled").font(.system(size: icon * 0.6))
                        .foregroundStyle(.white.opacity(0.6)).frame(width: icon, height: icon)
                }
            }
            .opacity(dim ? 0.5 : 1).saturation(dim ? 0.4 : 1)
            .frame(width: Layout.iconCell(icon), height: h)
            .background(glow(on))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(app?.name ?? "Full-screen app")
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.11), .white.opacity(0.045)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
            )
    }
}

struct SettingsTab: View {
    enum Page: String, CaseIterable { case general = "General", bar = "Bar", panel = "Pages", spaces = "Spaces", mouse = "Mouse", hover = "Hover bar", keyboard = "Keyboard" }
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
    @AppStorage("classicSwitching") var classic = false
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
                            .foregroundStyle(page == p.rawValue ? .white : .white.opacity(0.7))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(page == p.rawValue ? AnyShapeStyle(accentGradient) : AnyShapeStyle(.white.opacity(0.07))))
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
                    case .hover: hoverPage
                    case .keyboard: keyboard
                    }
                }
            }
            Text("Melcolm All-in-One Productivity · v1.8").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
        .toggleStyle(.switch).controlSize(.small)
    }

    @ViewBuilder var general: some View {
        row("Open at login") { Toggle("", isOn: Binding(get: { LaunchAtLogin.isOn }, set: { LaunchAtLogin.set($0) })).labelsHidden() }
        row("Accessibility (needed to switch Spaces)") {
            if AXIsProcessTrusted() { Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            else { LinkButton("Allow… (if already on, switch it off and on)") { SystemModel.open("com.apple.preference.security?Privacy_Accessibility") } }
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
        Text("Tick the pages you want on the home screen").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
        ForEach(PanelPage.listed, id: \.self) { t in
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
        row("Classic switching (slower, with animation)") { Toggle("", isOn: $classic).labelsHidden() }
        if !classic && !FastSwitch.available {
            HStack(alignment: .top, spacing: 8) {
                Text("Fast switching needs a trackpad Space swipe turned on, so classic switching is being used for now.")
                    .font(.system(size: 10.5)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                LinkButton("Trackpad…") { SystemModel.open("com.apple.Trackpad-Settings.extension") }
            }
        }
        row("Show display numbers (off = dots)") { Toggle("", isOn: $showNumbers).labelsHidden() }
        row("Show app icons (off = plain boxes)") { Toggle("", isOn: $showIcons).labelsHidden() }
        row("Other full-screen apps") {
            Picker("", selection: $dimOthers) { Text("Bright").tag(false); Text("Dimmed").tag(true) }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
        row("Clicking an app icon") {
            Picker("", selection: $iconClick) { Text("Opens the app").tag("app"); Text("Goes to Space").tag("space") }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
    }

    @ViewBuilder var mouse: some View {
        row("Open the whole panel on hover") { Toggle("", isOn: $hoverOpen).labelsHidden() }
        row("Scroll on the right side to change volume") { Toggle("", isOn: $scrollVolume).labelsHidden() }
        row("Scroll on the island to change Space") { Toggle("", isOn: $scrollSwitch).labelsHidden() }
        row("Close when clicking elsewhere") { Toggle("", isOn: $closeOutside).labelsHidden() }
    }

    @AppStorage("hoverBarMode") var hoverMode = "summary"
    @AppStorage("shortcuts") var shortcutsRaw = ""
    @AppStorage("draftShortcutName") var newName = ""
    @AppStorage("draftShortcutTarget") var newTarget = ""

    @ViewBuilder var hoverPage: some View {
        row("Show the hover bar when resting on the island") { Toggle("", isOn: $hoverPeek).labelsHidden() }
        if hoverOpen {
            Text("“Open the whole panel on hover” is on (Mouse), so the panel opens instead.")
                .font(.system(size: 10.5)).foregroundStyle(.orange)
        }
        row("Shows") {
            Picker("", selection: $hoverMode) {
                Text("Summary").tag("summary"); Text("Volume + Brightness").tag("volumeBrightness")
                Text("Shortcuts").tag("shortcuts"); Text("Music controls").tag("media")
            }.labelsHidden().frame(width: 200)
        }
        Text(hoverHelp).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if hoverMode == "shortcuts" {
            Divider().opacity(0.3)
            Text("SHORTCUTS").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            let items = Shortcut.parse(shortcutsRaw)
            ForEach(Array(items.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 8) {
                    s.icon.frame(width: 16, height: 16)
                    Text(s.name).fontWeight(.semibold)
                    Text(s.target).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { var l = items; l.remove(at: i); save(l) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.85)) }
                        .buttonStyle(.plain).help("Remove")
                }
            }
            HStack(spacing: 6) {
                TextField("Name", text: $newName).textFieldStyle(.roundedBorder).frame(width: 90)
                TextField("Link or app name (e.g. https://chatgpt.com or Notes)", text: $newTarget).textFieldStyle(.roundedBorder)
                Button { add() } label: { Image(systemName: "plus.circle.fill").foregroundStyle(accent) }
                    .buttonStyle(.plain).disabled(newName.isEmpty || newTarget.isEmpty)
            }.onSubmit(add)
        }
    }

    var hoverHelp: String {
        switch hoverMode {
        case "volumeBrightness": "Volume on the left half, brightness on the right. Click or drag either one."
        case "shortcuts": "Your own apps and links, one click each."
        case "media": "The current song with Previous, Play and Next."
        default: "One line: the timer, the song, or battery and output."
        }
    }
    func save(_ l: [Shortcut]) { shortcutsRaw = l.map { "\($0.name)|\($0.target)" }.joined(separator: "\n") }
    func add() {
        guard !newName.isEmpty, !newTarget.isEmpty else { return }
        save(Shortcut.parse(shortcutsRaw) + [Shortcut(name: newName, target: newTarget)])
        newName = ""; newTarget = ""
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
                .background(Capsule().fill(filled ? AnyShapeStyle(accentGradient) : AnyShapeStyle(.white.opacity(0.1))))
                .overlay(Capsule().strokeBorder(.white.opacity(filled ? 0.0 : 0.12), lineWidth: 0.7))
                .shadow(color: filled ? accent.opacity(0.45) : .clear, radius: 8, y: 2)
                .foregroundStyle(filled ? .white : .white)
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
        switch peek.kind {
        case .volumeBrightness: VolumeBrightnessBar()
        case .shortcuts: ShortcutsBar()
        case .media: MediaBar()
        case .text: textRow
        }
    }

    var textRow: some View {
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

// MARK: - Hover bar modes

/// A thin slider you can click or drag. Scrolling over it nudges it too.
struct MiniSlider: View {
    let icon: String; let value: Double; let set: (Double) -> Void
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent).frame(width: 16)
            GeometryReader { g in
                Capsule().fill(.white.opacity(0.15))
                    .overlay(alignment: .leading) { Capsule().fill(accentGradient).frame(width: max(6, g.size.width * value)) }
                    .frame(height: 6).frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { set(min(1, max(0, $0.location.x / g.size.width))) })
            }
            Text("\(Int(value * 100))%").font(.system(size: 10, weight: .semibold).monospacedDigit()).frame(width: 32, alignment: .trailing)
        }
    }
}

/// Volume on one half, brightness on the other.
struct VolumeBrightnessBar: View {
    @EnvironmentObject var sound: SoundModel
    @EnvironmentObject var system: SystemModel
    var body: some View {
        HStack(spacing: 16) {
            MiniSlider(icon: sound.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", value: sound.volume) { sound.setVolume($0) }
            if let b = system.brightness {
                MiniSlider(icon: "sun.max.fill", value: b) { system.setBrightness($0) }
            } else {
                Label("Brightness: built-in screen only", systemImage: "sun.max.fill").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 16).foregroundStyle(.white.opacity(0.9))
        .onAppear { system.refresh() }
    }
}

/// Your own apps and links, one click each. Set them in Settings ▸ Hover bar.
struct ShortcutsBar: View {
    @AppStorage("shortcuts") var raw = ""
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Shortcut.parse(raw)) { s in
                Button { s.open() } label: {
                    HStack(spacing: 5) {
                        s.icon.frame(width: 16, height: 16)
                        Text(s.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    }
                    .padding(.horizontal, 9).frame(height: 26)
                    .background(Capsule().fill(.white.opacity(0.09)).overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.7)))
                }.buttonStyle(PressStyle()).help(s.target)
            }
            if Shortcut.parse(raw).isEmpty {
                Text("Add apps and links in Settings ▸ Hover bar").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).foregroundStyle(.white.opacity(0.92))
    }
}

/// The current track with Previous / Play / Next.
struct MediaBar: View {
    @EnvironmentObject var playing: NowPlayingModel
    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let a = playing.artwork { Image(nsImage: a).resizable().aspectRatio(contentMode: .fill) }
                else { Image(systemName: "music.note").foregroundStyle(accent) }
            }.frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 5))
            Text(playing.title.isEmpty ? "Not playing" : playing.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            MediaButton(icon: "backward.fill") { playing.previous() }
            MediaButton(icon: playing.playing ? "pause.fill" : "play.fill") { playing.playPause() }
            MediaButton(icon: "forward.fill") { playing.next() }
        }
        .padding(.horizontal, 14).foregroundStyle(.white.opacity(0.92))
    }
}

/// One shortcut: "Name|https://link" or "Name|App Name".
struct Shortcut: Identifiable {
    let name: String; let target: String
    var id: String { name + target }
    var isLink: Bool { target.contains("://") || target.hasPrefix("www.") }
    var url: URL? {
        if isLink { return URL(string: target.hasPrefix("www.") ? "https://" + target : target) }
        for dir in ["/Applications", "/System/Applications", "/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
            let p = "\(dir)/\(target).app"
            if FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }
    @ViewBuilder var icon: some View {
        if !isLink, let u = url { Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable() }
        else { Image(systemName: isLink ? "globe" : "app.dashed").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent) }
    }
    func open() { if let u = url { NSWorkspace.shared.open(u) } }

    static func parse(_ raw: String) -> [Shortcut] {
        raw.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count == 2, !p[0].isEmpty, !p[1].isEmpty else { return nil }
            return Shortcut(name: p[0], target: p[1])
        }
    }
}
