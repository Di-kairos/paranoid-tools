#!/usr/bin/env bash
# Сборка ParanoidBar — нативного menu-bar агента (Фаза B). Command Line Tools достаточно для
# КОМПИЛЯЦИИ; для подписи/нотаризации/дистрибуции нужен Apple Developer аккаунт (см. ../README.md).
#
#   ./build.sh            — собрать исполняемый ./ParanoidBar (запусти его, чтобы увидеть пункт меню)
#   ./build.sh --bundle   — дополнительно собрать ParanoidBar.app (LSUIElement → агент без Dock-иконки)
set -euo pipefail
cd "$(dirname "$0")"

APP="ParanoidBar"
swiftc -O -o "$APP" "$APP.swift"
echo "Built ./$APP"

if [[ "${1:-}" == "--bundle" ]]; then
  BUNDLE="$APP.app"
  rm -rf "$BUNDLE"
  mkdir -p "$BUNDLE/Contents/MacOS"
  cp "$APP" "$BUNDLE/Contents/MacOS/$APP"
  cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ParanoidBar</string>
  <key>CFBundleIdentifier</key><string>com.di-kairos.paranoidbar</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>ParanoidBar</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
  echo "Bundled ./$BUNDLE"
  echo "Distribution: codesign --deep --options runtime --sign \"Developer ID Application: ...\" $BUNDLE"
  echo "             then notarize (xcrun notarytool) + staple. Needs an Apple Developer account."
fi
