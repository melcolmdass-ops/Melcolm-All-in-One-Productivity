import CoreAudio
import SwiftUI

let accent = Color(red: 0.40, green: 0.62, blue: 1.0)
let accent2 = Color(red: 0.62, green: 0.45, blue: 1.0)
let accentGradient = LinearGradient(colors: [Color(red: 0.36, green: 0.66, blue: 1.0), Color(red: 0.58, green: 0.42, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)

struct IslandView: View {
    @EnvironmentObject var state: IslandState
    @ObservedObject var hoverModel = HoverModel.shared
    @ObservedObject var optionDrag = OptionDrag.shared
    var hoverIsland: Bool { (hoverModel.island || (optionDrag.overBar != nil && optionDrag.overBar == state.displayID)) && !state.expanded }
    @AppStorage("colRev") var colRev = 0
    let toggle: () -> Void
    let hover: (Bool) -> Void
    var openPage: (PanelPage) -> Void = { _ in }

    var body: some View {
        // On a notched screen the collapsed island reaches into the notch so the two read as one shape.
        let attached = state.notchWidth > 0 && !state.expanded
        let collapsedW = attached ? state.collapsedWidth + state.notchWidth : state.collapsedWidth
        let w = state.expanded ? state.expandedWidth : collapsedW + 2 * state.peekExtra
        let h = state.expanded ? AppDelegate.expandedSize.height : state.barHeight + (state.peek?.height ?? 0)
        let radius: CGFloat = state.expanded ? 26 : state.peek != nil ? 16 : min(14, state.barHeight / 2.2)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)

        VStack(spacing: 0) {
            TopBar(toggle: toggle, openPage: openPage)
                .frame(width: state.expanded ? nil : collapsedW, height: state.barHeight)
            if state.expanded {
                PanelView()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.35, anchor: .top)),
                                            removal: .opacity.combined(with: .scale(scale: 0.5, anchor: .top))))
            } else if let p = state.peek {
                PeekRow(peek: p).frame(height: p.height)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: w, height: h, alignment: .top)
        .background(
            ZStack {
                shape.fill(Color.black)
                let _ = colRev
                // Resting anywhere on the island makes its outline glow brighter.
                shape.strokeBorder(BarColor.outline.color.opacity(hoverIsland ? 1 : 0.85), lineWidth: hoverIsland ? 2.2 : 1.6)
                    .neon(BarColor.outline.color, hoverIsland ? 1 : 0.4)
                    .animation(.easeOut(duration: 0.18), value: hoverIsland)
            }
            .shadow(color: .black.opacity(state.expanded ? 0.6 : 0), radius: 22, y: 10)
        )
        .clipShape(shape)
        .onHover { inside in HoverModel.shared.island = inside; hover(inside) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusEffectDisabled()
        .preferredColorScheme(.dark)
    }
}

// MARK: - Top bar (always visible): spaces | notch | live status + chevron

struct TopBar: View {
    @EnvironmentObject var state: IslandState
    @EnvironmentObject var spaces: SpacesModel
    @EnvironmentObject var timer: TimerModel
    @EnvironmentObject var playing: NowPlayingModel
    @EnvironmentObject var sound: SoundModel
    @AppStorage("barShowTimer") var showTimer = true
    @AppStorage("barShowMusic") var showMusic = true
    @AppStorage("barOrder") var barOrder = "timer,music"
    @AppStorage("colRev") var colRev = 0
    let toggle: () -> Void
    var openPage: (PanelPage) -> Void = { _ in }

