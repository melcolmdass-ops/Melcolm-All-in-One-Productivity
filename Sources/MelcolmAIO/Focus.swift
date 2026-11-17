import AppKit
import ApplicationServices
import SwiftUI

/// A focus mode is a saved list of things to do in one click, like a shortcut.
struct FocusMode: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = "Focus"
    var icon = "moon.fill"
    var hideApps = true          // hide every other app
    var minimize = false         // minimize every window
    var arrange = false          // auto-arrange what's left
    var quitApps = ""            // app names, comma separated
    var openApps = ""            // app names or web links, comma separated
    var keepAwake = true
    var dark = 0                 // 0 leave, 1 dark, 2 light
    var mute = false
    var timer = 0                // minutes, 0 = none
    var clock: String? = nil     // "stopwatch" = count up instead of a timer (optional so old saves still load)
    // Feedback when the focus starts (all optional so old saves still load).
    var feedback: String? = nil       // nil = off, "message" = your message, "steps" = your message + what it did
    var feedbackText: String? = nil   // your message, e.g. "Focus"
    var feedbackApps: Bool? = nil     // list the apps (with icons) under each step, not just "all apps"
    var useStopwatch: Bool { get { clock == "stopwatch" } set { clock = newValue ? "stopwatch" : nil } }
    var shortcut = ""            // a Shortcuts shortcut to run (e.g. one that turns on Do Not Disturb)

    static let icons = ["moon.fill", "brain.head.profile", "book.fill", "pencil", "video.fill", "briefcase.fill", "figure.run", "headphones"]

    /// One-line summary shown under the name.
    var summary: String {
        var p: [String] = []
        if minimize { p.append("minimize all") } else if hideApps { p.append("hide apps") }
        if !quitApps.isEmpty { p.append("quit \(quitApps)") }
        if !openApps.isEmpty { p.append("open \(openApps)") }
        if arrange { p.append("arrange") }
        if keepAwake { p.append("keep awake") }
        if mute { p.append("mute") }
        if useStopwatch { p.append("stopwatch") } else if timer > 0 { p.append("\(timer) min timer") }
        if !shortcut.isEmpty { p.append("run “\(shortcut)”") }
        return p.isEmpty ? "Does nothing yet. Click the pencil to choose." : p.joined(separator: " · ")
    }
}

final class FocusModel: ObservableObject {
    @Published var modes: [FocusMode] { didSet { save() } }
    @Published var active: String?
    @Published var editing: String?

    init() {
        if let d = Prefs.d.data(forKey: "focusModes"), let m = try? JSONDecoder().decode([FocusMode].self, from: d) { modes = m }
        else {
            modes = [FocusMode(name: "Deep Work", icon: "brain.head.profile", timer: 50),
                     FocusMode(name: "Wind Down", icon: "moon.fill", hideApps: false, keepAwake: false, dark: 1, mute: true)]
        }
    }

    private func save() { if let d = try? JSONEncoder().encode(modes) { Prefs.d.set(d, forKey: "focusModes") } }

    func add() { let m = FocusMode(name: "New Focus"); modes.append(m); editing = m.id }
    func remove(_ id: String) { modes.removeAll { $0.id == id }; if editing == id { editing = nil } }
    func binding(_ id: String) -> Binding<FocusMode> {
        Binding(get: { self.modes.first { $0.id == id } ?? FocusMode() },
                set: { n in if let i = self.modes.firstIndex(where: { $0.id == id }) { self.modes[i] = n } })
    }

