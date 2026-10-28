#!/bin/bash
# 构建 NetBar.app
#   ./build.sh            构建到 ./build/NetBar.app
#   ./build.sh install    构建并安装到 /Applications，然后启动
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NetBar"

APP="build/NetBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NetBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x NetBar 2>/dev/null || true
    rm -rf /Applications/NetBar.app
    cp -R "$APP" /Applications/
    open /Applications/NetBar.app
    echo "Installed to /Applications/NetBar.app"
fi
