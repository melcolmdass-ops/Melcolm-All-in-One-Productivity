import AppKit
import ApplicationServices

/// Reads a web player's own play bar and buttons through Chrome's accessibility tree, so a tab
/// or web app (YouTube Music) can be read and controlled without ever coming to the front.
enum WebAX {
    struct Found {
        var pos: Double = 0; var dur: Double = 0; var playing: Bool?
        var play: AXUIElement?; var next: AXUIElement?; var prev: AXUIElement?; var slider: AXUIElement?
        var hasTime: Bool { dur > 0 }
    }

    private static var enabled = Set<pid_t>()
    /// Chrome only builds the web page's accessibility tree when asked to.
    static func enable(_ pid: pid_t) {
        guard !enabled.contains(pid) else { return }
        let a = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(a, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        enabled.insert(pid)
    }

    private static func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
    }
    private static func str(_ e: AXUIElement, _ k: String) -> String { attr(e, k) as? String ?? "" }
    private static func num(_ e: AXUIElement, _ k: String) -> Double? { (attr(e, k) as? NSNumber)?.doubleValue }

    static func seconds(_ s: String) -> Double? {
        let p = s.split(separator: ":").compactMap { Double($0) }
        guard p.count >= 2, p.count == s.split(separator: ":").count else { return nil }
        return p.reduce(0) { $0 * 60 + $1 }
    }