    func start(_ m: FocusMode) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        active = m.id
        let me = ProcessInfo.processInfo.processIdentifier
        let names = { (s: String) in s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        var steps: [FocusStep] = []
        let quit = names(m.quitApps).map { $0.lowercased() }
        var quitList: [NSRunningApplication] = []
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular && a.processIdentifier != me {
            if quit.contains((a.localizedName ?? "").lowercased()) { quitList.append(a); a.terminate() }
        }
        if !quitList.isEmpty { steps.append(.init(icon: "xmark.app.fill", tint: .red, verb: "Quit", all: "the apps you picked", apps: quitList)) }
        if m.minimize {
            let list = Self.minimizeAll()
            steps.append(.init(icon: "rectangle.compress.vertical", tint: .purple, verb: "Minimized", all: "all windows", apps: list))
        } else if m.hideApps {
            var list: [NSRunningApplication] = []
            for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular && a.processIdentifier != me
                && a.bundleIdentifier != "com.apple.finder" && !a.isHidden { list.append(a); a.hide() }
            steps.append(.init(icon: "eye.slash.fill", tint: .orange, verb: "Hid", all: "all other apps", apps: list))
        }
        let opens = names(m.openApps)
        for item in opens {
            if item.contains("."), !item.hasSuffix(".app"), let url = URL(string: item.hasPrefix("http") ? item : "https://\(item)") {
                NSWorkspace.shared.open(url)
            } else {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", item]; try? p.run()
            }
        }
        if !opens.isEmpty { openedOutside(); steps.append(.init(icon: "arrow.up.forward.app.fill", tint: .green, verb: "Opened", all: opens.joined(separator: ", "), names: opens)) }
        if m.arrange { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { _ = Tiler.autoArrange() }
            steps.append(.init(icon: "rectangle.split.2x2.fill", tint: .blue, verb: "Arranged", all: "your windows")) }
        if m.keepAwake { if !app.system.awake { app.system.toggleAwake() }
            steps.append(.init(icon: "cup.and.saucer.fill", tint: .yellow, verb: "Keeping", all: "the screen awake")) }
        if m.mute { if !app.sound.muted { app.sound.toggleMute() }
            steps.append(.init(icon: "speaker.slash.fill", tint: .pink, verb: "Muted", all: "the sound")) }
        if m.useStopwatch { app.timer.startStopwatch(); steps.append(.init(icon: "stopwatch", tint: .cyan, verb: "Started", all: "the stopwatch")) }
        else if m.timer > 0 { app.timer.start(minutes: Double(m.timer)); steps.append(.init(icon: "timer", tint: .cyan, verb: "Started", all: "a \(m.timer) min timer")) }
        let scs = names(m.shortcut)
        for sc in scs {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); p.arguments = ["run", sc]; try? p.run()
        }
        if !scs.isEmpty { steps.append(.init(icon: "square.stack.3d.up.fill", tint: .indigo, verb: "Ran", all: scs.joined(separator: ", "))) }
        if let f = m.feedback {
            let title = (m.feedbackText ?? "").isEmpty ? m.name : m.feedbackText!
            FocusOverlay.show(title: title, icon: m.icon, steps: f == "steps" ? steps : [], showApps: m.feedbackApps ?? false)
        }
    }

    /// Ends the focus: lets the screen sleep again, brings sound back and shows hidden apps.
    func stop() {
        guard let app = NSApp.delegate as? AppDelegate, let m = modes.first(where: { $0.id == active }) else { active = nil; return }
        if m.keepAwake && app.system.awake { app.system.toggleAwake() }
        if m.mute && app.sound.muted { app.sound.toggleMute() }
        if m.useStopwatch, Prefs.bool("focusStopClock") { app.timer.pause() }
        if Prefs.bool("focusShowApps"), m.hideApps && !m.minimize { for a in NSWorkspace.shared.runningApplications where a.isHidden { a.unhide() } }
        active = nil
    }

    @discardableResult static func minimizeAll() -> [NSRunningApplication] {
        guard AXIsProcessTrusted() else { return [] }
        var done: [NSRunningApplication] = []
        let me = ProcessInfo.processInfo.processIdentifier
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular && a.processIdentifier != me {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v) == .success,
                  let list = v as? [AXUIElement] else { continue }
            for w in list { AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
            if !list.isEmpty { done.append(a) }
        }
        return done
    }
}

struct FocusPage: View {
    @EnvironmentObject var focus: FocusModel
    @Environment(\.lightPage) var light

    var body: some View {
        CompactStack {
            ForEach(focus.modes) { m in
                card(m)
                if focus.editing == m.id && !light { FocusEditor(mode: focus.binding(m.id)) }
            }
            if !light {
                Button { focus.add() } label: {
                    Label("New focus mode", systemImage: "plus").font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4])))
                        .contentShape(Rectangle())
                }.buttonStyle(PressStyle())
                SettingsLink(title: "Focus Settings", pane: "com.apple.Focus-Settings.extension")
            }
        }
    }

    func card(_ m: FocusMode) -> some View {
        let on = focus.active == m.id
        return Card {
            HStack(spacing: 12) {
                Image(systemName: m.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.12))))
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(.system(size: 13.5, weight: .bold))
                    Text(on ? "On · \(m.summary)" : m.summary).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if !light {
                    Button { focus.editing = focus.editing == m.id ? nil : m.id } label: {
                        Image(systemName: focus.editing == m.id ? "checkmark" : "pencil").font(.system(size: 11, weight: .bold))
                            .frame(width: 26, height: 26).background(Circle().fill(.white.opacity(0.08)))
                    }.buttonStyle(PressStyle()).help(focus.editing == m.id ? "Done" : "Edit")
                }
                Pill(on ? "Stop" : "Start", filled: !on) { on ? focus.stop() : focus.start(m) }
            }
        }
    }
}

