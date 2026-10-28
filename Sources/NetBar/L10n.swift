import Foundation

/// 界面语言。.system 跟随 macOS 的首选语言
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zhHans = "zh-Hans", zhHant = "zh-Hant", ja

    var id: String { rawValue }

    /// 语言自己的名称（不随界面语言变化）
    var nativeName: String {
        switch self {
        case .system: return L("lang_system")
        case .en: return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja: return "日本語"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: Prefs.language) ?? "") ?? .system
    }

    /// 实际使用的语言（把 .system 解析为具体语言）
    static var resolved: AppLanguage {
        let lang = current
        if lang != .system { return lang }
        for pref in Locale.preferredLanguages {
            let p = pref.lowercased()
            if p.hasPrefix("zh-hant") || p.hasPrefix("zh-tw") || p.hasPrefix("zh-hk") || p.hasPrefix("zh-mo") { return .zhHant }
            if p.hasPrefix("zh") { return .zhHans }
            if p.hasPrefix("ja") { return .ja }
            if p.hasPrefix("en") { return .en }
        }
        return .en
    }

    fileprivate var column: Int {
        switch self {
        case .en, .system: return 0
        case .zhHans: return 1
        case .zhHant: return 2
        case .ja: return 3
        }
    }
}

/// 取本地化字符串；带参数时按 String(format:) 格式化
func L(_ key: String, _ args: CVarArg...) -> String {
    guard let row = L10n.table[key] else { return key }
    let s = row[AppLanguage.resolved.column]
    return args.isEmpty ? s : String(format: s, arguments: args)
}

