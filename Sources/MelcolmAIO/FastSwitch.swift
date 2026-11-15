import AppKit
import Darwin

/// Instant Space switching: posts the same synthetic three-finger-swipe the trackpad makes
/// (the technique WhichSpace uses), so there is no sliding animation. Classic switching
/// (the Ctrl-arrow keyboard shortcuts) stays available as a setting.
enum FastSwitch {
    private enum Field {
        static let eventType = CGEventField(rawValue: 55)!
        static let gestureHIDType = CGEventField(rawValue: 110)!
        static let swipeMotion = CGEventField(rawValue: 123)!
        static let swipeProgress = CGEventField(rawValue: 124)!
        static let swipePositionX = CGEventField(rawValue: 125)!
        static let swipePositionY = CGEventField(rawValue: 126)!
        static let velocityX = CGEventField(rawValue: 129)!
        static let velocityY = CGEventField(rawValue: 130)!
        static let phase = CGEventField(rawValue: 132)!
        static let phase2 = CGEventField(rawValue: 134)!
        static let flavor = CGEventField(rawValue: 138)!
        static let timestamp = CGEventField(rawValue: 169)!
        static let iohidPayload: UInt16 = 4205
    }
    private static let dockControl: Int64 = 30
    private static let hidDockSwipe: Int64 = 23
    private static let horizontal: Int64 = 1
    private static let began: Int64 = 1, changed: Int64 = 2, ended: Int64 = 4
    private static let velocity = 2000.0
    private static let tinyProgress = Double(Float.leastNonzeroMagnitude)

    /// macOS 27 checks synthetic swipes against an IOHID payload (and needs the trackpad
    /// Space-swipe gesture turned on in System Settings).
    private static let needsPayload = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27

    /// True when macOS will accept our synthetic swipes.
    static var available: Bool {
        guard needsPayload else { return true }
        let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
        let keys = ["TrackpadThreeFingerHorizSwipeGesture", "TrackpadFourFingerHorizSwipeGesture"]
        var values = domains.flatMap { d in keys.map { pref($0, d as CFString, kCFPreferencesAnyHost) } }
        values.append(pref("com.apple.trackpad.threeFingerHorizSwipeGesture", kCFPreferencesAnyApplication, kCFPreferencesCurrentHost))
        values.append(pref("com.apple.trackpad.fourFingerHorizSwipeGesture", kCFPreferencesAnyApplication, kCFPreferencesCurrentHost))
        return values.contains { ($0 ?? 0) != 0 }
    }

    /// Moves one Space left or right. `scale` speeds up multi-Space jumps.
    @discardableResult
    static func step(right: Bool, scale: Double = 1) -> Bool {
        parkWindow()
        let v = velocity * scale
        guard needsPayload else {
            return plain(began, right, v) && plain(changed, right, v) && plain(ended, right, v)
        }
        // Dock flips HID swipes when natural scrolling is off.
        let natural = ((pref("com.apple.swipescrolldirection", kCFPreferencesAnyApplication, kCFPreferencesAnyHost)) ?? 1) != 0
        let dir = natural ? right : !right
        return augmented(began, dir, v) && augmented(changed, dir, v) && augmented(ended, dir, v)
    }

