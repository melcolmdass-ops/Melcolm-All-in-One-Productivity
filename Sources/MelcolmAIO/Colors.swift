import AppKit
import SwiftUI

/// The colours of the bar itself (the closed island). Stored as hex text; empty means the default.
enum BarColor: String, CaseIterable {
    case outline = "colOutline", notch = "colNotch", statusBox = "colStatusBox", status = "colStatus"
    case displayBox = "colDisplayBox", number = "colNumber", space = "colSpace"

    var title: String {
        switch self {
        case .outline: "Island outline"
        case .notch: "Notch outline"
        case .statusBox: "Play / Open box outline"
        case .status: "Music note, wave and timer"
        case .displayBox: "Display box outline"
        case .number: "Display number"
        case .space: "Space highlight"
        }
    }
    var fallback: Color {
        switch self {
        case .outline: .white.opacity(0.28)
        case .notch, .statusBox, .status, .number: accent
        case .displayBox: .white.opacity(0.55)
        case .space: Color(red: 0.25, green: 0.88, blue: 1.0)
        }
    }
    /// The colour in use right now.
    var color: Color { Color(hex: Prefs.d.string(forKey: rawValue) ?? "") ?? fallback }
}

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

struct ColorsPage: View {
    @AppStorage("colRev") var rev = 0       // views that draw the bar watch this, so a change shows at once
    static let swatches = ["FFFFFF", "66A0FF", "40E0FF", "5CE08A", "FFD84D", "FF9F40", "FF5A6A", "C77DFF", "FF7ACB"]

    var body: some View {
        let _ = rev
        VStack(alignment: .leading, spacing: 4) {
            ForEach(BarColor.allCases, id: \.self) { c in
                let cur = Prefs.d.string(forKey: c.rawValue) ?? ""
                VStack(alignment: .leading, spacing: 6) {
                    Text(c.title).font(.system(size: 12.5, weight: .medium))
                    HStack(spacing: 7) {
                        ForEach(Self.swatches, id: \.self) { h in
                            Button { set(c, h) } label: {
                                Circle().fill(Color(hex: h) ?? .white).frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: cur.uppercased() == h ? 2 : 0))
                                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                        ColorPicker("", selection: Binding(get: { c.color }, set: { set(c, $0.hex) }), supportsOpacity: false).labelsHidden()
                        Spacer(minLength: 0)
                        Button("Reset") { set(c, "") }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(cur.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(accent)).disabled(cur.isEmpty)
                    }
                }.padding(.vertical, 6)
                Divider().opacity(0.3)
            }
            Button { BarColor.allCases.forEach { Prefs.d.removeObject(forKey: $0.rawValue) }; rev += 1 } label: {
                Text("Reset all colours").font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08)))
            }.buttonStyle(.plain).padding(.top, 6)
        }
    }

    func set(_ c: BarColor, _ hex: String) {
        if hex.isEmpty { Prefs.d.removeObject(forKey: c.rawValue) } else { Prefs.d.set(hex, forKey: c.rawValue) }
        rev += 1
    }
}

// MARK: - Neon look shared by every box on the bar

extension View {
    /// A clean neon glow: a tight bright edge plus a soft halo.
    func neon(_ c: Color, _ strength: CGFloat = 1) -> some View {
        self.shadow(color: c.opacity(min(1, 0.95 * strength)), radius: 1.2 * strength)
            .shadow(color: c.opacity(min(1, 0.6 * strength)), radius: 6 * strength)
    }
}

/// One rounded box with a neon outline: dark glass inside, bright edge, soft glow.
struct NeonBox: View {
    let color: Color
    var radius: CGFloat = 9
    var strength: CGFloat = 1
    var body: some View {
        let r = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            r.fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
            r.fill(color.opacity(0.06))
            r.strokeBorder(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom), lineWidth: 1.3)
                .neon(color, strength)
            r.inset(by: 1.5).strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        }
    }
}

// MARK: - Hover highlight (a master rule): whatever you rest on lifts up and glows in its own colour

final class HoverModel: ObservableObject {
    static let shared = HoverModel()
    @Published var item: String?
    @Published var island = false
}

struct HoverLift: ViewModifier {
    let id: String
    let color: Color
    var radius: CGFloat = 7
    @ObservedObject var h = HoverModel.shared
    func body(content: Content) -> some View {
        let on = h.item == id
        let r = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                r.fill(color.opacity(on ? 0.16 : 0))
                    .overlay(r.strokeBorder(color.opacity(on ? 0.95 : 0), lineWidth: 1.2))
                    .neon(color, on ? 0.8 : 0)
            }
            .scaleEffect(on ? 1.07 : 1)
            .offset(y: on ? -1.5 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: on)
            .onHover { inside in
                if inside { h.item = id } else if h.item == id { h.item = nil }
            }
    }
}

extension View {
    func hoverLift(_ id: String, _ color: Color, radius: CGFloat = 7) -> some View { modifier(HoverLift(id: id, color: color, radius: radius)) }
}
