import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var model: NetworkModel
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
            Text("网络").font(.headline)
            Spacer()
            if model.wifi != nil {
                Text("Wi-Fi").font(.subheadline).foregroundStyle(.secondary)
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
            SectionTitle("当前连接")
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
        case .wifi, .hotspot: return model.wifi?.ssid ?? "已连接（需定位权限显示名称）"
        case .ethernet: return activeIface?.displayName ?? "以太网"
        case .wifiOff: return "Wi-Fi 已关闭"
        case .offline: return "未连接"
        }
    }

    private var subtitle: String {
        let ip = activeIface?.ipv4.first
        switch model.linkState {
        case .wifi, .hotspot:
            let kind = model.isHotspot ? "手机热点" : "Wi-Fi"
            let parts = [kind, model.wifi?.band, model.wifi.map { "\($0.rssi) dBm" }, ip].compactMap { $0 }
            return parts.joined(separator: " · ")
        case .ethernet:
            return ["有线", model.activeInterface, ip].compactMap { $0 }.joined(separator: " · ")
        case .wifiOff: return "打开 Wi-Fi 或插入网线以联网"
        case .offline: return "没有可用的网络连接"
        }
    }

    @ViewBuilder private var details: some View {
        let iface = activeIface
        VStack(spacing: 0) {
            if isWiFiActive, let w = model.wifi {
                InfoRow("网络名称", w.ssid ?? "—")
                InfoRow("BSSID", w.bssid ?? "—")
                InfoRow("信号 / 噪声", "\(w.rssi) dBm / \(w.noise) dBm（SNR \(w.rssi - w.noise) dB）")
                InfoRow("信道", [w.channel.map(String.init), w.band, w.width].compactMap { $0 }.joined(separator: " · "))
                InfoRow("协议", w.phyMode)
                InfoRow("协商速率", "\(Int(w.txRate)) Mbps")
                InfoRow("安全性", w.security)
                if let cc = w.countryCode { InfoRow("国家码", cc) }
            }
            if let iface {
                InfoRow("接口", "\(iface.displayName)（\(iface.bsdName)）")
                InfoRow("IPv4", iface.ipv4.joined(separator: "\n").nonEmpty ?? "—")
                if let m = iface.netmask { InfoRow("子网掩码", m) }
                InfoRow("路由器", model.global.routers[iface.bsdName] ?? "—")
                if !iface.ipv6.isEmpty { InfoRow("IPv6", iface.ipv6.joined(separator: "\n")) }
                if let mac = iface.mac { InfoRow("MAC 地址", mac) }
                if let mtu = iface.mtu { InfoRow("MTU", "\(mtu)") }
            }
            if !model.global.dns.isEmpty { InfoRow("DNS", model.global.dns.joined(separator: "\n")) }
            if let p = model.global.primaryInterface {
                InfoRow("默认路由", p + (InterfaceScanner.isTunnel(p) ? "（经代理/VPN）" : ""))
            }
        }
    }
}