    // macOS 27 strands the menu bar if a synthetic switch arrives while our own window is key,
    // so take it off screen for a moment.
    private static func parkWindow() {
        guard needsPayload, NSApp.isActive, let w = NSApp.keyWindow, w.isVisible else { return }
        // Stop being the key window without hiding: the island stays on screen (no blink).
        if let w = w as? NSPanel, w.becomesKeyOnlyIfNeeded || w.styleMask.contains(.nonactivatingPanel) {
            w.resignKey(); NSApp.deactivate(); return
        }
        w.orderOut(nil)
        // Come back the moment the new Space is on screen, not after a fixed wait.
        var token: NSObjectProtocol?
        let back = {
            if let t = token { NSWorkspace.shared.notificationCenter.removeObserver(t); token = nil }
            if !w.isVisible { w.orderFrontRegardless() }
        }
        token = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: back)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: back)   // fallback
    }

    private static func plain(_ phase: Int64, _ right: Bool, _ v: Double) -> Bool {
        guard let e = CGEvent(source: nil) else { return false }
        e.setIntegerValueField(Field.eventType, value: dockControl)
        e.setIntegerValueField(Field.gestureHIDType, value: hidDockSwipe)
        e.setIntegerValueField(Field.phase, value: phase)
        e.setDoubleValueField(Field.swipeProgress, value: right ? tinyProgress : -tinyProgress)
        e.setIntegerValueField(Field.swipeMotion, value: horizontal)
        e.setDoubleValueField(Field.velocityX, value: right ? v : -v)
        e.setDoubleValueField(Field.velocityY, value: right ? v : -v)
        e.post(tap: .cgSessionEventTap)
        return true
    }

    private static func augmented(_ phase: Int64, _ right: Bool, _ v: Double) -> Bool {
        guard let e = CGEvent(source: nil) else { return false }
        let sv = right ? v : -v
        e.setIntegerValueField(Field.eventType, value: dockControl)
        e.setIntegerValueField(Field.gestureHIDType, value: hidDockSwipe)
        e.setIntegerValueField(Field.phase, value: phase)
        e.setDoubleValueField(Field.swipeProgress, value: right ? 1 : -1)
        e.setIntegerValueField(Field.swipeMotion, value: horizontal)
        e.setDoubleValueField(Field.velocityX, value: sv)
        e.setDoubleValueField(Field.velocityY, value: 0)
        e.setIntegerValueField(Field.phase2, value: phase)
        e.setDoubleValueField(Field.flavor, value: 3)
        e.setDoubleValueField(Field.timestamp, value: Double(mach_absolute_time()))
        e.setDoubleValueField(Field.swipePositionX, value: 0.1)
        guard let data = e.data else { return false }
        var bytes = data as Data
        guard bytes.starts(with: [0, 0, 0, 2]) else { return false }
        let payload = iohid(e, phase, sv)
        let size = UInt16(payload.count)
        bytes.append(contentsOf: [UInt8(size >> 8), UInt8(size & 0xFF), UInt8(Field.iohidPayload >> 8), UInt8(Field.iohidPayload & 0xFF)])
        bytes.append(payload)
        guard let out = CGEvent(withDataAllocator: kCFAllocatorDefault, data: bytes as CFData) else { return false }
        out.post(tap: .cgSessionEventTap)
        return true
    }

    private struct Base { var size: UInt32; var type: UInt32; var options: UInt32; var depth: UInt8; var reserved: (UInt8, UInt8, UInt8) }
    private struct Gesture { var base: Base; var x: Int32; var y: Int32; var z: Int32; var mask: UInt32; var motion: UInt16; var flavor: UInt16; var progress: Int32 }
    private struct Vel { var base: Base; var x: Int32; var y: Int32; var z: Int32 }
    private struct Header { var timestamp: UInt64; var sender: UInt64; var options: UInt32; var attrLen: UInt32; var count: UInt32 }

    private static func iohid(_ e: CGEvent, _ phase: Int64, _ v: Double) -> Data {
        let ts = e.timestamp != 0 ? e.timestamp : mach_absolute_time()
        let progress = e.getDoubleValueField(Field.swipeProgress)
        var d = Data()
        var h = Header(timestamp: ts, sender: 0, options: 0, attrLen: 0, count: 2)
        withUnsafeBytes(of: &h) { d.append(contentsOf: $0) }
        var g = Gesture(base: Base(size: UInt32(MemoryLayout<Gesture>.size), type: 23, options: UInt32((phase & 0xFF) << 24), depth: 0, reserved: (0, 0, 0)),
                        x: fixed(e.getDoubleValueField(Field.swipePositionX)), y: fixed(e.getDoubleValueField(Field.swipePositionY)), z: 0,
                        mask: 0, motion: UInt16(horizontal), flavor: 3, progress: fixed(-progress))
        withUnsafeBytes(of: &g) { d.append(contentsOf: $0) }
        var vel = Vel(base: Base(size: UInt32(MemoryLayout<Vel>.size), type: 9, options: 0, depth: 1, reserved: (0, 0, 0)), x: fixed(-v), y: 0, z: 0)
        withUnsafeBytes(of: &vel) { d.append(contentsOf: $0) }
        return d
    }

    private static func fixed(_ value: Double) -> Int32 {
        let s = value * 65_536
        if s >= Double(Int32.max) { return .max }
        if s <= Double(Int32.min) { return .min }
        let f = Int32(s)
        return f == 0 && value != 0 ? (value > 0 ? 1 : -1) : f
    }

    private static func pref(_ key: String, _ app: CFString, _ host: CFString) -> Int? {
        (CFPreferencesCopyValue(key as CFString, app, kCFPreferencesCurrentUser, host) as? NSNumber)?.intValue
    }
}
