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
        AppUpdate(version: "2.41", date: "November 17th, 2026", title: "Double-tap keys, Space hotkeys, Notifications",
                  improvements: [],
                  fixes: [
                      "The focus workflow message and the completed pop-up now sit above the bar even when it is open. Click either one to close it early.",
                      "The open panel no longer covers an app's menus (Chrome's, for example) and keeps the same size when you switch apps: it only grows when something new has to fit. New Master Rule: The bar only resizes when it has to.",
                      "Dragging a full-screen app onto any display's space area now lands it in that display's Spaces. Only the number itself means \"go to this desktop\".",
                  ],
                  features: [
                      "Commands: every command can now also run when you double-tap a key (Left or Right ⌘, ⌥, ⌃, ⇧ or fn), including open or close the bar.",
                      "When you open the bar yourself (not on hover), a short line under the bar reminds you that ← → switch Spaces, with a Change keys link to Commands.",
                      "Switching Spaces with the arrows or the Next/Previous commands now wraps around: past the last Space you land on the first.",
                      "Settings ▸ Colors is now Colors & Display with two tabs. Display holds the Box style (Outlined, Soft, Minimal) and an on/off tick for the Space reminder, each with a picture.",
                      "Commands: each command now has a small picture and ONE trigger in a single dropdown: a hotkey, a double-tap, or Off (never both). Rows keep the same height.",
                      "New commands: Next Space and Previous Space, with your own key.",
                      "Notifications is now its own tab next to Home (Home | Notifications), grouped by app, newest app first, with Show more per app. Only apps that are turned on in System Settings ▸ Notifications appear. It needs Full Disk Access (quit and reopen the app after allowing it).",
                      "Notifications has Clear all (empties the list and dismisses the banners still showing) and a clear button on each app.",
                      "The Space-switch reminder now sits in an outlined box above the Home | Notifications tabs.",
                      "← → switch Spaces smoothly while the bar is open: the bar listens for the arrows even after a Space change moves the keyboard to another app, so every press works straight away.",
                  ],
                  icons: ["keyboard", "bell.badge.fill", "rectangle.on.rectangle"], tint: pink),
        AppUpdate(version: "2.40", date: "November 16th, 2026", title: "The bar stays put when you swipe",
                  improvements: [],
                  fixes: [
                      "Swiping between Spaces on the MacBook no longer makes the bar disappear and come back. The app now leaves it alone unless it is truly missing from the screen.",
                  ],
                  features: [],
                  icons: ["rectangle.on.rectangle", "hand.draw.fill"], tint: green),
        AppUpdate(version: "2.39", date: "November 16th, 2026", title: "See the whole workflow",
                  improvements: [],
                  fixes: [],
                  features: [
                      "When you edit a focus workflow, a small box at the top shows every step that will run, top to bottom, each in its own neat little box with its icon. It updates as you switch steps on and off or drag them into a new order.",
                  ],
                  icons: ["list.number", "rectangle.stack.fill"], tint: cyan),
        AppUpdate(version: "2.38", date: "November 16th, 2026", title: "Typing is just typing",
                  improvements: [],
                  fixes: [
                      "Pressing space while typing a name (or anything in a text box) no longer plays or pauses music. No shortcut fires while you type, except opening and closing the panel. Added as a Master Rule.",
                  ],
                  features: [],
                  icons: ["character.cursor.ibeam", "keyboard"], tint: green),
        AppUpdate(version: "2.37", date: "November 16th, 2026", title: "Focus Workflows crash fix",
                  improvements: [],
                  fixes: [
                      "Opening a focus workflow to edit it could close the app. Your Shortcuts list is now read quietly in the background instead.",
                  ],
                  features: [],
                  icons: ["wrench.and.screwdriver.fill"], tint: green),
        AppUpdate(version: "2.36", date: "November 16th, 2026", title: "Focus Workflows on the bar",
                  improvements: [
                      "Focus is now called Focus Workflows everywhere: Settings, Pages, Home and the pop-ups.",
                  ],
                  fixes: [],
                  features: [
                      "While a focus workflow runs, the bar shows it (its icon pulsing and its name) until it's done.",
                  ],
                  icons: ["brain.head.profile", "rectangle.topthird.inset.filled"], tint: purple),
        AppUpdate(version: "2.35", date: "November 16th, 2026", title: "Focus flows",
                  improvements: [
                      "Focus modes are now focus flows: press Run and it does its steps once, like a shortcut. No more Start and Stop.",
                      "Every step sits in its own box with a drag handle. Drag to choose the order; the flow runs in exactly that order (hide first, then minimize, and so on).",
                      "Removed Auto-arrange windows from focus.",
                  ],
                  fixes: [
                      "With Hide other apps and Minimize all windows both on, apps now get hidden, not just minimized.",
                  ],
                  features: [
                      "When a flow finishes, a short \"… flow completed\" pop-up shows at the bottom middle of the screen (switch it off in Settings ▸ Focus).",
                  ],
                  icons: ["line.3.horizontal", "checkmark.circle.fill", "brain.head.profile"], tint: purple),
        AppUpdate(version: "2.34", date: "November 16th, 2026", title: "Focus feedback",
                  improvements: [],
                  fixes: [],
                  features: [
                      "A focus can show feedback when it starts: your own message in the middle of the screen, or your message plus each thing it did, ticking in one by one (\"Hid all other apps for you\", \"Keeping the screen awake\").",
                      "Choose \"all apps\" wording or show each app it hid, minimized or quit, with their icons.",
                  ],
                  icons: ["text.bubble.fill", "list.bullet.rectangle.fill", "checkmark.circle.fill"], tint: purple),
        AppUpdate(version: "2.33", date: "November 16th, 2026", title: "Search with icons in focus pick lists",
                  improvements: [
                      "Adding apps or Shortcuts to a focus opens a list with a search box and each app's own icon. It stays open so you can add several.",
                      "Every chip shows its app icon; Shortcuts get a Shortcuts-style icon.",
                  ],
                  fixes: [], features: [],
                  icons: ["magnifyingglass", "square.grid.2x2.fill"], tint: purple),
        AppUpdate(version: "2.32", date: "November 16th, 2026", title: "Pick apps and Shortcuts from a list",
                  improvements: [
                      "Quit apps, Open apps and Run Shortcuts in a focus mode are now pick lists: choose from every app on your Mac or every Shortcut you have. Each one you add shows as its own outlined chip with its icon, and an ✕ to remove it.",
                      "Those boxes are twice as tall.",
                  ],
                  fixes: [],
                  features: [
                      "A focus mode can run more than one Shortcut.",
                  ],
                  icons: ["square.grid.2x2.fill", "square.stack.3d.up.fill"], tint: purple),
        AppUpdate(version: "2.31", date: "November 16th, 2026", title: "Cleaner focus modes, timer or stopwatch",
                  improvements: [
                      "Editing a focus mode is bigger and clearer: every option has its own picture and one line saying what it does.",
                      "Pick the icon for each focus mode from large buttons.",
                      "Removed the Dark / Light choice from focus modes to keep them simple.",
                  ],
                  fixes: [],
                  features: [
                      "A focus can run a Timer or a Stopwatch (or neither).",
                  ],
                  icons: ["stopwatch", "timer", "brain.head.profile"], tint: purple),
        AppUpdate(version: "2.30", date: "November 16th, 2026", title: "Focus in Settings, tabs on two rows",
                  improvements: [
                      "Settings tabs sit on two rows: General, Main Bar, Dragging, Utility Bar and Focus on top; Colors, Master Rules and Update Log below.",
                  ],
                  fixes: [],
                  features: [
                      "New Focus tab in Settings: edit your focus modes and choose how a focus ends (when its timer is done, show hidden apps, pop-up on/off).",
                  ],
                  icons: ["brain.head.profile", "gearshape.fill"], tint: purple),
        AppUpdate(version: "2.29", date: "November 16th, 2026", title: "Brighter drag circle",
                  improvements: [
                      "The circle around the pointer while you drag is bigger and brighter, with a dashed outer ring like the snap spots and a dark edge so it shows on white pages too.",
                  ],
                  fixes: [], features: [],
                  icons: ["circle.dashed", "smallcircle.filled.circle"], tint: cyan),
        AppUpdate(version: "2.28", date: "November 16th, 2026", title: "Snap spots really resize",
                  improvements: [],
                  fixes: [
                      "Dropping a window on a snap spot now makes it that size (left half is really half the screen, left third is a third), not just moves it there. Chrome and similar apps used to ignore the resize.",
                      "The spot under the pointer when you let go is the one used, even if you let go quickly.",
                  ],
                  features: [],
                  icons: ["rectangle.lefthalf.filled", "rectangle.split.3x1"], tint: blue),
        AppUpdate(version: "2.27", date: "November 16th, 2026", title: "Box style: Outlined, Soft or Minimal",
                  improvements: [
                      "The bar is calmer by default: display boxes and the Play / Open box use a faint fill instead of a glowing outline (Soft).",
                  ],
                  fixes: [],
                  features: [
                      "New Box style on the Colours page: Outlined (the old look), Soft, or Minimal (no boxes at all). A box still lights up while you drag something onto it.",
                  ],
                  icons: ["square.dashed", "square.fill", "square"], tint: purple),
        AppUpdate(version: "2.26", date: "November 16th, 2026", title: "One colour for all box outlines",
                  improvements: [
                      "Colours is simpler: the display boxes, the notch and the Play / Open box are all outlines, so one row, Box outlines, colours all of them.",
                  ],
                  fixes: [
                      "Removed the \"same as\" notes. They were more confusing than helpful.",
                  ],
                  features: [],
                  icons: ["paintpalette.fill", "square.dashed"], tint: purple),
        AppUpdate(version: "2.25", date: "November 16th, 2026", title: "Drop circle, smoother snapping, colour flash",
                  improvements: [
                      "Moving from one snap spot to another (left third to left half) switches at once. The old outline never hangs around.",
                      "Only one outline at a time: over a spot you see just the spot. Let go and the window shows again as it moves in.",
                  ],
                  fixes: [
                      "The snap outline no longer blinks or slides up and down while you drag between spots.",
                  ],
                  features: [
                      "A small circle sits around the pointer while you drag. It takes the spot's colour when you're over one, and sinks into it when you let go.",
                      "Picking a colour makes that part of the real bar glow for a second.",
                      "Colours shows a \"same as\" note when two parts share a colour, so you know why they blend.",
                  ],
                  icons: ["circle.dashed", "rectangle.split.3x1", "paintpalette.fill"], tint: cyan),
        AppUpdate(version: "2.24", date: "November 16th, 2026", title: "See what each colour changes",
                  improvements: [], fixes: [],
                  features: [
                      "Every row on the Colours page has a small picture of the bar. The part that row colours is lit in your chosen colour and the rest fades back, so you can see what you're changing as you pick.",
                  ],
                  icons: ["paintpalette.fill", "rectangle.topthird.inset.filled"], tint: purple),
        AppUpdate(version: "2.23", date: "November 16th, 2026", title: "Clearer drop onto a desktop",
                  improvements: [
                      "Dragging an app over a desktop number now says in words what will happen, under the bar: \"Let go: Claude leaves full screen onto Desktop 1\".",
                      "The desktop number gets a dashed white outline and a soft glow instead of a blinding block, so the number stays easy to read.",
                  ],
                  fixes: [], features: [],
                  icons: ["macwindow.and.arrow.down", "1.square"], tint: cyan),
        AppUpdate(version: "2.22", date: "November 16th, 2026", title: "Wi-Fi + Bluetooth pill, drag fixes",
                  improvements: [
                      "Dropping an app onto a desktop number on the bar now makes that number swell, fill bright and glow, so you can clearly see where it's going.",
                      "The New Space circle grows and glows when you drag over it, and its preview is much bigger and brighter.",
                  ],
                  fixes: [
                      "Dragging an app from the bar onto a desktop number now works on the MacBook too, not just the big display.",
                      "The drag spots now show on every display while you hold the drag key.",
                      "Dragging a window onto the bar no longer makes a second New Space. New Space is only the circle at the top.",
                  ],
                  features: [
                      "The Wi-Fi & Bluetooth button shows both icons. Tap one to open its tab straight away.",
                  ],
                  icons: ["wifi", "dot.radiowaves.left.and.right", "plus.rectangle.on.rectangle"], tint: cyan),
        AppUpdate(version: "2.21", date: "November 15th, 2026", title: "Play the right thing, Hide spot, Settings tabs",
                  improvements: [
                      "The Settings tabs (General, Main Bar, Dragging and the rest) have a solid button area, so every click lands.",
                  ],
                  fixes: [
                      "Dragging the play bar on YouTube / YouTube Music works without Chrome's \"Allow JavaScript from Apple Events\" setting: if the page won't move, the same song reopens at the spot you picked. The orange warning is gone.",
                      "With two things playing (say a song and a TV show), pressing Play on one row now plays that one, never the other.",
                      "Settings tabs that wouldn't switch when clicked now switch. The tab row always fits inside the panel, so the end tabs (General, Update Log) aren't half off the edge.",
                  ],
                  features: [
                      "New Hide option for snap spots: drag a window into that circle and the app hides, just like ⌘H.",
                      "New Master Rule: each Now Playing row only ever controls what it shows.",
                  ],
                  icons: ["play.circle.fill", "eye.slash.fill", "gearshape.fill"], tint: Color(red: 1.0, green: 0.42, blue: 0.7)),
        AppUpdate(version: "2.20", date: "November 15th, 2026", title: "Always shows what's playing, snap circles",
                  improvements: [
                      "Each snap spot is now a dashed circle you can see. Drop a window inside a circle to snap it; anywhere else it just moves.",
                      "Settings ▸ Dragging shows the same dashed circles around each spot.",
                  ],
                  fixes: [
                      "A song playing in the YouTube Music app on another display or Space now shows as playing, with its time moving and the wave on the bar.",
                      "Holding the drag key inside a full-screen app no longer shows the snap spots.",
                  ],
                  features: [
                      "Two new Master Rules: what you hear always shows as playing, and snap circles only appear on a desktop.",
                  ],
                  icons: ["waveform", "circle.dashed", "rectangle.3.group.fill"], tint: Color(red: 0.36, green: 0.62, blue: 1.0)),
        AppUpdate(version: "2.19", date: "November 15th, 2026", title: "Smoother, cleaner dragging",
                  improvements: [
                      "The snap dots are built once and just fade in and out, so they no longer flash when you tap or hold Option.",
                      "The window's picture fades into the dragged copy instead of popping in.",
                      "The blue snap box hides cleanly and never blinks when you move between spots quickly.",
                  ],
                  fixes: [
                      "The window no longer jumps a little at the very start of a drag.",
                      "Quickly pressing and releasing Option no longer leaves the dots half-shown.",
                  ],
                  features: [],
                  icons: ["sparkles", "wand.and.stars", "circle.grid.3x3.fill"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.18", date: "November 15th, 2026", title: "See the snap spots",
                  improvements: [
                      "A window dropped on the bar now always becomes the last Space, wherever you drop it, so other apps no longer open and close one after another to make room.",
                  ],
                  fixes: [],
                  features: [
                      "Hold Option and the snap spots appear on your screen as glowing dots with labels, so you know exactly where to drag.",
                      "The top-middle spot is now always \"New Space\": drag a window there and it becomes its own Space. It's locked in Settings so it can't be changed.",
                  ],
                  icons: ["circle.grid.3x3.fill", "plus.rectangle.on.rectangle", "lock.fill"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.17", date: "November 15th, 2026", title: "Better snapping",
                  improvements: [
                      "Snap spots are bigger and easier to hit, and once one shows it doesn't flicker off if your hand wobbles.",
                      "The blue snap box glides between spots and says what it'll do (like \"Left half\").",
                      "When you let go, the window glides into its spot instead of jumping.",
                      "The snap settings are now one big picture of your screen: tap a dot to pick a spot, see exactly where windows will go, and choose a layout from the tiles underneath.",
                  ],
                  fixes: [],
                  features: [],
                  icons: ["rectangle.3.group.fill", "hand.tap.fill", "sparkles"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.16", date: "November 15th, 2026", title: "Snap spots and drop spots",
                  improvements: [
                      "Dragging is lighter and smoother: the copy of the window no longer blurs what's behind it as it moves.",
                  ],
                  fixes: [],
                  features: [
                      "Drag a window into any edge or corner of the screen and a glowing box shows where it'll snap; let go and it takes that spot.",
                      "Settings ▸ Dragging has a picture of the screen with a picker on each of the 8 spots (corners and the middle of each edge). Choose a layout for each, or None.",
                      "Drop a window on a particular spot on the bar to choose where its new Space goes, between the apps already there and on whichever display you drop it.",
                  ],
                  icons: ["rectangle.3.group.fill", "macwindow.on.rectangle", "plus.rectangle.on.rectangle"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.15", date: "November 15th, 2026", title: "Dragging you can feel",
                  improvements: [
                      "A grabbed window lifts off the screen with a soft spring and a glow, and settles smoothly when you let go.",
                  ],
                  fixes: [],
                  features: [
                      "Drag a window over the bar and it shrinks into a glowing \"New Space\" tile, so you can see it's about to become a Space.",
                      "Let go on the bar and it zips into the bar, and the bar says \"App → new Space\".",
                  ],
                  icons: ["sparkles", "plus.rectangle.on.rectangle", "menubar.rectangle"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.14", date: "November 15th, 2026", title: "Instant dragging",
                  improvements: [
                      "Option-drag is now instant: a see-through copy of the window sticks to your pointer, and the window jumps there the moment you let go.",
                  ],
                  fixes: [
                      "No more lag while dragging, whatever app the window belongs to.",
                  ],
                  features: [],
                  icons: ["bolt.fill", "macwindow.on.rectangle", "cursorarrow.motionlines"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.13", date: "November 15th, 2026", title: "Even faster dragging",
                  improvements: [
                      "Option-drag now runs on its own, so the rest of the app can never slow your mouse or the window down.",
                  ],
                  fixes: [
                      "The ⌥ badge now shows the moment you hold the key while resting on something, and sticks to your pointer the whole time you drag.",
                  ],
                  features: [],
                  icons: ["hare.fill", "option", "cursorarrow.motionlines"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.12", date: "November 15th, 2026", title: "Fast, smooth window dragging",
                  improvements: [
                      "Holding Option and dragging a window is now fast and smooth: the window keeps up with your pointer instead of lagging behind.",
                      "Your mouse never slows down while you drag.",
                  ],
                  fixes: [],
                  features: [
                      "Hold the drag key and a small ⌥ badge appears beside your pointer, so you know you can grab any window.",
                  ],
                  icons: ["macwindow.and.cursorarrow", "hare.fill", "option"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.11", date: "November 15th, 2026", title: "Drag any window onto the bar",
                  improvements: [
                      "If the bar gets wider while the panel is open (like when you start the stopwatch), the panel now grows with it smoothly.",
                  ],
                  fixes: [
                      "Split View apps now show on the bar in the same order as on screen (left app on the left).",
                      "The bar now always shows on every Space, including full-screen apps like Claude and Premiere Pro and newly made Split Views.",
                  ],
                  features: [
                      "Hold Option and drag any window from anywhere on it, not just the top.",
                      "Drop that window on the bar and it becomes its own full-screen Space.",
                      "New Dragging page in Settings: turn it on or off and pick the key to hold (Option, Shift, Control or Command).",
                  ],
                  icons: ["macwindow.and.cursorarrow", "rectangle.split.2x1.fill", "stopwatch"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.10", date: "November 15th, 2026", title: "A smoother drop",
                  improvements: [
                      "When you let go, the app glides from your pointer straight into its new place in one smooth motion.",
                      "The other apps settle with the same motion, so nothing moves at a different speed.",
                      "An app dropped on another display fades out where you let go and grows into its new spot.",
                  ],
                  fixes: [
                      "The moved app no longer flashes when macOS finishes the move.",
                  ],
                  features: [],
                  icons: ["hand.draw.fill", "wind", "sparkles"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.9", date: "November 15th, 2026", title: "Apps slide aside while you drag",
                  improvements: [
                      "While you drag an app, the others slide aside to open a space exactly where it will land.",
                      "The space it came from closes up behind it, and a display's box stretches or shrinks as apps move in or out.",
                  ],
                  fixes: [
                      "The drop spot no longer jumps around while the apps are moving.",
                  ],
                  features: [
                      "Sliding apps replace the thin line that used to show the drop spot.",
                  ],
                  icons: ["arrow.left.and.right", "hand.draw.fill", "rectangle.split.3x1"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.8", date: "November 15th, 2026", title: "Faster swaps when you drag",
                  improvements: [
                      "Swapping two full-screen apps now moves just one of them, so it's about 2 seconds instead of 5 to 7.",
                      "Each step starts the moment macOS is ready instead of waiting a fixed time.",
                  ],
                  fixes: [
                      "An app no longer gets stuck out of full screen if macOS was still animating when it was asked to go back.",
                  ],
                  features: [
                      "New master rule: dragging is always smooth.",
                  ],
                  icons: ["hand.draw.fill", "bolt.fill", "arrow.left.arrow.right"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
        AppUpdate(version: "2.7", date: "November 15th, 2026", title: "Drag your full-screen apps around the bar",
                  improvements: [
                      "While you drag, a cyan line shows exactly where the app will land.",
                      "The display box you're over glows brighter, so you always know which display you're dropping on.",
                  ],
                  fixes: [
                      "Split View pairs (two apps sharing one box) stay together: they can't be dragged, and moving another app never pulls them apart.",
                  ],
                  features: [
                      "Drag a full-screen app between two others to move it there, on the same display or another one.",
                      "Drop a full-screen app on a display number to take it out of full screen onto that desktop.",
                      "Settings ▸ Main Bar ▸ Spaces has a new Drag box with pictures of what you can and can't do, and one on/off switch.",
                  ],
                  icons: ["hand.draw.fill", "arrow.left.arrow.right", "rectangle.split.3x1"], tint: Color(red: 0.25, green: 0.88, blue: 1.0)),
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
        MasterRule(icon: "character.cursor.ibeam", title: "Typing never fires a shortcut",
                   detail: "While you're typing in a text box (naming a focus workflow, a search box, a message), every key just types. Space won't play or pause music, numbers won't switch Spaces, arrows won't change the volume. The only shortcut that still works is the one that opens and closes the panel, whatever keys you set it to."),
        MasterRule(icon: "arrow.up.forward.app.fill", title: "Opening something outside closes the panel",
                   detail: "Click the artwork, a link, a settings button, a shortcut or anything that opens another app, and the panel closes while that thing opens."),
        MasterRule(icon: "cursorarrow.rays", title: "Whatever you rest on lights up",
                   detail: "Rest the pointer on anything in the bar (a display number, an app, the music, the arrow, the notch or the island itself) and it lifts up a little and glows in the colour you picked for it in Colors."),
        MasterRule(icon: "menubar.rectangle", title: "App menus are never covered",
                   detail: "If an app's menus (File, Edit, View…) would run under the island, your displays move to the right of the notch instead. The same goes for the open panel: it starts at the notch, so it never covers an app's menus."),
        MasterRule(icon: "arrow.up.left.and.arrow.down.right", title: "The bar only resizes when it has to",
                   detail: "The bar and the open panel keep the same size. They only grow when something new has to fit, like another display, a timer or a song. Switching apps never changes the size: when menus are in the way the bar slides over to the right side of the notch instead."),
        MasterRule(icon: "plus.rectangle.on.rectangle", title: "A dragged window always becomes the last Space",
                   detail: "Drop a window from your desktop onto the bar, or onto the top-middle New Space spot, and it always becomes the last Space on that display, wherever you let go. Nothing else opens, closes or moves to make room."),
        MasterRule(icon: "hand.draw.fill", title: "Dragging is always smooth",
                   detail: "Anything you drag on the bar follows your pointer, the other apps slide aside to make room where it will land, and the bar shows the new order the moment you let go while macOS catches up. Only what has to move moves, so a swap is one quick step."),
        MasterRule(icon: "waveform", title: "If you can hear it, it shows as playing",
                   detail: "Whenever sound is playing, its card shows the Pause button, its time keeps moving, and the bar shows the music note and wave. This holds even when the player is on another display or Space and its page stops reporting. When nothing has been playing for a few seconds, nothing shows as playing."),
        MasterRule(icon: "circle.dashed", title: "Snap circles only on a desktop",
                   detail: "Holding the drag key shows the dashed snap circles only on a desktop, where a window can actually be moved. Inside a full-screen app nothing appears. A window only snaps when you drop it inside a circle."),
        MasterRule(icon: "play.circle.fill", title: "Each player controls only itself",
                   detail: "Play, Pause, Next, Back and the play bar on a Now Playing row only ever act on the exact thing that row shows. If the app can't reach that one directly, it does nothing rather than risk starting something else."),
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
