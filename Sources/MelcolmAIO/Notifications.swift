import AppKit
import SQLite3
import SwiftUI

/// Your Mac's notifications, read from the Notification Center database.
/// macOS has no public way to list them, so this reads that file, which needs Full Disk Access.
final class NotificationsModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: Int64
        let bundle: String
        let app: String
        let title: String
        let subtitle: String
        let body: String
        let date: Date
    }

    @Published var items: [Item] = []
    @Published var needsAccess = false
    @Published var loaded = false
    private var timer: Timer?
    /// Everything delivered before this moment is hidden here ("Clear all").
    private var clearedAt: Date { Date(timeIntervalSinceReferenceDate: Prefs.d.double(forKey: "notifClearedAt")) }

    /// Hides everything in this list, and also asks Notification Center to dismiss what it is still showing.
    func clearAll() {
        Prefs.d.set(Date().timeIntervalSinceReferenceDate, forKey: "notifClearedAt")
        items = []
        DispatchQueue.global(qos: .userInitiated).async { Self.dismissOnScreen() }
    }

    /// Presses "Clear All" / "Close" on the banners and stacks Notification Center is showing (needs Accessibility).
    private static func dismissOnScreen() {
        guard AXIsProcessTrusted(),
              let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return }
        let app = AXUIElementCreateApplication(nc.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        func walk(_ e: AXUIElement, _ depth: Int) -> Bool {
            var names: CFArray?
            AXUIElementCopyActionNames(e, &names)
            if let n = (names as? [String])?.first(where: { $0.contains("Clear All") }) ?? (names as? [String])?.first(where: { $0.contains("Close") }) {
                AXUIElementPerformAction(e, n as CFString); return true
            }
            guard depth < 10 else { return false }
            var kids: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &kids)
            var any = false
            for k in (kids as? [AXUIElement]) ?? [] { if walk(k, depth + 1) { any = true } }
            return any
        }
        for _ in 0 ..< 8 {   // each press can reveal the next banner
            var wins: CFTypeRef?
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &wins)
            let hit = ((wins as? [AXUIElement]) ?? []).map { walk($0, 0) }.contains(true)
            if !hit { break }
            Thread.sleep(forTimeInterval: 0.35)
        }
    }
    private var names: [String: String] = [:]

    /// Where macOS keeps the file (it moved in macOS 15).
    private var candidates: [String] {
        let home = NSHomeDirectory()
        var l = ["\(home)/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        if let d = Self.darwinUserDir() { l.append("\(d)com.apple.notificationcenter/db2/db") }
        return l
    }
    private static func darwinUserDir() -> String? {
        var buf = [Int8](repeating: 0, count: 1024)
        guard confstr(_CS_DARWIN_USER_DIR, &buf, buf.count) > 0 else { return nil }
        return String(cString: buf)
    }

    func start() {
        reload()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.reload() }
    }
    func stop() { timer?.invalidate(); timer = nil }

    func reload() {
        DispatchQueue.global(qos: .utility).async {
            let r = self.read()
            DispatchQueue.main.async {
                self.loaded = true
                switch r {
                case .noAccess: self.needsAccess = true
                case .ok(let l): self.needsAccess = false; let l = l.filter { $0.date > self.clearedAt }; if l != self.items { self.items = l }
                }
            }
        }
    }

    private enum Result { case noAccess; case ok([Item]) }

    private func log(_ m: String) {
        let line = "\(Date()) \(m)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/melcolm-notif.log") { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
        else { try? line.write(toFile: "/tmp/melcolm-notif.log", atomically: true, encoding: .utf8) }
    }

    private func read() -> Result {
        let fm = FileManager.default
        guard let src = candidates.first(where: { fm.fileExists(atPath: $0) }) ?? candidates.first else { return .noAccess }
        // Work on a copy so the live database (and its write-ahead log) is never touched or locked.
        let tmp = NSTemporaryDirectory() + "melcolm-notif-\(ProcessInfo.processInfo.processIdentifier)"
        try? fm.removeItem(atPath: tmp)
        do { try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true) } catch { return .noAccess }
        defer { try? fm.removeItem(atPath: tmp) }
        var copied = false
        for suffix in ["", "-wal", "-shm"] {
            do { try fm.copyItem(atPath: src + suffix, toPath: tmp + "/db" + suffix); if suffix.isEmpty { copied = true } }
            catch { log("copy \(suffix) failed: \(error)") }
        }
        guard copied else { return .noAccess }
        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp + "/db", &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { log("open failed"); sqlite3_close(db); return .noAccess }
        defer { sqlite3_close(db) }
        var apps: [Int64: String] = [:]
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT app_id, identifier FROM app", -1, &st, nil) == SQLITE_OK {
            while sqlite3_step(st) == SQLITE_ROW { apps[sqlite3_column_int64(st, 0)] = String(cString: sqlite3_column_text(st, 1)) }
        }
        sqlite3_finalize(st)
        var out: [Item] = []
        guard sqlite3_prepare_v2(db, "SELECT rec_id, app_id, data, delivered_date FROM record ORDER BY delivered_date DESC LIMIT 60", -1, &st, nil) == SQLITE_OK else {
            log("query failed: \(String(cString: sqlite3_errmsg(db)))")
            var t: OpaquePointer?; var names: [String] = []
            if sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master", -1, &t, nil) == SQLITE_OK { while sqlite3_step(t) == SQLITE_ROW { names.append(String(cString: sqlite3_column_text(t, 0))) } }
            sqlite3_finalize(t); log("tables: \(names)")
            return .ok([]) }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW {
            let id = sqlite3_column_int64(st, 0)
            let bundle = apps[sqlite3_column_int64(st, 1)] ?? ""
            let secs = sqlite3_column_double(st, 3)
            guard let p = sqlite3_column_blob(st, 2) else { continue }
            let data = Data(bytes: p, count: Int(sqlite3_column_bytes(st, 2)))
            guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { continue }
            let req = plist["req"] as? [String: Any] ?? [:]
            let title = (req["titl"] as? String) ?? ""
            let sub = (req["subt"] as? String) ?? ""
            let body = (req["body"] as? String) ?? ""
            if title.isEmpty && sub.isEmpty && body.isEmpty { continue }
            out.append(Item(id: id, bundle: bundle, app: appName(bundle), title: title, subtitle: sub, body: body,
                            date: Date(timeIntervalSinceReferenceDate: secs)))
        }
        return .ok(out)
    }

    private func appName(_ bundle: String) -> String {
        if let n = names[bundle] { return n }
        var n = bundle.split(separator: ".").last.map(String.init)?.capitalized ?? bundle
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { n = FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "") }
        names[bundle] = n
        return n
    }

    static func icon(_ bundle: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
    static func open(_ bundle: String) {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { NSWorkspace.shared.open(u); openedOutside() }
    }
}

