import Foundation
import Network
import Combine
import ServiceManagement

/// 菜单栏图标的三种形态（加上离线/关闭等状态）
enum LinkState: Equatable {
    case wifi(strength: Double)
    case hotspot(strength: Double)
    case ethernet
    case wifiOff
    case offline
}

enum Prefs {
    static let showSpeed = "showSpeed"
    static let showName = "showName"
    static let showAllInterfaces = "showAllInterfaces"
    static let autoDetectHotspot = "autoDetectHotspot"
    static let showTunnelBadge = "showTunnelBadge"
    static let hotspotSSIDs = "hotspotSSIDs"
    static let notHotspotSSIDs = "notHotspotSSIDs"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showSpeed: false,
            showName: false,
            showAllInterfaces: false,
            autoDetectHotspot: true,
            showTunnelBadge: true,
        ])
    }
}

/// iPhone 个人热点固定使用 172.20.10.0/28 网段，网关为 172.20.10.1；192.168.43.1 是多数安卓热点的默认网关
private let hotspotRouters: [String: String] = ["172.20.10.1": "iPhone 热点网关", "192.168.43.1": "安卓热点网关"]
/// 手机热点默认名称里常见的关键词
private let hotspotNameKeywords = ["iphone", "ipad", "galaxy", "android", "redmi", "xiaomi", "huawei", "honor", "oppo", "vivo", "oneplus", "pixel", "realme", "iqoo", "meizu", "nova", "mate"]

final class NetworkModel: ObservableObject {
    @Published private(set) var interfaces: [NetInterface] = []
    @Published private(set) var global = GlobalNetState()
    @Published private(set) var wifi: WiFiInfo?
    @Published private(set) var rates: [String: (rx: Double, tx: Double)] = [:]
    @Published private(set) var totals: [String: (rx: UInt64, tx: UInt64)] = [:]
    @Published private(set) var linkState: LinkState = .offline
    @Published private(set) var activeInterface: String?
    @Published private(set) var locationAuthorized = false
    @Published private(set) var locationUndetermined = false

    @Published private(set) var scanResults: [ScanNetwork] = []
    @Published private(set) var scanning = false
    @Published private(set) var scanError: String?
    @Published private(set) var connectingSSID: String?
    @Published var connectError: String?

    @Published private(set) var publicIP: String?
    @Published private(set) var fetchingPublicIP = false

    @Published var hotspotSSIDs: Set<String> { didSet { save(hotspotSSIDs, Prefs.hotspotSSIDs) } }
    @Published var notHotspotSSIDs: Set<String> { didSet { save(notHotspotSSIDs, Prefs.notHotspotSSIDs) } }

    let wifiService = WiFiService()
    private let pathMonitor = NWPathMonitor()
    private var timer: Timer?
    private var lastCounters: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var lastCounterDate = Date()
    private var defaultsObserver: AnyCancellable?

    init() {
        let d = UserDefaults.standard
        hotspotSSIDs = Set(d.stringArray(forKey: Prefs.hotspotSSIDs) ?? [])
        notHotspotSSIDs = Set(d.stringArray(forKey: Prefs.notHotspotSSIDs) ?? [])

        wifiService.onChange = { [weak self] in self?.refresh() }
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        pathMonitor.start(queue: .global(qos: .utility))
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }

