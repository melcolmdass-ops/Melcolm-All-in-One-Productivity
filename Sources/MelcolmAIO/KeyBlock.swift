import AppKit
import SwiftUI

/// Keyboard Block: while it's on, every key press is swallowed (letters, shortcuts, volume and
/// brightness keys), so you can wipe or spray the keyboard. The mouse and trackpad still work, so
/// you turn it off with a click. It always starts off when the app opens.
final class KeyBlock: ObservableObject {
    static let shared = KeyBlock()
    @Published private(set) var on = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastPopup = Date.distantPast
    /// Key presses swallowed since launch (for the test hook).
    private(set) var blockedCount = 0

    func toggle() { set(!on) }

    func set(_ want: Bool) {
        guard want != on else { return }
        if want {
            guard AXIsProcessTrusted() else {
                SystemModel.open("com.apple.preference.security?Privacy_Accessibility"); openedOutside(); return
            }
            startTap()
            guard tap != nil else { return }
        } else {
            stopTap()
            KeyPopup.hide()
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { on = want }
    }

    private func startTap() {
        guard tap == nil else { return }
        // Key down/up, modifier keys, and the "system" keys (volume, brightness, play).
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
        let me = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask), callback: { _, type, e, ctx in
            let s = Unmanaged<KeyBlock>.fromOpaque(ctx!).takeUnretainedValue()
            return s.handle(type, e)
        }, userInfo: me)
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }

    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, on { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        guard on else { return Unmanaged.passUnretained(e) }
        if type == .keyDown { blockedCount += 1 }
        // One pop-up every 3 seconds at most, so pressing 100 keys while cleaning never floods the screen.
        if type == .keyDown, Prefs.bool("keyBlockPopup"), Date().timeIntervalSince(lastPopup) >= 3 {
            lastPopup = Date()
            let name = Self.name(e)
            DispatchQueue.main.async { KeyPopup.show(name) }
        }
        return nil
    }

    /// What's printed on the key: "K", "Space", "Return", "←"…
    static func name(_ e: CGEvent) -> String {
        let code = e.getIntegerValueField(.keyboardEventKeycode)
        let special: [Int64: String] = [49: "Space", 36: "Return", 76: "Enter", 48: "Tab", 51: "Delete", 117: "⌦", 53: "Esc",
                                        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down"]
        if let s = special[code] { return s }
        let fn: [Int64: Int] = [122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12]
        if let n = fn[code] { return "F\(n)" }
        var len = 0
        var chars = [UniChar](repeating: 0, count: 4)
        e.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &chars)
        let s = String(utf16CodeUnits: chars, count: len).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return s.isEmpty ? "Key" : s.uppercased()
    }
}

/// The pop-up in the middle of the screen while the keyboard is blocked: the key you pressed, then it fades away.
enum KeyPopup {
    private static var panel: NSPanel?
    private static var token = 0

    static func show(_ key: String) {
        token += 1; let t = token
        let sc = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: 260, height: 170)
        let p = panel ?? {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .statusBar + 2
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel = p; return p
        }()
        p.contentView = NSHostingView(rootView: KeyPopupView(key: key).frame(width: size.width, height: size.height))
        p.setFrame(NSRect(x: sc.frame.midX - size.width / 2, y: sc.frame.midY - size.height / 2, width: size.width, height: size.height), display: true)
        p.alphaValue = 0; p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
        // Stays a moment, then slowly fades.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard token == t else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 1.4; p.animator().alphaValue = 0 },
                                                 completionHandler: { if token == t { p.orderOut(nil) } })
        }
    }

    static func hide() { token += 1; panel?.orderOut(nil) }
}

struct KeyPopupView: View {
    let key: String
    var body: some View {
        VStack(spacing: 12) {
            Text(key).font(.system(size: key.count > 2 ? 22 : 40, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(minWidth: 72, minHeight: 72).padding(.horizontal, key.count > 2 ? 14 : 0)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.18))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.5), radius: 0, y: 4))
            Label("Keyboard blocked", systemImage: "lock.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(white: 0.06).opacity(0.94))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(accent.opacity(0.7), lineWidth: 1.5)))
        .preferredColorScheme(.dark)
    }
}

/// The Keyboard Block page: one switch.
struct KeyBlockPage: View {
    @ObservedObject var block = KeyBlock.shared
    var body: some View {
        CompactStack {
            ToggleRow(icon: block.on ? "keyboard.badge.ellipsis" : "keyboard", title: "Block the keyboard",
                      subtitle: block.on ? "Every key is blocked. Clean away, then click here to turn it off."
                                         : "Blocks every key so you can clean the keyboard. The mouse and trackpad still work.",
                      on: block.on, action: { block.toggle() })
        }
    }
}

// MARK: - Settings ▸ Feedback & Pop-ups

/// The pop-ups that show what just happened, each one a box you tick on or off, with a picture of where it shows.
struct FeedbackPage: View {
    @AppStorage("focusDonePopup") var focusDone = true
    @AppStorage("keyBlockPopup") var keyPopup = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pop-ups that tell you something just happened. Tap a box to turn it on or off.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            sectionLabel("Focus Workflows")
            option(on: $focusDone, title: "Workflow completed", sub: "When a focus workflow finishes, a pop-up shows at the bottom middle of the screen.",
                   spot: .bottom, preview: { FocusDone.show("Deep Work workflow completed", icon: "brain.head.profile") }) {
                Capsule().fill(Color(white: 0.06)).overlay(Capsule().strokeBorder(Color.green.opacity(0.8), lineWidth: 1))
                    .overlay(Image(systemName: "checkmark").font(.system(size: 5, weight: .heavy)).foregroundStyle(.green))
                    .frame(width: 40, height: 8)
            }
            sectionLabel("Keyboard Block")
            option(on: $keyPopup, title: "Key you pressed", sub: "While the keyboard is blocked, the key shows in the middle of the screen, then fades. One every 3 seconds at most, so cleaning never floods the screen.",
                   spot: .center, preview: { KeyPopup.show("K") }) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color(white: 0.06))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(accent, lineWidth: 1))
                    .overlay(Text("K").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white))
                    .frame(width: 22, height: 17)
            }
        }
    }

    /// One rectangle: a little screen showing where the pop-up appears, the words, and the switch.
    func option<P: View>(on: Binding<Bool>, title: String, sub: String, spot: UnitPoint, preview: @escaping () -> Void,
                         @ViewBuilder _ pic: () -> P) -> some View {
        let lit = on.wrappedValue
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))
                Capsule().fill(Color.black).frame(width: 24, height: 4).frame(maxHeight: .infinity, alignment: .top).padding(.top, 3)
                pic().opacity(lit ? 1 : 0.25)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: spot == .bottom ? .bottom : .center)
                    .padding(.bottom, spot == .bottom ? 7 : 0)
            }
            .frame(width: 84, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .bold))
                Text(sub).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(action: preview) {
                    Label("Show me", systemImage: "eye").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(accent)
                }.buttonStyle(.plain).disabled(!lit).opacity(lit ? 1 : 0.4)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: on).labelsHidden().tint(accent)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(lit ? accent.opacity(0.1) : Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(lit ? accent.opacity(0.7) : .white.opacity(0.1), lineWidth: 1.2)))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { on.wrappedValue.toggle() } }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: lit)
    }
}
