import AppKit
import CoreAudio
import CoreWLAN
import IOBluetooth
import IOKit.ps
import IOKit.pwr_mgt

// MARK: - Sound

/// 'vmvc' — lives in AudioToolbox, defined here to avoid linking it.
private let kAudioHardwareServiceDeviceProperty_VirtualMainVolume: AudioObjectPropertySelector = 0x766D7663

struct OutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

final class SoundModel: ObservableObject {
    @Published var volume: Double = 0.5
    @Published var muted = false
    @Published var devices: [OutputDevice] = []
    @Published var currentDevice: AudioDeviceID = 0
    @Published var inputVolume: Double = 0.5
    @Published var inputMuted = false
    @Published var inputs: [OutputDevice] = []
    @Published var currentInput: AudioDeviceID = 0
    @Published var inputAdjustable = true

    var onDeviceChange: ((String) -> Void)?

    init() {
        refresh()
        var a = Self.addr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main) { [weak self] _, _ in
            guard let self else { return }
            refresh()
            if let n = devices.first(where: { $0.id == self.currentDevice })?.name { onDeviceChange?(n) }
        }
    }

    /// Small step up/down from the real current volume (used by scrolling on the island).
    func nudge(_ d: Double) {
        currentDevice = Self.defaultDevice(input: false)
        let now = Self.getVolume(currentDevice, Self.out).map(Double.init) ?? volume
        setVolume(min(1, max(0, now + d)))
    }

    var outputName: String { devices.first { $0.id == currentDevice }?.name ?? "Output" }

    private static let out = kAudioDevicePropertyScopeOutput
    private static let inp = kAudioDevicePropertyScopeInput

    /// True while any app (dictation, a call…) is recording from the default microphone.
    @Published var micInUse = false
    func refreshMic() {
        let dev = Self.defaultDevice(input: true)
        var running: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        var a = Self.addr(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let on = dev != 0 && AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &running) == noErr && running != 0
        if on != micInUse { micInUse = on }
    }

    func refresh() {
        devices = Self.devices(Self.out)
        currentDevice = Self.defaultDevice(input: false)
        if let v = Self.getVolume(currentDevice, Self.out) { volume = Double(v) }
        muted = Self.getMute(currentDevice, Self.out)
        inputs = Self.devices(Self.inp)
        currentInput = Self.defaultDevice(input: true)
        let iv = Self.getVolume(currentInput, Self.inp)
        inputAdjustable = iv != nil
        if let iv { inputVolume = Double(iv) }
        inputMuted = Self.getMute(currentInput, Self.inp)
    }

    func setVolume(_ v: Double) {
        volume = v
        Self.setVolume(currentDevice, Self.out, v)
        if muted && v > 0 { toggleMute() }
    }

    func setInputVolume(_ v: Double) {
        inputVolume = v
        Self.setVolume(currentInput, Self.inp, v)
    }

    func toggleMute() {
        Self.setMute(currentDevice, Self.out, !muted)
        muted = Self.getMute(currentDevice, Self.out)
    }

    func toggleInputMute() {
        Self.setMute(currentInput, Self.inp, !inputMuted)
        inputMuted = Self.getMute(currentInput, Self.inp)
    }

    func select(_ d: OutputDevice) { Self.setDefault(d.id, input: false); refresh() }
    func selectInput(_ d: OutputDevice) { Self.setDefault(d.id, input: true); refresh() }

    private static func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultDevice(input: Bool) -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = addr(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    private static func setDefault(_ dev: AudioDeviceID, input: Bool) {
        var id = dev
        var a = addr(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    private static func getVolume(_ dev: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Float32? {
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope)
        if AudioObjectHasProperty(dev, &a), AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr { return v }
        // Many mics only expose a per-channel volume.
        for el: UInt32 in [0, 1] {
            var c = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: el)
            if AudioObjectHasProperty(dev, &c), AudioObjectGetPropertyData(dev, &c, 0, nil, &size, &v) == noErr { return v }
        }
        return nil
    }

    private static func setVolume(_ dev: AudioDeviceID, _ scope: AudioObjectPropertyScope, _ v: Double) {
        var value = Float32(v)
        let size = UInt32(MemoryLayout<Float32>.size)
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope)
        if AudioObjectHasProperty(dev, &a), AudioObjectSetPropertyData(dev, &a, 0, nil, size, &value) == noErr { return }
        for el: UInt32 in [0, 1, 2] {
            var c = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: el)
            if AudioObjectHasProperty(dev, &c) { AudioObjectSetPropertyData(dev, &c, 0, nil, size, &value) }
        }
    }

    private static func getMute(_ dev: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var v = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var a = addr(kAudioDevicePropertyMute, scope)
        AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v)
        return v != 0
    }

    private static func setMute(_ dev: AudioDeviceID, _ scope: AudioObjectPropertyScope, _ on: Bool) {
        var value: UInt32 = on ? 1 : 0
        var a = addr(kAudioDevicePropertyMute, scope)
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private static func devices(_ scope: AudioObjectPropertyScope) -> [OutputDevice] {
        var a = addr(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
        return ids.compactMap { id in
            var sAddr = addr(kAudioDevicePropertyStreams, scope)
            var sSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &sAddr, 0, nil, &sSize)
            guard sSize > 0 else { return nil }
            var nAddr = addr(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(id, &nAddr, 0, nil, &nSize, &name)
            let n = (name?.takeRetainedValue() as String?) ?? "Device \(id)"
            // Hide the hidden aggregate devices apps create (e.g. Zoom, Teams).
            if n.hasPrefix("CADefaultDeviceAggregate") { return nil }
            return OutputDevice(id: id, name: n)
        }
    }
}

// MARK: - Now playing

final class NowPlayingModel: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var app = ""
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var artwork: NSImage?
    var onTrackChange: ((String, String) -> Void)?
    private var artURL = ""

    init() {
        // Move the progress bar smoothly between the 3-second refreshes.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if playing, duration > 0 { position = min(duration, position + 1) }
            for i in others.indices where others[i].playing && others[i].duration > 0 {
                others[i].position = min(others[i].duration, others[i].position + 1)
            }
        }
    }

    var appIcon: NSImage? {
        guard app == "Spotify" || app == "Music", let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app == "Spotify" ? "com.spotify.client" : "com.apple.Music") else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    @Published var seekBlocked = false     // Chrome refused the jump (JavaScript from Apple Events is off in that profile)
    @Published var jsHint = false          // true when Chrome/Safari refused to share the artist
    private var busy = false
    private var lastBrowserTitle = ""
    private let browserQueue = DispatchQueue(label: "melcolm.browser-media")

    /// What's playing: Spotify / Music first (they report everything), then any browser tab or
    /// web app (Chrome, Safari, Brave, Edge, Arc) such as YouTube Music.
    func refresh() {
        if refreshScripts() {
            var l = BrowserMedia.scan(); for i in l.indices { fillFromVideo(&l[i]); applyAX(&l[i]) }
            others = l.sorted { $0.id < $1.id }; probeAX(l); return
        }
        // AppleScript has to run on the main thread; the scan is a few milliseconds.
        var list = BrowserMedia.scan()
        for i in list.indices { fillFromVideo(&list[i]); applyAX(&list[i]) }
        probeAX(list)
        for i in list.indices where !list[i].knownState || held(list[i].id) { if let f = forced[list[i].id] { list[i].playing = f } }
        let main = list.first(where: { forced[$0.id] ?? $0.playing }) ?? list.first
        mainID = main?.id ?? ""
        others = list.sorted { $0.id < $1.id }            // fixed order, so cards never swap places
        jsHint = list.contains { $0.needsJS }
        applyBrowser(main)
        jsHint = list.contains { $0.needsJS }
    }

    /// The play bar and buttons read from the page's accessibility tree (works with Chrome's
    /// JavaScript setting off, and without bringing the tab forward).
    private var ax: [String: (found: WebAX.Found, at: Date)] = [:]
    private var probing = false
    private func applyAX(_ r: inout BrowserMedia.Result) {
        if held(r.id) { r.playing = forced[r.id] ?? r.playing; return }
        guard !r.knownState, let (f, at) = ax[r.id], Date().timeIntervalSince(at) < 10 else { return }
        if let p = f.playing { r.playing = p; r.knownState = true; forced[r.id] = nil }
        if f.hasTime {
            r.duration = f.dur
            r.position = min(f.dur, f.pos + (r.playing ? Date().timeIntervalSince(at) : 0))
            r.needsJS = false
        }
    }
    private func probeAX(_ list: [BrowserMedia.Result]) {
        guard !probing, !list.isEmpty, AXIsProcessTrusted() else { return }
        probing = true
        let jobs = list.compactMap { r -> (String, pid_t, String)? in
            guard !r.knownState || r.duration == 0, let pid = BrowserMedia.pid(r) else { return nil }
            return (r.id, pid, r.pwa != 0 ? "" : r.title)
        }
        browserQueue.async { [weak self] in
            var out: [String: WebAX.Found] = [:]
            for (id, pid, title) in jobs { if let f = WebAX.find(pid: pid, title: title) { out[id] = f } }
            DispatchQueue.main.async {
                guard let self else { return }
                self.probing = false
                let now = Date()
                for (id, f) in out { self.ax[id] = (f, now) }
                for i in self.others.indices { self.applyAX(&self.others[i]) }
                if let m = self.mainResult, self.app == "Browser", let f = out[m.id] {
                    if let p = f.playing, !self.held(m.id) { self.playing = p }
                    if f.hasTime { self.position = f.pos; self.duration = f.dur }
                }
                if let m = self.mainResult, self.app == "Browser", self.duration == 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }   // not there yet: look again soon
                }
                BrowserMedia.log("ax \(out.map { "\($0.key) pos=\($0.value.pos)/\($0.value.dur) play=\(String(describing: $0.value.playing))" })")
            }
        }
    }

    /// Every other playing or paused tab / web app, shown under the main card.
    @Published var others: [BrowserMedia.Result] = []
    @Published var thumbs: [String: NSImage] = [:]
    private var videoInfo: [String: (String, String)] = [:]

    /// Title, channel and thumbnail from the YouTube video id (no browser setting needed).
    private func fillFromVideo(_ r: inout BrowserMedia.Result) {
        let id = r.videoID
        guard !id.isEmpty else { return }
        if let (t, a) = videoInfo[id] {
            if r.title.isEmpty { r.title = t }
            if BrowserMedia.isSite(r.artist) { r.artist = a }
        } else if !fetching.contains(id) {
            fetching.insert(id)
            guard let u = URL(string: "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(id)") else { return }
            URLSession.shared.dataTask(with: u) { [weak self] d, _, _ in
                let o = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let t = o?["title"] as? String ?? ""
                let a = (o?["author_name"] as? String ?? "").replacingOccurrences(of: " - Topic", with: "")
                DispatchQueue.main.async { self?.videoInfo[id] = (t, a); self?.refresh() }
            }.resume()
        }
        if r.title.isEmpty { r.title = r.artist.isEmpty ? "YouTube" : r.artist }
        if thumbs[r.artwork] == nil, !r.artwork.isEmpty, !fetching.contains(r.artwork), let u = URL(string: r.artwork) {
            let key = r.artwork; fetching.insert(key)
            URLSession.shared.dataTask(with: u) { [weak self] d, _, _ in
                guard let d, let img = NSImage(data: d) else { return }
                DispatchQueue.main.async { self?.thumbs[key] = img }
            }.resume()
        }
    }
    private var fetching = Set<String>()

    /// Remembered play state per tab when the browser won't tell us (no JavaScript access).
    private var forced: [String: Bool] = [:]
    private var mainID = ""
    var mainResult: BrowserMedia.Result? { others.first { $0.id == mainID } ?? others.first }
    func isPlaying(_ r: BrowserMedia.Result) -> Bool { r.knownState && !held(r.id) ? r.playing : (forced[r.id] ?? r.playing) }
    /// For 3 seconds after you press Play/Pause, what you pressed wins over the page (which updates late).
    private var pressedAt: [String: Date] = [:]
    func held(_ id: String) -> Bool { Date().timeIntervalSince(pressedAt[id] ?? .distantPast) < 3 }

    /// Plays or pauses exactly that tab. Others keep doing what they were doing.
    func toggle(_ r: BrowserMedia.Result) {
        let was = isPlaying(r)
        // Never bring the tab forward: only the artwork does that. Page JavaScript first, then the
        // page's own Play/Pause button (accessibility), then the keyboard's play/pause key.
        let button = ax[r.id]?.found.play
        let viaAX = WebAX.press(button)
        let viaJS = !viaAX && BrowserMedia.togglePlay(r)
        if !viaAX && !viaJS { Self.mediaKey(16) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.refresh() }
        BrowserMedia.log("toggle \(r.id) was=\(was) ax=\(viaAX) js=\(viaJS) axAge=\(ax[r.id].map { Date().timeIntervalSince($0.at) } ?? -1)")
        if let f = ax[r.id] { ax[r.id] = (f.found, .distantPast) }   // keep the button, drop its old play state
        forced[r.id] = !was
        pressedAt[r.id] = Date()
        if let i = others.firstIndex(where: { $0.id == r.id }) { others[i].playing = !was }
        if mainID == r.id { playing = !was }
        // Check the press took by looking at the very button that was pressed: if it still has the same
        // name ("play" stayed "play"), the page ignored it, so press it once more. Reading the whole page
        // again could land on another window and press a second time, which undid your press.
        if viaAX, let btn = button, let before = WebAX.label(btn) {
            let stamp = pressedAt[r.id]
            browserQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let after = WebAX.label(btn), after == before else { return }
                DispatchQueue.main.async {
                    guard let self, self.pressedAt[r.id] == stamp else { return }   // pressed again since: leave it
                    BrowserMedia.log("toggle retry \(r.id) button still '\(after)'")
                    WebAX.press(btn)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { self.refresh() }
    }

    private static func key(_ code: CGKeyCode) {
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    }
    func show(_ r: BrowserMedia.Result) { BrowserMedia.show(r); openedOutside() }

    /// Jumps to a point in the track (seconds).
    func seek(_ t: Double) {
        if app == "Spotify" || app == "Music" {
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"\(app)\" to set player position to \(t)")?.executeAndReturnError(&err)
            position = t; return
        }
        if let r = mainResult { seek(r, to: t) }
    }
    func seek(_ r: BrowserMedia.Result, to t: Double) {
        let ok = BrowserMedia.seek(r, to: t) || WebAX.seek(ax[r.id]?.found.slider, to: t)
        seekBlocked = !ok && !r.browser.isEmpty
        if ok {
            if let i = others.firstIndex(where: { $0.id == r.id }) { others[i].position = t }
            if mainID == r.id { position = t }
        }
    }
    func skip(_ r: BrowserMedia.Result, forward: Bool) {
        let b = forward ? ax[r.id]?.found.next : ax[r.id]?.found.prev
        if !BrowserMedia.skip(r, forward: forward) && !WebAX.press(b) { Self.mediaKey(forward ? 17 : 18) }
        later()
    }

    private func applyBrowser(_ found: BrowserMedia.Result?) {
        guard let found else {
            // One empty read (the browser busy right after a click) shouldn't make the card blink away.
            if app == "Browser", Date().timeIntervalSince(lastSeen) < 4 { return }
            if app == "Browser" { title = ""; artist = ""; app = ""; duration = 0; artwork = nil; artURL = ""; playing = false }
            return
        }
        lastSeen = Date()
        var m = found
        let key = m.id + "|" + m.title
        if m.duration > 0 { lengths[key] = m.duration }
        else if let d = lengths[key] { m.duration = d }   // same track as before: the bar shows at once
        let changed = m.title != title
        title = m.title; artist = m.artist; app = "Browser"; playing = m.playing
        position = m.position; duration = m.duration
        jsHint = m.needsJS
        if !m.artwork.isEmpty { loadArt(m.artwork) } else if changed { artwork = nil; artURL = "" }
        if changed { onTrackChange?(title, artist) }
    }

    private var lastSeen = Date.distantPast
    private var lengths: [String: Double] = [:]
    private var artistCache: [String: String] = [:]

    /// YouTube's public "oEmbed" info gives the channel (the artist for music) for a video id.
    private func fetchArtist(_ id: String) {
        if let a = artistCache[id] { artist = a; return }
        guard let u = URL(string: "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(id)") else { return }
        URLSession.shared.dataTask(with: u) { [weak self] d, _, _ in
            guard let d, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  var name = o["author_name"] as? String else { return }
            name = name.replacingOccurrences(of: " - Topic", with: "")
            DispatchQueue.main.async {
                guard let self else { return }
                self.artistCache[id] = name
                if self.app == "Browser" { self.artist = name }
            }
        }.resume()
    }

    /// Asks Spotify or Music directly. Returns true if one of them is the thing playing.
    @discardableResult
    private func refreshScripts() -> Bool {
        for player in ["Spotify", "Music"] {
            guard NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == player }) else { continue }
            let extra = player == "Spotify"
                ? "((duration of current track) / 1000) & \"\\n\" & (artwork url of current track)"
                : "(duration of current track) & \"\\n\""
            let src = """
            tell application "\(player)"
              if player state is stopped then return ""
              return (name of current track) & "\\n" & (artist of current track) & "\\n" & (player state as string) & "\\n" & (player position) & "\\n" & \(extra)
            end tell
            """
            var err: NSDictionary?
            if let out = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue, !out.isEmpty {
                let p = out.components(separatedBy: "\n")
                func at(_ i: Int) -> String { p.count > i ? p[i] : "" }
                let changed = at(0) != title
                title = at(0); artist = at(1); playing = at(2) == "playing"; app = player
                position = Double(at(3).replacingOccurrences(of: ",", with: ".")) ?? 0
                duration = Double(at(4).replacingOccurrences(of: ",", with: ".")) ?? 0
                loadArt(at(5))
                if changed, !title.isEmpty { onTrackChange?(title, artist) }
                return playing || BrowserMedia.audioPlayingProcess() == nil
            }
        }
        return false
    }

    private func loadArt(_ url: String) {
        guard url != artURL else { return }
        artURL = url; artwork = nil
        guard let u = URL(string: url), !url.isEmpty else { return }
        URLSession.shared.dataTask(with: u) { d, _, _ in
            guard let d, let img = NSImage(data: d) else { return }
            DispatchQueue.main.async { if self.artURL == url { self.artwork = img } }
        }.resume()
    }

    func playPause() {
        if app == "Browser", let r = mainResult { toggle(r); return }
        Self.mediaKey(16); playing.toggle(); later()
    }
    func next() { if app == "Browser", let r = mainResult { skip(r, forward: true) } else { Self.mediaKey(17); later() } }
    func previous() { if app == "Browser", let r = mainResult { skip(r, forward: false) } else { Self.mediaKey(18); later() } }
    func openApp() {
        openedOutside()
        if app == "Browser" { if let r = mainResult { BrowserMedia.show(r) } else { BrowserMedia.focusPlayingBrowser() }; return }
        if app == "Spotify" || app == "Music", let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app == "Spotify" ? "com.spotify.client" : "com.apple.Music") {
            NSWorkspace.shared.open(url)
        }
    }

    private func later() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() } }

    private static func mediaKey(_ key: Int32) {
        func post(_ down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
        post(true); post(false)
    }
}

