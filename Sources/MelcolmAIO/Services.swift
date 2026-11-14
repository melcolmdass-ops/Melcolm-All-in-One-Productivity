import AppKit
import CoreAudio
import CoreWLAN
import IOBluetooth
import IOKit.ps

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

    /// Reads Spotify or Music (the two apps that expose their track to scripts).
    /// Controls use the system media keys, so they also drive YouTube in a browser.
    func refresh() {
        for player in ["Spotify", "Music"] {
            guard NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == player }) else { continue }
            let src = """
            tell application "\(player)"
              if player state is stopped then return ""
              return (name of current track) & "\\n" & (artist of current track) & "\\n" & (player state as string)
            end tell
            """
            var err: NSDictionary?
            if let out = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue, !out.isEmpty {
                let parts = out.components(separatedBy: "\n")
                title = parts[0]
                artist = parts.count > 1 ? parts[1] : ""
                playing = parts.count > 2 && parts[2] == "playing"
                app = player
                return
            }
        }
        if app.isEmpty == false { title = ""; artist = ""; app = "" }
    }

    func playPause() { Self.mediaKey(16); playing.toggle(); later() }
    func next() { Self.mediaKey(17); later() }
    func previous() { Self.mediaKey(18); later() }
    func openApp() {
        if !app.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app == "Spotify" ? "com.spotify.client" : "com.apple.Music") {
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
    }

    func toggleWifi() {
        try? CWWiFiClient.shared().interface()?.setPower(!wifiOn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }
}
