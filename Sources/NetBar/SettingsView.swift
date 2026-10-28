import SwiftUI
import AppKit
import Combine

/// 设置窗口（⌘,）
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var observer: AnyCancellable?

    func show(model: NetworkModel) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            host.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
            observer = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.window?.title = L("settings") }
        }
        window?.title = L("settings")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: NetworkModel
    @AppStorage(Prefs.language) private var language = AppLanguage.system.rawValue
    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(model: model)
                .tabItem { Label(L("tab_general"), systemImage: "gearshape") }
                .tag("general")
            MenuBarSettings()
                .tabItem { Label(L("tab_menubar"), systemImage: "menubar.rectangle") }
                .tag("menubar")
            HotspotSettings(model: model)
                .tabItem { Label(L("hotspot"), systemImage: "cellularbars") }
                .tag("hotspot")
            AboutSettings()
                .tabItem { Label(L("tab_about"), systemImage: "info.circle") }
                .tag("about")
        }
        .frame(width: 500)
        .formStyle(.grouped)
        .id(language)
    }
}

// MARK: - 通用

private struct GeneralSettings: View {
    @ObservedObject var model: NetworkModel
    @AppStorage(Prefs.language) private var language = AppLanguage.system.rawValue
    @AppStorage(Prefs.showAllInterfaces) private var showAll = false
    @AppStorage(Prefs.refreshInterval) private var interval = 2.0

    var body: some View {
        Form {
            Section {
            Picker(L("language"), selection: $language) {
                ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0.rawValue) }
            }
            Toggle(L("launch_at_login"), isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            Picker(L("refresh_interval"), selection: $interval) {
                ForEach([1.0, 2.0, 5.0, 10.0], id: \.self) { Text(L("seconds_fmt", Int($0))).tag($0) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle(L("show_all_interfaces"), isOn: $showAll)
                Text(L("show_all_help")).font(.caption).foregroundStyle(.secondary)
            }

            }
            Section {
            LabeledContent(L("location_permission")) {
                HStack {
                    Text(model.locationAuthorized ? L("granted") : L("not_granted"))
                        .foregroundStyle(model.locationAuthorized ? .green : .orange)
                    if !model.locationAuthorized {
                        Button(model.locationUndetermined ? L("authorize") : L("open_location_settings")) {
                            if model.locationUndetermined { model.requestLocation() } else { openSystemURL(SystemURL.location) }
                        }
                    }
                }
            }
            LabeledContent(L("system")) {
                VStack(alignment: .leading, spacing: 6) {
                    Button(L("network_settings")) { openSystemURL(SystemURL.network) }
                    Button(L("hide_system_icon")) { openSystemURL(SystemURL.controlCenter) }
                    Text(L("hide_system_icon_help")).font(.caption).foregroundStyle(.secondary)
                }
            }
            }
        }
    }
}

// MARK: - 菜单栏

private struct MenuBarSettings: View {
    @AppStorage(Prefs.showSpeed) private var showSpeed = false
    @AppStorage(Prefs.showName) private var showName = false
    @AppStorage(Prefs.showTunnelBadge) private var showTunnelBadge = true

    var body: some View {
        Form {
            Section {
                Toggle(L("show_speed"), isOn: $showSpeed)
                Toggle(L("show_name"), isOn: $showName)
                Toggle(L("show_badge"), isOn: $showTunnelBadge)
            }
            Section(L("icon_preview")) {
                HStack(spacing: 0) {
                    preview(.wifi(strength: 1), L("wifi"))
                    preview(.ethernet, L("wired"))
                    preview(.hotspot(strength: 1), L("hotspot"))
                    preview(.wifiOff, L("icon_off"))
                    preview(.offline, L("icon_offline"))
                }
            }
        }
    }

    private func preview(_ state: LinkState, _ title: String) -> some View {
        VStack(spacing: 4) {
            Image(nsImage: StatusIcon.image(for: state, tunnelBadge: false))
                .renderingMode(.template)
                .frame(height: 18)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 热点

private struct HotspotSettings: View {
    @ObservedObject var model: NetworkModel
    @AppStorage(Prefs.autoDetectHotspot) private var autoDetect = true
    @State private var newSSID = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(L("auto_detect"), isOn: $autoDetect)
                    Text(L("auto_detect_help")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section(L("marked_hotspots")) {
            ssidList(model.hotspotSSIDs) { model.hotspotSSIDs.remove($0) }
            HStack {
                TextField("", text: $newSSID, prompt: Text(L("add_ssid_placeholder")))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .onSubmit(add)
                Button(L("add"), action: add).disabled(newSSID.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            }
            if !model.notHotspotSSIDs.isEmpty {
                Section(L("excluded_hotspots")) {
                    ssidList(model.notHotspotSSIDs) { model.notHotspotSSIDs.remove($0) }
                }
            }
        }
    }

    private func add() {
        let s = newSSID.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        model.hotspotSSIDs.insert(s)
        model.notHotspotSSIDs.remove(s)
        newSSID = ""
        model.refresh()
    }

    private func ssidList(_ set: Set<String>, remove: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            if set.isEmpty {
                Text(L("none")).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(set.sorted(), id: \.self) { ssid in
                HStack {
                    Image(systemName: "cellularbars").foregroundStyle(.secondary)
                    Text(ssid)
                    Spacer()
                    Button { remove(ssid); model.refresh() } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help(L("remove"))
                }
                .padding(.vertical, 3)
                if ssid != set.sorted().last { Divider() }
            }
        }
    }
}

// MARK: - 关于

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("NetBar").font(.title2.weight(.semibold))
            Text(L("version_fmt", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"))
                .foregroundStyle(.secondary)
            Text(L("about_desc")).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
