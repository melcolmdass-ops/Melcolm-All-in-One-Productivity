import AppKit
import SwiftUI

@_silgen_name("_CGSDefaultConnection") private func moveConn() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func moveDisplaySpaces(_ conn: Int32) -> Unmanaged<CFArray>?
@_silgen_name("_AXUIElementGetWindow") private func axWindowID(_ e: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - Dragging full-screen apps on the bar

/// Where a dragged app would land.
enum SpaceDrop: Equatable {
    case desktop(String)          // a display's number: leave full screen, go onto that desktop
    case slot(String, Int)        // a display, and the position among its full-screen apps
}

/// The drag in progress. Cell frames are kept here (not published) so the drop spot can be worked out.
final class SpaceDragModel: ObservableObject {
    static let shared = SpaceDragModel()
    @Published var dragging: Int?            // space id being dragged
    @Published var offset: CGSize = .zero
    @Published var target: SpaceDrop?
    var frames: [String: CGRect] = [:]       // "box-<display>", "num-<display>", "app-<space id>"
    var home: [String: CGRect] = [:]         // where everything sat when the drag began (cells slide, these don't)
    var source: String?                      // the display the app is dragged from
    var gap: CGFloat = 0                     // room the dragged app takes up
    var droppedAt = Date.distantPast         // a drop isn't also a click

    func begin(_ id: Int, model m: SpacesModel) {
        guard dragging != id else { return }
        home = frames
        source = m.displays.first { g in g.spaces.contains { $0.id == id } }?.id
        gap = (frames["app-\(id)"]?.width ?? 30) + 2
        dragging = id
        NSCursor.closedHand.push()
    }

    /// How far a cell slides so the dragged app has room where it would land.
    func shift(_ s: SpaceItem, in g: DisplayGroup) -> CGFloat {
        guard let id = dragging, s.id != id else { return 0 }
        var x: CGFloat = 0
        let fulls = Layout.fullscreens(g)
        // Close the hole the dragged app left behind.
        if g.id == source, let a = fulls.firstIndex(where: { $0.id == id }), let b = fulls.firstIndex(of: s), b > a { x -= gap }
        // Open a hole where it will land.
        if case .slot(let d, let k)? = target, d == g.id, let j = fulls.filter({ $0.id != id }).firstIndex(of: s), j >= k { x += gap }
        return x
    }
    /// How much wider (or narrower) a display's box looks while an app is dragged in (or out of) it.
    func grow(_ g: DisplayGroup) -> CGFloat {
        guard dragging != nil else { return 0 }
        var x: CGFloat = 0
        if g.id == source { x -= gap }
        if case .slot(let d, _)? = target, d == g.id { x += gap }
        return x
    }

    /// Works out the drop spot under the pointer (x only: the bar is one row).
    func update(_ p: CGPoint, offset o: CGSize, model m: SpacesModel) {
        offset = o
        var t: SpaceDrop?
        for g in m.displays {
            guard let box = home["box-\(g.id)"], p.x >= box.minX - 6, p.x <= box.maxX + 6,
                  p.y >= box.minY - 40, p.y <= box.maxY + 40 else { continue }
            if let n = home["num-\(g.id)"], p.x <= n.maxX + 2 { t = .desktop(g.id); break }
            let others = Layout.fullscreens(g).filter { $0.id != dragging }
            let k = others.filter { s in (home["app-\(s.id)"]?.midX ?? .infinity) < p.x }.count
            t = .slot(g.id, k); break
        }
        if t != target { withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { target = t } }
    }

    func end(model m: SpacesModel) {
        defer {
            NSCursor.pop()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragging = nil; offset = .zero; target = nil; source = nil }
            droppedAt = Date()
        }
        guard let id = dragging, let t = target,
              let from = m.displays.first(where: { g in g.spaces.contains { $0.id == id } }),
              let i = Layout.fullscreens(from).firstIndex(where: { $0.id == id }) else { return }
        if case .slot(let d, let k) = t, d == from.id, k == i { return }   // dropped where it was
        SpaceMover.start(space: id, to: t, model: m)
    }
}

/// Moves full-screen windows between Spaces with Accessibility: leave full screen, move the
/// window to the right display, go full screen again, then fix the order. macOS has no call to
/// place a Space directly, so the order is fixed by re-entering full screen on the neighbours
/// (a new full-screen Space always lands next to its desktop).
enum SpaceMover {
    private static let q = DispatchQueue(label: "melcolm.spacemove")
    private(set) static var busy = false

