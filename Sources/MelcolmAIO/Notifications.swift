import AppKit
import SQLite3
import SwiftUI

/// Your Mac's notifications, read from the Notification Center database (needs Full Disk Access),
/// and filtered by the Mac's own Notification settings so only apps that are turned on show up.
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
    struct Group: Identifiable, Equatable {
        let bundle: String
        let app: String
        let items: [Item]
        var id: String { bundle }
    }

    static let shared = NotificationsModel()

    @Published var items: [Item] = []
    @Published var needsAccess = false
    @Published var loaded = false
    @Published var expanded = Set<String>()     // apps showing all their notifications
    private var timer: Timer?
    private var names: [String: String] = [:]
    private var watchers = 0

    /// Newest app first, each app's notifications newest first.
    var groups: [Group] {
        var order: [String] = []
        var by: [String: [Item]] = [:]
        for i in items { if by[i.bundle] == nil { order.append(i.bundle) }; by[i.bundle, default: []].append(i) }
        return order.map { Group(bundle: $0, app: by[$0]![0].app, items: by[$0]!) }
    }

    // MARK: Clearing

    /// Everything delivered before this moment is hidden here ("Clear all").
    private var clearedAt: Date { Date(timeIntervalSinceReferenceDate: Prefs.d.double(forKey: "notifClearedAt")) }
    private var clearedApp: [String: Double] { (Prefs.d.dictionary(forKey: "notifClearedApp") as? [String: Double]) ?? [:] }

    func clear(app bundle: String) {
        var d = clearedApp; d[bundle] = Date().timeIntervalSinceReferenceDate
        Prefs.d.set(d, forKey: "notifClearedApp")
        items.removeAll { $0.bundle == bundle }
    }

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

    // MARK: Reading

    private var candidates: [String] {
        var l = ["\(NSHomeDirectory())/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        if let d = Self.darwinUserDir() { l.append("\(d)com.apple.notificationcenter/db2/db") }
        return l
    }
    private static func darwinUserDir() -> String? {
        var buf = [Int8](repeating: 0, count: 1024)
        guard confstr(_CS_DARWIN_USER_DIR, &buf, buf.count) > 0 else { return nil }
        return String(cString: buf)
    }

    /// Keep reading while a notifications view is on screen.
    func start() {
        watchers += 1
        reload()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.reload() }
    }
    func stop() {
        watchers = max(0, watchers - 1)
        if watchers == 0 { timer?.invalidate(); timer = nil }
    }

    func reload() {
        DispatchQueue.global(qos: .utility).async {
            let r = self.read()
            DispatchQueue.main.async {
                self.loaded = true
                switch r {
                case .noAccess: self.needsAccess = true
                case .ok(let l):
                    self.needsAccess = false
                    let all = self.clearedApp
                    let l = l.filter { $0.date > self.clearedAt && $0.date > Date(timeIntervalSinceReferenceDate: all[$0.bundle] ?? 0) }
                    if l != self.items { self.items = l }
                }
            }
        }
    }

    private enum Result { case noAccess; case ok([Item]) }

    /// Apps you turned notifications off for in System Settings ▸ Notifications (lower-case bundle ids).
    /// "auth" is the permission mask: 4 = alerts. 0, or badge/sound only, means the app can't show notifications.
    private func turnedOff() -> Set<String> {
        let pl = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist"
        guard let d = FileManager.default.contents(atPath: pl),
              let o = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any],
              let apps = o["apps"] as? [[String: Any]] else { return [] }
        var off = Set<String>()
        for a in apps {
            guard let id = a["bundle-id"] as? String, let auth = a["auth"] as? Int else { continue }
            if auth & 4 == 0 { off.insert(id.lowercased()) }
        }
        return off
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
            if (try? fm.copyItem(atPath: src + suffix, toPath: tmp + "/db" + suffix)) != nil, suffix.isEmpty { copied = true }
        }
        guard copied else { return .noAccess }
        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp + "/db", &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { sqlite3_close(db); return .noAccess }
        defer { sqlite3_close(db) }
        var apps: [Int64: String] = [:]
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT app_id, identifier FROM app", -1, &st, nil) == SQLITE_OK {
            while sqlite3_step(st) == SQLITE_ROW { apps[sqlite3_column_int64(st, 0)] = String(cString: sqlite3_column_text(st, 1)) }
        }
        sqlite3_finalize(st)
        let off = turnedOff()
        var out: [Item] = []
        guard sqlite3_prepare_v2(db, "SELECT rec_id, app_id, data, delivered_date FROM record ORDER BY delivered_date DESC LIMIT 200", -1, &st, nil) == SQLITE_OK else { return .ok([]) }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW {
            let id = sqlite3_column_int64(st, 0)
            let bundle = apps[sqlite3_column_int64(st, 1)] ?? ""
            if off.contains(bundle.lowercased()) { continue }
            let secs = sqlite3_column_double(st, 3)
            guard let p = sqlite3_column_blob(st, 2) else { continue }
            let data = Data(bytes: p, count: Int(sqlite3_column_bytes(st, 2)))
            guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { continue }
            let req = plist["req"] as? [String: Any] ?? [:]
            let title = (req["titl"] as? String) ?? "", sub = (req["subt"] as? String) ?? "", body = (req["body"] as? String) ?? ""
            if title.isEmpty && sub.isEmpty && body.isEmpty { continue }
            out.append(Item(id: id, bundle: bundle, app: appName(bundle), title: title, subtitle: sub, body: body,
                            date: Date(timeIntervalSinceReferenceDate: secs)))
        }
        return .ok(out)
    }

    private func appName(_ bundle: String) -> String {
        if let n = names[bundle] { return n }
        let id = bundle.split(separator: ":").last.map(String.init) ?? bundle
        var n = id.split(separator: ".").last.map(String.init)?.capitalized ?? id
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { n = FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "") }
        names[bundle] = n
        return n
    }

    static func icon(_ bundle: String) -> NSImage? {
        let id = bundle.split(separator: ":").last.map(String.init) ?? bundle
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
    static func open(_ bundle: String) {
        let id = bundle.split(separator: ":").last.map(String.init) ?? bundle
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { NSWorkspace.shared.open(u); openedOutside() }
    }
}

