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
        case .dragging: "Hold a key to drag any window, and drag apps on the bar."
        case .mouse: "Scrolling, hovering and clicking on the island."
        case .hover: "The strip that drops down when you rest on the island."
        case .panel: "Which pages are on Home, their order, and which show in Quick View."
        case .focus: "Your focus workflows: steps that run in order, once, like a shortcut."
        case .colors: "Pick the colours of the closed bar: outlines, boxes and highlights."
        case .look: "How things look and what shows. Tick each one on or off and see it right here."
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
        case .dragging:
            HStack(spacing: 10) {
                Image(systemName: "macwindow.and.cursorarrow").font(.system(size: 26)).foregroundStyle(accent)
                Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(.secondary)
                Image(systemName: "menubar.rectangle").font(.system(size: 26)).foregroundStyle(.cyan)
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
        case .focus:
            HStack(spacing: 10) {
                ForEach(["brain.head.profile", "moon.fill", "book.fill"], id: \.self) { i in
                    Image(systemName: i).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 9).fill(i == "brain.head.profile" ? accent : Color(white: 0.2)))
                }
            }
        case .colors:
            HStack(spacing: 8) {
                ForEach(["66A0FF", "40E0FF", "5CE08A", "FFD84D", "FF7ACB"], id: \.self) { h in Circle().fill(Color(hex: h) ?? .white).frame(width: 22, height: 22) }
            }
        case .look:
            HStack(spacing: 8) { ForEach(["Outlined", "Soft", "Minimal"], id: \.self) { t in Text(t).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 7).frame(height: 20).background(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(t == "Outlined" ? 0.8 : 0.25), lineWidth: 1)) } }
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

/// A tiny picture of what a page looks like, for the Pages and Utility Bar lists.
struct PagePicture: View {
    let page: PanelPage
    func g(_ n: String, _ c: Color = .white, _ s: CGFloat = 10) -> some View { Image(systemName: n).font(.system(size: s, weight: .bold)).foregroundStyle(c) }
    func bar(_ w: CGFloat, _ f: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: w, height: 4)
            Capsule().fill(accent).frame(width: w * f, height: 4)
        }
    }
    var body: some View {
        HStack(spacing: 3) {
            switch page {
            case .nowPlaying: g("backward.fill", .white.opacity(0.6), 7); g("play.fill", accent, 9); g("forward.fill", .white.opacity(0.6), 7)
            case .sound: g("speaker.wave.2.fill", accent, 9); bar(24, 0.7); g("mic.fill", .white.opacity(0.7), 8)
            case .brightness: g("sun.max.fill", .yellow, 10); bar(34, 0.6)
            case .network: g("wifi", accent, 10); g("dot.radiowaves.left.and.right", .white.opacity(0.7), 9)
            case .batteries: g("battery.75percent", .green, 11); g("airpods", .white.opacity(0.7), 9)
            case .awake: g("cup.and.saucer.fill", .orange, 10); Text("on").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white.opacity(0.7))
            case .dark: g("circle.lefthalf.filled", .white, 11); g("moon.fill", .white.opacity(0.6), 8)
            case .timer: g("timer", .red, 10); Text("15:01").font(.system(size: 8.5, weight: .heavy).monospacedDigit()).foregroundStyle(.white)
            case .layouts:
                HStack(spacing: 1.5) {
                    RoundedRectangle(cornerRadius: 1.5).fill(accent).frame(width: 9, height: 12)
                    VStack(spacing: 1.5) { RoundedRectangle(cornerRadius: 1.5).fill(.white.opacity(0.4)).frame(width: 9, height: 5.2); RoundedRectangle(cornerRadius: 1.5).fill(.white.opacity(0.4)).frame(width: 9, height: 5.2) }
                }
            case .focus: g("moon.fill", .purple, 10); g("arrow.right", .white.opacity(0.5), 7); g("checkmark.circle.fill", .green, 9)
            default: g(page.icon)
            }
        }
        .frame(width: 72, height: 22)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 0.13)))
    }
}

/// "Hold a key, drag a window, drop it on the bar": three steps drawn out.
struct HoldDragPicture: View {
    let key: String
    func step(_ n: Int, _ label: String, @ViewBuilder _ pic: () -> some View) -> some View {
        VStack(spacing: 5) {
            ZStack { pic() }.frame(width: 84, height: 54)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.13)))
            HStack(spacing: 4) {
                Text("\(n)").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white).frame(width: 14, height: 14).background(Circle().fill(accent))
                Text(label).font(.system(size: 10.5, weight: .semibold))
            }
        }
    }
    var body: some View {
        HStack(spacing: 6) {
            step(1, "Hold") {
                Text(key).font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 34, height: 30).background(RoundedRectangle(cornerRadius: 7).fill(accent))
                    .shadow(color: accent.opacity(0.7), radius: 6)
            }
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            step(2, "Drag") {
                RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 34, height: 24).offset(x: -12, y: 6)
                RoundedRectangle(cornerRadius: 4).fill(accent.opacity(0.35)).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(accent, lineWidth: 1.5)).frame(width: 34, height: 24).offset(x: 8, y: -2)
                Image(systemName: "cursorarrow").font(.system(size: 13)).foregroundStyle(.white).offset(x: 20, y: 8)
            }
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            step(3, "Drop") {
                VStack(spacing: 5) {
                    Capsule().fill(.black).overlay(Capsule().strokeBorder(.cyan, lineWidth: 1)).frame(width: 64, height: 10)
                    Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.cyan)
                    RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.35)).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(accent, lineWidth: 1)).frame(width: 24, height: 16)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