/// Every setting of one focus mode: big, clear rows, each with its own picture.
struct FocusEditor: View {
    @Binding var mode: FocusMode
    @EnvironmentObject var focus: FocusModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Name", text: $mode.name).textFieldStyle(.roundedBorder).font(.system(size: 14, weight: .semibold))
                    Button { focus.remove(mode.id) } label: { Image(systemName: "trash").foregroundStyle(.red) }
                        .buttonStyle(.plain).help("Delete this focus mode")
                }
                section("Icon for this focus mode")
                HStack(spacing: 8) {
                    ForEach(FocusMode.icons, id: \.self) { i in
                        Button { mode.icon = i } label: {
                            Image(systemName: i).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(mode.icon == i ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.08))))
                        }.buttonStyle(PressStyle())
                    }
                }
                section("When it starts")
                option("eye.slash.fill", .orange, "Hide other apps", "Only what you need stays on screen", $mode.hideApps)
                option("rectangle.compress.vertical", .purple, "Minimize all windows", "Sends every window to the Dock", $mode.minimize)
                option("rectangle.split.2x2.fill", .blue, "Auto-arrange windows", "Lines up what's left side by side", $mode.arrange)
                option("cup.and.saucer.fill", .yellow, "Keep the screen awake", "Your Mac won't sleep", $mode.keepAwake)
                option("speaker.slash.fill", .pink, "Mute sound", "Silence until the focus ends", $mode.mute)
                section("Clock")
                HStack(spacing: 8) {
                    clockChoice("None", "xmark", !mode.useStopwatch && mode.timer == 0) { mode.useStopwatch = false; mode.timer = 0 }
                    clockChoice("Timer", "timer", !mode.useStopwatch && mode.timer > 0) { mode.useStopwatch = false; if mode.timer == 0 { mode.timer = 25 } }
                    clockChoice("Stopwatch", "stopwatch", mode.useStopwatch) { mode.useStopwatch = true }
                }
                if !mode.useStopwatch && mode.timer > 0 {
                    Picker("", selection: $mode.timer) {
                        Text("25 min").tag(25); Text("50 min").tag(50); Text("90 min").tag(90)
                    }.pickerStyle(.segmented).labelsHidden()
                }
                section("Feedback")
                HStack(spacing: 8) {
                    clockChoice("Off", "bell.slash", mode.feedback == nil) { mode.feedback = nil }
                    clockChoice("Message", "text.bubble.fill", mode.feedback == "message") { mode.feedback = "message" }
                    clockChoice("Message + steps", "list.bullet.rectangle.fill", mode.feedback == "steps") { mode.feedback = "steps" }
                }
                if mode.feedback != nil {
                    TextField("Your message, e.g. Focus. Let's go, Melcolm.", text: Binding(get: { mode.feedbackText ?? "" }, set: { mode.feedbackText = $0 }))
                        .textFieldStyle(.roundedBorder).font(.system(size: 13))
                }
                if mode.feedback == "steps" {
                    HStack(spacing: 8) {
                        clockChoice("Say \"all apps\"", "square.grid.2x2", !(mode.feedbackApps ?? false)) { mode.feedbackApps = false }
                        clockChoice("Show each app", "app.badge.fill", mode.feedbackApps ?? false) { mode.feedbackApps = true }
                    }
                }
                section("More")
                ChipPicker(title: "Quit apps", add: "Add app", choices: Installed.apps, icon: Installed.icon, text: $mode.quitApps)
                ChipPicker(title: "Open apps", add: "Add app", choices: Installed.apps, icon: Installed.icon, text: $mode.openApps)
                ChipPicker(title: "Run Shortcuts", add: "Add shortcut", choices: Installed.shortcuts, icon: { _ in nil }, text: $mode.shortcut)
            }
            .font(.system(size: 12)).toggleStyle(.switch).controlSize(.regular).tint(accent)
        }
    }

    func section(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary).padding(.top, 2)
    }

    /// One big switch row: a coloured picture, a title, one line on what it does.
    func option(_ icon: String, _ c: Color, _ title: String, _ text: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(c.opacity(on.wrappedValue ? 0.9 : 0.25)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: on).labelsHidden()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(on.wrappedValue ? 0.07 : 0.03)))
        .contentShape(Rectangle())
        .onTapGesture { on.wrappedValue.toggle() }
    }

    func clockChoice(_ title: String, _ icon: String, _ on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.07))))
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }

    func field(_ title: String, _ hint: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField(hint, text: text).textFieldStyle(.roundedBorder)
        }
    }
}