    /// Looks through one window (the one whose title contains `title`, or the first) of that app.
    static func find(pid: pid_t, title: String) -> Found? {
        guard AXIsProcessTrusted() else { BrowserMedia.log("ax not trusted"); return nil }
        enable(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        var wins = attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if !wins.contains(where: { !title.isEmpty && str($0, kAXTitleAttribute).localizedCaseInsensitiveContains(title.prefix(30)) }) {
            wins += allWindows(pid).filter { w in !wins.contains { CFEqual($0, w) } }   // other Spaces aren't in the normal list
        }
        guard !wins.isEmpty else { BrowserMedia.log("ax pid \(pid): no windows"); return nil }
        BrowserMedia.log("ax pid \(pid) title=\(title) wins=\(wins.map { str($0, kAXTitleAttribute) })")
        let t = title.prefix(30)
        // The window showing that tab; else any window that has a player (e.g. the YouTube Music app).
        let pick = wins.filter { !t.isEmpty && str($0, kAXTitleAttribute).localizedCaseInsensitiveContains(t) }
        let rest = wins.filter { w in let n = str(w, kAXTitleAttribute).lowercased(); return n.isEmpty || n.contains("youtube") || n.contains("spotify") || n.contains("soundcloud") || n.contains("music") }
        for w in pick + rest { if let f = scan(w) { return f } }
        return nil
    }

    private static func scan(_ win: AXUIElement) -> Found? {
        var f = Found(); var queue = [win]; var seen = 0
        while !queue.isEmpty, seen < 6000 {
            let e = queue.removeFirst(); seen += 1
            let role = str(e, kAXRoleAttribute)
            if role == kAXStaticTextRole, f.dur == 0 {
                let v = str(e, kAXValueAttribute)
                let parts = v.components(separatedBy: " / ")
                if parts.count == 2, let a = seconds(parts[0].trimmingCharacters(in: .whitespaces)),
                   let b = seconds(parts[1].trimmingCharacters(in: .whitespaces)), b > 0 { f.pos = a; f.dur = b }
            } else if role == kAXSliderRole {
                let label = (str(e, kAXDescriptionAttribute) + " " + str(e, kAXTitleAttribute)).lowercased()
                if label.contains("seek") || label.contains("progress") || label.contains("playback") {
                    f.slider = e
                    if f.dur == 0, let v = num(e, kAXValueAttribute), let m = num(e, kAXMaxValueAttribute), m > 1 { f.pos = v; f.dur = m }
                }
            } else if role == kAXButtonRole {
                let label = (str(e, kAXDescriptionAttribute) + " " + str(e, kAXTitleAttribute)).trimmingCharacters(in: .whitespaces).lowercased()
                if f.play == nil, label.hasPrefix("pause") { f.play = e; f.playing = true }
                else if f.play == nil, label.hasPrefix("play") && !label.hasPrefix("playlist") && !label.contains("all") { f.play = e; f.playing = false }
                else if f.next == nil, label.hasPrefix("next") { f.next = e }
                else if f.prev == nil, label.hasPrefix("previous") { f.prev = e }
            }
            if let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf: kids) }
        }
        BrowserMedia.log("ax scanned \(seen) play=\(f.play != nil) dur=\(f.dur)")
        return f.play != nil || f.hasTime ? f : nil
    }

    /// Every window of the app, including ones on other Spaces or in full screen. The normal
    /// window list only has the current Space, so ask for each element id directly (as AltTab does).
    private typealias MakeElement = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private static let make: MakeElement? = {
        guard let f = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken") else { BrowserMedia.log("ax no remote token fn"); return nil }
        return unsafeBitCast(f, to: MakeElement.self)
    }()
    /// Every window of an app on any Space (the normal list only has the current Space's).
    static func windowsEverywhere(_ pid: pid_t) -> [AXUIElement] {
        windowCache[pid] = nil
        return allWindows(pid).filter { str($0, kAXRoleAttribute) == kAXWindowRole }
    }

    private static var windowCache: [pid_t: (wins: [AXUIElement], at: Date)] = [:]
    static func allWindows(_ pid: pid_t) -> [AXUIElement] {
        if let c = windowCache[pid], Date().timeIntervalSince(c.at) < 15 { return c.wins }
        guard let make else { return [] }
        var out: [AXUIElement] = []
        for id: UInt64 in 0 ..< 6000 {
            var token = Data(count: 20)
            token.replaceSubrange(0 ..< 4, with: withUnsafeBytes(of: pid) { Data($0) })
            token.replaceSubrange(4 ..< 8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
            token.replaceSubrange(8 ..< 12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
            token.replaceSubrange(12 ..< 20, with: withUnsafeBytes(of: id) { Data($0) })
            guard let e = make(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(e, 0.1)
            let role = str(e, kAXRoleAttribute)
            if role == kAXWindowRole || role == "AXWebArea" { out.append(e) }
        }
        windowCache[pid] = (out, Date())
        BrowserMedia.log("ax sweep \(out.map { str($0, kAXRoleAttribute) + ":" + str($0, kAXTitleAttribute).prefix(30) })")
        return out
    }

    @discardableResult static func press(_ e: AXUIElement?) -> Bool {
        guard let e else { return false }
        return AXUIElementPerformAction(e, kAXPressAction as CFString) == .success
    }

    static func seek(_ e: AXUIElement?, to t: Double) -> Bool {
        guard let e else { return false }
        return AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, NSNumber(value: t)) == .success
    }
}

/// Battery levels: the Mac, plus every connected Bluetooth device that reports one
/// (AirPods left / right / case, keyboards, mice, headphones).
struct BatteryItem: Identifiable, Equatable {
    let id: String; let name: String; let icon: String; let percent: Int; var charging = false
}

final class BatteryModel: ObservableObject {
    @Published var devices: [BatteryItem] = []
    private let q = DispatchQueue(label: "melcolm.batteries")

    init() {
        refresh()
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        q.async { [weak self] in
            let list = Self.bluetooth() + Self.ioreg()
            var seen = Set<String>(); let unique = list.filter { seen.insert($0.id).inserted }
            DispatchQueue.main.async { if self?.devices != unique { self?.devices = unique } }
        }
    }

    private static func run(_ path: String, _ args: [String]) -> Data {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return Data() }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); return d
    }

    private static func icon(_ type: String, _ name: String) -> String {
        let n = name.lowercased(), t = type.lowercased()
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods") { return "airpods" }
        if t.contains("keyboard") || n.contains("keyboard") { return "keyboard" }
        if t.contains("mouse") || n.contains("mouse") { return "computermouse" }
        if t.contains("trackpad") || n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if t.contains("headphone") || t.contains("headset") { return "headphones" }
        return "dot.radiowaves.left.and.right"
    }

    private static func bluetooth() -> [BatteryItem] {
        let d = run("/usr/sbin/system_profiler", ["-json", "SPBluetoothDataType"])
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let top = (o["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let conn = top["device_connected"] as? [[String: Any]] else { return [] }
        var out: [BatteryItem] = []
        for entry in conn { for (name, v) in entry {
            guard let info = v as? [String: Any] else { continue }
            let type = info["device_minorType"] as? String ?? ""
            func pct(_ k: String) -> Int? { (info[k] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
            let ic = icon(type, name)
            let parts: [(String, String, Int?)] = [("Left", "L", pct("device_batteryLevelLeft")), ("Right", "R", pct("device_batteryLevelRight")),
                                                   ("Case", "Case", pct("device_batteryLevelCase")), ("", "", pct("device_batteryLevelMain"))]
            for (label, _, p) in parts { if let p {
                let caseIcon = ic.hasPrefix("airpods") ? (ic == "airpodspro" ? "airpodspro.chargingcase.wireless.fill" : "airpods.chargingcase.fill") : ic
                out.append(BatteryItem(id: "\(name)|\(label)", name: label.isEmpty ? name : "\(name) \(label)", icon: label == "Case" ? caseIcon : ic, percent: p))
            } }
        } }
        return out
    }

    /// Magic Keyboard / Mouse / Trackpad report here, not in system_profiler.
    private static func ioreg() -> [BatteryItem] {
        let d = run("/usr/sbin/ioreg", ["-r", "-k", "BatteryPercent", "-a"])
        guard let arr = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [[String: Any]] else { return [] }
        return arr.compactMap { e in
            guard let p = e["BatteryPercent"] as? Int, let name = e["Product"] as? String else { return nil }
            return BatteryItem(id: "\(name)|", name: name, icon: icon("", name), percent: p,
                               charging: (e["BatteryStatusFlags"] as? Int).map { $0 & 2 != 0 } ?? false)
        }
    }
}