// MARK: - Timer & stopwatch

final class TimerModel: ObservableObject {
    enum Mode: String { case timer = "Timer", stopwatch = "Stopwatch" }
    @Published var mode: Mode = .timer
    @Published var remaining: TimeInterval = 0
    @Published var elapsed: TimeInterval = 0
    @Published var running = false
    @Published var finished = false
    private var tick: Timer?
    var onFinish: (() -> Void)?
    private var lastTick = Date()

    var isActive: Bool { running || remaining > 0 || elapsed > 0 }
    var display: String { Self.format(mode == .timer ? remaining : elapsed) }

    func start(minutes: Double) {
        mode = .timer; remaining = minutes * 60; finished = false; resume()
    }

    func startStopwatch() { mode = .stopwatch; elapsed = 0; resume() }

    func resume() {
        running = true; lastTick = Date()
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.step() }
    }

    func pause() { running = false; tick?.invalidate() }
    func reset() { pause(); remaining = 0; elapsed = 0; finished = false }

    private func step() {
        let now = Date(); let dt = now.timeIntervalSince(lastTick); lastTick = now
        if mode == .stopwatch { elapsed += dt; return }
        remaining = max(0, remaining - dt)
        if remaining == 0 {
            pause(); finished = true
            NSSound(named: "Glass")?.play()
            onFinish?()
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    func openClock() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") { NSWorkspace.shared.open(url); openedOutside() }
    }
}