        if wifiService.locationUndetermined { wifiService.requestLocation() }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 0.3
    }

    private func save(_ set: Set<String>, _ key: String) {
        UserDefaults.standard.set(Array(set).sorted(), forKey: key)
    }

    // MARK: 刷新

    func refresh() {
        let d = UserDefaults.standard
        let newInterfaces = InterfaceScanner.scan(includeHidden: d.bool(forKey: Prefs.showAllInterfaces))
        let newGlobal = InterfaceScanner.globalState()
        let newWifi = wifiService.currentInfo()

        let counters = InterfaceScanner.byteCounters()
        let now = Date()
        let dt = now.timeIntervalSince(lastCounterDate)
        if dt > 0.5 {
            var r: [String: (Double, Double)] = [:]
            for (name, c) in counters {
                guard let p = lastCounters[name] else { continue }
                let rx = c.rx >= p.rx ? Double(c.rx - p.rx) / dt : 0
                let tx = c.tx >= p.tx ? Double(c.tx - p.tx) / dt : 0
                r[name] = (rx, tx)
            }
            rates = r
            lastCounters = counters
            lastCounterDate = now
        }
        totals = counters

        if newInterfaces != interfaces { interfaces = newInterfaces }
        global = newGlobal
        if newWifi != wifi { wifi = newWifi }
        locationAuthorized = wifiService.locationAuthorized
        locationUndetermined = wifiService.locationUndetermined

        let (state, active) = computeLinkState()
        if state != linkState { linkState = state }
        if active != activeInterface { activeInterface = active }
    }

    /// 选出“真正承载流量的物理网卡”：默认路由若是 utun（代理/VPN），则回退到有网关的物理网卡
    private func computeLinkState() -> (LinkState, String?) {
        let wifiName = wifi?.interfaceName
        let wifiUp = wifi?.isAssociated == true
        let byName = Dictionary(uniqueKeysWithValues: interfaces.map { ($0.bsdName, $0) })

        func isWired(_ name: String) -> Bool {
            guard let i = byName[name] else { return false }
            return i.kind == .ethernet && name != wifiName && !i.ipv4.isEmpty
        }

        var active: String?
        if let p = global.primaryInterface, p == wifiName || isWired(p) {
            active = p
        } else if let wired = interfaces.first(where: { isWired($0.bsdName) && global.routers[$0.bsdName] != nil }) {
            active = wired.bsdName
        } else if wifiUp {
            active = wifiName
        } else if let wired = interfaces.first(where: { isWired($0.bsdName) }) {
            active = wired.bsdName
        }

        guard let a = active else {
            if wifi?.powerOn == false { return (.wifiOff, nil) }
            return (.offline, nil)
        }
        if a == wifiName, let w = wifi {
            return (isHotspot ? .hotspot(strength: w.strength) : .wifi(strength: w.strength), a)
        }
        return (.ethernet, a)
    }

    // MARK: 热点

    var wifiRouter: String? {
        guard let n = wifi?.interfaceName else { return nil }
        return global.routers[n]
    }

    /// 自动识别依据（nil 表示未识别为热点）
    var hotspotAutoReason: String? {
        guard UserDefaults.standard.bool(forKey: Prefs.autoDetectHotspot) else { return nil }
        if let r = wifiRouter, let why = hotspotRouters[r] { return "网关 \(r)（\(why)）" }
        if let ssid = wifi?.ssid?.lowercased(),
           let k = hotspotNameKeywords.first(where: { ssid.contains($0) }) {
            return "网络名称包含 “\(k)”"
        }
        return nil
    }

    var hotspotAutoDetected: Bool { hotspotAutoReason != nil }

    /// 当前 Wi-Fi 是否视为手机热点：手动标记 > 手动排除 > 自动识别
    var isHotspot: Bool {
        guard wifi?.isAssociated == true else { return false }
        if let ssid = wifi?.ssid {
            if hotspotSSIDs.contains(ssid) { return true }
            if notHotspotSSIDs.contains(ssid) { return false }
        }
        return hotspotAutoDetected
    }

    func setCurrentIsHotspot(_ on: Bool) {
        guard let ssid = wifi?.ssid else { return }
        if on {
            hotspotSSIDs.insert(ssid); notHotspotSSIDs.remove(ssid)
        } else {
            hotspotSSIDs.remove(ssid)
            if hotspotAutoDetected { notHotspotSSIDs.insert(ssid) }
        }
        refresh()
    }

    func isHotspotSSID(_ ssid: String) -> Bool {
        hotspotSSIDs.contains(ssid) || (ssid == wifi?.ssid && isHotspot)
    }

    var hasActiveTunnel: Bool {
        interfaces.contains { $0.kind == .tunnel && !$0.ipv4.isEmpty }
    }

    // MARK: Wi-Fi 操作

    func requestLocation() { wifiService.requestLocation() }

    func setWiFiPower(_ on: Bool) {
        do { try wifiService.setPower(on) } catch { connectError = error.localizedDescription }
        if !on { scanResults = [] }
        refresh()
        if on { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.scan() } }
    }

    func disconnectWiFi() {
        wifiService.disconnect()
        refresh()
    }

    func scan() {
        guard !scanning, wifi?.powerOn == true else { return }
        scanning = true
        scanError = nil
        DispatchQueue.global(qos: .userInitiated).async { [wifiService] in
            let result: Result<[ScanNetwork], Error> = Result { try wifiService.scan() }
            DispatchQueue.main.async {
                self.scanning = false
                switch result {
                case .success(let list): self.scanResults = list
                case .failure(let e): self.scanError = e.localizedDescription
                }
            }
        }
    }

    func connect(_ net: ScanNetwork, password: String?, completion: @escaping (Bool) -> Void) {
        connectingSSID = net.ssid
        connectError = nil
        DispatchQueue.global(qos: .userInitiated).async { [wifiService] in
            let result = Result { try wifiService.connect(net.network, password: password) }
            DispatchQueue.main.async {
                self.connectingSSID = nil
                switch result {
                case .success:
                    completion(true)
                case .failure(let e):
                    self.connectError = "连接“\(net.ssid)”失败：\(e.localizedDescription)"
                    completion(false)
                }
                self.refresh()
            }
        }
    }

    // MARK: 公网 IP（仅在用户点击时请求）

    func fetchPublicIP() {
        guard !fetchingPublicIP, let url = URL(string: "https://api.ipify.org") else { return }
        fetchingPublicIP = true
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                self.fetchingPublicIP = false
                if let data, let s = String(data: data, encoding: .utf8), !s.isEmpty {
                    self.publicIP = s.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    self.publicIP = "查询失败" + (error.map { "：\($0.localizedDescription)" } ?? "")
                }
            }
        }.resume()
    }

    // MARK: 开机启动

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                connectError = "设置开机启动失败：\(error.localizedDescription)（请先把 NetBar 放到“应用程序”文件夹）"
            }
            objectWillChange.send()
        }
    }
}