    var body: some View {
        let left = state.notchWidth > 0 ? state.leftDisplays : Int.max
        HStack(spacing: 0) {
            // Display 1 sits left of the notch, the others right of it. If the front app's menus would
            // run under the left side, every display moves right so no menu is ever covered.
            Group {
                if left > 0 {
                    SpacesStrip(first: 0, count: left)
                        .padding(state.notchWidth > 0 ? .trailing : .leading, state.notchWidth > 0 ? 18 : 14)
                } else { Color.clear }
            }
            .frame(width: state.expanded && state.notchWidth > 0 ? (state.expandedWidth - state.notchWidth) / 2 : state.leftWing,
                   alignment: state.notchWidth > 0 ? .trailing : .leading)
            if state.notchWidth > 0 { NotchButton(toggle: toggle).frame(width: state.notchWidth) }
            if state.notchWidth == 0 { Spacer(minLength: 0) }
            HStack(spacing: 8) {
                if state.notchWidth > 0 && left < spaces.displays.count {
                    SpacesStrip(first: left, count: nil)
                }
                if sound.micInUse {
                    Image(systemName: "mic.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Circle().fill(Color.orange))
                        .help("Microphone is on")
                }
                let _ = (barOrder, showTimer, showMusic)
                // One glowing box: [what's playing | arrow]. Left half opens its page, right half opens the panel.
                HStack(spacing: 0) {
                if let a = BarActivity.current(timerOn: timer.isActive, musicOn: playing.playing) {
                    Button { openPage(a.page) } label: {
                        Group {
                            if a == .timer {
                                Label(timer.display, systemImage: timer.mode == .timer ? "timer" : "stopwatch")
                                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(timer.finished ? .orange : BarColor.status.color)
                                    .lineLimit(1)
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "music.note").font(.system(size: 14, weight: .bold)).foregroundStyle(BarColor.status.color)
                                    BeatWave().scaleEffect(1.25)
                                }
                            }
                        }.padding(.horizontal, 9).frame(maxHeight: .infinity).contentShape(Rectangle())
                        .hoverLift("bar-status", BarColor.status.color)
                    }.buttonStyle(PressStyle()).help(a == .music ? "\(playing.title) · click to open Now Playing" : "Click to open Clock")
                    Capsule().fill(BarColor.statusBox.color.opacity(0.45)).frame(width: 1, height: 14)
                }
                Button(action: toggle) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .heavy))
                        .rotationEffect(.degrees(state.expanded ? 180 : 0))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 40).frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .hoverLift("bar-arrow", BarColor.statusBox.color)
                }
                .buttonStyle(.plain)
                .help("Open Melcolm (⌃⌥Space)")
                }
                .frame(height: max(20, state.barHeight - 4))
                .background { NeonBox(color: BarColor.statusBox.color) }
            }
            .padding(state.notchWidth > 0 ? .leading : .trailing, state.notchWidth > 0 ? 18 : 10)
            .frame(maxWidth: .infinity, alignment: state.notchWidth > 0 ? .leading : .trailing)
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
    @AppStorage("colRev") var colRev = 0
    @AppStorage("dragSpaces") var dragOn = true
    @ObservedObject var drag = SpaceDragModel.shared
    @Namespace var ns
    var first = 0
    var count: Int? = nil

    var body: some View {
        let icon = state.iconSize
        let h = min(icon + 2 * Layout.cellPad, state.barHeight - 4)
        let all = spaces.displays
        let shown = Array(all.dropFirst(min(first, all.count)).prefix(count ?? all.count))
        HStack(spacing: Layout.chipGap) {
            ForEach(shown) { g in
                let desktops = Layout.desktops(g)
                let home = desktops.first { $0.id == g.currentID } ?? desktops.first
                HStack(spacing: 2) {
                    if let home { numberCell(g, home, on: home.id == g.currentID, icon: icon, h: h - 2) }
                    else { Color.clear.frame(width: Layout.numberCell(icon), height: h - 2) }
                    let fulls = Layout.fullscreens(g)
                    if !fulls.isEmpty {
                        Capsule().fill(BarColor.displayBox.color.opacity(0.35)).frame(width: 1, height: icon * 0.65)
                            .padding(.horizontal, 4)
                    }
                    ForEach(fulls, id: \.cellKey) { s in
                        appCell(g, s, on: s.id == g.currentID, icon: icon, h: h - 2)
                            .offset(x: drag.shift(s, in: g))
                            .zIndex(drag.dragging == s.id ? 2 : 0)
                            // Moving to another display: fade out at the pointer, grow into its new place.
                            .transition(.asymmetric(insertion: .scale(scale: 0.55).combined(with: .opacity), removal: .opacity))
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: Layout.groupWidth(g, icon: icon, m: spaces), height: h, alignment: .leading)
                .background(alignment: .leading) {
                    // The box stretches or shrinks with the apps sliding inside it while you drag.
                    NeonBox(color: BarColor.displayBox.color, strength: drag.target.map { Self.display(of: $0) == g.id } == true ? 1.2 : 0.7)
                        .frame(width: Layout.groupWidth(g, icon: icon, m: spaces) + drag.grow(g))
                }
                .dragFrame("box-\(g.id)")
                .zIndex(g.spaces.contains { $0.id == drag.dragging } ? 2 : 0)
                .help("Display \(g.number)")
            }
        }
        .animation(SpaceDragModel.drop, value: spaces.displays)
    }

    static func display(of t: SpaceDrop) -> String {
        switch t { case .desktop(let d): d; case .slot(let d, _): d }
    }

    /// One outline per display; it slides from cell to cell instead of vanishing and reappearing.
    func glow(_ on: Bool, _ display: String) -> some View {
        let r = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack {
            if on {
                let cyan = BarColor.space.color
                ZStack {
                    r.fill(LinearGradient(colors: [cyan.opacity(style == "box" ? 0.38 : 0.22), cyan.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                    r.strokeBorder(cyan, lineWidth: 1.3).neon(cyan, style == "glow" ? 0.9 : 0.3)
                }
                .padding(.vertical, 0.5).padding(.horizontal, 0.5)
                .matchedGeometryEffect(id: "glow-\(display)", in: ns)
            }
        }
    }

    func numberCell(_ g: DisplayGroup, _ home: SpaceItem, on: Bool, icon: CGFloat, h: CGFloat) -> some View {
        Button { spaces.switchTo(home) } label: {
            Group {
                if showNumbers {
                    Text("\(g.number)").font(.system(size: icon * 0.72, weight: .heavy, design: .rounded))
                        .foregroundStyle(on ? .white : BarColor.number.color.opacity(0.9))
                } else {
                    Circle().fill(on ? .white : BarColor.number.color).frame(width: 8, height: 8)
                }
            }
            .frame(width: Layout.numberCell(icon), height: h)
            .background(glow(on, g.id))
            .overlay {
                // Drop a dragged app here to take it out of full screen onto this desktop.
                if drag.target == .desktop(g.id) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(BarColor.space.color, lineWidth: 1.6)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(BarColor.space.color.opacity(0.25)))
                        .neon(BarColor.space.color, 1).scaleEffect(1.12)
                }
            }
            .contentShape(Rectangle())
            .hoverLift("num-\(g.id)", BarColor.number.color, radius: 6)
            .dragFrame("num-\(g.id)")
        }
        .buttonStyle(PressStyle())
        .help("Desktop \(g.number)")
    }

    func appCell(_ g: DisplayGroup, _ s: SpaceItem, on: Bool, icon: CGFloat, h: CGFloat) -> some View {
        let list = Array((spaces.apps[s.id] ?? []).prefix(2))
        let app = list.first
        let dim = dimOthers && !on
        let canDrag = dragOn && list.count <= 1 && !spaces.split.contains(s.id) && !SpaceMover.busy
        let lifted = drag.dragging == s.id
        return Button {
            if Date().timeIntervalSince(drag.droppedAt) < 0.35 { return }
            if let app, iconClick == "app" { spaces.focus(app, on: s) } else { spaces.switchTo(s) }
        } label: {
            Group {
                if showIcons, !list.isEmpty {
                    // Split view: both apps sit in the same highlighted box.
                    HStack(spacing: 3) {
                        // The icon always fits inside its highlight, so the outline is never covered.
                        let ic = max(14, min(icon, h - 3))
                        ForEach(list) { a in Image(nsImage: a.icon).resizable().interpolation(.high).frame(width: ic, height: ic) }
                    }
                } else {
                    Image(systemName: "rectangle.inset.filled").font(.system(size: icon * 0.6))
                        .foregroundStyle(.white.opacity(0.6)).frame(width: icon, height: icon)
                }
            }
            .opacity(dim ? 0.5 : 1).saturation(dim ? 0.4 : 1)
            .frame(width: Layout.iconCell(icon, apps: max(1, list.count)), height: h)
            .background(glow(on, g.id))
            .contentShape(Rectangle())
            .hoverLift("app-\(s.id)", BarColor.space.color, radius: 6)
            .dragFrame("app-\(s.id)")
            .scaleEffect(lifted ? 1.15 : 1)
            .shadow(color: lifted ? BarColor.space.color.opacity(0.8) : .clear, radius: 8)
            .offset(lifted ? drag.offset : .zero)
        }
        .buttonStyle(PressStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { v in
                    drag.begin(s.id, model: spaces)
                    drag.update(v.location, offset: CGSize(width: v.translation.width, height: max(-6, min(6, v.translation.height))), model: spaces)
                }
                .onEnded { _ in drag.end(model: spaces) },
            including: canDrag ? .all : .subviews)
        .help(list.isEmpty ? "Full-screen app" : list.map(\.name).joined(separator: " + "))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.compactPage) var compact
    var body: some View {
        content.padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 6 : 14).frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.105))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            )
    }
}