/// Settings ▸ Focus: how every focus starts and ends, plus the focus modes themselves.
struct FocusSettings: View {
    @AppStorage("focusEndWithTimer") var endWithTimer = true
    @AppStorage("focusShowApps") var showApps = true
    @AppStorage("focusStopClock") var stopClock = true
    @AppStorage("popFocus") var popFocus = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When a focus ends").font(.system(size: 12.5, weight: .semibold))
            Toggle("End the focus when its timer is done", isOn: $endWithTimer)
            Toggle("Stop the stopwatch when the focus ends", isOn: $stopClock)
            Toggle("Show the apps it hid", isOn: $showApps)
            Toggle("Pop-up under the bar when a focus starts or stops", isOn: $popFocus)
            Divider().opacity(0.3).padding(.vertical, 4)
            Text("Focus modes").font(.system(size: 12.5, weight: .semibold))
            Text("Click the pencil to change what a mode does.").font(.system(size: 11)).foregroundStyle(.secondary)
            FocusPage()
        }
        .toggleStyle(.switch).controlSize(.small).tint(accent)
    }
}

/// The apps on this Mac and your Shortcuts, read once, for the pick lists.
enum Installed {
    static let apps: [String] = {
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var out = Set<String>()
        for d in dirs { for f in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where f.hasSuffix(".app") { out.insert(String(f.dropLast(4))) } }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()
    private static var shortcutCache: [String]?
    static var shortcuts: [String] {
        if let c = shortcutCache { return c }
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); p.arguments = ["list"]; p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        let list = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty } ?? []
        shortcutCache = list.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return shortcutCache!
    }
    private static var icons: [String: NSImage] = [:]
    static func icon(_ name: String) -> NSImage? {
        if let i = icons[name] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) ?? NSWorkspace.shared.fullPath(forApplication: name).map({ URL(fileURLWithPath: $0) }) else { return nil }
        let i = NSWorkspace.shared.icon(forFile: url.path); icons[name] = i
        return i
    }
}

/// A tall box of picked items, each in its own outlined chip (with an ✕), and a drop-down to add more.
/// Saved as comma-separated text, so older focus modes keep working.
struct ChipPicker: View {
    let title: String
    let add: String
    let choices: [String]
    let icon: (String) -> NSImage?
    @Binding var text: String

    @StateObject private var ui = PickUI()
    private var open: Bool { ui.open }
    private var query: String { ui.query }