enum L10n {
    /// key: [English, 简体中文, 繁體中文, 日本語]
    static let table: [String: [String]] = [
        // 通用
        "network": ["Network", "网络", "網路", "ネットワーク"],
        "wifi": ["Wi-Fi", "Wi-Fi", "Wi-Fi", "Wi-Fi"],
        "ethernet": ["Ethernet", "以太网", "乙太網路", "Ethernet"],
        "wired": ["Wired", "有线", "有線", "有線"],
        "hotspot": ["Personal Hotspot", "手机热点", "個人熱點", "インターネット共有"],
        "connected": ["Connected", "已连接", "已連線", "接続済み"],
        "not_connected": ["Not Connected", "未连接", "未連線", "未接続"],
        "wifi_off": ["Wi-Fi Off", "Wi-Fi 已关闭", "Wi-Fi 已關閉", "Wi-Fi オフ"],
        "tunnel_name": ["VPN / Proxy Tunnel", "VPN / 代理隧道", "VPN / 代理通道", "VPN / プロキシトンネル"],
        "copy": ["Copy", "拷贝", "拷貝", "コピー"],
        "copied": ["Copied", "已拷贝", "已拷貝", "コピーしました"],
        "click_to_copy": ["Click to copy", "点击拷贝", "按一下拷貝", "クリックでコピー"],
        "cancel": ["Cancel", "取消", "取消", "キャンセル"],
        "none": ["None", "无", "無", "なし"],
        "unknown": ["Unknown", "未知", "未知", "不明"],

        // 当前连接
        "current_connection": ["Current Connection", "当前连接", "目前連線", "現在の接続"],
        "connected_need_location": ["Connected (Location access needed for name)", "已连接（需定位权限显示名称）", "已連線（需定位權限顯示名稱）", "接続済み（名前の表示には位置情報が必要）"],
        "wifi_off_hint": ["Turn on Wi-Fi or plug in a cable to get online", "打开 Wi-Fi 或插入网线以联网", "開啟 Wi-Fi 或插入網路線以連線", "Wi-Fi をオンにするかケーブルを接続してください"],
        "offline_hint": ["No network connection available", "没有可用的网络连接", "沒有可用的網路連線", "利用可能なネットワーク接続がありません"],
        "ssid_label": ["Network Name", "网络名称", "網路名稱", "ネットワーク名"],
        "signal_noise": ["Signal / Noise", "信号 / 噪声", "訊號 / 雜訊", "信号 / ノイズ"],
        "channel": ["Channel", "信道", "頻道", "チャンネル"],
        "protocol": ["Protocol", "协议", "協定", "規格"],
        "tx_rate": ["Tx Rate", "协商速率", "傳輸速率", "転送レート"],
        "security": ["Security", "安全性", "安全性", "セキュリティ"],
        "country": ["Country Code", "国家码", "國家代碼", "国コード"],
        "interface": ["Interface", "接口", "介面", "インターフェイス"],
        "netmask": ["Subnet Mask", "子网掩码", "子網路遮罩", "サブネットマスク"],
        "router": ["Router", "路由器", "路由器", "ルーター"],
        "mac": ["MAC Address", "MAC 地址", "MAC 位址", "MAC アドレス"],
        "default_route": ["Default Route", "默认路由", "預設路由", "デフォルトルート"],
        "via_tunnel": [" (via proxy/VPN)", "（经代理/VPN）", "（經代理/VPN）", "（プロキシ/VPN 経由）"],

        // 热点
        "this_is_hotspot": ["This is a phone hotspot", "这是手机热点", "這是手機熱點", "これはスマホのテザリング"],
        "hotspot_need_ssid": ["Location access is needed to read the Wi-Fi name before marking", "需要定位权限读取 Wi-Fi 名称后才能标记", "需要定位權限讀取 Wi-Fi 名稱後才能標記", "マークするには位置情報で Wi-Fi 名を読み取る必要があります"],
        "hotspot_auto_fmt": ["Auto-detected: %@", "已自动识别：%@", "已自動識別：%@", "自動検出：%@"],
        "reason_router_fmt": ["gateway %@ (%@)", "网关 %@（%@）", "閘道 %@（%@）", "ゲートウェイ %@（%@）"],
        "iphone_gateway": ["iPhone hotspot gateway", "iPhone 热点网关", "iPhone 熱點閘道", "iPhone テザリングのゲートウェイ"],
        "android_gateway": ["Android hotspot gateway", "安卓热点网关", "Android 熱點閘道", "Android テザリングのゲートウェイ"],
        "reason_name_fmt": ["name contains “%@”", "网络名称包含 “%@”", "網路名稱包含「%@」", "名前に「%@」を含む"],

        // 网卡
        "interfaces": ["Interfaces", "网络接口", "網路介面", "インターフェイス"],
        "badge_physical": ["Physical Link", "物理链路", "實體連結", "物理リンク"],
        "no_ip": ["No IP address", "无 IP 地址", "無 IP 位址", "IP アドレスなし"],
        "status": ["Status", "状态", "狀態", "状態"],
        "status_up_running": ["Up · Running", "已启用 · 运行中", "已啟用 · 執行中", "有効 · 動作中"],
        "status_up": ["Up", "已启用", "已啟用", "有効"],
        "status_down": ["Down", "已停用", "已停用", "無効"],
        "link_local": ["Link-Local", "链路本地", "鏈路本機", "リンクローカル"],
        "total_traffic": ["Total Traffic", "累计流量", "累計流量", "累計通信量"],

        // 附近网络
        "nearby": ["Nearby Wi-Fi", "附近的 Wi-Fi", "附近的 Wi-Fi", "近くの Wi-Fi"],
        "rescan": ["Rescan", "重新扫描", "重新掃描", "再スキャン"],
        "scan_failed_fmt": ["Scan failed: %@", "扫描失败：%@", "掃描失敗：%@", "スキャン失敗：%@"],
        "scanning": ["Scanning…", "正在扫描…", "正在掃描…", "スキャン中…"],
        "no_networks": ["No networks found", "未发现网络", "未發現網路", "ネットワークが見つかりません"],
        "need_location_list": ["Location access is needed to show network names", "需要定位权限才能显示网络名称", "需要定位權限才能顯示網路名稱", "ネットワーク名の表示には位置情報が必要です"],
        "mark_hotspot": ["Mark as Phone Hotspot", "标记为手机热点", "標記為手機熱點", "テザリングとしてマーク"],
        "unmark_hotspot": ["Unmark Phone Hotspot", "取消手机热点标记", "取消手機熱點標記", "テザリングのマークを解除"],
        "disconnect": ["Disconnect", "断开连接", "中斷連線", "接続解除"],
        "copy_ssid": ["Copy Network Name", "拷贝网络名称", "拷貝網路名稱", "ネットワーク名をコピー"],
        "password": ["Password", "密码", "密碼", "パスワード"],
        "join": ["Join", "加入", "加入", "接続"],

        // 底栏
        "querying": ["Querying…", "查询中…", "查詢中…", "照会中…"],
        "public_ip_fmt": ["Public IP: %@", "公网 IP：%@", "公用 IP：%@", "グローバル IP：%@"],
        "query_public_ip": ["Check Public IP", "查询公网 IP", "查詢公用 IP", "グローバル IP を確認"],
        "public_ip_help": ["Queries api.ipify.org (with a proxy on, this is the proxy exit IP). Right-click to copy.", "通过 api.ipify.org 查询出口 IP（开启代理时即为代理出口）；右键拷贝", "透過 api.ipify.org 查詢出口 IP（開啟代理時即為代理出口）；按右鍵拷貝", "api.ipify.org で出口 IP を照会（プロキシ使用時はプロキシの出口）。右クリックでコピー"],
        "query_failed": ["Failed", "查询失败", "查詢失敗", "失敗"],
        "settings_ellipsis": ["Settings…", "设置…", "設定⋯", "設定…"],
        "quit": ["Quit NetBar", "退出 NetBar", "結束 NetBar", "NetBar を終了"],

        // 横幅 / 错误
        "location_banner": ["macOS requires Location access to read the Wi-Fi name and scan networks. NetBar never uses your location.", "macOS 需要定位权限才能读取 Wi-Fi 名称和扫描网络。NetBar 不会使用你的位置。", "macOS 需要定位權限才能讀取 Wi-Fi 名稱和掃描網路。NetBar 不會使用你的位置。", "Wi-Fi 名の取得とスキャンには位置情報の許可が必要です。NetBar が位置情報を使うことはありません。"],
        "authorize": ["Allow", "授权", "授權", "許可"],
        "open_location_settings": ["Open Location Settings", "打开定位权限设置", "打開定位權限設定", "位置情報の設定を開く"],
        "connect_failed_fmt": ["Couldn’t join “%@”: %@", "连接“%@”失败：%@", "連線「%@」失敗：%@", "「%@」に接続できません：%@"],
        "login_failed_fmt": ["Couldn’t change Launch at Login: %@ (move NetBar to Applications first)", "设置开机启动失败：%@（请先把 NetBar 放到“应用程序”文件夹）", "設定登入時開啟失敗：%@（請先將 NetBar 放到「應用程式」檔案夾）", "ログイン時に起動を設定できません：%@（先に NetBar をアプリケーションへ移動してください）"],
        "no_wifi_card": ["No Wi-Fi interface found", "未找到 Wi-Fi 网卡", "找不到 Wi-Fi 網卡", "Wi-Fi インターフェイスが見つかりません"],

        // 菜单栏提示
        "tip_wifi_fmt": ["Wi-Fi: %@", "Wi-Fi：%@", "Wi-Fi：%@", "Wi-Fi：%@"],
        "tip_hotspot_fmt": ["Phone hotspot: %@", "手机热点：%@", "手機熱點：%@", "テザリング：%@"],
        "tip_ethernet": ["Wired network", "有线网络", "有線網路", "有線ネットワーク"],
        "tip_offline": ["No network", "未连接网络", "未連線網路", "ネットワーク未接続"],

        // 安全性 / 协议
        "sec_open": ["None (open)", "无（开放网络）", "無（開放網路）", "なし（オープン）"],
        "sec_personal": ["Personal", "个人级", "個人級", "パーソナル"],
        "sec_enterprise": ["Enterprise", "企业级", "企業級", "エンタープライズ"],
        "sec_dynamic_wep": ["Dynamic WEP", "动态 WEP", "動態 WEP", "ダイナミック WEP"],
        "sec_owe": ["Enhanced Open (OWE)", "OWE 增强开放", "OWE 增強開放", "拡張オープン (OWE)"],
        "sec_owe_transition": ["OWE Transition", "OWE 过渡", "OWE 過渡", "OWE トランジション"],

        // 设置窗口
        "settings": ["Settings", "设置", "設定", "設定"],
        "tab_general": ["General", "通用", "一般", "一般"],
        "tab_menubar": ["Menu Bar", "菜单栏", "選單列", "メニューバー"],
        "tab_about": ["About", "关于", "關於", "情報"],
        "language": ["Language", "语言", "語言", "言語"],
        "lang_system": ["System Default", "跟随系统", "跟隨系統", "システムに従う"],
        "launch_at_login": ["Launch at Login", "开机启动", "登入時開啟", "ログイン時に起動"],
        "show_all_interfaces": ["Show All Interfaces", "显示所有网络接口", "顯示所有網路介面", "すべてのインターフェイスを表示"],
        "show_all_help": ["Includes disconnected and internal system interfaces", "包括未连接的网卡和系统内部接口", "包括未連線的網卡和系統內部介面", "未接続やシステム内部のインターフェイスも含む"],
        "refresh_interval": ["Refresh Interval", "刷新间隔", "重新整理間隔", "更新間隔"],
        "seconds_fmt": ["%d s", "%d 秒", "%d 秒", "%d 秒"],
        "show_speed": ["Show Network Speed", "显示网速", "顯示網速", "通信速度を表示"],
        "show_name": ["Show Network Name", "显示网络名称", "顯示網路名稱", "ネットワーク名を表示"],
        "show_badge": ["Show Dot When Proxy / VPN Is Active", "代理 / VPN 启用时图标显示圆点", "代理 / VPN 啟用時圖示顯示圓點", "プロキシ / VPN 使用中はドットを表示"],
        "icon_preview": ["Icons", "图标", "圖示", "アイコン"],
        "icon_off": ["Off", "关闭", "關閉", "オフ"],
        "icon_offline": ["Offline", "离线", "離線", "オフライン"],
        "auto_detect": ["Auto-Detect Phone Hotspots", "自动识别手机热点", "自動識別手機熱點", "テザリングを自動検出"],
        "auto_detect_help": ["Gateway 172.20.10.1 / 192.168.43.1, or a name containing iPhone, Galaxy, Redmi, etc.", "网关为 172.20.10.1 / 192.168.43.1，或网络名称包含 iPhone、Galaxy、Redmi 等关键词", "閘道為 172.20.10.1 / 192.168.43.1，或網路名稱包含 iPhone、Galaxy、Redmi 等關鍵字", "ゲートウェイが 172.20.10.1 / 192.168.43.1、または名前に iPhone・Galaxy・Redmi などを含む"],
        "marked_hotspots": ["Networks Marked as Hotspots", "已标记为热点的网络", "已標記為熱點的網路", "テザリングとしてマークしたネットワーク"],
        "excluded_hotspots": ["Excluded from Auto-Detection", "已排除自动识别的网络", "已排除自動識別的網路", "自動検出から除外したネットワーク"],
        "add_ssid_placeholder": ["Network name", "输入网络名称", "輸入網路名稱", "ネットワーク名"],
        "add": ["Add", "添加", "加入", "追加"],
        "remove": ["Remove", "移除", "移除", "削除"],
        "system": ["System", "系统", "系統", "システム"],
        "location_permission": ["Location Access", "定位权限", "定位權限", "位置情報"],
        "granted": ["Allowed", "已授权", "已授權", "許可済み"],
        "not_granted": ["Not Allowed", "未授权", "未授權", "未許可"],
        "network_settings": ["Network Settings…", "网络设置…", "網路設定⋯", "ネットワーク設定…"],
        "hide_system_icon": ["Hide System Wi-Fi Icon…", "隐藏系统自带 Wi-Fi 图标…", "隱藏系統內建 Wi-Fi 圖示⋯", "システムの Wi-Fi アイコンを隠す…"],
        "hide_system_icon_help": ["System Settings → Control Center → Wi-Fi → Don’t Show in Menu Bar", "系统设置 → 控制中心 → Wi-Fi → 不在菜单栏中显示", "系統設定 → 控制中心 → Wi-Fi → 不要在選單列中顯示", "システム設定 → コントロールセンター → Wi-Fi → メニューバーに表示しない"],
        "version_fmt": ["Version %@", "版本 %@", "版本 %@", "バージョン %@"],
        "about_desc": ["A network status menu for macOS that replaces the built-in Wi-Fi icon.", "替代 macOS 自带 Wi-Fi 图标的网络状态工具。", "取代 macOS 內建 Wi-Fi 圖示的網路狀態工具。", "macOS 標準の Wi-Fi アイコンを置き換えるネットワーク状態ツール。"],

        // 主菜单
        "menu_edit": ["Edit", "编辑", "編輯", "編集"],
        "menu_cut": ["Cut", "剪切", "剪下", "カット"],
        "menu_paste": ["Paste", "粘贴", "貼上", "ペースト"],
        "menu_select_all": ["Select All", "全选", "全選", "すべてを選択"],
        "menu_close": ["Close Window", "关闭窗口", "關閉視窗", "ウインドウを閉じる"],
    ]
}
