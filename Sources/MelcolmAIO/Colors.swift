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
                    HStack(alignment: .center) {
                        Text(c.title).font(.system(size: 12.5, weight: .medium))
                        Spacer(minLength: 8)
                        MiniBar(part: c)
                    }
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

/// A small drawing of the bar for the Colours page. The part this row colours is drawn in its
/// live colour (so picking a colour changes it right here); every other part is faded back.
struct MiniBar: View {
    let part: BarColor
    func col(_ p: BarColor) -> Color { p.color.opacity(p == part ? 1 : 0.22) }
    func glow(_ p: BarColor) -> CGFloat { p == part ? 1 : 0 }
    var body: some View {
        let island = UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9, style: .continuous)
        HStack(spacing: 6) {
            // Display boxes: number + a full-screen app, the current one lit by the Space highlight.
            ForEach(1...2, id: \.self) { n in
                HStack(spacing: 3) {
                    Text("\(n)").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(col(.number))
                        .neon(BarColor.number.color, glow(.number) * 0.5)
                        .frame(width: 14, height: 16)
                        .background(RoundedRectangle(cornerRadius: 4).fill(n == 1 ? col(.space).opacity(part == .space ? 0.3 : 0.1) : .clear)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(n == 1 ? col(.space) : .clear, lineWidth: 1.2))
                            .neon(BarColor.space.color, n == 1 ? glow(.space) * 0.8 : 0))
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.35)).frame(width: 12, height: 12)
                }
                .padding(.horizontal, 4).frame(height: 20)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(col(.displayBox), lineWidth: 1.2)
                    .neon(BarColor.displayBox.color, glow(.displayBox) * 0.8))
            }
            // The notch.
            UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6, style: .continuous)
                .fill(Color.black).frame(width: 38, height: 18)
                .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6, style: .continuous)
                    .strokeBorder(col(.notch), lineWidth: 1.2))
                .neon(BarColor.notch.color, glow(.notch) * 0.8)
            // Play / Open box with the music note and wave inside.
            HStack(spacing: 3) {
                Image(systemName: "music.note").font(.system(size: 10, weight: .bold))
                HStack(spacing: 1.5) { ForEach([5.0, 9, 6, 11, 7], id: \.self) { h in Capsule().frame(width: 2, height: h) } }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4))
            }
            .foregroundStyle(col(.status))
            .padding(.horizontal, 5).frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(col(.statusBox), lineWidth: 1.2)
                .neon(BarColor.statusBox.color, glow(.statusBox) * 0.8))
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(island.fill(Color.black))
        .overlay(island.strokeBorder(col(.outline), lineWidth: 1.4).neon(BarColor.outline.color, glow(.outline) * 0.6))
        .allowsHitTesting(false)
        .help("Where \(part.title.lowercased()) shows on the bar")
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