    /// The drop-down: a search box and every choice with its icon. Click to add; it stays open to add more.
    var picker: some View {
        let left = choices.filter { !items.contains($0) && (query.isEmpty || $0.localizedCaseInsensitiveContains(query)) }
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $ui.query).textFieldStyle(.plain).font(.system(size: 13))
                if !query.isEmpty { Button { ui.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08)))
            ScrollView {
                LazyVStack(spacing: 2) {
                    if left.isEmpty { Text(query.isEmpty ? "Nothing more to add" : "No match").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20) }
                    ForEach(left, id: \.self) { c in
                        Button { set(items + [c]) } label: {
                            HStack(spacing: 10) {
                                chipIcon(c, size: 24)
                                Text(c).font(.system(size: 13)).lineLimit(1)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(accent.opacity(0.8))
                            }
                            .padding(.horizontal, 8).frame(height: 34)
                            .contentShape(Rectangle())
                        }.buttonStyle(PickRowStyle())
                    }
                }
            }
            .frame(height: 300)
        }
        .padding(10).frame(width: 300)
        .onDisappear { ui.query = "" }
    }

    @ViewBuilder func chipIcon(_ name: String, size: CGFloat) -> some View {
        if let i = icon(name) { Image(nsImage: i).resizable().frame(width: size, height: size) }
        else {
            // Shortcuts have no public icon, so they get the Shortcuts look.
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.35, blue: 0.55), Color(red: 0.45, green: 0.35, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
    }

    var items: [String] { text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    func set(_ list: [String]) { text = list.joined(separator: ", ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { it in
                    HStack(spacing: 5) {
                        chipIcon(it, size: 18)
                        Text(it).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Button { set(items.filter { $0 != it }) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.secondary)
                        }.buttonStyle(.plain).help("Remove")
                    }
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(Capsule().fill(accent.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(accent.opacity(0.8), lineWidth: 1.2))
                }
                Button { ui.open.toggle() } label: {
                    Label(add, systemImage: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                        .padding(.horizontal, 9).frame(height: 26)
                        .background(Capsule().strokeBorder(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .popover(isPresented: $ui.open, arrowEdge: .bottom) { picker }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

/// Lays chips out left to right and wraps onto new lines.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > w { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX, x + s.width > b.maxX { x = b.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

/// A list row that lights up under the pointer.
struct PickRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }
    struct Row: View {
        let configuration: ButtonStyleConfiguration
        @StateObject private var h = PickUI()
        private var hot: Bool { h.open }
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(configuration.isPressed ? 0.16 : hot ? 0.09 : 0)))
                .onHover { h.open = $0 }
        }
    }
}

final class PickUI: ObservableObject {
    @Published var open = false
    @Published var query = ""
}

/// One thing a focus did, for the feedback overlay.
struct FocusStep: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let verb: String          // "Hid"
    let all: String           // "all other apps"
    var apps: [NSRunningApplication] = []
    var names: [String] = []  // opened apps (not running yet, so only names)
    func line(_ each: Bool) -> String {
        let n = apps.compactMap(\.localizedName)
        if each, !n.isEmpty { return "\(verb) \(n.count == 1 ? n[0] : "\(n.count) apps") for you" }
        return "\(verb) \(all) for you"
    }
    var icons: [NSImage] { apps.compactMap(\.icon) + names.compactMap { Installed.icon($0) } }
}

/// A big, calm message in the middle of the screen when a focus starts: your words first,
/// then (if you chose it) each thing it did, one by one. Click anywhere on it to close.
enum FocusOverlay {
    private static var panel: NSPanel?
    static func show(title: String, icon: String, steps: [FocusStep], showApps: Bool) {
        panel?.orderOut(nil)
        guard let sc = NSScreen.main else { return }
        let size = NSSize(width: 520, height: 108 + CGFloat(steps.count) * 48 + (showApps && steps.contains { !$0.icons.isEmpty } ? 34 : 0))
        let p = NSPanel(contentRect: NSRect(x: sc.frame.midX - size.width / 2, y: sc.frame.midY - size.height / 2, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let m = OverlayModel()
        p.contentView = NSHostingView(rootView: FocusOverlayView(title: title, icon: icon, steps: steps, showApps: showApps, m: m) { hide() })
        p.alphaValue = 0; p.orderFrontRegardless(); panel = p
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
        // Steps appear one after another, then it fades away by itself.
        for i in 0...steps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + Double(i) * 0.45) { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { m.shown = i } }
        }
        let stay = 2.6 + Double(steps.count) * 0.45 + (showApps ? 1 : 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + stay) { if panel === p { hide() } }
    }
    static func hide() {
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
    }
}

final class OverlayModel: ObservableObject { @Published var shown = -1 }

struct FocusOverlayView: View {
    let title: String
    let icon: String
    let steps: [FocusStep]
    let showApps: Bool
    @ObservedObject var m: OverlayModel
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accentGradient))
                Text(title).font(.system(size: 30, weight: .heavy)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
            }
            .opacity(m.shown >= 0 ? 1 : 0).offset(y: m.shown >= 0 ? 0 : 8)
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, st in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: st.icon).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(st.tint.opacity(0.85)))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(st.line(showApps)).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        if showApps, !st.icons.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(Array(st.icons.prefix(12).enumerated()), id: \.offset) { _, img in Image(nsImage: img).resizable().frame(width: 26, height: 26) }
                                if st.icons.count > 12 { Text("+\(st.icons.count - 12)").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(.green)
                }
                .opacity(m.shown > i ? 1 : 0).offset(x: m.shown > i ? 0 : -14)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(white: 0.04).opacity(0.97))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(accent.opacity(0.6), lineWidth: 1.5)))
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .preferredColorScheme(.dark)
    }
}
