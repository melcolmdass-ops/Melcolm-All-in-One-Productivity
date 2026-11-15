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
        if dark == 1 { p.append("dark") } else if dark == 2 { p.append("light") }
        if mute { p.append("mute") }
        if timer > 0 { p.append("\(timer) min timer") }
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
        if m.arrange { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { _ = Tiler.autoArrange() } }
        if m.keepAwake && !app.system.awake { app.system.toggleAwake() }
        if (m.dark == 1 && !app.system.dark) || (m.dark == 2 && app.system.dark) { app.system.toggleDark() }
        if m.mute && !app.sound.muted { app.sound.toggleMute() }
        if m.timer > 0 { app.timer.start(minutes: Double(m.timer)) }
        if !m.shortcut.isEmpty {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); p.arguments = ["run", m.shortcut]; try? p.run()
        }
    }

    /// Ends the focus: lets the screen sleep again, brings sound back and shows hidden apps.
    func stop() {
        guard let app = NSApp.delegate as? AppDelegate, let m = modes.first(where: { $0.id == active }) else { active = nil; return }
        if m.keepAwake && app.system.awake { app.system.toggleAwake() }
        if m.mute && app.sound.muted { app.sound.toggleMute() }
        if m.hideApps && !m.minimize { for a in NSWorkspace.shared.runningApplications where a.isHidden { a.unhide() } }
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

/// Every setting of one focus mode, as simple switches and boxes.
struct FocusEditor: View {
    @Binding var mode: FocusMode
    @EnvironmentObject var focus: FocusModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Name", text: $mode.name).textFieldStyle(.roundedBorder)
                    Button { focus.remove(mode.id) } label: { Image(systemName: "trash").foregroundStyle(.red) }
                        .buttonStyle(.plain).help("Delete this focus mode")
                }
                HStack(spacing: 6) {
                    ForEach(FocusMode.icons, id: \.self) { i in
                        Button { mode.icon = i } label: {
                            Image(systemName: i).font(.system(size: 11)).frame(width: 24, height: 24)
                                .background(Circle().fill(mode.icon == i ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.08))))
                        }.buttonStyle(.plain)
                    }
                }
                Toggle("Hide other apps", isOn: $mode.hideApps)
                Toggle("Minimize all windows", isOn: $mode.minimize)
                Toggle("Auto-arrange windows", isOn: $mode.arrange)
                Toggle("Keep the screen awake", isOn: $mode.keepAwake)
                Toggle("Mute sound", isOn: $mode.mute)
                Picker("Look", selection: $mode.dark) {
                    Text("Leave").tag(0); Text("Dark").tag(1); Text("Light").tag(2)
                }.pickerStyle(.segmented)
                Picker("Timer", selection: $mode.timer) {
                    Text("None").tag(0); Text("25 min").tag(25); Text("50 min").tag(50); Text("90 min").tag(90)
                }.pickerStyle(.segmented)
                field("Quit apps", "e.g. Messages, Mail", $mode.quitApps)
                field("Open", "apps or links, e.g. Notes, youtube.com", $mode.openApps)
                field("Run Shortcut", "name of a Shortcut, e.g. Do Not Disturb on", $mode.shortcut)
            }
            .font(.system(size: 12)).toggleStyle(.switch).controlSize(.small).tint(accent)
        }
    }

    func field(_ title: String, _ hint: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField(hint, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
