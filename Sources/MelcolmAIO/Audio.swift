import SwiftUI
import AppKit
import CoreAudio

/// Listens to the Mac's sound output (a "tap" on system audio) and turns it into five bar
/// heights that jump with the music: bass on the left, treble on the right.
final class AudioLevels: ObservableObject {
    @Published var bars: [CGFloat] = Array(repeating: 0.1, count: 5)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "melcolm.levels", qos: .userInteractive)
    private var running = false
    // One-pole filter state for bass / mid / treble.
    private var lp1: Float = 0, lp2: Float = 0
    private var env: [Float] = [0, 0, 0]
    private var peak: Float = 0.05
    private var lastPublish = Date.distantPast
    private var fallback: Timer?

    func start() {
        guard !running else { return }
        running = true
        if #available(macOS 14.2, *), startTap() { return }
        // No permission or older macOS: bounce gently instead of showing nothing.
        fallback = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.bars = (0 ..< 5).map { _ in CGFloat.random(in: 0.2 ... 0.9) }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        fallback?.invalidate(); fallback = nil
        if let p = procID { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p); procID = nil }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = AudioObjectID(kAudioObjectUnknown) }
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
        bars = Array(repeating: 0.1, count: 5)
    }

    @available(macOS 14.2, *)
    private func startTap() -> Bool {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { return false }

        var outID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &outID)
        var uidRef: Unmanaged<CFString>?
        var usize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var ua = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(outID, &ua, 0, nil, &usize, &uidRef)
        guard let outUID = uidRef?.takeRetainedValue() as String? else { return false }

        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Melcolm Levels",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID) == noErr else { return false }
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue) { [weak self] _, inData, _, _, _ in
            self?.process(inData)
        }
        guard status == noErr, AudioDeviceStart(aggID, procID) == noErr else { return false }
        return true
    }

    private func process(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        var e: [Float] = [0, 0, 0]
        var n = 0
        for b in buffers {
            guard let raw = b.mData else { continue }
            let count = Int(b.mDataByteSize) / MemoryLayout<Float>.size
            let p = raw.assumingMemoryBound(to: Float.self)
            let ch = max(1, Int(b.mNumberChannels))
            var i = 0
            while i < count {
                let x = p[i]
                lp1 += 0.03 * (x - lp1)        // ~200 Hz: bass
                lp2 += 0.35 * (x - lp2)        // ~3 kHz
                let bass = lp1, mid = lp2 - lp1, high = x - lp2
                e[0] += bass * bass; e[1] += mid * mid; e[2] += high * high
                n += 1; i += ch
            }
        }
        guard n > 0 else { return }
        for k in 0 ..< 3 {
            let level = sqrt(e[k] / Float(n))
            // Fast attack, slower release: bars jump on the beat and fall back.
            env[k] = level > env[k] ? level : env[k] * 0.82 + level * 0.18
        }
        let loudest = max(env[0], env[1], env[2])
        peak = max(loudest, peak * 0.995)             // auto-gain so quiet and loud songs both fill the bars
        guard Date().timeIntervalSince(lastPublish) > 0.033 else { return }
        lastPublish = Date()
        func norm(_ v: Float) -> CGFloat { CGFloat(min(1, max(0.08, (v / max(peak, 0.02)) * 0.95))) }
        let b = norm(env[0]), m = norm(env[1]), h = norm(env[2])
        let out: [CGFloat] = [b, (b + m) / 2, m, (m + h) / 2, h]
        DispatchQueue.main.async { [weak self] in self?.bars = out }
    }
}

/// Five bars that move with the music.
struct BeatWave: View {
    @EnvironmentObject var levels: AudioLevels
    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0 ..< 5, id: \.self) { i in
                Capsule().fill(accent).frame(width: 2.5, height: 3 + levels.bars[i] * 15)
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: 0.06), value: levels.bars)
    }
}
