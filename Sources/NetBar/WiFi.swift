import Foundation
import CoreWLAN
import CoreLocation

struct WiFiInfo: Equatable {
    var interfaceName: String
    var powerOn: Bool
    var ssid: String?
    var bssid: String?
    var rssi: Int
    var noise: Int
    var txRate: Double
    var channel: Int?
    var band: String?
    var width: String?
    var security: String
    var phyMode: String
    var countryCode: String?
    var mac: String?

    /// 已关联到某个 AP（即使因定位权限读不到 SSID）
    var isAssociated: Bool { powerOn && channel != nil && rssi != 0 }

    var strength: Double { WiFiInfo.strength(rssi: rssi) }

    static func strength(rssi: Int) -> Double {
        switch rssi {
        case let r where r >= -55: return 1.0
        case let r where r >= -67: return 0.75
        case let r where r >= -75: return 0.5
        default: return 0.25
        }
    }
}

struct ScanNetwork: Identifiable, Equatable {
    var id: String { ssid }
    let ssid: String
    let rssi: Int
    let secure: Bool
    let band: String?
    let known: Bool
    let network: CWNetwork

    static func == (a: ScanNetwork, b: ScanNetwork) -> Bool {
        a.ssid == b.ssid && a.rssi == b.rssi && a.secure == b.secure && a.known == b.known
    }
}

final class WiFiService: NSObject, CWEventDelegate, CLLocationManagerDelegate {
    let client = CWWiFiClient.shared()
    private let location = CLLocationManager()
    var onChange: (() -> Void)?

    var interface: CWInterface? { client.interface() }

    override init() {
        super.init()
        client.delegate = self
        for event in [CWEventType.ssidDidChange, .bssidDidChange, .linkDidChange, .powerDidChange, .modeDidChange] {
            try? client.startMonitoringEvent(with: event)
        }
        location.delegate = self
    }

    // MARK: 定位权限（macOS 14+ 读取 SSID 必需）

    var locationAuthorized: Bool {
        switch location.authorizationStatus {
        case .authorizedAlways, .authorized: return true
        default: return false
        }
    }

    var locationUndetermined: Bool { location.authorizationStatus == .notDetermined }

    func requestLocation() {
        location.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { self.onChange?() }
    }

    // MARK: CWEventDelegate

    private func notify() { DispatchQueue.main.async { self.onChange?() } }
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) { notify() }
    func bssidDidChangeForWiFiInterface(withName interfaceName: String) { notify() }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) { notify() }
    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { notify() }
    func modeDidChangeForWiFiInterface(withName interfaceName: String) { notify() }

    // MARK: 当前状态

    func currentInfo() -> WiFiInfo? {
        guard let i = interface, let name = i.interfaceName else { return nil }
        let ch = i.wlanChannel()
        return WiFiInfo(
            interfaceName: name,
            powerOn: i.powerOn(),
            ssid: i.ssid(),
            bssid: i.bssid(),
            rssi: i.rssiValue(),
            noise: i.noiseMeasurement(),
            txRate: i.transmitRate(),
            channel: ch.map { $0.channelNumber },
            band: ch.map { Self.bandName($0.channelBand) } ?? nil,
            width: ch.map { Self.widthName($0.channelWidth) } ?? nil,
            security: Self.securityName(i.security()),
            phyMode: Self.phyName(i.activePHYMode()),
            countryCode: i.countryCode(),
            mac: i.hardwareAddress()
        )
    }

    func setPower(_ on: Bool) throws {
        try interface?.setPower(on)
    }

    func disconnect() {
        interface?.disassociate()
    }

    var knownSSIDs: Set<String> {
        guard let profiles = interface?.configuration()?.networkProfiles.array as? [CWNetworkProfile] else { return [] }
        return Set(profiles.compactMap { $0.ssid })
    }

    /// 阻塞调用，需在后台线程执行
    func scan() throws -> [ScanNetwork] {
        guard let i = interface else { return [] }
        let raw = try i.scanForNetworks(withName: nil, includeHidden: false)
        let known = knownSSIDs
        var best: [String: CWNetwork] = [:]
        for n in raw {
            guard let ssid = n.ssid, !ssid.isEmpty else { continue }
            if let cur = best[ssid], cur.rssiValue >= n.rssiValue { continue }
            best[ssid] = n
        }
        return best.values.map { n in
            ScanNetwork(
                ssid: n.ssid!,
                rssi: n.rssiValue,
                secure: !n.supportsSecurity(.none),
                band: n.wlanChannel.map { Self.bandName($0.channelBand) } ?? nil,
                known: known.contains(n.ssid!),
                network: n
            )
        }
        .sorted { ($0.known ? 1 : 0, $0.rssi) > ($1.known ? 1 : 0, $1.rssi) }
    }

    /// 阻塞调用，需在后台线程执行。password 为 nil 时使用系统已保存的凭据
    func connect(_ network: CWNetwork, password: String?) throws {
        guard let i = interface else { throw NSError(domain: "NetBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到 Wi-Fi 网卡"]) }
        try i.associate(to: network, password: password)
    }

    // MARK: 名称映射

    static func bandName(_ b: CWChannelBand) -> String? {
        switch b {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        default: return nil
        }
    }

    static func widthName(_ w: CWChannelWidth) -> String? {
        switch w {
        case .width20MHz: return "20 MHz"
        case .width40MHz: return "40 MHz"
        case .width80MHz: return "80 MHz"
        case .width160MHz: return "160 MHz"
        default: return nil
        }
    }

    static func phyName(_ m: CWPHYMode) -> String {
        switch m {
        case .mode11a: return "802.11a"
        case .mode11b: return "802.11b"
        case .mode11g: return "802.11g"
        case .mode11n: return "Wi-Fi 4 (802.11n)"
        case .mode11ac: return "Wi-Fi 5 (802.11ac)"
        case .mode11ax: return "Wi-Fi 6 (802.11ax)"
        case .modeNone: return "—"
        @unknown default: return m.rawValue == 7 ? "Wi-Fi 7 (802.11be)" : "未知"
        }
    }

    static func securityName(_ s: CWSecurity) -> String {
        switch s {
        case .none: return "无（开放网络）"
        case .WEP: return "WEP"
        case .wpaPersonal: return "WPA 个人级"
        case .wpaPersonalMixed: return "WPA/WPA2 个人级"
        case .wpa2Personal: return "WPA2 个人级"
        case .personal: return "个人级"
        case .dynamicWEP: return "动态 WEP"
        case .wpaEnterprise: return "WPA 企业级"
        case .wpaEnterpriseMixed: return "WPA/WPA2 企业级"
        case .wpa2Enterprise: return "WPA2 企业级"
        case .enterprise: return "企业级"
        case .wpa3Personal: return "WPA3 个人级"
        case .wpa3Enterprise: return "WPA3 企业级"
        case .wpa3Transition: return "WPA2/WPA3 个人级"
        case .OWE: return "OWE 增强开放"
        case .oweTransition: return "OWE 过渡"
        case .unknown: return "未知"
        @unknown default: return "未知"
        }
    }
}
