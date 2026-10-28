import AppKit
import CoreWLAN

/// 仿系统样式的“加入 Wi-Fi 网络”弹窗：
/// 标题说明需要的密码类型，密码框 + 显示密码；企业级网络额外要求用户名。
/// 点“加入”后在弹窗内转圈等待，失败时留在弹窗里显示原因，可直接重试。
final class JoinDialog: NSObject, NSTextFieldDelegate {
    private let net: ScanNetwork
    private let model: NetworkModel
    private let alert = NSAlert()

    private let userField = NSTextField()
    private let secureField = NSSecureTextField()
    private let plainField = NSTextField()
    private let showPassword = NSButton(checkboxWithTitle: L("show_password"), target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var joining = false

    private var joinButton: NSButton { alert.buttons[0] }
    private var cancelButton: NSButton { alert.buttons[1] }
    private var password: String { showPassword.state == .on ? plainField.stringValue : secureField.stringValue }

    /// 显示弹窗，模态直到用户加入成功或取消
    static func present(for net: ScanNetwork, model: NetworkModel, initialError: String? = nil) {
        NotificationCenter.default.post(name: .closePopover, object: nil)
        // 等弹出面板关闭、当前 SwiftUI 事件处理完再进入模态
        DispatchQueue.main.async {
            let dialog = JoinDialog(net: net, model: model)
            if let initialError { dialog.showStatus(initialError, isError: true) }
            dialog.run()
        }
    }

    private init(net: ScanNetwork, model: NetworkModel) {
        self.net = net
        self.model = model
        super.init()
        build()
    }

    private func build() {
        alert.icon = Self.wifiIcon()
        alert.messageText = net.isEnterprise
            ? L("join_title_enterprise_fmt", net.ssid)
            : L("join_title_fmt", net.ssid, WiFiService.securityName(net.security))
        alert.informativeText = ""
        alert.addButton(withTitle: L("join"))
        alert.addButton(withTitle: L("cancel"))
        cancelButton.keyEquivalent = "\u{1b}"
        joinButton.target = self
        joinButton.action = #selector(join)

        for f in [userField, secureField, plainField] {
            f.delegate = self
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 210).isActive = true
        }
        userField.placeholderString = L("username")
        plainField.isHidden = true
        showPassword.target = self
        showPassword.action = #selector(togglePasswordVisibility)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.maximumNumberOfLines = 3
        statusLabel.preferredMaxLayoutWidth = 190
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.widthAnchor.constraint(equalToConstant: 190).isActive = true

        // 密码框与明文框叠放，切换“显示密码”时互换
        let passwordStack = NSView()
        passwordStack.translatesAutoresizingMaskIntoConstraints = false
        for f in [secureField, plainField] {
            passwordStack.addSubview(f)
            NSLayoutConstraint.activate([
                f.leadingAnchor.constraint(equalTo: passwordStack.leadingAnchor),
                f.trailingAnchor.constraint(equalTo: passwordStack.trailingAnchor),
                f.topAnchor.constraint(equalTo: passwordStack.topAnchor),
                f.bottomAnchor.constraint(equalTo: passwordStack.bottomAnchor),
            ])
        }

        let status = NSStackView(views: [spinner, statusLabel])
        status.spacing = 6
        status.alignment = .top

        var rows: [[NSView]] = []
        if net.isEnterprise { rows.append([label(L("username")), userField]) }
        rows.append([label(L("password")), passwordStack])
        rows.append([NSGridCell.emptyContentView, showPassword])
        rows.append([NSGridCell.emptyContentView, status])

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .none
        grid.column(at: 1).xPlacement = .leading
        for r in 0..<grid.numberOfRows { grid.row(at: r).yPlacement = .center }
        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.frame.size = grid.fittingSize
        container.frame.size.height += 4
        alert.accessoryView = container
        updateJoinEnabled()
    }

    /// 调试用：返回布局好的弹窗窗口，不进入模态
    static func debugWindow(for net: ScanNetwork, model: NetworkModel, error: String?) -> NSWindow {
        let d = JoinDialog(net: net, model: model)
        if let error { d.showStatus(error, isError: true) }
        d.alert.layout()
        objc_setAssociatedObject(d.alert.window, "dialog", d, .OBJC_ASSOCIATION_RETAIN)
        return d.alert.window
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s + (AppLanguage.resolved == .en ? ":" : "："))
        l.alignment = .right
        return l
    }

    private func run() {
        alert.layout()
        alert.window.initialFirstResponder = net.isEnterprise ? userField : secureField
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: 交互

    func controlTextDidChange(_ obj: Notification) {
        if let f = obj.object as? NSTextField, f === plainField || f === secureField {
            // 两个框保持同步
            if f === plainField { secureField.stringValue = plainField.stringValue } else { plainField.stringValue = secureField.stringValue }
        }
        if !joining { statusLabel.stringValue = "" }
        updateJoinEnabled()
    }

    @objc private func togglePasswordVisibility() {
        let show = showPassword.state == .on
        plainField.isHidden = !show
        secureField.isHidden = show
        alert.window.makeFirstResponder(show ? plainField : secureField)
        (alert.window.firstResponder as? NSText)?.selectedRange = NSRange(location: password.count, length: 0)
    }

    private func updateJoinEnabled() {
        let p = password
        let ok: Bool
        if net.isEnterprise {
            ok = !userField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty && !p.isEmpty
        } else if net.isWEP {
            ok = [5, 13, 10, 26].contains(p.count)
        } else {
            // WPA 系列：8–63 个字符，或 64 位十六进制
            ok = (8...64).contains(p.count)
        }
        joinButton.isEnabled = ok && !joining
    }

    private func showStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    @objc private func join() {
        guard joinButton.isEnabled else { return }
        setJoining(true)
        showStatus(L("joining"), isError: false)
        let user = net.isEnterprise ? userField.stringValue.trimmingCharacters(in: .whitespaces) : nil
        model.connect(net, username: user, password: password, reportError: false) { [self] error in
            setJoining(false)
            if let error {
                showStatus(L("join_failed_fmt", error.localizedDescription), isError: true)
                alert.window.makeFirstResponder(showPassword.state == .on ? plainField : secureField)
            } else {
                NSApp.stopModal(withCode: .alertFirstButtonReturn)
                alert.window.orderOut(nil)
            }
        }
    }

    private func setJoining(_ on: Bool) {
        joining = on
        on ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        for f in [userField, secureField, plainField] { f.isEnabled = !on }
        showPassword.isEnabled = !on
        updateJoinEnabled()
    }

    // MARK: 图标

    /// 蓝色圆角方块 + 白色 Wi-Fi，接近系统弹窗里的样式
    static func wifiIcon() -> NSImage {
        let size = NSSize(width: 64, height: 64)
        return NSImage(size: size, flipped: false) { rect in
            let body = rect.insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: body, xRadius: 13, yRadius: 13)
            NSGradient(starting: NSColor(calibratedRed: 0.27, green: 0.62, blue: 1.0, alpha: 1),
                       ending: NSColor(calibratedRed: 0.0, green: 0.40, blue: 0.95, alpha: 1))?
                .draw(in: path, angle: -90)
            let cfg = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let g = glyph.size
                glyph.draw(in: NSRect(x: (rect.width - g.width) / 2, y: (rect.height - g.height) / 2, width: g.width, height: g.height))
            }
            return true
        }
    }
}

extension Notification.Name {
    static let closePopover = Notification.Name("NetBarClosePopover")
}
