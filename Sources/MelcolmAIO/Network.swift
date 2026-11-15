import AppKit
import CoreLocation
import CoreWLAN
import IOBluetooth
import SwiftUI

/// Wi-Fi networks in range and paired Bluetooth devices, like the Control Center menus.
final class NetworkModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Net: Identifiable, Equatable {
        let ssid: String; let bars: Int; let secure: Bool; let known: Bool; let hotspot: Bool
        var id: String { ssid }
    }
    struct Device: Identifiable, Equatable {
        let address: String; let name: String; let connected: Bool; let icon: String
        var id: String { address }
    }

    @Published var nets: [Net] = []
    @Published var scanning = false
    @Published var joining: String?
    @Published var askPassword: String?      // SSID waiting for a password
    @Published var password = ""
    @Published var error: String?
    @Published var showOther = false
    @Published var openWifi = false      // the lists, in the small pop-up
    @Published var openBT = false
    @Published var tab = 0              // pop-up: 0 Wi-Fi, 1 Bluetooth
    @Published var devices: [Device] = []
    @Published var busy: Set<String> = []

    private var raw: [String: CWNetwork] = [:]
    private let location = CLLocationManager()
    private var known: [String] = []

    override init() {
        super.init()
        location.delegate = self
    }

    /// macOS only names Wi-Fi networks for apps allowed to use Location.
    func askLocation() {
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
    }
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) { scan() }

    var iface: CWInterface? { CWWiFiClient.shared().interface() }

    func scan() {
        askLocation()
        guard !scanning, let i = iface, i.powerOn() else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = (try? i.scanForNetworks(withName: nil)) ?? []
            let known = Self.preferred(i.interfaceName ?? "en0")
            DispatchQueue.main.async { self.apply(found, known) }
        }
    }

    private func apply(_ found: Set<CWNetwork>, _ known: [String]) {
        self.known = known
        var best: [String: CWNetwork] = [:]
        for n in found {
            guard let s = n.ssid, !s.isEmpty else { continue }
            if let b = best[s], b.rssiValue >= n.rssiValue { continue }
            best[s] = n
        }
        raw = best
        let current = iface?.ssid()
        let list = best.values.map { n -> Net in
            let s = n.ssid ?? ""
            let r = n.rssiValue
            let bars = r > -60 ? 3 : r > -72 ? 2 : 1
            let low = s.lowercased()
            let hot = ["iphone", "ipad", "hotspot", "pixel", "galaxy", "android"].contains { low.contains($0) }
            return Net(ssid: s, bars: bars, secure: !n.supportsSecurity(.none), known: known.contains(s) || s == current, hotspot: hot)
        }
        nets = list.sorted { ($0.bars, $1.ssid) > ($1.bars, $0.ssid) }
        scanning = false
    }

    static func preferred(_ name: String) -> [String] {
        let p = Process(); let out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = ["-listpreferredwirelessnetworks", name]
        p.standardOutput = out; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.split(separator: "\n").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Known and open networks join straight away; a new locked one asks for its password first.
    func join(_ n: Net) {
        error = nil
        if n.secure && !n.known && askPassword != n.ssid { askPassword = n.ssid; password = ""; return }
        connect(n.ssid, password: n.known ? nil : (n.secure ? password : nil))
    }

    func submitPassword() { if let s = askPassword { connect(s, password: password) } }

    private func connect(_ ssid: String, password: String?) {
        guard let i = iface else { return }
        joining = ssid
        let net = raw[ssid]
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = false
            if let net, password != nil || !(self.nets.first { $0.ssid == ssid }?.known ?? false) {
                ok = (try? i.associate(to: net, password: password)) != nil
            } else {
                // Known network: networksetup uses the password saved in the keychain.
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                p.arguments = ["-setairportnetwork", i.interfaceName ?? "en0", ssid]
                let out = Pipe(); p.standardOutput = out; p.standardError = out
                try? p.run(); p.waitUntilExit()
                let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                ok = p.terminationStatus == 0 && !text.lowercased().contains("error") && !text.lowercased().contains("could not")
            }
            DispatchQueue.main.async {
                self.joining = nil
                if ok { self.askPassword = nil; self.password = "" }
                else { self.error = "Couldn't join \(ssid)." }
                self.scan()
            }
        }
    }

    func disconnect() { iface?.disassociate(); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.scan() } }

    // MARK: Bluetooth

    func refreshDevices() {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let list = paired.map { d in
            Device(address: d.addressString ?? d.name ?? "?", name: d.name ?? "Device", connected: d.isConnected(), icon: Self.icon(d))
        }
        let sorted = list.sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
        if sorted != devices { devices = sorted }
    }

    func toggle(_ dev: Device) {
        guard let d = IOBluetoothDevice(addressString: dev.address) else { return }
        busy.insert(dev.address)
        DispatchQueue.global(qos: .userInitiated).async {
            if d.isConnected() { d.closeConnection() } else { d.openConnection() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.busy.remove(dev.address); self.refreshDevices()
            }
        }
    }

    static func icon(_ d: IOBluetoothDevice) -> String {
        let n = (d.name ?? "").lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") || n.contains("headphone") || n.contains("buds") { return "headphones" }
        if n.contains("keyboard") { return "keyboard" }
        if n.contains("mouse") { return "magicmouse" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if n.contains("iphone") { return "iphone" }
        if n.contains("ipad") { return "ipad" }
        if n.contains("watch") { return "applewatch" }
        if n.contains("speaker") || n.contains("homepod") { return "hifispeaker" }
        switch d.deviceClassMajor {
        case 0x04: return "headphones"
        case 0x05: return "keyboard"
        case 0x02: return "iphone"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - Views

/// "Choose a network ›" in the small pop-up: opens the full list right there.
/// "Show all 14" / "Show less" under a list. No animation, so the pop-up resizes in one go.
func expand(_ open: Bool, count: Int, _ toggle: @escaping () -> Void) -> some View {
    Button(action: toggle) {
        HStack {
            Text(open ? "Show less" : "Show all \(count)").font(.system(size: 12, weight: .semibold))
            Spacer()
            Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 12).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
        .contentShape(Rectangle())
    }.buttonStyle(PressStyle())
}

func more(_ title: String, open: Binding<Bool>) -> some View {
    Button { withAnimation(.easeOut(duration: 0.2)) { open.wrappedValue.toggle() } } label: {
        HStack {
            Image(systemName: "list.bullet").font(.system(size: 11, weight: .semibold))
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
        }
        .foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 12).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
        .contentShape(Rectangle())
    }.buttonStyle(PressStyle())
}

/// A round icon that fills with the accent colour when that thing is on or connected.
struct NetIcon: View {
    let name: String; let on: Bool
    var body: some View {
        Image(systemName: name).font(.system(size: 12, weight: .semibold))
            .foregroundStyle(on ? .white : .white.opacity(0.85))
            .frame(width: 26, height: 26)
            .background(Circle().fill(on ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.12))))
    }
}