struct SettingsTab: View {
    enum Page: String, CaseIterable { case general = "General", commands = "Commands", bar = "Bar", display = "Display on bar", spaces = "Spaces", dragging = "Dragging", mouse = "Mouse", hover = "Hover bar", panel = "Pages", utility = "Utility Bar", colors = "Colors", rules = "Master Rules", updates = "Update Log" }
    /// Top tabs, each with its own sub-tabs.
    static let groups: [(name: String, tabs: [Page])] = [
        ("General", [.general, .commands]), ("Main Bar", [.bar, .panel, .display, .spaces, .mouse, .hover]), ("Dragging", [.dragging]), ("Utility Bar", [.utility]), ("Colors", [.colors]),
        ("Master Rules", [.rules]), ("Update Log", [.updates]),
    ]
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
    @AppStorage("homePinned") var homePinned = ""
    @AppStorage("scrollSwitches") var scrollSwitch = true
    @AppStorage("closeOnClickOutside") var closeOutside = true
    @AppStorage("hotkeyToggle") var hkToggle = true
    @AppStorage("hotkeyNumbers") var hkNumbers = true

    var body: some View {
        VStack(spacing: 10) {
            let cur = Page(rawValue: page) ?? .general
            let group = Self.groups.first { $0.tabs.contains(cur) } ?? Self.groups[0]
            HStack(spacing: 3) {
                ForEach(Self.groups, id: \.name) { g in
                    let on = g.name == group.name
                    Button { page = g.tabs[0].rawValue } label: {
                        Text(g.name).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).fixedSize()
                            .foregroundStyle(on ? .white : .white.opacity(0.7))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Capsule().fill(on ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.06))))
                    }.buttonStyle(.plain)
                }
            }
            if group.tabs.count > 1 {
                HStack(spacing: 14) {
                    ForEach(group.tabs, id: \.self) { t in
                        Button { page = t.rawValue } label: {
                            VStack(spacing: 3) {
                                Text(t == .general ? "Main" : t.rawValue).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(t == cur ? .white : .white.opacity(0.5))
                                Capsule().fill(t == cur ? accent : .clear).frame(height: 2)
                            }.fixedSize().contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if cur != .updates { SettingsVisual(page: cur) }
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    switch Page(rawValue: page) ?? .general {
                    case .general: general
                    case .bar: bar
                    case .display: displayPage
                    case .panel: panelPage
                    case .spaces: spacesPage
                    case .dragging: DraggingSettings()
                    case .mouse: mouse
                    case .hover: hoverPage
                    case .commands: commandsPage
                    case .utility: utilityPage
                    case .colors: ColorsPage()
                    case .rules: MasterRulesPage()
                    case .updates: UpdateLogPage()
                    }
                }
            }
            Text("Melcolm All-in-One Productivity · v2.13").font(.system(size: 10)).foregroundStyle(.tertiary)
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
    }

    /// Everything that shows up in the bar while something is going on.
    @ViewBuilder var displayPage: some View {
        sectionLabel("Beside the arrow (only one fits)")
        Text("When more than one is going, the one highest up shows. Click it in the bar to open its page.")
            .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        let order = BarActivity.order
        ForEach(Array(order.enumerated()), id: \.element) { i, a in
            HStack(spacing: 8) {
                Text("\(i + 1)").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(accent).frame(width: 14)
                Image(systemName: a.icon).frame(width: 18)
                Text(a.title).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Button { move(a, -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain).disabled(i == 0).help("Show first")
                Button { move(a, 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain).disabled(i == order.count - 1)
                Toggle("", isOn: a == .timer ? $barTimer : $barMusic).labelsHidden()
            }
            .padding(.horizontal, 8).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.05)))
            .onDrag { NSItemProvider(object: a.rawValue as NSString) }
            .onDrop(of: [.text], isTargeted: nil) { items in
                items.first?.loadObject(ofClass: NSString.self) { s, _ in
                    guard let s = s as? String, let from = BarActivity(rawValue: s) else { return }
                    DispatchQueue.main.async { place(from, at: i) }
                }
                return true
            }
        }
        Hairline().padding(.vertical, 2)
        row("Pop-ups for song, output and timer") { Toggle("", isOn: $live).labelsHidden() }
    }

    @AppStorage("barOrder") var barOrder = "timer,music"
    @AppStorage("utilityBar") var utilityBar = true
    @AppStorage("utilityItems") var utilityRaw = "sound,network,brightness,batteries"

    @ViewBuilder var utilityPage: some View {
        row("Show the utility bar (bottom of Home)") { Toggle("", isOn: $utilityBar).labelsHidden() }
        Text("Pick what sits on the bar. Click one on Home and its page opens as a pop-up right there. Order follows Pages.")
            .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        let on = Set(utilityRaw.split(separator: ",").map(String.init))
        ForEach(PanelPage.listed, id: \.self) { p in
            row(p.title) {
                Toggle("", isOn: Binding(get: { on.contains(p.rawValue) }, set: { v in
                    var set = on; if v { set.insert(p.rawValue) } else { set.remove(p.rawValue) }
                    utilityRaw = PanelPage.listed.filter { set.contains($0.rawValue) }.map(\.rawValue).joined(separator: ",")
                })).labelsHidden()
            }
        }
    }
    func move(_ a: BarActivity, _ d: Int) {
        var l = BarActivity.order
        guard let i = l.firstIndex(of: a), l.indices.contains(i + d) else { return }
        l.swapAt(i, i + d); barOrder = l.map(\.rawValue).joined(separator: ",")
    }
    func place(_ a: BarActivity, at j: Int) {
        var l = BarActivity.order.filter { $0 != a }
        l.insert(a, at: min(j, l.count)); barOrder = l.map(\.rawValue).joined(separator: ",")
    }

    @ViewBuilder var panelPage: some View {
        HStack {
            Text("PAGE").font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary)
            Spacer()
            Text("QUICK VIEW (\(PanelPage.pinned(homePinned).count)/\(PanelPage.maxPinned))").font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary).frame(width: 130)
            Text("SHOW").font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary).frame(width: 44)
        }
        ForEach(PanelPage.listed, id: \.self) { t in
            row(t.title, drag: t) {
                let pins = PanelPage.pinned(homePinned)
                Toggle("", isOn: Binding(
                    get: { pins.contains(t) },
                    set: { on in
                        var l = pins.filter { $0 != t }
                        if on { l.append(t) }
                        homePinned = l.prefix(PanelPage.maxPinned).map(\.rawValue).joined(separator: ",")
                    })).labelsHidden().disabled(!pins.contains(t) && pins.count >= PanelPage.maxPinned)
                    .frame(width: 130)
                Toggle("", isOn: Binding(
                    get: { !hiddenTiles.split(separator: ",").contains(Substring(t.rawValue)) },
                    set: { show in
                        var set = Set(hiddenTiles.split(separator: ",").map(String.init))
                        if show { set.remove(t.rawValue) } else { set.insert(t.rawValue) }
                        hiddenTiles = set.sorted().joined(separator: ",")
                    })).labelsHidden().frame(width: 44)
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

    @AppStorage("hoverBarMode") var hoverMode = "smart"
    @AppStorage("popSong") var popSong = true
    @AppStorage("popOutput") var popOutput = true
    @AppStorage("popTimer") var popTimer = true
    @AppStorage("popCharge") var popCharge = true
    @AppStorage("popBattery") var popBattery = true
    @AppStorage("popFocus") var popFocus = true
    @AppStorage("popSpace") var popSpace = false
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
                Text("Smart").tag("smart"); Divider()
                Text("Summary").tag("summary"); Text("Volume + Brightness").tag("volumeBrightness")
                Text("Shortcuts").tag("shortcuts"); Text("Music controls").tag("media")
            }.labelsHidden().frame(width: 200)
        }
        Text(hoverHelp).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        sectionLabel("Pop up when")
        row("A new song starts") { Toggle("", isOn: $popSong).labelsHidden() }
        row("Sound moves to AirPods or speakers") { Toggle("", isOn: $popOutput).labelsHidden() }
        row("The timer ends") { Toggle("", isOn: $popTimer).labelsHidden() }
        row("Charger plugged in or out") { Toggle("", isOn: $popCharge).labelsHidden() }
        row("Battery gets low (20%, 10%)") { Toggle("", isOn: $popBattery).labelsHidden() }
        row("A Focus mode starts or ends") { Toggle("", isOn: $popFocus).labelsHidden() }
        row("You switch Space (shows which)") { Toggle("", isOn: $popSpace).labelsHidden() }
        if hoverMode == "shortcuts" {
            sectionLabel("Shortcuts")
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
        case "smart": "Music controls while a song plays, otherwise one line with the timer, or battery and output."
        default: "One line: the timer, the song, or battery and output."
        }
    }
    func save(_ l: [Shortcut]) { shortcutsRaw = l.map { "\($0.name)|\($0.target)" }.joined(separator: "\n") }
    func add() {
        guard !newName.isEmpty, !newTarget.isEmpty else { return }
        save(Shortcut.parse(shortcutsRaw) + [Shortcut(name: newName, target: newTarget)])
        newName = ""; newTarget = ""
    }

    @AppStorage("cmdMods") var cmdMods = "ctrlOpt"
    @AppStorage("hotkeyNumbers") var hkNumbersOn = true

    @ViewBuilder var commandsPage: some View {
        row("Shortcuts use") {
            Picker("", selection: $cmdMods) {
                ForEach(Hotkeys.modifierChoices, id: \.id) { Text($0.label).tag($0.id) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
        sectionLabel("Commands")
        ForEach(Hotkeys.commands) { c in CommandRow(c: c, mods: Hotkeys.modifierChoices.first { $0.id == cmdMods }?.label ?? "⌃⌥") }
        row("Go to desktop 1…9") {
            Text((Hotkeys.modifierChoices.first { $0.id == cmdMods }?.label ?? "⌃⌥") + "1…9").font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary).padding(.horizontal, 8).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.08)))
            Toggle("", isOn: $hkNumbersOn).labelsHidden()
        }
        Text("While the panel is open: Esc goes back · Space plays/pauses · ↑↓ volume · ←→ or 1–9 desktops · , Settings")
            .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        row("Mission Control shortcuts") { LinkButton("Keyboard Shortcuts…") { SystemModel.open("com.apple.Keyboard-Settings.extension") } }
    }

    func row<C: View>(_ title: String, drag: PanelPage? = nil, @ViewBuilder _ control: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack {
                if drag != nil {
                    Image(systemName: "line.3.horizontal").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 16).help("Drag to reorder")
                }
                Text(title).font(.system(size: 12.5, weight: .medium)); Spacer(); control()
            }.frame(minHeight: 30).contentShape(Rectangle())
            Hairline().padding(.top, 6)
        }
        .modifier(PageDrag(page: drag, order: $pageOrder))
    }
    @AppStorage("pageOrder") var pageOrder = ""
}