struct NotificationsPage: View {
    @StateObject private var model = NotificationsModel()

    var body: some View {
        VStack(spacing: 10) {
            if model.needsAccess {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Allow notifications").font(.system(size: 14, weight: .bold))
                                Text("macOS keeps notifications private. To show them here, add Melcolm All-in-One under Full Disk Access, then come back.")
                                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        LinkButton("Open Full Disk Access…") {
                            SystemModel.open("com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
                        }
                    }.padding(.vertical, 4)
                }
            } else if model.items.isEmpty {
                Text(model.loaded ? "No notifications" : "Loading…").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
            } else {
                HStack {
                    Text("\(model.items.count) notification\(model.items.count == 1 ? "" : "s")").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { withAnimation(.snappy(duration: 0.25)) { model.clearAll() } } label: {
                        HStack(spacing: 4) { Image(systemName: "xmark.circle.fill"); Text("Clear all") }
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(.white.opacity(0.14)))
                    }.buttonStyle(PressStyle())
                }
                ForEach(model.items) { n in
                    Button { NotificationsModel.open(n.bundle) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Group {
                                if let i = NotificationsModel.icon(n.bundle) { Image(nsImage: i).resizable() }
                                else { Image(systemName: "bell.fill").foregroundStyle(accent) }
                            }.frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(n.app.uppercased()).font(.system(size: 9.5, weight: .heavy)).kerning(0.6).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(n.date, style: .relative).font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                                if !n.title.isEmpty { Text(n.title).font(.system(size: 12.5, weight: .bold)).lineLimit(1) }
                                if !n.subtitle.isEmpty { Text(n.subtitle).font(.system(size: 11.5, weight: .semibold)).lineLimit(1) }
                                if !n.body.isEmpty { Text(n.body).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.75)).lineLimit(3) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.105))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1)))
                        .contentShape(Rectangle())
                    }.buttonStyle(PressStyle())
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
