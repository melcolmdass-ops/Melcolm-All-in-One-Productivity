import SwiftUI

/// A small picture at the top of each Settings section showing what it changes.
struct SettingsVisual: View {
    let page: SettingsTab.Page

    var body: some View {
        HStack(spacing: 14) {
            ZStack { drawing }
                .frame(width: 190, height: 74)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .heavy))
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.105))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1)))
    }

    var title: String { page == .general ? "Main" : page.rawValue }
    var caption: String {
        switch page {
        case .general: "Start at login, permissions, reset and quit."
        case .commands: "Keyboard shortcuts that work from any app."
        case .bar: "Where the island sits, how tall it is and its icon size."
        case .display: "What shows beside the arrow, and the pop-ups under the bar."
        case .spaces: "Your desktops and full-screen apps, one box per display."
        case .mouse: "Scrolling, hovering and clicking on the island."
        case .hover: "The strip that drops down when you rest on the island."
        case .panel: "Which pages are on Home, their order, and which show in Quick View."
        case .colors: "Pick the colours of the closed bar: outlines, boxes and highlights."
        case .utility: "Quick buttons at the bottom of Home; each opens its page as a pop-up."
        case .rules: "Things the app always does, everywhere. You can't switch these off."
        case .updates: "Every update, in plain words."
        }
    }

    // MARK: drawings

    func pill<C: View>(width: CGFloat = 150, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 4) { c() }
            .padding(.horizontal, 6).frame(width: width, height: 20)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8, style: .continuous).fill(.black))
    }
    func box(_ n: String, on: Bool = false) -> some View {
        Text(n).font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(on ? .white : accent)
            .frame(width: 16, height: 14)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? accent.opacity(0.35) : Color(white: 0.2))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(on ? accent : .clear, lineWidth: 1)))
    }
    var chevron: some View {
        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
            .frame(width: 18, height: 12).background(Capsule().fill(.white.opacity(0.15)))
    }
    func key(_ t: String) -> some View {
        Text(t).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
            .frame(minWidth: 30, minHeight: 30).padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.22))
                .shadow(color: .black.opacity(0.6), radius: 0, y: 2))
    }
    func tile(_ c: Color) -> some View {
        RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.2)).frame(width: 40, height: 18)
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 10, height: 10).padding(.leading, 4) }
    }
    func chip(_ icon: String, _ t: String, _ c: Color, on: Bool = false) -> some View {
        HStack(spacing: 2) { Image(systemName: icon).foregroundStyle(c); Text(t) }
            .font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 5).frame(height: 14).background(Capsule().fill(.white.opacity(on ? 0.25 : 0.1)))
    }

    @ViewBuilder var drawing: some View {
        switch page {
        case .general:
            HStack(spacing: 12) {
                Image(systemName: "power.circle.fill").font(.system(size: 26)).foregroundStyle(.green)
                Image(systemName: "lock.shield.fill").font(.system(size: 26)).foregroundStyle(accent)
                Image(systemName: "arrow.counterclockwise.circle.fill").font(.system(size: 26)).foregroundStyle(.orange)
            }
        case .commands:
            HStack(spacing: 5) { key("⌃"); key("⌥"); key("Space") }
        case .bar:
            VStack { pill { box("1", on: true); box("2"); Spacer(); chevron }; Spacer() }
                .overlay(alignment: .bottom) {
                    HStack(spacing: 4) { Image(systemName: "arrow.up.and.down"); Text("height · size") }
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 10)
                }
        case .display:
            VStack(spacing: 6) {
                pill { box("1", on: true); Spacer()
                    Label("01:42", systemImage: "timer").font(.system(size: 8, weight: .bold).monospacedDigit()).foregroundStyle(accent)
                        .padding(.horizontal, 3).background(RoundedRectangle(cornerRadius: 4).strokeBorder(.yellow, lineWidth: 1))
                    chevron }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(accent).frame(width: 10, height: 10)
                    Text("Now playing · Song").font(.system(size: 8, weight: .medium))
                }.padding(.horizontal, 8).frame(height: 16).background(Capsule().fill(.black))
                Spacer(minLength: 0)
            }
        case .spaces:
            HStack(spacing: 8) {
                ForEach(1 ... 2, id: \.self) { n in
                    VStack(spacing: 4) {
                        HStack(spacing: 3) { box("\(n)", on: n == 1); Circle().fill(.orange).frame(width: 10); Circle().fill(.blue).frame(width: 10) }
                            .padding(4).background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
                        Image(systemName: "display").font(.system(size: 18)).foregroundStyle(.secondary)
                    }
                }
            }
        case .mouse:
            VStack { pill { box("1", on: true); box("2"); Spacer(); chevron }; Spacer() }
                .overlay {
                    HStack(spacing: 18) {
                        Image(systemName: "cursorarrow.rays").font(.system(size: 18)).foregroundStyle(.white)
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 14, weight: .bold)).foregroundStyle(accent)
                    }.padding(.top, 22)
                }
        case .rules, .updates:
            HStack(spacing: 10) {
                ForEach(["1", "2", "3"], id: \.self) { n in
                    Text(n).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(accent)
                        .frame(width: 30, height: 30).background(NeonBox(color: accent, radius: 8, strength: 0.6))
                }
            }
        case .colors:
            HStack(spacing: 8) {
                ForEach(["66A0FF", "40E0FF", "5CE08A", "FFD84D", "FF7ACB"], id: \.self) { h in Circle().fill(Color(hex: h) ?? .white).frame(width: 22, height: 22) }
            }
        case .hover:
            VStack(spacing: 0) {
                pill(width: 160) { box("1", on: true); Spacer(); chevron }
                HStack(spacing: 5) {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 7)); Capsule().fill(accent).frame(width: 40, height: 3)
                    Image(systemName: "sun.max.fill").font(.system(size: 7)); Capsule().fill(.yellow).frame(width: 30, height: 3)
                }
                .foregroundStyle(.white).frame(width: 160, height: 18)
                .background(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(Color(white: 0.05)))
                .overlay(alignment: .bottomTrailing) { Image(systemName: "cursorarrow").font(.system(size: 12)).offset(x: -60, y: -16) }
                Spacer(minLength: 0)
            }
        case .panel:
            VStack(spacing: 4) {
                HStack(spacing: 4) { tile(.pink); tile(.blue); tile(.yellow) }
                HStack(spacing: 4) { tile(.cyan); tile(.green); tile(.purple) }
            }
            .overlay(alignment: .leading) { Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).offset(x: -12) }
        case .utility:
            VStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sound").font(.system(size: 7, weight: .heavy))
                    Capsule().fill(accent).frame(width: 60, height: 3)
                }
                .padding(5).background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.24)))
                HStack(spacing: 3) {
                    chip("speaker.wave.2.fill", "56%", accent, on: true); chip("sun.max.fill", "50", .yellow)
                    chip("wifi", "On", .cyan); chip("battery.75percent", "76", .green)
                }
            }
        }
    }
}