private struct HotspotToggle: View {
    @ObservedObject var model: NetworkModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: Binding(get: { model.isHotspot }, set: { model.setCurrentIsHotspot($0) })) {
                Label("这是手机热点", systemImage: "cellularbars").font(.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(model.wifi?.ssid == nil)
            if model.wifi?.ssid == nil {
                Text("需要定位权限读取 Wi-Fi 名称后才能标记").font(.caption2).foregroundStyle(.secondary)
            } else if let why = model.hotspotAutoReason, !model.hotspotSSIDs.contains(model.wifi?.ssid ?? ""), model.isHotspot {
                Text("已自动识别：\(why)").font(.caption2).foregroundStyle(.secondary)
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
            SectionTitle("网络接口")
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
                            if iface.bsdName == model.global.primaryInterface { Badge("默认路由", .blue) }
                            if iface.bsdName == model.activeInterface && iface.bsdName != model.global.primaryInterface { Badge("物理链路", .green) }
                        }
                        Text(iface.ipv4.first ?? iface.ipv6.first ?? (iface.isRunning ? "无 IP 地址" : "未连接"))
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
                    InfoRow("状态", iface.isUp ? (iface.isRunning ? "已启用 · 运行中" : "已启用") : "已停用")
                    if !iface.ipv4.isEmpty { InfoRow("IPv4", iface.ipv4.joined(separator: "\n")) }
                    if let m = iface.netmask { InfoRow("子网掩码", m) }
                    if let r = model.global.routers[iface.bsdName] { InfoRow("路由器", r) }
                    if !iface.ipv6.isEmpty { InfoRow("IPv6", iface.ipv6.joined(separator: "\n")) }
                    if !iface.linkLocalIPv6.isEmpty { InfoRow("链路本地", iface.linkLocalIPv6.joined(separator: "\n")) }
                    if let mac = iface.mac { InfoRow("MAC 地址", mac) }
                    if let mtu = iface.mtu { InfoRow("MTU", "\(mtu)") }
                    if let total { InfoRow("累计流量", "↓ \(Format.bytes(total.rx))   ↑ \(Format.bytes(total.tx))") }
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
    @State private var passwordFor: String?
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle("附近的 Wi-Fi")
                Spacer()
                if model.scanning {
                    ProgressView().controlSize(.mini)
                } else {
                    Button { model.scan() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("重新扫描")
                        .disabled(model.wifi?.powerOn != true)
                }
            }
            if model.wifi?.powerOn != true {
                Placeholder("Wi-Fi 已关闭")
            } else if let e = model.scanError {
                Placeholder("扫描失败：\(e)")
            } else if model.scanResults.isEmpty {
                Placeholder(model.scanning ? "正在扫描…" : (model.locationAuthorized ? "未发现网络" : "需要定位权限才能显示网络名称"))
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
                    Button("取消手机热点标记") { model.hotspotSSIDs.remove(net.ssid) }
                } else {
                    Button("标记为手机热点") {
                        model.hotspotSSIDs.insert(net.ssid); model.notHotspotSSIDs.remove(net.ssid)
                    }
                }
                if isCurrent { Button("断开连接") { model.disconnectWiFi() } }
                Button("拷贝网络名称") { copy(net.ssid) }
            }

            if passwordFor == net.ssid {
                HStack(spacing: 6) {
                    SecureField("密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { join(net) }
                    Button("取消") { passwordFor = nil; password = "" }
                    Button("加入") { join(net) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(password.isEmpty || model.connectingSSID != nil)
                }
                .controlSize(.small)
                .padding(.leading, 36)
                .padding(.trailing, 6)
                .padding(.bottom, 4)
            }
        }
    }

    private func tap(_ net: ScanNetwork, isCurrent: Bool) {
        guard !isCurrent, model.connectingSSID == nil else { return }
        if !net.secure || net.known {
            model.connect(net, password: nil) { ok in
                if !ok && net.secure { model.connectError = nil; passwordFor = net.ssid }
            }
        } else {
            password = ""
            passwordFor = net.ssid
        }
    }

    private func join(_ net: ScanNetwork) {
        guard !password.isEmpty else { return }
        model.connect(net, password: password) { ok in
            if ok { passwordFor = nil; password = "" }
        }
    }
}

// MARK: - 底栏

private struct FooterView: View {
    @ObservedObject var model: NetworkModel
    @AppStorage(Prefs.showSpeed) private var showSpeed = false
    @AppStorage(Prefs.showName) private var showName = false
    @AppStorage(Prefs.showTunnelBadge) private var showTunnelBadge = true
    @AppStorage(Prefs.showAllInterfaces) private var showAll = false
    @AppStorage(Prefs.autoDetectHotspot) private var autoHotspot = true

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.fetchPublicIP()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    if model.fetchingPublicIP {
                        Text("查询中…")
                    } else {
                        Text(model.publicIP.map { "公网 IP：\($0)" } ?? "查询公网 IP")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("通过 api.ipify.org 查询出口 IP（开启代理时即为代理出口）；右键拷贝")
            .contextMenu { if let ip = model.publicIP { Button("拷贝") { copy(ip) } } }

            Spacer()

            Menu {
                Toggle("菜单栏显示网速", isOn: $showSpeed)
                Toggle("菜单栏显示网络名称", isOn: $showName)
                Toggle("代理 / VPN 启用时图标显示圆点", isOn: $showTunnelBadge)
                Toggle("显示所有网络接口", isOn: $showAll)
                Toggle("自动识别手机热点", isOn: $autoHotspot)
                Toggle("开机启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                Divider()
                Button("网络设置…") { openURL("x-apple.systempreferences:com.apple.Network-Settings.extension") }
                Button("隐藏系统自带 Wi-Fi 图标…") { openURL("x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") }
                if !model.locationAuthorized {
                    Button("定位权限设置…") { openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") }
                }
                Divider()
                Button("退出 NetBar") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
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
                Text("macOS 需要定位权限才能读取 Wi-Fi 名称和扫描网络。NetBar 不会使用你的位置。")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button(model.locationUndetermined ? "授权" : "打开定位权限设置") {
                    if model.locationUndetermined {
                        model.requestLocation()
                    } else {
                        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
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
            Text(label).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            Text(copied ? "已拷贝" : value)
                .foregroundStyle(copied ? Color.accentColor : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.monospacedDigit())
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard value != "—" else { return }
            copy(value)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { copied = false }
        }
        .help("点击拷贝")
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

private func copy(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

private func openURL(_ s: String) {
    if let url = URL(string: s) { NSWorkspace.shared.open(url) }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
