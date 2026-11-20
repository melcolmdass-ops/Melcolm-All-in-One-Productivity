import AppKit
import SwiftUI
import ApplicationServices

/// Window views: drop a window on a Split, Triple or Quad spot and it is arranged with your most
/// recent other windows on that display, straight away (no pop-up). Fewer windows open than the view
/// holds? Only the ones there are get placed.
enum WindowView: String, CaseIterable, Identifiable {
    case split, triple, quad
    var id: String { rawValue }
    var title: String { self == .split ? "Split view" : self == .triple ? "Triple view" : "Quad view" }
    var icon: String { self == .split ? "rectangle.split.2x1" : self == .triple ? "rectangle.split.3x1" : "rectangle.split.2x2" }
    var count: Int { self == .split ? 2 : self == .triple ? 3 : 4 }
    var blurb: String {
        switch self {
        case .split: "The window you drop takes the left, your most recent other window the right."
        case .triple: "Three side by side: the one you drop, then your two most recent."
        case .quad: "Four in a grid: the one you drop top left, then your three most recent."
        }
    }

    /// The gap between windows (and around them) when "Keep gaps" is on.
    static let gap: CGFloat = 10

    /// Columns and rows of the view's grid.
    var grid: (cols: Int, rows: Int) { self == .split ? (2, 1) : self == .triple ? (3, 1) : (2, 2) }

    /// The spots, in reading order, inside `r` (top-left coords). Every spot is the same size, with one
    /// gap between windows and around the edge.
    func slots(in r: CGRect, gap g: CGFloat) -> [CGRect] {
        let (c, n) = grid
        let w = (r.width - CGFloat(c + 1) * g) / CGFloat(c), h = (r.height - CGFloat(n + 1) * g) / CGFloat(n)
        return (0..<n).flatMap { row in (0..<c).map { col in
            CGRect(x: (r.minX + g + CGFloat(col) * (w + g)).rounded(), y: (r.minY + g + CGFloat(row) * (h + g)).rounded(),
                   width: w.rounded(.down), height: h.rounded(.down))
        } }
    }

    /// The spots for exactly `count` windows: a Quad view with 3 windows still uses 3 equal columns, etc.
    static func fitted(count n: Int, in r: CGRect, gap g: CGFloat, base: WindowView) -> [CGRect] {
        switch n {
        case 1: return [CGRect(x: r.minX + g, y: r.minY + g, width: r.width - 2 * g, height: r.height - 2 * g).integral]
        case 2: return WindowView.split.slots(in: r, gap: g)
        case 3: return WindowView.triple.slots(in: r, gap: g)
        default: return base.slots(in: r, gap: g)
        }
    }

    struct Win { let pid: pid_t; let wid: CGWindowID; var thumb: CGRect? = nil }

    /// Stage Manager on? (Then the other apps sit as small thumbnails at the screen's edge.)
    static var stageManager: Bool {
        (CFPreferencesCopyAppValue("GloballyEnabled" as CFString, "com.apple.WindowManager" as CFString) as? Bool) ?? false
    }

    /// Other windows on this display, most recently used first: the ones on screen (front to back),
    /// then, with Stage Manager on, the thumbnails in its strip at the edge (top one first).
    static func recent(excluding wid: CGWindowID, on display: CGRect) -> [Win] {
        let me = ProcessInfo.processInfo.processIdentifier
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let stage = stageManager
        var out: [Win] = [], strip: [Win] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let p = w[kCGWindowOwnerPID as String] as? pid_t, p != me,
                  let n = w[kCGWindowNumber as String] as? CGWindowID, n != wid,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (w[kCGWindowAlpha as String] as? CGFloat ?? 1) > 0.1,
                  let app = NSRunningApplication(processIdentifier: p), app.activationPolicy == .regular else { continue }
            // Testing only: `-debugArrangeOnly "TextEdit,Calculator"` limits which apps can be picked.
            if let only = UserDefaults.standard.string(forKey: "debugArrangeOnly"),
               !only.split(separator: ",").contains(where: { $0 == app.localizedName ?? "" }) { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard display.contains(CGPoint(x: r.midX, y: r.midY)) else { continue }
            if r.width > 200, r.height > 150 { out.append(Win(pid: p, wid: n)); continue }
            // A Stage Manager thumbnail: small, standing at the left or right edge of the screen.
            let atEdge = r.minX - display.minX < 160 || display.maxX - r.maxX < 160
            if stage, atEdge, r.width >= 30, r.height >= 30, r.width < 260, r.height < 300,
               !strip.contains(where: { $0.pid == p }) {   // one per app group: a click brings the whole group
                strip.append(Win(pid: p, wid: n, thumb: r))
            }
        }
        strip.sort { ($0.thumb?.minY ?? 0) < ($1.thumb?.minY ?? 0) }
        return out + strip.filter { s in !out.contains { $0.pid == s.pid && $0.wid == s.wid } }
    }

