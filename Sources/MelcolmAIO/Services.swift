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
            guard let self, playing, duration > 0 else { return }
            position = min(duration, position + 1)
        }
    }

    var appIcon: NSImage? {
        guard app == "Spotify" || app == "Music", let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app == "Spotify" ? "com.spotify.client" : "com.apple.Music") else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    @Published var jsHint = false          // true when Chrome/Safari refused to share the artist
    private var busy = false
    private var lastBrowserTitle = ""
    private let browserQueue = DispatchQueue(label: "melcolm.browser-media")

    /// What's playing: Spotify / Music first (they report everything), then any browser tab or
    /// web app (Chrome, Safari, Brave, Edge, Arc) such as YouTube Music.
    func refresh() {
        if refreshScripts() { return }
        // AppleScript has to run on the main thread; the scan is a few milliseconds.
        applyBrowser(BrowserMedia.scan())
    }

    private func applyBrowser(_ m: BrowserMedia.Result?) {
        guard let m else {
            if app == "Browser" { title = ""; artist = ""; app = ""; duration = 0; artwork = nil; artURL = ""; playing = false }
            return
        }
        let changed = m.title != title
        title = m.title; artist = m.artist; app = "Browser"; playing = m.playing
        position = m.position; duration = m.duration
        jsHint = m.needsJS
        if BrowserMedia.isSite(m.artist), !m.videoID.isEmpty { fetchArtist(m.videoID) }
        if !m.artwork.isEmpty { loadArt(m.artwork) } else if changed { artwork = nil; artURL = "" }
        if changed { onTrackChange?(title, artist) }
    }

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

    func playPause() { Self.mediaKey(16); playing.toggle(); later() }
    func next() { Self.mediaKey(17); later() }
    func previous() { Self.mediaKey(18); later() }
    func openApp() {
        if app == "Browser" { BrowserMedia.focusPlayingBrowser(); return }
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
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") { NSWorkspace.shared.open(url) }
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
    private var assertion: IOPMAssertionID = 0

    func refresh() {
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
           let first = list.first,
           let d = IOPSGetPowerSourceDescription(info, first)?.takeUnretainedValue() as? [String: Any] {
            battery = d[kIOPSCurrentCapacityKey] as? Int
            charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
        }
        let wifi = CWWiFiClient.shared().interface()
        wifiOn = wifi?.powerOn() ?? false
        wifiName = wifi?.ssid()
        bluetoothOn = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
        dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        brightness = Brightness.get().map(Double.init)
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
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
    }

    func toggleWifi() {
        try? CWWiFiClient.shared().interface()?.setPower(!wifiOn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
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
    struct Result { var title: String; var artist: String; var playing: Bool; var position: Double; var duration: Double; var artwork: String; var needsJS: Bool; var videoID = "" }
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

    /// pid of a process holding a "Playing audio" power assertion (what Chrome/Safari do while sound plays).
    static func audioPlayingProcess() -> pid_t? {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess, let d = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return nil }
        let ids = Set(browsers.map(\.bundle))
        for (pid, list) in d where list.contains(where: { ($0["AssertName"] as? String) == "Playing audio" }) {
            if let b = NSRunningApplication(processIdentifier: pid_t(truncating: pid))?.bundleIdentifier, ids.contains(b) { return pid_t(truncating: pid) }
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

    static func scan() -> Result? {
        let audible = audioPlayingProcess() != nil
        log("scan audible=\(audible) running=\(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter { $0.contains("chrome") || $0.contains("Chrome") })")
        var best: (Result, score: Int)?
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
                repeat with t in tabs of w
                  set ti to ti + 1
                  set out to out & wi & sep & ti & sep & (\(nameExpr)) & sep & (URL of t) & linefeed
                end repeat
              end repeat
            end tell
            return out
            """
            var err: NSDictionary?
            let res = NSAppleScript(source: src)?.executeAndReturnError(&err)
            if UserDefaults.standard.bool(forKey: "debugLog") {
                let line = "\(Date()) \(b.name) audible=\(audible) err=\(String(describing: err)) text=\(String(describing: res?.stringValue?.prefix(300)))\n"
                if let h = FileHandle(forWritingAtPath: "/tmp/melcolm-np.log") { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() } else { try? line.write(toFile: "/tmp/melcolm-np.log", atomically: true, encoding: .utf8) }
            }
            guard let text = res?.stringValue else { continue }
            for line in text.split(separator: "\n") {
                let f = line.components(separatedBy: "\t")
                guard f.count >= 4, let wi = Int(f[0]), let ti = Int(f[1]) else { continue }
                let url = f[3]
                guard mediaHosts.contains(where: { url.contains($0) }) else { continue }
                let (title, site) = clean(f[2])
                guard !title.isEmpty, !sites.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) else { continue }
                // Prefer actual watch/track pages over home pages.
                let score = (url.contains("watch") || url.contains("/track") || url.contains("/album") ? 2 : 0) + (b.safari ? 0 : 1)
                if best == nil || score > best!.score {
                    var r = Result(title: title, artist: site, playing: audible, position: 0, duration: 0, artwork: "", needsJS: false)
                    r.videoID = videoID(url)
                    // YouTube / YouTube Music: the video's own thumbnail works as cover art (centre-cropped).
                    if !r.videoID.isEmpty { r.artwork = "https://i.ytimg.com/vi/\(r.videoID)/hqdefault.jpg" }
                    if let js = mediaInfo(b, wi, ti) {
                        if !js.title.isEmpty { r.title = js.title }
                        if !js.artist.isEmpty { r.artist = js.artist }
                        if !js.art.isEmpty { r.artwork = js.art }
                        r.position = js.pos; r.duration = js.dur
                        if audible == false { r.playing = js.playing }
                    } else { needsJS = true }
                    best = (r, score)
                }
            }
        }
        if var r = best?.0 { r.needsJS = needsJS && r.videoID.isEmpty && r.artwork.isEmpty; return r }
        return nil
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
