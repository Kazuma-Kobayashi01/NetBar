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
        return (img?.withSymbolConfiguration(cfg.applying(.preferringMonochrome()))) ?? NSImage()
    }

    /// 有线：左侧竖直网线插头 + 右侧 MacBook
    static func wiredImage(pointSize: CGFloat = 14) -> NSImage {
        let laptop = symbol("laptopcomputer", pointSize: pointSize)
        let rawPlug = symbol("cable.connector", pointSize: pointSize)
        // 插头缩放到比笔记本略高、垂直居中，整体宽度只比笔记本多一点
        let plugH = laptop.size.height * 1.35
        let plugW = rawPlug.size.width * plugH / max(rawPlug.size.height, 1)
        let gap: CGFloat = 0  // 两个符号自带左右留白
        let size = NSSize(width: plugW + gap + laptop.size.width, height: max(plugH, laptop.size.height))
        let img = NSImage(size: size, flipped: false) { _ in
            let ly = (size.height - laptop.size.height) / 2
            laptop.draw(in: NSRect(x: plugW + gap, y: ly, width: laptop.size.width, height: laptop.size.height))
            rawPlug.draw(in: NSRect(x: 0, y: (size.height - plugH) / 2, width: plugW, height: plugH))
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
