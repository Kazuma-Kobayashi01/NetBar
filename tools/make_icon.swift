// 生成 Resources/AppIcon.icns
//   swift tools/make_icon.swift [preview.png]
// 设计：蓝色渐变圆角方块（macOS 图标网格 824/1024），中间是白色 Wi-Fi，
// 底部一条白色“菜单栏”胶囊，里面是 NetBar 的三种图标：Wi-Fi / 网线+MacBook / 热点信号格
import AppKit

let canvas: CGFloat = 1024

func symbol(_ name: String, _ size: CGFloat, _ color: NSColor, weight: NSFont.Weight = .semibold) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
}

func drawCentered(_ img: NSImage, cx: CGFloat, cy: CGFloat, height: CGFloat? = nil) {
    var s = img.size
    if let h = height { s = NSSize(width: s.width * h / s.height, height: h) }
    img.draw(in: NSRect(x: cx - s.width / 2, y: cy - s.height / 2, width: s.width, height: s.height))
}

func drawIcon() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 185
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // 阴影
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 渐变底色
    NSGradient(colors: [
        NSColor(srgbRed: 0.33, green: 0.72, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.45, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.27, blue: 0.86, alpha: 1),
    ], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: path, angle: -90)

    // 顶部高光
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 主图形：Wi-Fi
    let wifi = symbol("wifi", 400, .white, weight: .bold)
    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor(srgbRed: 0.05, green: 0.15, blue: 0.5, alpha: 0.35)
    glyphShadow.shadowBlurRadius = 18
    glyphShadow.shadowOffset = NSSize(width: 0, height: -8)
    glyphShadow.set()
    drawCentered(wifi, cx: 512, cy: 590, height: 330)
    NSGraphicsContext.restoreGraphicsState()

    // 底部“菜单栏”胶囊
    let pill = NSRect(x: 232, y: 196, width: 560, height: 132)
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 66, yRadius: 66).fill()

    let ink = NSColor(srgbRed: 0.10, green: 0.38, blue: 0.92, alpha: 1)
    let y = pill.midY
    drawCentered(symbol("wifi", 60, ink), cx: pill.minX + 105, cy: y, height: 58)

    // 竖直网线 + MacBook
    let plug = symbol("cable.connector", 60, ink)
    let laptop = symbol("laptopcomputer", 60, ink)
    let lh: CGFloat = 52, ph: CGFloat = 70
    let lw = laptop.size.width * lh / laptop.size.height
    let pw = plug.size.width * ph / plug.size.height
    let total = pw + lw
    let x0 = pill.midX - total / 2
    plug.draw(in: NSRect(x: x0, y: y - ph / 2, width: pw, height: ph))
    laptop.draw(in: NSRect(x: x0 + pw, y: y - lh / 2, width: lw, height: lh))

    drawCentered(symbol("cellularbars", 60, ink), cx: pill.maxX - 105, cy: y, height: 54)
}

func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(px: base * scale).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")

if CommandLine.arguments.count > 1 {
    try! render(px: 512).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
