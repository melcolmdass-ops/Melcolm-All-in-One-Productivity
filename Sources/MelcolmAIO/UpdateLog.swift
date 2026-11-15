import SwiftUI

// MARK: - Update Log: every version, in plain words, three tabs each

struct AppUpdate: Identifiable {
    var id: String { version }
    let version: String
    let date: String
    let title: String
    let improvements: [String]
    let fixes: [String]
    let features: [String]
    /// The picture under the tabs: a few icons that show what changed, in one colour.
    let icons: [String]
    let tint: Color
}

enum UpdateLog {
    static let perPage = 10
    private static let blue = Color(red: 0.36, green: 0.62, blue: 1.0), cyan = Color(red: 0.25, green: 0.88, blue: 1.0)
    private static let pink = Color(red: 1.0, green: 0.42, blue: 0.7), green = Color(red: 0.3, green: 0.92, blue: 0.5)
    private static let purple = Color(red: 0.7, green: 0.48, blue: 1.0), yellow = Color(red: 1.0, green: 0.82, blue: 0.3)
    private static let orange = Color(red: 1.0, green: 0.6, blue: 0.25)

    /// Newest first.
    static let all: [AppUpdate] = [
        AppUpdate(version: "2.6", date: "November 15th, 2026", title: "Everything lights up when you rest on it",
                  improvements: [
                      "Play / Pause reacts right away: it reads the player's own button in a third of a second instead of waiting 1.5 seconds.",
                      "Scrubbing is instant: the bar jumps where you let go and the song catches up in the background.",
                      "The play bar is thicker and red.",
                      "Low Power Mode asks for your password only the first time.",
                  ],
                  fixes: [
                      "Play / Pause no longer shows the opposite state after a song changes.",
                      "Scrubbing no longer freezes the panel.",
                  ],
                  features: [
                      "Hover highlight: every part of the bar lifts up and glows in its own colour when you rest on it.",
                  ],
                  icons: ["cursorarrow.rays", "playpause.fill", "slider.horizontal.below.rectangle"], tint: Color(red: 1.0, green: 0.42, blue: 0.7)),
        AppUpdate(version: "2.5", date: "November 15th, 2026", title: "Play buttons that tell the truth, and much bigger icons",
                  improvements: [
                      "Icons on the bar are about twice as big, and the Small / Medium / Large sizes are all bigger.",
                      "Layouts on Home sit two per row, so every button shows its whole name.",
                      "\"Open on Home\" is now called Quick View.",
                  ],
                  fixes: [
                      "The Play / Pause button no longer shows the opposite of what's happening in YouTube Music.",
                      "Pressing Play no longer starts a different song from the queue by mistake.",
                      "Play / Pause works for YouTube Music without Chrome's JavaScript setting, so it doesn't matter when Chrome turns it off.",
                  ],
                  features: [],
                  icons: ["playpause.fill", "plus.magnifyingglass", "square.grid.2x2.fill"], tint: pink),
        AppUpdate(version: "2.4", date: "November 15th, 2026", title: "Sleek neon bar, smart arranging and Low Power Mode",
                  improvements: [
                      "Every box on the bar has a cleaner, stronger neon glow.",
                      "The highlight on the Space you're in is slimmer and neater.",
                      "Opening and closing the panel is smoother. It shrinks back into the notch instead of just vanishing.",
                  ],
                  fixes: [
                      "The panel no longer jumps back to Home halfway through closing.",
                      "When an app has lots of menus (like Chrome), the island never covers them. Your displays move to the right side instead.",
                  ],
                  features: [
                      "Display 1 sits left of the notch and your other displays sit right of it.",
                      "Auto-arrange has an arrow: pick an arrangement from pictures (centre, halves, thirds, quarters and more).",
                      "Low Power Mode switch on the Batteries page and in the battery pop-up (password only the first time).",
                      "Master Rules page: things the app always does, like closing when you open a link.",
                      "This Update Log!",
                  ],
                  icons: ["sparkles", "rectangle.split.3x1.fill", "bolt.badge.automatic.fill"], tint: cyan),
        AppUpdate(version: "2.3", date: "November 14th, 2026", title: "Wi-Fi lists, Minimize all Spaces and a live play bar",
                  improvements: ["Wi-Fi and Bluetooth show their lists right in the pop-up.", "Layouts in the dropdown each have a small picture."],
                  fixes: ["Minimize all (Spaces) visits each Space that won't close on its own.", "The notch outline and the boxes no longer touch."],
                  features: ["Drag the play bar to jump around in songs playing in web players.", "The notch is now the open button, with a glowing outline.", "Colors tab: pick the colour of every outline on the bar."],
                  icons: ["wifi", "arrow.down.right.and.arrow.up.left", "music.note"], tint: blue),
        AppUpdate(version: "2.2", date: "November 14th, 2026", title: "Minimize everything in one click",
                  improvements: ["Layouts sit in one tidy row on Home."],
                  fixes: [],
                  features: ["Minimize all (desktop) hides every window on your desktop.", "Minimize all (Spaces) closes every full-screen app on every display."],
                  icons: ["rectangle.compress.vertical", "arrow.down.right.and.arrow.up.left"], tint: purple),
        AppUpdate(version: "2.1", date: "November 14th, 2026", title: "Focus modes and smarter Spaces",
                  improvements: ["Layouts show in two rows, with a hidden section for ones you don't use.", "Two apps side by side share one Space box."],
                  fixes: ["The island moves out of the way of app menus."],
                  features: ["Wi-Fi and Bluetooth controls like Control Center.", "Focus modes."],
                  icons: ["moon.fill", "square.split.2x1.fill"], tint: purple),
        AppUpdate(version: "2.0", date: "November 14th, 2026", title: "The utility bar",
                  improvements: ["Settings has tabs inside tabs, so things are easier to find.", "Every Settings section has a little picture explaining it."],
                  fixes: ["Batteries no longer get cut off in the pop-up."],
                  features: ["Utility bar: small buttons at the bottom of Home that open a page as a pop-up.", "Choose what shows beside the arrow on the bar."],
                  icons: ["square.grid.3x1.below.line.grid.1x2.fill", "slider.horizontal.3"], tint: green),
        AppUpdate(version: "1.9", date: "November 14th, 2026", title: "Batteries bar and the Clock",
                  improvements: ["Timer is now called Clock.", "Pick which shows first on the bar: the clock or the music."],
                  fixes: ["Play and skip no longer pull the browser tab to the front."],
                  features: ["Batteries bar: your Mac, AirPods (left, right and case) and keyboard, with hide and show.", "The play bar works for YouTube Music."],
                  icons: ["battery.75percent", "airpodspro", "timer"], tint: green),
        AppUpdate(version: "1.8", date: "November 14th, 2026", title: "Now Playing page",
                  improvements: ["Every music player uses the same card.", "Smoother opening and closing."],
                  fixes: ["The Now Playing tile stopped blinking."],
                  features: ["Now Playing page with play, pause and skip for every tab.", "Hover bar: rest on the island for quick controls."],
                  icons: ["music.note.list", "play.fill"], tint: pink),
        AppUpdate(version: "1.7", date: "November 14th, 2026", title: "The island joins the notch",
                  improvements: ["New look: gradients, glass cards and glowing icons."],
                  fixes: ["The island is centred across the notch."],
                  features: [],
                  icons: ["capsule.fill", "paintbrush.fill"], tint: purple),
        AppUpdate(version: "1.6", date: "November 14th, 2026", title: "Apple-style Now Playing",
                  improvements: ["YouTube songs show their picture and the artist."],
                  fixes: ["On the MacBook the island sits right beside the notch."],
                  features: ["Pages settings: choose what's on Home."],
                  icons: ["music.note", "photo.fill"], tint: pink),
        AppUpdate(version: "1.5", date: "November 14th, 2026", title: "Music from your browser and window layouts",
                  improvements: ["Bigger arrow and brighter boxes."],
                  fixes: [],
                  features: ["Sees music playing in any browser tab or web app.", "A wave that moves to the beat.", "Layouts page: snap windows into halves and thirds."],
                  icons: ["waveform", "rectangle.split.2x1.fill"], tint: blue),
        AppUpdate(version: "1.4", date: "November 14th, 2026", title: "One page per button",
                  improvements: ["Faster Space switching (with a classic option)."],
                  fixes: [],
                  features: ["Pages for Sound, Mic, Brightness, Wi-Fi, Bluetooth, Keep Awake, Dark Mode and Timer."],
                  icons: ["square.grid.2x2.fill", "speaker.wave.2.fill"], tint: blue),
        AppUpdate(version: "1.3", date: "November 14th, 2026", title: "Cleaner Space boxes",
                  improvements: ["Boxes show the desktop number and your full-screen apps only."],
                  fixes: ["No more repeated Accessibility pop-ups."],
                  features: ["A glowing outline on the app you're using."],
                  icons: ["rectangle.on.rectangle", "sparkles"], tint: cyan),
        AppUpdate(version: "1.2", date: "November 14th, 2026", title: "Pop-ups and keyboard control",
                  improvements: ["One box per display."],
                  fixes: ["Permissions are remembered between updates."],
                  features: ["Little pop-ups when the song or speaker changes.", "Scroll on the island to change the volume.", "Control everything from the keyboard."],
                  icons: ["keyboard", "bell.fill"], tint: yellow),
        AppUpdate(version: "1.1", date: "November 14th, 2026", title: "App icons and Settings",
                  improvements: ["Sound, Now Playing and the mic are together."],
                  fixes: [],
                  features: ["Space boxes with app icons.", "Settings pages.", "Keyboard shortcuts."],
                  icons: ["gearshape.fill", "app.fill"], tint: orange),
        AppUpdate(version: "1.0", date: "November 14th, 2026", title: "Melcolm All-in-One is born",
                  improvements: [],
                  fixes: [],
                  features: ["A notch island showing your Spaces.", "Sound, now playing, a timer and your Mac's status in one place."],
                  icons: ["sparkles", "macbook"], tint: orange),
    ]
}