// MARK: - Battery, Wi-Fi, Bluetooth

final class SystemModel: ObservableObject {
    @Published var battery: Int?
    @Published var charging = false
    @Published var wifiOn = false
    @Published var wifiName: String?
    @Published var bluetoothOn = false
    @Published var awake = false
    @Published var dark = false
    @Published var brightness: Double?
    @Published var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var lowPowerBusy = false
    private var powerObserver: NSObjectProtocol?

    /// Low Power Mode on or off for the Mac. macOS asks for your password (or Touch ID) each time.
    func setLowPower(_ on: Bool) {
        if powerObserver == nil {
            powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
        lowPowerBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "do shell script \"/usr/bin/pmset -a lowpowermode \(on ? 1 : 0)\" with administrator privileges with prompt \"Melcolm wants to turn Low Power Mode \(on ? "on" : "off").\""]
            try? p.run(); p.waitUntilExit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.lowPowerBusy = false
                self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
    private var assertion: IOPMAssertionID = 0

    func refresh() {
        refreshPower()
        let wifi = CWWiFiClient.shared().interface()
        wifiOn = wifi?.powerOn() ?? false
        wifiName = wifi?.ssid()
        bluetoothOn = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
        dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        brightness = Brightness.get().map(Double.init)
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    func refreshPower() {
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
           let first = list.first,
           let d = IOPSGetPowerSourceDescription(info, first)?.takeUnretainedValue() as? [String: Any] {
            battery = d[kIOPSCurrentCapacityKey] as? Int
            let c = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            if c != charging { charging = c }
        }
    }

    func toggleBluetooth() {
        typealias SetPower = @convention(c) (Int32) -> Void
        if let h = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY),
           let f = dlsym(h, "IOBluetoothPreferenceSetControllerPowerState") {
            unsafeBitCast(f, to: SetPower.self)(bluetoothOn ? 0 : 1)
            bluetoothOn.toggle()
        } else { Self.open("com.apple.BluetoothSettings") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refresh() }
    }

    /// Keeps the screen from sleeping until turned off again.
    func toggleAwake() {
        if awake { IOPMAssertionRelease(assertion) }
        else { IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn), "Melcolm Keep Awake" as CFString, &assertion) }
        awake.toggle()
    }

    func toggleDark() {
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")?
            .executeAndReturnError(&err)
        if err == nil { dark.toggle() }
    }

    func setBrightness(_ v: Double) { brightness = v; Brightness.set(Float(v)) }

    static func screenshot() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")); openedOutside()
    }

    func toggleWifi() {
        try? CWWiFiClient.shared().interface()?.setPower(!wifiOn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url); openedOutside() }
    }
}

