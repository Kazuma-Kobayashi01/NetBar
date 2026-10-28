# NetBar

替代 macOS 自带 Wi-Fi 菜单栏图标的网络状态工具（Swift / AppKit + SwiftUI，macOS 13+）。

## 功能

- **三种图标**，按实际承载流量的网卡自动切换：
  - Wi-Fi（随信号强度变化）
  - 网线 + MacBook（有线网卡）
  - 📶 手机热点（随信号强度变化）
  - 另有 Wi-Fi 关闭 / 无网络状态；开启代理 TUN / VPN 时可在图标右上角显示小圆点
- **手机热点标记**：在“当前连接”里打开“这是手机热点”，或在附近网络上右键标记。
  也可以自动识别：网关是 172.20.10.1（iPhone）或 192.168.43.1（常见安卓），或网络名包含 iPhone / Galaxy / Redmi / HUAWEI 等关键词。手动标记优先于自动识别。
- **详细信息**：SSID、BSSID、RSSI / 噪声 / SNR、信道 / 频段 / 带宽、Wi-Fi 协议、协商速率、安全性、IPv4 / IPv6、子网掩码、路由器、DNS、MAC、MTU、实时速率、累计流量。点击任一行即可拷贝。
- **连接 Wi-Fi**：扫描附近网络，点击即可连接（已保存的网络无需密码），也可以打开 / 关闭 Wi-Fi、断开连接。
- **多网卡显示**：Wi-Fi、USB / 雷雳网卡、网桥，以及代理软件的 `utun`（Clash、Surge 等的 TUN 模式），并标出“默认路由”和“物理链路”。只有链路本地地址的系统 utun 默认隐藏。
- **设置窗口**（面板右下角齿轮，或 ⌘,）：
  - 通用：界面语言、开机启动、刷新间隔、显示所有接口、定位权限状态，以及跳转到系统设置
  - 菜单栏：显示网速 / 网络名称 / 代理圆点，并预览所有图标
  - 手机热点：自动识别开关，以及管理已标记的热点和排除列表（可手动添加网络名）
- **多语言**：English、简体中文、繁體中文、日本語。默认跟随系统，也可以在设置里切换，切换后立即生效。
- 手动查询公网 IP（开启代理时就是出口 IP）。

## 构建与安装

```bash
./build.sh install
```

这条命令会构建、做 ad-hoc 签名、复制到 `/Applications/NetBar.app` 并启动。只运行 `./build.sh` 则只构建到 `build/NetBar.app`。

首次启动时请**允许定位权限**：从 macOS 14 起，必须有定位权限才能读取 Wi-Fi 名称和扫描附近网络。NetBar 不会读取你的位置。

### 隐藏系统自带的 Wi-Fi 图标

打开系统设置 → 控制中心 → Wi-Fi → “不在菜单栏中显示”。也可以在 NetBar 的齿轮菜单里选“隐藏系统自带 Wi-Fi 图标…”直接跳转到这个页面。

## 调试

```bash
build/NetBar.app/Contents/MacOS/NetBar --dump               # 在终端打印识别到的网络状态
build/NetBar.app/Contents/MacOS/NetBar --snapshot out.png   # 把面板离屏渲染成 PNG
build/NetBar.app/Contents/MacOS/NetBar --snapshot s.png --settings -language ja -settingsTab hotspot  # 渲染设置页（临时指定语言和标签页）
```