/// Which tab each update shows and which page you're on (kept while the app runs).
final class UpdateLogState: ObservableObject {
    static let shared = UpdateLogState()
    @Published var tab: [String: Int] = [:]
    @Published var page = 0
}

struct UpdateLogPage: View {
    @ObservedObject var m = UpdateLogState.shared

    var body: some View {
        let list = UpdateLog.all
        let pages = max(1, Int(ceil(Double(list.count) / Double(UpdateLog.perPage))))
        let page = min(m.page, pages - 1)
        let slice = Array(list.dropFirst(page * UpdateLog.perPage).prefix(UpdateLog.perPage))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(list.count) updates").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                pager(page, pages)
            }
            ForEach(slice) { u in UpdateCard(u: u, tab: Binding(get: { m.tab[u.version] ?? Self.firstTab(u) }, set: { m.tab[u.version] = $0 })) }
            HStack { Spacer(); pager(page, pages) }
        }
    }

    static func firstTab(_ u: AppUpdate) -> Int { !u.improvements.isEmpty ? 0 : !u.fixes.isEmpty ? 1 : 2 }

    func pager(_ page: Int, _ pages: Int) -> some View {
        HStack(spacing: 6) {
            Button { m.page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }.disabled(page == 0)
            ForEach(0 ..< pages, id: \.self) { i in
                Button { m.page = i } label: {
                    Text("\(i + 1)").font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(i == page ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.07))))
                }
            }
            Button { m.page = min(pages - 1, page + 1) } label: { Image(systemName: "chevron.right") }.disabled(page >= pages - 1)
        }
        .buttonStyle(.plain).font(.system(size: 10, weight: .bold))
    }
}