    /// Where a window is right now (top-left coords), or nil if macOS no longer lists it.
    static func bounds(_ wid: CGWindowID) -> CGRect? {
        guard let d = (CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]])?.first,
              let b = d[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
    }

    /// Posts a pointer event (our own: the drag tap lets it through).
    private static func mouse(_ t: CGEventType, _ p: CGPoint, shift: Bool = false) {
        OptionDrag.passThroughUntil = Date().addingTimeInterval(1)
        let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)
        if shift { e?.flags = .maskShift }
        e?.post(tap: .cghidEventTap)
    }

    /// Stage Manager: brings a window that's sitting in the strip onto the stage you're on. The strip hides when a
    /// window covers the screen's edge, so the pointer rests on the edge first to slide it back in, then
    /// shift-clicks the window's thumbnail (Stage Manager's own "add to this stage").
    static func addToStage(_ wid: CGWindowID, display: CGRect) {
        guard var t = bounds(wid), t.width < 260 else { return }      // already full size: it's on the stage
        let left = t.midX < display.midX
        if t.minX < display.minX + 2 || t.maxX > display.maxX - 2 {
            let edge = CGPoint(x: left ? display.minX + 1 : display.maxX - 2, y: min(max(t.midY, display.minY + 60), display.maxY - 60))
            for dx in [0.0, 1.0, 0.0] { mouse(.mouseMoved, CGPoint(x: edge.x + (left ? dx : -dx), y: edge.y)); Thread.sleep(forTimeInterval: 0.08) }
            Thread.sleep(forTimeInterval: 0.6)
            guard let n = bounds(wid) else { return }
            t = n
            guard t.minX >= display.minX, t.maxX <= display.maxX else { return }
        }
        let at = CGPoint(x: t.midX, y: t.midY)
        mouse(.mouseMoved, at); Thread.sleep(forTimeInterval: 0.05)
        mouse(.leftMouseDown, at, shift: true); Thread.sleep(forTimeInterval: 0.05)
        mouse(.leftMouseUp, at, shift: true)
        Thread.sleep(forTimeInterval: 0.45)
    }

    /// Arranges the dropped window plus the most recent others into this view. `visible` is the
    /// display's usable area and `display` the whole display, both in top-left screen coords.
    func arrange(pid: pid_t, wid: CGWindowID, visible: CGRect, display: CGRect) {
        let gap: CGFloat = Prefs.bool("viewGaps") ? Self.gap : 0
        DispatchQueue.global(qos: .userInitiated).async {
            let stage = Self.stageManager
            // Let Stage Manager finish settling after the drop (it may have just sent the last app to its strip).
            if stage { Thread.sleep(forTimeInterval: 0.3) }
            let others = Self.recent(excluding: wid, on: display).filter { w in
                // Never pull a full-screen window out of its Space.
                guard let ax = SpaceMover.window(pid: w.pid, wid: w.wid) else { return false }
                return !SpaceMover.isFull(ax)
            }
            let wins = [Win(pid: pid, wid: wid)] + others.prefix(count - 1)
            // Exactly the view you chose: Triple always makes three spots, even with fewer windows open.
            let spots = self.slots(in: visible, gap: gap)
            BrowserMedia.log("views \(self.rawValue) stage=\(stage) wins=\(wins.map { "\($0.wid)\($0.thumb != nil ? "T" : "")" })")
            // Stage Manager first: bring the other windows onto this stage BEFORE anything moves (the dropped window is
            // already the front app, so nothing gets sent back to the strip). Then every window goes to its spot once.
            if stage {
                let back = CGEvent(source: nil)?.location ?? .zero
                for w in wins.dropFirst() { Self.addToStage(w.wid, display: display) }
                CGWarpMouseCursorPosition(back)
            }
            // One movement each, back to front so the dropped window ends up on top.
            for (w, r) in zip(wins, spots).reversed() {
                guard let ax = SpaceMover.window(pid: w.pid, wid: w.wid) else { continue }
                OptionDrag.setFrame(ax, app: AXUIElementCreateApplication(w.pid), to: r, within: visible)
            }
            DispatchQueue.main.sync {
                if let ax = SpaceMover.window(pid: pid, wid: wid) { AXUIElementPerformAction(ax, kAXRaiseAction as CFString) }
                // With Stage Manager the dropped app is already in front; activating it again would send the rest to the strip.
                if !stage { NSRunningApplication(processIdentifier: pid)?.activate() }
            }
            BrowserMedia.log("views placed \(wins.map { "\($0.wid)=\(Self.bounds($0.wid).map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "-")" })")
        }
    }
}
