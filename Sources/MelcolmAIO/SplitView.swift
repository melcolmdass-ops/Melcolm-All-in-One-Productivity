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

    /// Shift-click on a Stage Manager thumbnail: adds that window to the stage you're on (Stage Manager's own rule),
    /// then the pointer goes back where it was.
    static func addToStage(_ thumb: CGRect) {
        let back = CGEvent(source: nil)?.location ?? .zero
        let at = CGPoint(x: thumb.midX, y: thumb.midY)
        OptionDrag.passThroughUntil = Date().addingTimeInterval(1)
        for t: CGEventType in [.leftMouseDown, .leftMouseUp] {
            let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: at, mouseButton: .left)
            e?.flags = .maskShift
            e?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.05)
        }
        CGWarpMouseCursorPosition(back)
    }

    /// Arranges the dropped window plus the most recent others into this view. `visible` is the
    /// display's usable area and `display` the whole display, both in top-left screen coords.
    func arrange(pid: pid_t, wid: CGWindowID, visible: CGRect, display: CGRect) {
        let gap: CGFloat = Prefs.bool("viewGaps") ? Self.gap : 0
        let spots = slots(in: visible, gap: gap)
        DispatchQueue.global(qos: .userInitiated).async {
            // Let Stage Manager finish settling after the drop (it may have just sent the last app to its strip).
            if Self.stageManager { Thread.sleep(forTimeInterval: 0.45) }
            let others = Self.recent(excluding: wid, on: display).filter { w in
                // Never pull a full-screen window out of its Space.
                guard let ax = SpaceMover.window(pid: w.pid, wid: w.wid) else { return false }
                return !SpaceMover.isFull(ax)
            }
            let wins = [Win(pid: pid, wid: wid)] + others.prefix(count - 1)
            // Stage Manager: bring the chosen thumbnails onto this stage first.
            let thumbs = wins.compactMap(\.thumb)
            if !thumbs.isEmpty {
                for t in thumbs { Self.addToStage(t); Thread.sleep(forTimeInterval: 0.6) }
                Thread.sleep(forTimeInterval: 0.3)
            }
            // Placed back to front, so the dropped window ends up on top.
            for (w, r) in zip(wins, spots).reversed() {
                guard let ax = SpaceMover.window(pid: w.pid, wid: w.wid) else { continue }
                OptionDrag.setFrame(ax, app: AXUIElementCreateApplication(w.pid), to: r)
                AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
            }
            DispatchQueue.main.async {
                if let ax = SpaceMover.window(pid: pid, wid: wid) { AXUIElementPerformAction(ax, kAXRaiseAction as CFString) }
                NSRunningApplication(processIdentifier: pid)?.activate()
            }
        }
    }
}