/// One update: version, date, title, three tabs (Improvements · Fixes · New features), then its picture.
struct UpdateCard: View {
    let u: AppUpdate
    @Binding var tab: Int

    var body: some View {
        let groups: [(String, String, [String], Color)] = [
            ("Improvements", "arrow.up.circle.fill", u.improvements, Color(red: 0.25, green: 0.88, blue: 1.0)),
            ("Fixes", "wrench.and.screwdriver.fill", u.fixes, Color(red: 1.0, green: 0.62, blue: 0.3)),
            ("New features", "sparkles", u.features, Color(red: 0.75, green: 0.52, blue: 1.0)),
        ]
        let cur = groups[tab]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("V\(u.version)").font(.system(size: 10.5, weight: .heavy, design: .rounded)).foregroundStyle(u.tint)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(u.tint.opacity(0.14)).overlay(Capsule().strokeBorder(u.tint.opacity(0.5), lineWidth: 1)))
                Spacer()
                Text(u.date).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(u.title).font(.system(size: 14, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(0 ..< 3, id: \.self) { i in
                    let g = groups[i]; let on = i == tab
                    Button { tab = i } label: {
                        HStack(spacing: 5) {
                            Text(g.0).font(.system(size: 11, weight: .bold))
                            Text("\(g.2.count)").font(.system(size: 10, weight: .heavy, design: .rounded))
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Circle().fill(on ? g.3.opacity(0.3) : .white.opacity(0.08)))
                        }
                        .foregroundStyle(on ? .white : .white.opacity(g.2.isEmpty ? 0.3 : 0.7))
                        .padding(.horizontal, 9).frame(height: 26)
                        .background {
                            let r = RoundedRectangle(cornerRadius: 8, style: .continuous)
                            r.fill(on ? g.3.opacity(0.16) : .white.opacity(0.04))
                            r.strokeBorder(on ? g.3 : .white.opacity(0.12), lineWidth: on ? 1.3 : 1)
                        }
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(g.2.isEmpty)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if cur.2.isEmpty {
                    Text("Nothing here in this update.").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                ForEach(Array(cur.2.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: cur.1).font(.system(size: 10, weight: .bold)).foregroundStyle(cur.3)
                        Text(line).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: tab)
            // The same picture for all three tabs.
            HStack(spacing: 10) {
                ForEach(u.icons, id: \.self) { ic in
                    Image(systemName: ic).font(.system(size: 20, weight: .semibold)).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(u.tint)
                        .frame(width: 52, height: 44)
                        .background(NeonBox(color: u.tint, radius: 11, strength: 0.6))
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [u.tint.opacity(0.12), Color(white: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.085))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.09), lineWidth: 1)))
    }
}

// MARK: - Master Rules: things the app always does, everywhere

struct MasterRule: Identifiable {
    var id: String { title }
    let icon: String, title: String, detail: String
    static let all: [MasterRule] = [
        MasterRule(icon: "arrow.up.forward.app.fill", title: "Opening something outside closes the panel",
                   detail: "Click the artwork, a link, a settings button, a shortcut or anything that opens another app, and the panel closes while that thing opens."),
        MasterRule(icon: "cursorarrow.rays", title: "Whatever you rest on lights up",
                   detail: "Rest the pointer on anything in the bar (a display number, an app, the music, the arrow, the notch or the island itself) and it lifts up a little and glows in the colour you picked for it in Colors."),
        MasterRule(icon: "menubar.rectangle", title: "App menus are never covered",
                   detail: "If an app's menus (File, Edit, View…) would run under the island, your displays move to the right of the notch instead."),
    ]
}

struct MasterRulesPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("These always happen, everywhere in the app. More will be added as the app grows.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(MasterRule.all.enumerated()), id: \.offset) { i, r in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(accent)
                        .frame(width: 26, height: 26).background(NeonBox(color: accent, radius: 8, strength: 0.5))
                    VStack(alignment: .leading, spacing: 3) {
                        Label(r.title, systemImage: r.icon).font(.system(size: 13, weight: .bold))
                        Text(r.detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.04)))
            }
        }
    }
}