    static func start(space id: Int, to t: SpaceDrop, model m: SpacesModel) {
        guard !busy, SpacesModel.ensureAccessibility(), let info = fullInfo(space: id) else { NSSound.beep(); return }
        busy = true
        m.preview(moving: id, to: t)
        q.async {
            switch t {
            case .desktop(let d): toDesktop(pid: info.pid, wid: info.wid, display: d)
            case .slot(let d, let k):
                move(pid: info.pid, wid: info.wid, display: d, index: k)
            }
            DispatchQueue.main.async { busy = false; m.endPreview() }
        }
    }

    // MARK: reading Spaces

    private static func raw() -> [NSDictionary] { (moveDisplaySpaces(moveConn())?.takeRetainedValue() as? [NSDictionary]) ?? [] }

    /// Two apps side by side (Split View) share one Space. Those are never moved or re-entered.
    static func isSplit(_ s: NSDictionary) -> Bool {
        (((s["TileLayoutManager"] as? NSDictionary)?["TileSpaces"] as? [Any])?.count ?? 1) > 1
    }

    /// The Split View Spaces right now (the bar won't let these be dragged).
    static func splitIDs() -> Set<Int> {
        Set(raw().flatMap { ($0["Spaces"] as? [NSDictionary]) ?? [] }.filter(isSplit).compactMap { ($0["ManagedSpaceID"] as? Int) ?? ($0["id64"] as? Int) })
    }

    /// The window filling a full-screen Space (older Spaces only list it under their tile).
    static func wid(_ s: NSDictionary) -> Int {
        (s["fs_wid"] as? Int)
            ?? (((s["TileLayoutManager"] as? NSDictionary)?["TileSpaces"] as? [NSDictionary])?.first?["TileWindowID"] as? Int) ?? 0
    }
    static func pid(_ s: NSDictionary) -> Int? {
        (s["pid"] as? Int) ?? (((s["TileLayoutManager"] as? NSDictionary)?["TileSpaces"] as? [NSDictionary])?.first?["pid"] as? Int)
    }

    /// The app and window that own a full-screen Space (nil for Split View).
    static func fullInfo(space id: Int) -> (pid: pid_t, wid: CGWindowID)? {
        for d in raw() {
            for s in (d["Spaces"] as? [NSDictionary]) ?? [] where ((s["ManagedSpaceID"] as? Int) ?? (s["id64"] as? Int)) == id {
                let w = wid(s)
                guard !isSplit(s), let pid = pid(s), w != 0 else { return nil }
                let wid = w
                return (pid_t(pid), CGWindowID(wid))
            }
        }
        return nil
    }

    /// The full-screen Spaces of a display, left to right: their window, and whether it's a Split View pair.
    static func order(_ display: String) -> [(wid: CGWindowID, split: Bool)] {
        guard let d = raw().first(where: { ($0["Display Identifier"] as? String) == display }) else { return [] }
        return ((d["Spaces"] as? [NSDictionary]) ?? []).compactMap { s in
            (s["type"] as? Int) == 4 ? (CGWindowID(wid(s)), isSplit(s)) : nil
        }
    }

    static func screen(_ display: String) -> NSScreen? {
        NSScreen.screens.first { SpacesModel.uuid(of: $0) == display }
            ?? (display == "Main" ? NSScreen.screens.first : nil)
    }

    // MARK: Accessibility