/// Built-in screen brightness via the private DisplayServices framework (external monitors don't support it).
enum Brightness {
    private typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (UInt32, Float) -> Int32
    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static var builtIn: UInt32? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func get() -> Float? {
        guard let lib, let f = dlsym(lib, "DisplayServicesGetBrightness"), let d = builtIn else { return nil }
        var v: Float = 0
        return unsafeBitCast(f, to: Get.self)(d, &v) == 0 ? v : nil
    }

    static func set(_ v: Float) {
        guard let lib, let f = dlsym(lib, "DisplayServicesSetBrightness"), let d = builtIn else { return }
        _ = unsafeBitCast(f, to: Set.self)(d, v)
    }
}


/// Finds what a web browser (or a web app like YouTube Music) is playing, by reading tab titles
/// and, when the browser allows it, the page's media info (artist, artwork, progress).
enum BrowserMedia {
    static var debugAX: Bool { UserDefaults.standard.bool(forKey: "debugAX") }
    struct Result { var title: String; var artist: String; var playing: Bool; var position: Double; var duration: Double; var artwork: String; var needsJS: Bool; var videoID = ""; var browser = ""; var window = 0; var tab = 0; var url = ""; var knownState = false; var generic = false; var pwa: pid_t = 0
        var id: String { "\(browser)|\(url)" } }
    static func isSite(_ s: String) -> Bool { s.isEmpty || sites.contains { $0.caseInsensitiveCompare(s) == .orderedSame } }
    static func videoID(_ url: String) -> String {
        guard url.contains("youtube.com"), let c = URLComponents(string: url), let v = c.queryItems?.first(where: { $0.name == "v" })?.value else { return "" }
        return v
    }

