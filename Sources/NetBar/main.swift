import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = NetworkModel()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeft

        popover.behavior = .transient
        popover.animates = false
        let host = NSHostingController(rootView: PopoverView(model: model))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.updateButton() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
        updateButton()
        buildMainMenu()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .map { _ in AppLanguage.resolved }
            .removeDuplicates()
            .sink { [weak self] _ in self?.buildMainMenu() }
            .store(in: &cancellables)
    }

    /// 菜单栏应用没有可见的主菜单，但 ⌘, / ⌘Q / ⌘W 和编辑快捷键（粘贴密码等）仍然通过它分发
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("settings_ellipsis"), action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("menu_close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: L("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("menu_edit"))
        editMenu.addItem(withTitle: L("menu_cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("menu_paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("menu_select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc func openSettings() {
        popover.performClose(nil)
        SettingsWindowController.shared.show(model: model)
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let d = UserDefaults.standard
        let badge = d.bool(forKey: Prefs.showTunnelBadge) && model.hasActiveTunnel
        button.image = StatusIcon.image(for: model.linkState, tunnelBadge: badge)

        var parts: [String] = []
        if d.bool(forKey: Prefs.showName) {
            switch model.linkState {
            case .wifi, .hotspot: if let s = model.wifi?.ssid { parts.append(s) }
            case .ethernet: parts.append(L("wired"))
            default: break
            }
        }
        if d.bool(forKey: Prefs.showSpeed), let a = model.activeInterface, let r = model.rates[a] {
            parts.append("↓\(Format.rate(r.rx)) ↑\(Format.rate(r.tx))")
        }
        if parts.isEmpty {
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
        } else {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            button.attributedTitle = NSAttributedString(string: " " + parts.joined(separator: "  "), attributes: [.font: font])
            button.imagePosition = .imageLeft
        }
        button.toolTip = tooltip()
    }

    private func tooltip() -> String {
        switch model.linkState {
        case .wifi: return L("tip_wifi_fmt", model.wifi?.ssid ?? L("connected"))
        case .hotspot: return L("tip_hotspot_fmt", model.wifi?.ssid ?? L("connected"))
        case .ethernet: return L("tip_ethernet")
        case .wifiOff: return L("wifi_off")
        case .offline: return L("tip_offline")
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            model.scan()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

Prefs.registerDefaults()

// 调试：NetBar --dump 打印当前识别到的网络状态后退出
if CommandLine.arguments.contains("--dump") {
    let m = NetworkModel()
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    m.refresh()
    print("linkState:", m.linkState, "active:", m.activeInterface ?? "-", "hotspot:", m.isHotspot)
    print("global:", m.global)
    print("wifi:", m.wifi.map { "\($0)" } ?? "-")
    print("location authorized:", m.locationAuthorized, "hotspot reason:", m.hotspotAutoReason ?? "-")
    m.scan()
    for _ in 0..<40 where m.scanning || m.scanResults.isEmpty { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    print("scan:", m.scanResults.map { "\($0.ssid)(\($0.rssi)\($0.known ? ",known" : ""))" }, m.scanError ?? "")
    for i in m.interfaces {
        print(" -", i.bsdName, i.displayName, i.kind, i.ipv4, i.ipv6, i.mac ?? "", m.rates[i.bsdName].map { "rx \(Format.rate($0.rx)) tx \(Format.rate($0.tx))" } ?? "")
    }
    exit(0)
}

// 调试：NetBar --snapshot out.png 把弹出面板离屏渲染成图片
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    let m = NetworkModel()
    let deadline = Date().addingTimeInterval(4)
    m.scan()
    while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    m.refresh()
    let host: NSView = CommandLine.arguments.contains("--settings")
        ? NSHostingView(rootView: SettingsView(model: m))
        : NSHostingView(rootView: PopoverView(model: m))
    let size = host.fittingSize
    let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
    win.backgroundColor = .windowBackgroundColor
    win.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    let icons: [LinkState] = [.wifi(strength: 1), .wifi(strength: 0.5), .hotspot(strength: 0.75), .ethernet, .wifiOff, .offline]
    let strip = NSImage(size: NSSize(width: 40 * icons.count, height: 28), flipped: false) { _ in
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 40 * icons.count, height: 28).fill()
        for (k, st) in icons.enumerated() {
            let img = StatusIcon.image(for: st, tunnelBadge: k == 0)
            img.draw(in: NSRect(x: CGFloat(k) * 40 + (40 - img.size.width) / 2, y: (28 - img.size.height) / 2, width: img.size.width, height: img.size.height))
        }
        return true
    }
    let iconsURL = URL(fileURLWithPath: CommandLine.arguments[i + 1]).deletingPathExtension().appendingPathExtension("icons.png")
    let tiff = strip.tiffRepresentation!
    try! NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!.write(to: iconsURL)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
