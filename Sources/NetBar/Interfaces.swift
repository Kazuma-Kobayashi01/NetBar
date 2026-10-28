import Foundation
import SystemConfiguration
import Darwin

enum InterfaceKind {
    case wifi, ethernet, tunnel, bridge, other

    var symbol: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector.horizontal"
        case .tunnel: return "lock.shield"
        case .bridge: return "point.3.connected.trianglepath.dotted"
        case .other: return "network"
        }
    }
}

struct NetInterface: Identifiable, Equatable {
    var id: String { bsdName }
    let bsdName: String
    var displayName: String
    var kind: InterfaceKind
    var isUp = false
    var isRunning = false
    var ipv4: [String] = []
    var netmask: String?
    var ipv6: [String] = []          // 全局 / ULA 地址
    var linkLocalIPv6: [String] = []
    var mac: String?
    var mtu: Int?

    /// 有可用地址（排除仅有 fe80 链路本地地址的系统 utun）
    var hasUsableAddress: Bool { !ipv4.isEmpty || !ipv6.isEmpty }
}

struct GlobalNetState {
    var primaryInterface: String?
    var primaryRouter: String?
    var routers: [String: String] = [:]   // bsdName -> IPv4 router
    var dns: [String] = []
}

enum InterfaceScanner {
    /// 不在列表中显示的系统内部接口
    private static let hiddenPrefixes = ["lo", "gif", "stf", "awdl", "llw", "anpi", "ap", "XHC", "pktap", "iptap"]

    private static var scInfoCache: [String: (name: String, type: String)] = [:]
    private static var scInfoCacheDate = Date.distantPast

    /// 通过 SystemConfiguration 获取接口的本地化名称和类型（如 “Wi-Fi”、“USB 10/100/1000 LAN”）
    private static func scInfo() -> [String: (name: String, type: String)] {
        if Date().timeIntervalSince(scInfoCacheDate) < 30 { return scInfoCache }
        var map: [String: (String, String)] = [:]
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for iface in all {
                guard let bsd = SCNetworkInterfaceGetBSDName(iface) as String? else { continue }
                let name = (SCNetworkInterfaceGetLocalizedDisplayName(iface) as String?) ?? bsd
                let type = (SCNetworkInterfaceGetInterfaceType(iface) as String?) ?? ""
                map[bsd] = (name, type)
            }
        }
        scInfoCache = map
        scInfoCacheDate = Date()
        return map
    }

    static func isTunnel(_ name: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap", "wg", "feth", "zt"].contains { name.hasPrefix($0) }
    }

    static func scan(includeHidden: Bool) -> [NetInterface] {
        let info = scInfo()
        var dict: [String: NetInterface] = [:]
        var order: [String] = []

        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let name = String(cString: ifa.ifa_name)
            if dict[name] == nil {
                let sc = info[name]
                let kind: InterfaceKind
                if sc?.type == (kSCNetworkInterfaceTypeIEEE80211 as String) {
                    kind = .wifi
                } else if isTunnel(name) {
                    kind = .tunnel
                } else if name.hasPrefix("bridge") {
                    kind = .bridge
                } else if name.hasPrefix("en") {
                    kind = .ethernet
                } else {
                    kind = .other
                }
                var display = sc?.name ?? name
                if kind == .tunnel { display = L("tunnel_name") }
                dict[name] = NetInterface(bsdName: name, displayName: display, kind: kind)
                order.append(name)
            }
            var iface = dict[name]!
            let flags = Int32(ifa.ifa_flags)
            iface.isUp = flags & IFF_UP != 0
            iface.isRunning = flags & IFF_RUNNING != 0

            guard let addr = ifa.ifa_addr else { dict[name] = iface; continue }
            switch Int32(addr.pointee.sa_family) {
            case AF_INET:
                if let s = numericHost(addr) { iface.ipv4.append(s) }
                if iface.netmask == nil, let m = ifa.ifa_netmask, let s = numericHost(m) { iface.netmask = s }
            case AF_INET6:
                if let s = numericHost(addr) {
                    let clean = s.components(separatedBy: "%").first ?? s
                    if clean.lowercased().hasPrefix("fe80") { iface.linkLocalIPv6.append(clean) } else { iface.ipv6.append(clean) }
                }
            case AF_LINK:
                addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl in
                    let alen = Int(dl.pointee.sdl_alen)
                    if alen == 6 {
                        let nlen = Int(dl.pointee.sdl_nlen)
                        let bytes = withUnsafeBytes(of: dl.pointee.sdl_data) { Array($0) }
                        if nlen + alen <= bytes.count {
                            iface.mac = bytes[nlen..<(nlen + alen)].map { String(format: "%02x", $0) }.joined(separator: ":")
                        }
                    }
                }
                if let data = ifa.ifa_data {
                    iface.mtu = Int(data.assumingMemoryBound(to: if_data.self).pointee.ifi_mtu)
                }
            default: break
            }
            dict[name] = iface
        }

        return order.compactMap { dict[$0] }.filter { iface in
            if iface.kind == .wifi { return true }
            if includeHidden { return !iface.bsdName.hasPrefix("lo") }
            if hiddenPrefixes.contains(where: { iface.bsdName.hasPrefix($0) }) { return false }
            return iface.isUp && iface.hasUsableAddress
        }
    }

    private static func numericHost(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let len = socklen_t(addr.pointee.sa_len)
        guard getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: host)
    }

    /// 64 位收发字节计数（getifaddrs 里的 if_data 是 32 位，4GB 就会回绕）
    static func byteCounters() -> [String: (rx: UInt64, tx: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return [:] }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return [:] }

        var result: [String: (UInt64, UInt64)] = [:]
        buf.withUnsafeBytes { raw in
            var offset = 0
            var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                if Int32(hdr.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= len {
                    let h2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if if_indextoname(UInt32(h2.ifm_index), &nameBuf) != nil {
                        result[String(cString: nameBuf)] = (h2.ifm_data.ifi_ibytes, h2.ifm_data.ifi_obytes)
                    }
                }
                if hdr.ifm_msglen == 0 { break }
                offset += Int(hdr.ifm_msglen)
            }
        }
        return result
    }

    private static let store = SCDynamicStoreCreate(nil, "NetBar" as CFString, nil, nil)

    static func globalState() -> GlobalNetState {
        var state = GlobalNetState()
        guard let store else { return state }
        if let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            state.primaryInterface = ipv4["PrimaryInterface"] as? String
            state.primaryRouter = ipv4["Router"] as? String
        }
        if let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any] {
            state.dns = dns["ServerAddresses"] as? [String] ?? []
        }
        let pattern = "State:/Network/Service/[^/]+/IPv4" as CFString
        if let values = SCDynamicStoreCopyMultiple(store, nil, [pattern] as CFArray) as? [String: Any] {
            for case let dict as [String: Any] in values.values {
                if let ifname = dict["InterfaceName"] as? String, let router = dict["Router"] as? String {
                    state.routers[ifname] = router
                }
            }
        }
        if let p = state.primaryInterface, state.routers[p] == nil, let r = state.primaryRouter {
            state.routers[p] = r
        }
        return state
    }
}

enum Format {
    static func rate(_ bytesPerSec: Double) -> String {
        let units = ["B", "K", "M", "G"]
        var v = max(bytesPerSec, 0)
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1024; i += 1 }
        if i == 0 { return "\(Int(v))B" }
        return v < 10 ? String(format: "%.1f%@", v, units[i]) : String(format: "%.0f%@", v, units[i])
    }

    static func bytes(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .binary)
    }
}