    private struct Browser { let name: String; let bundle: String; let safari: Bool }
    private static let browsers = [
        Browser(name: "Google Chrome", bundle: "com.google.Chrome", safari: false),
        Browser(name: "Brave Browser", bundle: "com.brave.Browser", safari: false),
        Browser(name: "Microsoft Edge", bundle: "com.microsoft.edgemac", safari: false),
        Browser(name: "Arc", bundle: "company.thebrowser.Browser", safari: false),
        Browser(name: "Chromium", bundle: "org.chromium.Chromium", safari: false),
        Browser(name: "Safari", bundle: "com.apple.Safari", safari: true),
    ]
    private static let sites = ["YouTube Music", "YouTube", "Spotify", "SoundCloud", "Apple Music", "TIDAL", "Deezer", "Bandcamp", "Pandora", "Twitch", "Vimeo", "Amazon Music"]
    private static let mediaHosts = ["youtube.com", "spotify.com", "soundcloud.com", "music.apple.com", "tidal.com", "deezer.com", "bandcamp.com", "pandora.com", "twitch.tv", "vimeo.com", "music.amazon"]

    /// Chrome / Edge / Brave "installed apps" (like the YouTube Music app) are their own little apps.
    static func isAppShell(_ bundle: String) -> Bool {
        bundle.hasPrefix("com.google.Chrome.app.") || bundle.hasPrefix("com.microsoft.edgemac.app.") || bundle.hasPrefix("com.brave.Browser.app.")
    }

