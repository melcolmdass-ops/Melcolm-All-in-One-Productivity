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

    func refresh() {
        devices = Self.outputDevices()
        currentDevice = Self.defaultOutput()
        if let v = Self.getVolume(currentDevice) { volume = Double(v) }
        muted = Self.getMute(currentDevice)
    }

    func setVolume(_ v: Double) {
        volume = v
        var value = Float32(v)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                              mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(currentDevice, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if muted && v > 0 { toggleMute() }
    }

    func toggleMute() {
        var value: UInt32 = muted ? 0 : 1
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(currentDevice, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        muted = Self.getMute(currentDevice)
    }

    func select(_ d: OutputDevice) {
        var id = d.id
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        refresh()
    }

    private static func defaultOutput() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func getVolume(_ dev: AudioDeviceID) -> Float32? {
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                              mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func getMute(_ dev: AudioDeviceID) -> Bool {
        var v = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v)
        return v != 0
    }

    private static func outputDevices() -> [OutputDevice] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids.compactMap { id in
            var sAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                   mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var sSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &sAddr, 0, nil, &sSize)
            guard sSize > 0 else { return nil }
            var nAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var nSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(id, &nAddr, 0, nil, &nSize, &name)
            return OutputDevice(id: id, name: (name?.takeRetainedValue() as String?) ?? "Device \(id)")
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
