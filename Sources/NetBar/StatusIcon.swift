import AppKit

/// 菜单栏图标：Wi-Fi / 网线+MacBook / 手机热点 📶
enum StatusIcon {
    private static let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)

    static func image(for state: LinkState, tunnelBadge: Bool) -> NSImage {
        let base: NSImage
        switch state {
        case .wifi(let s):
            base = symbol("wifi", variable: s)
        case .hotspot(let s):
            base = symbol("cellularbars", variable: s)
        case .ethernet:
            base = wiredImage()
        case .wifiOff:
            base = symbol("wifi.slash")
        case .offline:
            base = symbol("wifi.exclamationmark")
        }
        let img = tunnelBadge ? withBadge(base) : base
        img.isTemplate = true
        return img
    }

    static func symbol(_ name: String, variable: Double? = nil, pointSize: CGFloat? = nil) -> NSImage {
        let cfg = pointSize.map { NSImage.SymbolConfiguration(pointSize: $0, weight: .medium) } ?? config
        let img: NSImage?
        if let v = variable {
            img = NSImage(systemSymbolName: name, variableValue: v, accessibilityDescription: name)
        } else {
            img = NSImage(systemSymbolName: name, accessibilityDescription: name)
        }
        return (img?.withSymbolConfiguration(cfg)) ?? NSImage()
    }

    /// 有线：左侧网线插头 + 右侧 MacBook
    static func wiredImage(pointSize: CGFloat = 14) -> NSImage {
        let laptop = symbol("laptopcomputer", pointSize: pointSize)
        let plug = symbol("cable.connector.horizontal", pointSize: pointSize * 0.85)
        let gap: CGFloat = 1
        let size = NSSize(width: plug.size.width + gap + laptop.size.width,
                          height: max(plug.size.height, laptop.size.height))
        let img = NSImage(size: size, flipped: false) { _ in
            let ly = (size.height - laptop.size.height) / 2
            laptop.draw(in: NSRect(x: plug.size.width + gap, y: ly, width: laptop.size.width, height: laptop.size.height))
            // 插头与笔记本键盘底座大致齐平
            let py = ly + laptop.size.height * 0.12
            plug.draw(in: NSRect(x: 0, y: py, width: plug.size.width, height: plug.size.height))
            return true
        }
        img.isTemplate = true
        return img
    }

    /// 存在代理/VPN 隧道时，右上角加一个小圆点
    private static func withBadge(_ base: NSImage) -> NSImage {
        let d: CGFloat = 4.5
        let size = NSSize(width: base.size.width + d * 0.6, height: base.size.height)
        return NSImage(size: size, flipped: false) { _ in
            base.draw(in: NSRect(x: 0, y: 0, width: base.size.width, height: base.size.height))
            let dot = NSRect(x: size.width - d, y: size.height - d, width: d, height: d)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
    }
}