/// The Notifications tab: grouped by app, only apps that are on in System Settings ▸ Notifications.
struct NotificationsPage: View {
    @ObservedObject private var model = NotificationsModel.shared
    private let preview = 3

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
                                Text("macOS keeps notifications private. To show them here, add Melcolm All-in-One under Full Disk Access, then quit and reopen the app.")
                                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        LinkButton("Open Full Disk Access…") {
                            SystemModel.open("com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
                        }
                    }.padding(.vertical, 4)
                }
            } else {
                HStack(spacing: 8) {
                    Text(model.items.isEmpty ? "Matches your Mac's Notification settings" : "\(model.items.count) from \(model.groups.count) app\(model.groups.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { SystemModel.open("com.apple.Notifications-Settings.extension") } label: {
                        Image(systemName: "gearshape").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 24)
                            .background(Circle().fill(.white.opacity(0.1)))
                    }.buttonStyle(PressStyle()).help("Notification settings")
                    if !model.items.isEmpty {
                        Button { withAnimation(.snappy(duration: 0.25)) { model.clearAll() } } label: {
                            HStack(spacing: 4) { Image(systemName: "xmark.circle.fill"); Text("Clear all") }
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(.white.opacity(0.14)))
                        }.buttonStyle(PressStyle())
                    }
                }
                if model.items.isEmpty {
                    Text(model.loaded ? "No notifications" : "Loading…").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 24)
                }
                ForEach(model.groups) { g in group(g) }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    func group(_ g: NotificationsModel.Group) -> some View {
        let open = model.expanded.contains(g.bundle)
        let shown = open ? g.items : Array(g.items.prefix(preview))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { NotificationsModel.open(g.bundle) } label: {
                    HStack(spacing: 8) {
                        Group {
                            if let i = NotificationsModel.icon(g.bundle) { Image(nsImage: i).resizable() }
                            else { Image(systemName: "bell.fill").foregroundStyle(accent) }
                        }.frame(width: 22, height: 22)
                        Text(g.app.uppercased()).font(.system(size: 10.5, weight: .heavy)).kerning(0.6)
                        Text("\(g.items.count)").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).frame(height: 16)
                            .background(Capsule().fill(.white.opacity(0.14)))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).help("Open \(g.app)")
                Spacer()
                Button { withAnimation(.snappy(duration: 0.25)) { model.clear(app: g.bundle) } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 20)
                        .background(Circle().fill(.white.opacity(0.1)))
                }.buttonStyle(PressStyle()).help("Clear \(g.app)")
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            ForEach(shown) { n in
                Hairline().padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(n.title.isEmpty ? (n.subtitle.isEmpty ? n.body : n.subtitle) : n.title).font(.system(size: 12.5, weight: .bold)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(n.date, style: .relative).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    if !n.title.isEmpty, !n.subtitle.isEmpty { Text(n.subtitle).font(.system(size: 11.5, weight: .semibold)).lineLimit(1) }
                    if !n.title.isEmpty || !n.subtitle.isEmpty, !n.body.isEmpty {
                        Text(n.body).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
                    }
                }.padding(.horizontal, 12).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
            }
            if g.items.count > preview {
                Button { withAnimation(.snappy(duration: 0.25)) { if open { model.expanded.remove(g.bundle) } else { model.expanded.insert(g.bundle) } } } label: {
                    Text(open ? "Show less" : "Show \(g.items.count - preview) more").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.plain)
            } else { Color.clear.frame(height: 4) }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.105))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1)))
    }
}