struct NetRow<Trailing: View>: View {
    let icon: String; let on: Bool; let title: String; var subtitle: String? = nil
    let action: () -> Void
    @ViewBuilder var trailing: Trailing
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                NetIcon(name: icon, on: on)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: on ? .semibold : .regular)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                trailing
            }
            .padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Wi-Fi and Bluetooth. In the small pop-up only one shows at a time (tabs on top), so it always fits the screen.
struct NetworkPage: View {
    @EnvironmentObject var net: NetworkModel
    @Environment(\.lightPage) var light
    var body: some View {
        if light {
            CompactStack {
                Picker("", selection: $net.tab) { Text("Wi-Fi").tag(0); Text("Bluetooth").tag(1) }
                    .pickerStyle(.segmented).labelsHidden()
                if net.tab == 0 { WifiPage() } else { BluetoothPage() }
            }
        } else { CompactStack { WifiPage(); BluetoothPage() } }
    }
}

struct WifiPage: View {
    @EnvironmentObject var system: SystemModel
    @EnvironmentObject var net: NetworkModel
    @Environment(\.lightPage) var light

    var body: some View {
        CompactStack {
            ToggleRow(icon: system.wifiOn ? "wifi" : "wifi.slash", title: "Wi-Fi",
                      subtitle: system.wifiOn ? (system.wifiName ?? "On") : "Off", on: system.wifiOn,
                      action: { system.toggleWifi(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { net.scan() } })
            if system.wifiOn {
                let current = system.wifiName
                // One list: known and hotspots first, then by signal. Top 5, then "Show all".
                let rest = net.nets.filter { $0.ssid != current }
                    .sorted { ($0.known || $0.hotspot ? 0 : 1, -$0.bars, $0.ssid) < ($1.known || $1.hotspot ? 0 : 1, -$1.bars, $1.ssid) }
                if let current {
                    Card {
                        NetRow(icon: "wifi", on: true, title: current, subtitle: "Connected", action: {}) {
                            Button("Disconnect") { net.disconnect() }.buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    sectionLabel("NETWORKS")
                    Spacer()
                    if net.scanning { ProgressView().controlSize(.mini) }
                }
                if rest.isEmpty {
                    Text(net.scanning ? "Looking for networks…" : "No networks found. If none ever show, allow Location for Melcolm in Privacy settings.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    if light {
                        // Pop-up: the whole list, scrolling in a fixed box, so the pop-up never changes size.
                        ScrollView(showsIndicators: true) { netList(rest) }.frame(height: min(CGFloat(rest.count) * 44 + 8, 230))
                    } else {
                        netList(net.showOther ? rest : Array(rest.prefix(5)))
                        if rest.count > 5 { expand(net.showOther, count: rest.count) { net.showOther.toggle() } }
                    }
                }
                if let e = net.error { Text(e).font(.system(size: 11)).foregroundStyle(.orange) }
            }
            SettingsLink(title: "Wi-Fi Settings", pane: "com.apple.wifi-settings-extension")
        }
        .onAppear { net.scan() }
    }

    func section(_ title: String, _ list: [NetworkModel.Net], hotspot: Bool = false) -> some View {
        VStack(spacing: 6) { sectionLabel(title); netList(list, hotspot: hotspot) }
    }

    func netList(_ list: [NetworkModel.Net], hotspot: Bool = false) -> some View {
        Card {
            VStack(spacing: 0) {
                ForEach(list) { n in
                    if n.id != list.first?.id { Hairline() }
                    NetRow(icon: hotspot || n.hotspot ? "personalhotspot" : "wifi", on: false, title: n.ssid, action: { net.join(n) }) {
                        HStack(spacing: 6) {
                            if net.joining == n.ssid { ProgressView().controlSize(.mini) }
                            if n.secure { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                            Image(systemName: n.bars >= 3 ? "wifi" : n.bars == 2 ? "wifi.exclamationmark" : "wifi")
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(n.bars >= 2 ? 0.8 : 0.4))
                        }
                    }
                    if net.askPassword == n.ssid {
                        HStack(spacing: 8) {
                            SecureField("Password", text: $net.password).textFieldStyle(.roundedBorder)
                                .onSubmit { net.submitPassword() }
                            Pill("Join", filled: true) { net.submitPassword() }
                        }.padding(.bottom, 6)
                    }
                }
            }
        }
    }
}

struct BluetoothPage: View {
    @EnvironmentObject var system: SystemModel
    @EnvironmentObject var net: NetworkModel
    @Environment(\.lightPage) var light

    var body: some View {
        CompactStack {
            ToggleRow(icon: "dot.radiowaves.left.and.right", title: "Bluetooth",
                      subtitle: system.bluetoothOn ? "On" : "Off", on: system.bluetoothOn,
                      action: { system.toggleBluetooth(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { net.refreshDevices() } })
            if system.bluetoothOn && !net.devices.isEmpty {
                let shown = light || net.openBT ? net.devices : Array(net.devices.prefix(5))
                sectionLabel("DEVICES")
                ScrollView(showsIndicators: true) { Card {
                    VStack(spacing: 0) {
                        ForEach(shown) { d in
                            if d.id != shown.first?.id { Hairline() }
                            NetRow(icon: d.icon, on: d.connected, title: d.name, subtitle: d.connected ? "Connected" : nil,
                                   action: { net.toggle(d) }) {
                                if net.busy.contains(d.address) { ProgressView().controlSize(.mini) }
                                else {
                                    Text(d.connected ? "Disconnect" : "Connect").font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(d.connected ? AnyShapeStyle(.secondary) : AnyShapeStyle(accent))
                                }
                            }
                        }
                    }
                } }.frame(height: min(CGFloat(shown.count) * 44 + 12, light ? 230 : 10_000))
                if !light && net.devices.count > 5 { expand(net.openBT, count: net.devices.count) { net.openBT.toggle() } }
            }
            SettingsLink(title: "Bluetooth Settings", pane: "com.apple.BluetoothSettings")
        }
        .onAppear { net.refreshDevices() }
    }
}