struct Pill: View {
    let title: String; var filled = false; let action: () -> Void
    init(_ title: String, filled: Bool = false, action: @escaping () -> Void) { self.title = title; self.filled = filled; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(filled ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.1))))
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
            // Every pop-up looks the same: a small rounded badge, then one line.
            Group {
                if let art = peek.image { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) }
                else { Image(systemName: peek.icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
            }
            .frame(width: 18, height: 18).background(accent).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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
                    .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: max(6, g.size.width * value)) }
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
                    .background(Capsule().fill(.white.opacity(0.1)))
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
    func open() { if let u = url { NSWorkspace.shared.open(u); openedOutside() } }

    static func parse(_ raw: String) -> [Shortcut] {
        raw.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count == 2, !p[0].isEmpty, !p[1].isEmpty else { return nil }
            return Shortcut(name: p[0], target: p[1])
        }
    }
}

/// One command: its name, the key you can change, and an on/off switch.
struct CommandRow: View {
    let c: Hotkeys.Command; let mods: String
    @AppStorage var key: String
    @AppStorage var on: Bool
    init(c: Hotkeys.Command, mods: String) {
        self.c = c; self.mods = mods
        _key = AppStorage(wrappedValue: c.key, "cmd.\(c.id).key")
        _on = AppStorage(wrappedValue: c.on, Hotkeys.onKey(c.id))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(c.title).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Text(mods).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                Picker("", selection: $key) { ForEach(Hotkeys.keys, id: \.label) { Text($0.label).tag($0.label) } }
                    .labelsHidden().frame(width: 74)
                Toggle("", isOn: $on).labelsHidden()
            }.frame(minHeight: 30)
            Hairline().padding(.top, 6)
        }
    }
}


