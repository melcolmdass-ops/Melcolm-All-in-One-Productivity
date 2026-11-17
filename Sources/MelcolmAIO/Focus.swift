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
        let quit = names(m.quitApps).map { $0.lowercased() }
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular && a.processIdentifier != me {
            if quit.contains((a.localizedName ?? "").lowercased()) { a.terminate() }
        }
        if m.minimize { Self.minimizeAll() }
        else if m.hideApps {
            for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular && a.processIdentifier != me
                && a.bundleIdentifier != "com.apple.finder" { a.hide() }
        }
        for item in names(m.openApps) {
            if item.contains("."), !item.hasSuffix(".app"), let url = URL(string: item.hasPrefix("http") ? item : "https://\(item)") {
                NSWorkspace.shared.open(url)
            } else {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", item]; try? p.run()
            }
        }
        if !names(m.openApps).isEmpty { openedOutside() }
        if m.arrange { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { _ = Tiler.autoArrange() } }
        if m.keepAwake && !app.system.awake { app.system.toggleAwake() }
        if m.mute && !app.sound.muted { app.sound.toggleMute() }
        if m.useStopwatch { app.timer.startStopwatch() } else if m.timer > 0 { app.timer.start(minutes: Double(m.timer)) }
        if !m.shortcut.isEmpty {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); p.arguments = ["run", m.shortcut]; try? p.run()
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

    static func minimizeAll() {
        guard AXIsProcessTrusted() else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular && a.processIdentifier != me {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(a.processIdentifier), kAXWindowsAttribute as CFString, &v) == .success,
                  let list = v as? [AXUIElement] else { continue }
            for w in list { AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
        }
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
                section("More")
                field("Quit apps", "e.g. Messages, Mail", $mode.quitApps)
                field("Open", "apps or links, e.g. Notes, youtube.com", $mode.openApps)
                field("Run Shortcut", "name of a Shortcut, e.g. Do Not Disturb on", $mode.shortcut)
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
