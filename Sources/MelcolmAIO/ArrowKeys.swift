import AppKit

/// While the bar is open, ← and → change Space even if another app has the keyboard.
/// Switching Spaces hands the keyboard to whatever is on the new Space; listening here (and swallowing
/// the arrow) means the next press always works straight away, and never leaks into the app underneath.
final class ArrowKeys {
    static let shared = ArrowKeys()
    /// Returns true when the bar is open and the arrow should be used (false while typing in a text box).
    var wants: () -> Bool = { false }
    var step: (Int) -> Void = { _ in }
    private var tap: CFMachPort?
    private var last = Date.distantPast

    func start() {
        guard tap == nil, AXIsProcessTrusted() else {
            if tap == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.start() } }
            return
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: { _, type, e, ctx in
            let s = Unmanaged<ArrowKeys>.fromOpaque(ctx!).takeUnretainedValue()
            return s.handle(type, e)
        }, userInfo: me)
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        let code = e.getIntegerValueField(.keyboardEventKeycode)
        guard code == 123 || code == 124,
              e.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              !Hotkeys.paused, wants() else { return Unmanaged.passUnretained(e) }
        // Holding the key repeats, but one Space at a time reads smoother than a rush.
        let now = Date()
        if now.timeIntervalSince(last) >= 0.14 { last = now; step(code == 123 ? -1 : 1) }
        return nil
    }
}