/// The notch itself is the open button: a soft glowing outline hugs its edge, brighter on hover.
struct NotchButton: View {
    @EnvironmentObject var state: IslandState
    let toggle: () -> Void
    @AppStorage("notchHover") var hot = false
    @AppStorage("colRev") var colRev = 0

    var body: some View {
        let accent = BarColor.notch.color
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
        Button(action: toggle) {
            shape.fill(Color.black)
                .overlay(shape.strokeBorder(LinearGradient(colors: [accent.opacity(0.5), accent], startPoint: .top, endPoint: .bottom),
                                            lineWidth: hot || state.expanded ? 1.8 : 1.4))
                .neon(accent, hot || state.expanded ? 1.2 : 0.75)
                .padding(.horizontal, -3).padding(.bottom, -3)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hot = h } }
        .help("Open Melcolm (⌃⌥Space)")
        .animation(.easeOut(duration: 0.2), value: state.expanded)
    }
}

extension View {
    /// Remembers where a bar cell is, so a drag can tell what it's over.
    func dragFrame(_ key: String) -> some View {
        background(GeometryReader { p in
            Color.clear
                .onAppear { SpaceDragModel.shared.frames[key] = p.frame(in: .global) }
                .onChange(of: p.frame(in: .global)) { _, f in SpaceDragModel.shared.frames[key] = f }
        })
    }
}
