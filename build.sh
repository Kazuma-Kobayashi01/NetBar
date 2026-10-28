#!/bin/bash
# 构建 NetBar.app（Release：通用二进制 arm64 + x86_64，体积优化并去除符号）
#   ./build.sh            构建到 ./build/NetBar.app
#   ./build.sh install    构建并安装到 /Applications，然后启动
#   ./build.sh dist       构建并打包 dist/NetBar-<版本>.zip 和 .dmg
set -euo pipefail
cd "$(dirname "$0")"

FLAGS=(-c release --arch arm64 --arch x86_64
       -Xswiftc -Osize -Xswiftc -wmo
       -Xlinker -dead_strip)
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/NetBar"

APP="build/NetBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NetBar"
strip -rSTx "$APP/Contents/MacOS/NetBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/NetBar"), $(du -sh "$APP" | cut -f1))"

case "${1:-}" in
install)
    pkill -x NetBar 2>/dev/null || true
    rm -rf /Applications/NetBar.app
    cp -R "$APP" /Applications/
    open /Applications/NetBar.app
    echo "Installed to /Applications/NetBar.app"
    ;;
dist)
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
    mkdir -p dist
    ZIP="dist/NetBar-$VERSION.zip"
    DMG="dist/NetBar-$VERSION.dmg"
    rm -f "$ZIP" "$DMG"
    ditto -c -k --keepParent "$APP" "$ZIP"

    STAGE=$(mktemp -d)
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -quiet -volname "NetBar" -srcfolder "$STAGE" -fs HFS+ -format ULFO "$DMG"
    rm -rf "$STAGE"
    ls -lh "$ZIP" "$DMG"
    ;;
esac