    static func window(pid: pid_t, wid: CGWindowID) -> AXUIElement? {
        func id(_ w: AXUIElement) -> CGWindowID { var n: CGWindowID = 0; _ = axWindowID(w, &n); return n }
        let app = AXUIElementCreateApplication(pid)
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v)
        if let w = (v as? [AXUIElement])?.first(where: { id($0) == wid }) { return w }
        if let w = WebAX.windowsEverywhere(pid).first(where: { id($0) == wid }) { return w }
        // Not reachable from here: bring the app forward (macOS goes to its Space), then ask again.
        DispatchQueue.main.sync { NSRunningApplication(processIdentifier: pid)?.activate() }
        for _ in 0 ..< 12 {
            Thread.sleep(forTimeInterval: 0.15)
            var list: CFTypeRef?
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list)
            if let w = (list as? [AXUIElement])?.first(where: { id($0) == wid }) { return w }
        }
        var main: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &main)
        if let m = main, CFGetTypeID(m) == AXUIElementGetTypeID(), isFull(m as! AXUIElement) { return (m as! AXUIElement) }
        return nil
    }

    static func isFull(_ w: AXUIElement) -> Bool {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(w, "AXFullScreen" as CFString, &v)
        return (v as? Bool) ?? false
    }

    @discardableResult
    static func setFull(_ w: AXUIElement, _ on: Bool, pid: pid_t) -> Bool {
        if isFull(w) == on { return true }
        var err = AXUIElementSetAttributeValue(w, "AXFullScreen" as CFString, on as CFBoolean)
        if err != .success {
            // Some apps only take it while they're in front.
            DispatchQueue.main.sync { NSRunningApplication(processIdentifier: pid)?.activate() }
            Thread.sleep(forTimeInterval: 0.5)
            err = AXUIElementSetAttributeValue(w, "AXFullScreen" as CFString, on as CFBoolean)
        }
        // Go on the moment macOS has made (or removed) the Space, plus a short beat for its animation.
        var wid: CGWindowID = 0; _ = axWindowID(w, &wid)
        func hasSpace() -> Bool { raw().contains { (($0["Spaces"] as? [NSDictionary]) ?? []).contains { ($0["type"] as? Int) == 4 && CGWindowID(Self.wid($0)) == wid } } }
        let until = Date().addingTimeInterval(5)
        var asked = Date()
        while Date() < until, isFull(w) != on || hasSpace() != on {
            Thread.sleep(forTimeInterval: 0.04)
            // macOS ignores the request while it's still animating the last one: ask again.
            if UserDefaults.standard.bool(forKey: "debugLog") { BrowserMedia.log("spacemove t full=\(isFull(w)) space=\(hasSpace())") }
            if Date().timeIntervalSince(asked) > 0.7, isFull(w) != on {
                err = AXUIElementSetAttributeValue(w, "AXFullScreen" as CFString, on as CFBoolean); asked = Date()
            }
        }
        Thread.sleep(forTimeInterval: on ? 0.45 : 0.55)
        BrowserMedia.log("spacemove full=\(on) err=\(err.rawValue) now=\(isFull(w))")
        return isFull(w) == on
    }

    private static func point(_ w: AXUIElement, _ k: String) -> CGPoint? {
        var v: CFTypeRef?; var p = CGPoint.zero
        guard AXUIElementCopyAttributeValue(w, k as CFString, &v) == .success, let v else { return nil }
        AXValueGetValue(v as! AXValue, .cgPoint, &p); return p
    }
    private static func size(_ w: AXUIElement) -> CGSize? {
        var v: CFTypeRef?; var s = CGSize.zero
        guard AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &v) == .success, let v else { return nil }
        AXValueGetValue(v as! AXValue, .cgSize, &s); return s
    }

    /// Screen frames in Accessibility's top-left coordinates.
    private static func axRect(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    /// Puts the window in the middle of a display, shrunk to fit if needed.
    static func place(_ w: AXUIElement, on screen: NSScreen, onlyIfElsewhere: Bool) {
        let vis = axRect(screen.visibleFrame)
        if onlyIfElsewhere, let p = point(w, kAXPositionAttribute), axRect(screen.frame).contains(CGPoint(x: p.x + 40, y: p.y + 10)) { return }
        var s = size(w) ?? CGSize(width: vis.width * 0.7, height: vis.height * 0.7)
        s.width = min(s.width, vis.width); s.height = min(s.height, vis.height)
        var o = CGPoint(x: vis.midX - s.width / 2, y: vis.midY - s.height / 2)
        if let sv = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
        if let pv = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
        Thread.sleep(forTimeInterval: 0.3)
    }

    // MARK: the moves

    static func toDesktop(pid: pid_t, wid: CGWindowID, display: String) {
        guard let w = window(pid: pid, wid: wid) else { BrowserMedia.log("spacemove no window \(wid)"); return }
        guard setFull(w, false, pid: pid) else { return }
        if let s = screen(display) { place(w, on: s, onlyIfElsewhere: true) }
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        DispatchQueue.main.async { NSRunningApplication(processIdentifier: pid)?.activate() }
    }

    /// macOS always puts a newly full-screened app last on its display. So to get the wanted order,
    /// keep the longest run at the front that's already in order, and send only the rest to the back
    /// (leave + re-enter full screen) one by one. A swap of two apps re-enters just one of them.
    static func move(pid: pid_t, wid: CGWindowID, display: String, index k: Int) {
        let now = order(display)
        let cross = !now.contains { $0.wid == wid }
        var want = now.filter { $0.wid != wid }
        want.insert((wid, false), at: min(k, want.count))
        // Already-in-order front run (the moved app can't stay put if it's coming from another display).
        var keep = 0, j = 0
        while keep < want.count {
            let x = want[keep].wid
            if cross && x == wid { break }
            guard let at = now[j...].firstIndex(where: { $0.wid == x }) else { break }
            j = at + 1; keep += 1
        }
        let cycle = Array(want.dropFirst(keep))
        BrowserMedia.log("spacemove now \(now.map(\.wid)) want \(want.map(\.wid)) re-enter \(cycle.map(\.wid))")
        // Re-entering a Split View pair would pull it apart, so then only the dragged app moves.
        let blocked = cycle.contains { $0.wid != wid && ($0.split || $0.wid == 0) }
        for o in (blocked ? [(wid, false)] : cycle).map(\.0) {
            let op = o == wid ? pid : (owner(o) ?? 0)
            guard let ow = window(pid: op, wid: o) else { continue }
            guard setFull(ow, false, pid: op) else { continue }
            if o == wid, let s = screen(display) { place(ow, on: s, onlyIfElsewhere: true) }
            setFull(ow, true, pid: op)
        }
        BrowserMedia.log("spacemove done \(order(display).map(\.wid))")
        // Finish on the app that was moved.
        DispatchQueue.main.async { NSRunningApplication(processIdentifier: pid)?.activate() }
    }

    private static func owner(_ wid: CGWindowID) -> pid_t? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]] else { return nil }
        return info.first?[kCGWindowOwnerPID as String] as? pid_t
    }
}

