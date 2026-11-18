import AppKit

/// Double-tap a modifier key (like Right ⌘) to run a command: open or close the bar, change Space, and so on.
/// A tap is press + let go quickly with no other key in between, so normal shortcuts like ⌘C never count.
final class DoubleTap {
    static let shared = DoubleTap()

    /// The keys you can double-tap: label, hardware key code and the modifier flag that key sets.
    static let keys: [(label: String, code: UInt16, flag: NSEvent.ModifierFlags)] = [
        ("Left ⌘", 55, .command), ("Right ⌘", 54, .command),
        ("Left ⌥", 58, .option), ("Right ⌥", 61, .option),
        ("Left ⌃", 59, .control), ("Right ⌃", 62, .control),
        ("Left ⇧", 56, .shift), ("Right ⇧", 60, .shift),
        ("fn", 63, .function),
    ]
    static func prefKey(_ id: String) -> String { "cmd.\(id).dbl" }

    /// What each command does (filled in by AppDelegate).
    var actions: [String: () -> Void] = [:]
    /// Commands that have a double-tap key set, e.g. ["toggle": "Right ⌘"].
    var commandIDs: [String] = []

    private var monitors: [Any] = []
    private var downAt: [UInt16: Date] = [:]
    private var lastTap: (code: UInt16, at: Date)?
    private var dirty = false          // another key or click happened while a modifier was held

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e) }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e); return e }) { monitors.append(l) }
    }

    private func handle(_ e: NSEvent) {
        guard e.type == .flagsChanged else { dirty = true; lastTap = nil; return }
        guard let k = Self.keys.first(where: { $0.code == e.keyCode }) else { return }
        let pressed = e.modifierFlags.contains(k.flag)
        if pressed {
            // Pressing a modifier while another is already down is a shortcut, not a tap.
            let others = e.modifierFlags.intersection([.command, .option, .control, .shift]).subtracting(k.flag)
            dirty = !others.isEmpty
            downAt[k.code] = Date()
            return
        }
        guard let t = downAt.removeValue(forKey: k.code) else { return }
        let now = Date()
        guard !dirty, now.timeIntervalSince(t) < 0.3 else { lastTap = nil; return }
        if let l = lastTap, l.code == k.code, now.timeIntervalSince(l.at) < 0.45 {
            lastTap = nil
            fire(k.label)
        } else {
            lastTap = (k.code, now)
        }
    }

    private func fire(_ label: String) {
        for id in commandIDs where Prefs.d.string(forKey: Self.prefKey(id)) == label {
            if let a = actions[id] { DispatchQueue.main.async { a() } }
        }
    }
}