    /// On-screen rectangles of those app windows, so a browser window can be matched to its app.
    static func appWindows() -> [(pid: pid_t, rect: CGRect)] {
        let pids = Set(NSWorkspace.shared.runningApplications.filter { isAppShell($0.bundleIdentifier ?? "") }.map(\.processIdentifier))
        guard !pids.isEmpty, let arr = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let pid = d[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (d[kCGWindowLayer as String] as? Int) == 0, let bd = d[kCGWindowBounds as String],
                  let r = CGRect(dictionaryRepresentation: bd as! CFDictionary), r.width > 100 else { return nil }
            return (pid, r)
        }
    }

    private static var lastAudible = Date.distantPast
    /// "Is sound playing" with a few seconds of memory, so a brief gap doesn't flip every card.
    static func audibleNow() -> Bool {
        if audioPlayingProcess() != nil { lastAudible = Date() }
        return Date().timeIntervalSince(lastAudible) < 4
    }

    /// pid of a process holding a "Playing audio" power assertion (what Chrome/Safari do while sound plays).
    static func audioPlayingProcess() -> pid_t? {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess, let d = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return nil }
        let ids = Set(browsers.map(\.bundle))
        for (pid, list) in d where list.contains(where: { ($0["AssertName"] as? String) == "Playing audio" }) {
            if let b = NSRunningApplication(processIdentifier: pid_t(truncating: pid))?.bundleIdentifier,
               ids.contains(b) || isAppShell(b) { return pid_t(truncating: pid) }
        }
        return nil
    }

    static func focusPlayingBrowser() {
        if let pid = audioPlayingProcess() { NSRunningApplication(processIdentifier: pid)?.activate() }
    }

    static func log(_ m: String) {
        guard UserDefaults.standard.bool(forKey: "debugLog") else { return }
        let line = "\(Date()) \(m)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/melcolm-np.log") { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() } else { try? line.write(toFile: "/tmp/melcolm-np.log", atomically: true, encoding: .utf8) }
    }

    /// Every media tab or web-app window (e.g. the YouTube Music Chrome app), playing ones first.
    static func scan() -> [Result] {
        let audible = audibleNow()
        let appWins = appWindows()
        var all: [(Result, Int)] = []
        var needsJS = false
        for b in browsers {
            guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == b.bundle }) else { continue }
            let nameExpr = b.safari ? "name of t" : "title of t"
            let src = """
            set out to ""
            set sep to (ASCII character 9)
            tell application "\(b.name)"
              set wi to 0
              repeat with w in windows
                set wi to wi + 1
                set ti to 0
                set bb to bounds of w
                set bs to ((item 1 of bb) as text) & "," & ((item 2 of bb) as text) & "," & ((item 3 of bb) as text) & "," & ((item 4 of bb) as text)
                repeat with t in tabs of w
                  set ti to ti + 1
                  set out to out & wi & sep & ti & sep & (\(nameExpr)) & sep & (URL of t) & sep & bs & linefeed
                end repeat
              end repeat
            end tell
            return out
            """
            var err: NSDictionary?
            let res = NSAppleScript(source: src)?.executeAndReturnError(&err)
            log("\(b.name) audible=\(audible) err=\(String(describing: err)) text=\(String(describing: res?.stringValue?.prefix(400)))")
            guard let text = res?.stringValue else { continue }
            for line in text.split(separator: "\n") {
                let f = line.components(separatedBy: "\t")
                guard f.count >= 4, let wi = Int(f[0]), let ti = Int(f[1]) else { continue }
                let url = f[3]
                guard mediaHosts.contains(where: { url.contains($0) }) else { continue }
                // YouTube Studio and other dashboards are not players.
                guard !url.contains("studio.youtube.com"), !url.contains("accounts.") else { continue }
                var (title, site) = clean(f[2]); var generic = false
                let vid = videoID(url)
                // YouTube Music often titles the page just "YouTube Music"; the video id still says what it is.
                if sites.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) {
                    guard !vid.isEmpty else { continue }
                    site = title; title = ""; generic = true
                }
                guard !title.isEmpty || !vid.isEmpty else { continue }
                var r = Result(title: title, artist: site, playing: false, position: 0, duration: 0, artwork: "", needsJS: false)
                r.videoID = vid; r.generic = generic; r.browser = b.name; r.window = wi; r.tab = ti; r.url = url
                if f.count >= 5 {
                    let n = f[4].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    if n.count == 4 {
                        let rect = CGRect(x: n[0], y: n[1], width: n[2] - n[0], height: n[3] - n[1])
                        if let hit = appWins.first(where: { abs($0.rect.minX - rect.minX) < 4 && abs($0.rect.minY - rect.minY) < 4 && abs($0.rect.width - rect.width) < 4 }) { r.pwa = hit.pid }
                    }
                }
                // The installed app (e.g. YouTube Music) keeps the plain page title; find it by name.
                if r.pwa == 0, generic, !b.safari,
                   let shell = NSWorkspace.shared.runningApplications.first(where: { isAppShell($0.bundleIdentifier ?? "") && $0.localizedName?.caseInsensitiveCompare(site) == .orderedSame }) {
                    r.pwa = shell.processIdentifier
                }
                if !vid.isEmpty { r.artwork = "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg" }
                if let js = mediaInfo(b, wi, ti) {
                    if !js.title.isEmpty { r.title = js.title }
                    if !js.artist.isEmpty { r.artist = js.artist }
                    if !js.art.isEmpty { r.artwork = js.art }
                    r.position = js.pos; r.duration = js.dur; r.playing = js.playing; r.knownState = true
                } else { needsJS = true }
                let score = (r.playing ? 8 : 0) + (r.generic ? 0 : 4) + (url.contains("watch") || url.contains("/track") || url.contains("/album") ? 2 : 0) + (b.safari ? 0 : 1)
                all.append((r, score))
            }
        }
        var list = all.sorted { $0.1 > $1.1 }.map(\.0)
        log("results \(list.map { "\($0.title)|pwa=\($0.pwa)|play=\($0.playing)" }) appWins=\(appWins.map { "\($0.pid):\($0.rect)" })")
        // Without page access we only know that *something* in the browser is making sound.
        // YouTube Music only puts the song in the page title while it plays.
        if audible, !list.contains(where: \.playing), !list.isEmpty, !list[0].generic || list.count == 1 { list[0].playing = true }
        for i in list.indices { list[i].needsJS = needsJS && !list[i].knownState }
        return list
    }

    /// Plays or pauses one particular tab (needs the browser's JavaScript-from-Apple-Events setting).
    static func togglePlay(_ r: Result) -> Bool {
        // Press the site's own Play/Pause button first (YouTube Music and YouTube re-pause the video
        // a second later if only the <video> is played, because their player still thinks it's paused).
        let js = "(function(){var b=document.querySelector('ytmusic-player-bar #play-pause-button,.ytp-play-button,[data-testid=control-button-playpause]');if(b){b.click();return 'ok'}var v=document.querySelector('video,audio');if(!v)return 'no';if(v.paused){v.play()}else{v.pause()}return 'ok'})()"
        let src = r.browser == "Safari"
            ? "tell application \"Safari\" to do JavaScript \"\(js)\" in tab \(r.tab) of window \(r.window)"
            : "tell application \"\(r.browser)\" to tell tab \(r.tab) of window \(r.window) to execute javascript \"\(js)\""
        var err: NSDictionary?
        return NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue == "ok"
    }

    static func seek(_ r: Result, to t: Double) -> Bool {
        let js = "(function(){var v=document.querySelector('video,audio');if(!v)return 'no';v.currentTime=\(t);return 'ok'})()"
        let src = r.browser == "Safari"
            ? "tell application \"Safari\" to do JavaScript \"\(js)\" in tab \(r.tab) of window \(r.window)"
            : "tell application \"\(r.browser)\" to tell tab \(r.tab) of window \(r.window) to execute javascript \"\(js)\""
        var err: NSDictionary?
        let out = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue
        log("js seek \(r.browser) w\(r.window) t\(r.tab) pwa=\(r.pwa) → \(out ?? "nil") \(err?["NSAppleScriptErrorMessage"] ?? "")")
        return out == "ok"
    }

    /// Next / previous track inside one tab (YouTube Music and YouTube buttons).
    static func skip(_ r: Result, forward: Bool) -> Bool {
        let sel = forward ? ".next-button,.ytp-next-button" : ".previous-button,.ytp-prev-button"
        let js = "(function(){var b=document.querySelector('\(sel)');if(!b)return 'no';b.click();return 'ok'})()"
        let src = r.browser == "Safari"
            ? "tell application \"Safari\" to do JavaScript \"\(js)\" in tab \(r.tab) of window \(r.window)"
            : "tell application \"\(r.browser)\" to tell tab \(r.tab) of window \(r.window) to execute javascript \"\(js)\""
        var err: NSDictionary?
        return NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue == "ok"
    }

    /// The process that owns that tab: the installed web app, or the browser itself.
    static func pid(_ r: Result) -> pid_t? {
        if r.pwa != 0 { return r.pwa }
        guard let b = browsers.first(where: { $0.name == r.browser }), !b.safari else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == b.bundle }?.processIdentifier
    }

    /// Brings that tab (or web-app window) to the front.
    static func show(_ r: Result) {
        if r.pwa != 0, let a = NSRunningApplication(processIdentifier: r.pwa) {
            if let u = a.bundleURL { NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration()) }
            a.activate(options: [.activateAllWindows])
            return
        }
        let src = r.browser == "Safari"
            ? "tell application \"Safari\"\n set current tab of window \(r.window) to tab \(r.tab) of window \(r.window)\n set index of window \(r.window) to 1\n activate\n end tell"
            : "tell application \"\(r.browser)\"\n set active tab index of window \(r.window) to \(r.tab)\n set index of window \(r.window) to 1\n activate\n end tell"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
    }

    private static func clean(_ raw: String) -> (String, String) {
        var t = raw.trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)
        for s in sites {
            for sep in [" | ", " - ", " – ", " · ", " • "] where t.lowercased().hasSuffix((sep + s).lowercased()) {
                return (String(t.dropLast((sep + s).count)), s)
            }
        }
        return (t, "")
    }

    private struct Info { var title: String; var artist: String; var art: String; var playing: Bool; var pos: Double; var dur: Double }

    /// The page's own media info. Needs "Allow JavaScript from Apple Events" turned on in the browser.
    private static func mediaInfo(_ b: Browser, _ w: Int, _ t: Int) -> Info? {
        let js = "(function(){var m=navigator.mediaSession&&navigator.mediaSession.metadata;var v=document.querySelector('video,audio');var a='';if(m&&m.artwork&&m.artwork.length){a=m.artwork[m.artwork.length-1].src}return JSON.stringify({t:m?m.title:'',a:m?m.artist:'',art:a,p:v?!v.paused:false,pos:v?v.currentTime:0,dur:v&&isFinite(v.duration)?v.duration:0})})()"
        let src = b.safari
            ? "tell application \"Safari\" to do JavaScript \"\(js)\" in tab \(t) of window \(w)"
            : "tell application \"\(b.name)\" to tell tab \(t) of window \(w) to execute javascript \"\(js)\""
        var err: NSDictionary?
        guard let out = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue,
              let d = out.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return Info(title: o["t"] as? String ?? "", artist: o["a"] as? String ?? "", art: o["art"] as? String ?? "",
                    playing: o["p"] as? Bool ?? false, pos: (o["pos"] as? NSNumber)?.doubleValue ?? 0, dur: (o["dur"] as? NSNumber)?.doubleValue ?? 0)
    }
}