// MARK: - Settings: the Dragging box on Spaces

struct DragSpacesCard: View {
    @AppStorage("dragSpaces") var on = true

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.draw.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                        .frame(width: 30, height: 30).background(NeonBox(color: accent, radius: 8, strength: 0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drag apps between Spaces").font(.system(size: 13, weight: .heavy))
                        Text("Grab a full-screen app on the bar and drop it where you want it.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: $on).labelsHidden()
                }
                VStack(spacing: 8) {
                    rule(true, "Drop it between two apps", "The others slide aside to make room, and it moves there, on this display or another one.") { betweenPicture }
                    rule(true, "Drop it on a display number", "It leaves full screen and goes onto that desktop.") { numberPicture }
                    rule(false, "Desktops and Split View pairs", "The numbers themselves, and two apps sharing a box, can't be dragged.") { cantPicture }
                }
                .opacity(on ? 1 : 0.45)
            }
        }
    }

    func rule<P: View>(_ ok: Bool, _ title: String, _ text: String, @ViewBuilder _ pic: () -> P) -> some View {
        HStack(spacing: 10) {
            ZStack { pic() }
                .frame(width: 118, height: 42)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red)
                        .font(.system(size: 11, weight: .bold))
                    Text(title).font(.system(size: 11.5, weight: .bold))
                }
                Text(text).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // Small drawings of the bar
    func app(_ c: Color, _ t: String = "", lifted: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous).fill(c).frame(width: 13, height: 13)
            .overlay(Text(t).font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.white))
            .shadow(color: lifted ? BarColor.space.color.opacity(0.9) : .clear, radius: 4)
    }
    func num(_ n: String, glow: Bool = false) -> some View {
        Text(n).font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(glow ? .white : accent)
            .frame(width: 13, height: 15)
            .background(RoundedRectangle(cornerRadius: 3.5).fill(glow ? BarColor.space.color.opacity(0.35) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 3.5).strokeBorder(glow ? BarColor.space.color : .clear, lineWidth: 1)))
    }
    func strip<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 3) { c() }.padding(.horizontal, 5).frame(height: 19)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 0.8))
    }
    var insertBar: some View { Capsule().fill(BarColor.space.color).frame(width: 2.5, height: 14).shadow(color: BarColor.space.color, radius: 3) }

    var betweenPicture: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) { Spacer().frame(width: 44); app(.orange, lifted: true) ; Image(systemName: "arrow.down.right").font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.8)) }
            strip { num("2"); app(.purple, "M"); insertBar; app(.blue) }
        }
    }
    var numberPicture: some View {
        HStack(spacing: 6) {
            strip { num("1", glow: true); app(.blue) }
            Image(systemName: "arrow.left").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.8))
            app(.orange, lifted: true)
        }
    }
    var cantPicture: some View {
        HStack(spacing: 8) {
            strip { num("1") }.overlay(alignment: .topTrailing) { cross }
            strip { app(.purple, "M"); app(.blue) }.overlay(alignment: .topTrailing) { cross }
        }
    }
    var cross: some View {
        Image(systemName: "xmark").font(.system(size: 6.5, weight: .black)).foregroundStyle(.white)
            .frame(width: 11, height: 11).background(Circle().fill(.red)).offset(x: 5, y: -5)
    }
}
