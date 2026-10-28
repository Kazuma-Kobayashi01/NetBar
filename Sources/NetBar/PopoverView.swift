import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var model: NetworkModel
    @AppStorage(Prefs.language) private var language = AppLanguage.system.rawValue
    @State private var contentHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.locationAuthorized && model.wifi?.ssid == nil && model.wifi?.isAssociated == true { LocationBanner(model: model) }
                    if let err = model.connectError { ErrorBanner(text: err) { model.connectError = nil } }
                    CurrentConnectionView(model: model)
                    InterfacesView(model: model)
                    NearbyNetworksView(model: model)
                }
                .padding(12)
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                })
            }
            .frame(height: min(contentHeight, 580))
            .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
            Divider()
            FooterView(model: model)
        }
        .frame(width: 360)
        // 切换语言时整体重建，让所有 L() 重新取值
        .id(language)
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - 顶栏

private struct HeaderView: View {
    @ObservedObject var model: NetworkModel

    var body: some View {
        HStack {
            Text(L("network")).font(.headline)
            Spacer()
            if model.wifi != nil {
                Text(L("wifi")).font(.subheadline).foregroundStyle(.secondary)
                Toggle("", isOn: Binding(get: { model.wifi?.powerOn ?? false },
                                         set: { model.setWiFiPower($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - 当前连接

private struct CurrentConnectionView: View {
    @ObservedObject var model: NetworkModel
    @AppStorage("detailsExpanded") private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(L("current_connection"))
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                    HStack(spacing: 10) {
                        LinkIcon(state: model.linkState, size: 22)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(model.activeInterface == nil ? Color.secondary.opacity(0.2) : Color.accentColor))
                            .foregroundStyle(model.activeInterface == nil ? Color.secondary : Color.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let a = model.activeInterface, let r = model.rates[a] {
                            RateView(rx: r.rx, tx: r.tx)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isWiFiActive {
                    HotspotToggle(model: model)
                }

                if expanded { details }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
    }

    private var isWiFiActive: Bool {
        if case .wifi = model.linkState { return true }
        if case .hotspot = model.linkState { return true }
        return false
    }

    private var activeIface: NetInterface? {
        model.interfaces.first { $0.bsdName == model.activeInterface }
    }

    private var title: String {
        switch model.linkState {
        case .wifi, .hotspot: return model.wifi?.ssid ?? L("connected_need_location")
        case .ethernet: return activeIface?.displayName ?? L("ethernet")
        case .wifiOff: return L("wifi_off")
        case .offline: return L("not_connected")
        }
    }

    private var subtitle: String {
        let ip = activeIface?.ipv4.first
        switch model.linkState {
        case .wifi, .hotspot:
            let kind = model.isHotspot ? L("hotspot") : L("wifi")
            let parts = [kind, model.wifi?.band, model.wifi.map { "\($0.rssi) dBm" }, ip].compactMap { $0 }
            return parts.joined(separator: " · ")
        case .ethernet:
            return [L("wired"), model.activeInterface, ip].compactMap { $0 }.joined(separator: " · ")
        case .wifiOff: return L("wifi_off_hint")
        case .offline: return L("offline_hint")
        }
    }

    @ViewBuilder private var details: some View {
        let iface = activeIface
        VStack(spacing: 0) {
            if isWiFiActive, let w = model.wifi {
                InfoRow(L("ssid_label"), w.ssid ?? "—")
                InfoRow("BSSID", w.bssid ?? "—")
                InfoRow(L("signal_noise"), "\(w.rssi) dBm / \(w.noise) dBm (SNR \(w.rssi - w.noise) dB)")
                InfoRow(L("channel"), [w.channel.map(String.init), w.band, w.width].compactMap { $0 }.joined(separator: " · "))
                InfoRow(L("protocol"), w.phyMode)
                InfoRow(L("tx_rate"), "\(Int(w.txRate)) Mbps")
                InfoRow(L("security"), w.security)
                if let cc = w.countryCode { InfoRow(L("country"), cc) }
            }
            if let iface {
                InfoRow(L("interface"), "\(iface.displayName) (\(iface.bsdName))")
                InfoRow("IPv4", iface.ipv4.joined(separator: "\n").nonEmpty ?? "—")
                if let m = iface.netmask { InfoRow(L("netmask"), m) }
                InfoRow(L("router"), model.global.routers[iface.bsdName] ?? "—")
                if !iface.ipv6.isEmpty { InfoRow("IPv6", iface.ipv6.joined(separator: "\n")) }
                if let mac = iface.mac { InfoRow(L("mac"), mac) }
                if let mtu = iface.mtu { InfoRow("MTU", "\(mtu)") }
            }
            if !model.global.dns.isEmpty { InfoRow("DNS", model.global.dns.joined(separator: "\n")) }
            if let p = model.global.primaryInterface {
                InfoRow(L("default_route"), p + (InterfaceScanner.isTunnel(p) ? L("via_tunnel") : ""))
            }
        }
    }
}

private struct HotspotToggle: View {
    @ObservedObject var model: NetworkModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: Binding(get: { model.isHotspot }, set: { model.setCurrentIsHotspot($0) })) {
                Label(L("this_is_hotspot"), systemImage: "cellularbars").font(.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(model.wifi?.ssid == nil)
            if model.wifi?.ssid == nil {
                Text(L("hotspot_need_ssid")).font(.caption2).foregroundStyle(.secondary)
            } else if let why = model.hotspotAutoReason, !model.hotspotSSIDs.contains(model.wifi?.ssid ?? ""), model.isHotspot {
                Text(L("hotspot_auto_fmt", why)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 网卡列表

private struct InterfacesView: View {
    @ObservedObject var model: NetworkModel
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(L("interfaces"))
            VStack(spacing: 2) {
                ForEach(model.interfaces) { iface in
                    row(iface)
                }
            }
        }
    }

    private func row(_ iface: NetInterface) -> some View {
        let isOpen = expanded.contains(iface.bsdName)
        let rate = model.rates[iface.bsdName]
        let total = model.totals[iface.bsdName]
        let inactive = !iface.hasUsableAddress
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { expanded.remove(iface.bsdName) } else { expanded.insert(iface.bsdName) }
                }
            } label: {
                HStack(spacing: 8) {
                    KindIcon(kind: iface.kind)
                        .frame(width: 22)
                        .foregroundStyle(inactive ? .secondary : .primary)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(iface.displayName).font(.callout).lineLimit(1)
                            Text(iface.bsdName).font(.caption2).foregroundStyle(.secondary)
                            if iface.bsdName == model.global.primaryInterface { Badge(L("default_route"), .blue) }
                            if iface.bsdName == model.activeInterface && iface.bsdName != model.global.primaryInterface { Badge(L("badge_physical"), .green) }
                        }
                        Text(iface.ipv4.first ?? iface.ipv6.first ?? (iface.isRunning ? L("no_ip") : L("not_connected")))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let rate, !inactive { RateView(rx: rate.rx, tx: rate.tx) }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle())

            if isOpen {
                VStack(spacing: 0) {
                    InfoRow(L("status"), iface.isUp ? (iface.isRunning ? L("status_up_running") : L("status_up")) : L("status_down"))
                    if !iface.ipv4.isEmpty { InfoRow("IPv4", iface.ipv4.joined(separator: "\n")) }
                    if let m = iface.netmask { InfoRow(L("netmask"), m) }
                    if let r = model.global.routers[iface.bsdName] { InfoRow(L("router"), r) }
                    if !iface.ipv6.isEmpty { InfoRow("IPv6", iface.ipv6.joined(separator: "\n")) }
                    if !iface.linkLocalIPv6.isEmpty { InfoRow(L("link_local"), iface.linkLocalIPv6.joined(separator: "\n")) }
                    if let mac = iface.mac { InfoRow(L("mac"), mac) }
                    if let mtu = iface.mtu { InfoRow("MTU", "\(mtu)") }
                    if let total { InfoRow(L("total_traffic"), "↓ \(Format.bytes(total.rx))   ↑ \(Format.bytes(total.tx))") }
                }
                .padding(.leading, 36)
                .padding(.trailing, 6)
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - 附近 Wi-Fi

private struct NearbyNetworksView: View {
    @ObservedObject var model: NetworkModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(L("nearby"))
                Spacer()
                if model.scanning {
                    ProgressView().controlSize(.mini)
                } else {
                    Button { model.scan() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help(L("rescan"))
                        .disabled(model.wifi?.powerOn != true)
                }
            }
            if model.wifi?.powerOn != true {
                Placeholder(L("wifi_off"))
            } else if let e = model.scanError {
                Placeholder(L("scan_failed_fmt", e))
            } else if model.scanResults.isEmpty {
                Placeholder(model.scanning ? L("scanning") : (model.locationAuthorized ? L("no_networks") : L("need_location_list")))
            } else {
                VStack(spacing: 2) {
                    ForEach(model.scanResults) { net in
                        row(net)
                    }
                }
            }
        }
    }

    private func row(_ net: ScanNetwork) -> some View {
        let isCurrent = net.ssid == model.wifi?.ssid
        let isHotspot = model.isHotspotSSID(net.ssid)
        return VStack(spacing: 4) {
            Button { tap(net, isCurrent: isCurrent) } label: {
                HStack(spacing: 8) {
                    Image(systemName: isHotspot ? "cellularbars" : "wifi",
                          variableValue: WiFiInfo.strength(rssi: net.rssi))
                        .frame(width: 22)
                    Text(net.ssid).font(.callout).lineLimit(1)
                    if let b = net.band { Text(b).font(.caption2).foregroundStyle(.tertiary) }
                    Spacer()
                    if model.connectingSSID == net.ssid { ProgressView().controlSize(.mini) }
                    if net.secure { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    if isCurrent { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor) }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle())
            .contextMenu {
                if model.hotspotSSIDs.contains(net.ssid) {
                    Button(L("unmark_hotspot")) { model.hotspotSSIDs.remove(net.ssid) }
                } else {
                    Button(L("mark_hotspot")) {
                        model.hotspotSSIDs.insert(net.ssid); model.notHotspotSSIDs.remove(net.ssid)
                    }
                }
                if isCurrent { Button(L("disconnect")) { model.disconnectWiFi() } }
                Button(L("copy_ssid")) { copyToPasteboard(net.ssid) }
            }
        }
    }

    private func tap(_ net: ScanNetwork, isCurrent: Bool) {
        guard !isCurrent, model.connectingSSID == nil else { return }
        if !net.secure {
            model.connect(net, password: nil) { _ in }
        } else if net.known && !net.isEnterprise {
            // 已保存的网络先用系统钥匙串里的密码，失败再弹窗
            model.connect(net, password: nil, reportError: false) { error in
                if error != nil { JoinDialog.present(for: net, model: model, initialError: L("saved_password_failed")) }
            }
        } else {
            JoinDialog.present(for: net, model: model)
        }
    }
}

// MARK: - 底栏

private struct FooterView: View {
    @ObservedObject var model: NetworkModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.fetchPublicIP()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    if model.fetchingPublicIP {
                        Text(L("querying"))
                    } else {
                        Text(model.publicIP.map { L("public_ip_fmt", $0) } ?? L("query_public_ip"))
                            .lineLimit(1)
                    }
                }
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(L("public_ip_help"))
            .contextMenu { if let ip = model.publicIP { Button(L("copy")) { copyToPasteboard(ip) } } }

            Spacer()

            Button { SettingsWindowController.shared.show(model: model) } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(L("settings_ellipsis") + "  ⌘,")

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(L("quit"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 横幅

private struct LocationBanner: View {
    @ObservedObject var model: NetworkModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "location.slash").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("location_banner"))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button(model.locationUndetermined ? L("authorize") : L("open_location_settings")) {
                    if model.locationUndetermined {
                        model.requestLocation()
                    } else {
                        openSystemURL(SystemURL.location)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

private struct ErrorBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
    }
}

// MARK: - 小组件

struct LinkIcon: View {
    let state: LinkState
    var size: CGFloat = 16

    var body: some View {
        switch state {
        case .wifi(let s): Image(systemName: "wifi", variableValue: s).font(.system(size: size, weight: .medium))
        case .hotspot(let s): Image(systemName: "cellularbars", variableValue: s).font(.system(size: size, weight: .medium))
        case .ethernet: Image(nsImage: StatusIcon.wiredImage(pointSize: size)).renderingMode(.template)
        case .wifiOff: Image(systemName: "wifi.slash").font(.system(size: size, weight: .medium))
        case .offline: Image(systemName: "wifi.exclamationmark").font(.system(size: size, weight: .medium))
        }
    }
}

private struct KindIcon: View {
    let kind: InterfaceKind

    var body: some View {
        if kind == .ethernet {
            Image(nsImage: StatusIcon.wiredImage(pointSize: 12)).renderingMode(.template)
        } else {
            Image(systemName: kind.symbol).font(.system(size: 13))
        }
    }
}

private struct RateView: View {
    let rx: Double
    let tx: Double

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("↓ " + Format.rate(rx))
            Text("↑ " + Format.rate(tx))
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    init(_ text: String, _ color: Color) { self.text = text; self.color = color }
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}

private struct Placeholder: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).padding(.vertical, 4).padding(.horizontal, 6)
    }
}

/// 一行“标签：值”，点击拷贝值
private struct InfoRow: View {
    let label: String
    let value: String
    @State private var copied = false

    init(_ label: String, _ value: String) { self.label = label; self.value = value }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(copied ? L("copied") : value)
                .foregroundStyle(copied ? Color.accentColor : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.monospacedDigit())
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard value != "—" else { return }
            copyToPasteboard(value)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { copied = false }
        }
        .help(L("click_to_copy"))
    }
}

private struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.07 : 0))))
                .onHover { hovering = $0 }
        }
    }
}

enum SystemURL {
    static let location = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
    static let network = "x-apple.systempreferences:com.apple.Network-Settings.extension"
    static let controlCenter = "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
}

func copyToPasteboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

func openSystemURL(_ s: String) {
    if let url = URL(string: s) { NSWorkspace.shared.open(url) }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
