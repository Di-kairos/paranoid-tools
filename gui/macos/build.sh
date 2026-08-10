#!/usr/bin/env bash
# Сборка и дистрибуция ParanoidBar — нативного menu-bar агента (Фаза B).
# Command Line Tools достаточно для КОМПИЛЯЦИИ, ПОДПИСИ (codesign) и НОТАРИЗАЦИИ (notarytool/stapler).
# Для реальной дистрибуции нужен Apple Developer аккаунт (Developer ID Application cert) — см. ../README.md.
#
#   ./build.sh                          — собрать исполняемый ./ParanoidBar
#   ./build.sh --bundle                 — + собрать ParanoidBar.app (LSUIElement → агент без Dock-иконки)
#   ./build.sh --bundle --sign ID       — + подписать .app. ID = "Developer ID Application: Имя (TEAMID)"
#                                         или "-" для ad-hoc подписи (локальный тест механики, НЕ дистрибуция)
#   ./build.sh --bundle --sign ID --notarize PROFILE
#                                       — + нотаризовать через notarytool и застейплить (нужен реальный ID +
#                                         keychain-профиль: `xcrun notarytool store-credentials PROFILE …`)
#   --dmg                               — + собрать ParanoidBar-X.Y.Z.dmg (.app + симлинк на /Applications).
#                                         Образ подписывается тем же ID и нотаризуется отдельным заходом:
#                                         Gatekeeper проверяет САМ dmg при открытии, тикета вложенного
#                                         .app для этого недостаточно.
#   --version X.Y.Z                     — версия бандла (иначе берётся из $VERSION или дефолт ниже)
#
# ПОРЯДОК дистрибуции: --bundle → --sign "Developer ID Application: …" → --notarize <profile>.
# Ad-hoc (--sign -) проходит codesign, но НЕ проходит Gatekeeper и notarytool (нет TeamIdentifier) —
# это дымовой тест пайплайна, не выпуск.
set -euo pipefail
cd "$(dirname "$0")"

APP="ParanoidBar"
BUNDLE="$APP.app"
VERSION="${VERSION:-0.1.0}"

# --- разбор аргументов ---
DO_BUNDLE=0
DO_DMG=0
SIGN_ID=""
NOTARY_PROFILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)   DO_BUNDLE=1; shift ;;
    --dmg)      DO_DMG=1; shift ;;
    --sign)     SIGN_ID="${2:?--sign требует identity (\"Developer ID Application: …\" или \"-\")}"; shift 2 ;;
    --notarize) NOTARY_PROFILE="${2:?--notarize требует имя keychain-профиля notarytool}"; shift 2 ;;
    --version)  VERSION="${2:?--version требует X.Y.Z}"; shift 2 ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
done

# --sign/--notarize/--dmg подразумевают бандл
[[ -n "$SIGN_ID" || -n "$NOTARY_PROFILE" || "$DO_DMG" == "1" ]] && DO_BUNDLE=1
# нотаризация без подписи бессмысленна
if [[ -n "$NOTARY_PROFILE" && -z "$SIGN_ID" ]]; then
  echo "ошибка: --notarize требует --sign с реальным Developer ID (ad-hoc не нотаризуется)" >&2
  exit 2
fi

# --- 1. компиляция ---
swiftc -O -o "$APP" "$APP.swift"
echo "Built ./$APP"
[[ "$DO_BUNDLE" == "0" ]] && exit 0

# --- 2. бандл ---
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$APP" "$BUNDLE/Contents/MacOS/$APP"
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ParanoidBar</string>
  <key>CFBundleIdentifier</key><string>com.di-kairos.paranoidbar</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>ParanoidBar</string>
  <key>NSHumanReadableCopyright</key><string>Di-kairos · MIT</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
echo "Bundled ./$BUNDLE (v$VERSION)"

# --- 3. подпись (опц.) ---
if [[ -z "$SIGN_ID" ]]; then
  echo
  echo "Не подписано. Для дистрибуции:"
  echo "  ./build.sh --bundle --sign \"Developer ID Application: Имя (TEAMID)\" --notarize <profile>"
  echo "  (нужен Apple Developer аккаунт — см. ../README.md)"
else
  # hardened runtime (--options runtime) обязателен для нотаризации
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$BUNDLE"
  codesign --verify --strict --verbose=2 "$BUNDLE"
  if [[ "$SIGN_ID" == "-" ]]; then
    echo "Подписано ad-hoc (дымовой тест механики; НЕ пройдёт Gatekeeper/notarytool)."
  else
    echo "Подписано: $SIGN_ID"

    # --- 4. нотаризация + staple (опц.) ---
    if [[ -z "$NOTARY_PROFILE" ]]; then
      echo "Нотаризация пропущена. Добавь --notarize <profile> для выпуска."
    else
      ZIP="$APP-$VERSION.zip"
      ditto -c -k --keepParent "$BUNDLE" "$ZIP"
      xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
      xcrun stapler staple "$BUNDLE"
      xcrun stapler validate "$BUNDLE"
      spctl --assess --type execute --verbose=4 "$BUNDLE" || true
      rm -f "$ZIP"
      echo "Нотаризовано и застейплено: ./$BUNDLE — готово к дистрибуции."
    fi
  fi
fi

[[ "$DO_DMG" == "0" ]] && exit 0

# --- 5. dmg (опц.) ---
# Образ проверяется Gatekeeper'ом как самостоятельный артефакт: пользователь открывает
# СНАЧАЛА dmg, и тикет вложенного .app на этой стадии ещё не читается. Поэтому dmg
# подписывается и нотаризуется своим заходом, а не наследует статус бандла.
DMG="$APP-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-n-drop: перетащить .app в папку рядом
rm -f "$DMG"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
echo "Собран ./$DMG"

if [[ -z "$SIGN_ID" || "$SIGN_ID" == "-" ]]; then
  echo "dmg НЕ подписан (нет реального Developer ID) — Gatekeeper его отвергнет."
  exit 0
fi
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
echo "dmg подписан: $SIGN_ID"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "dmg не нотаризован. Добавь --notarize <profile> для выпуска."
  exit 0
fi
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
# для dmg проверяется подпись самого образа, а не исполняемость содержимого
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG" || true
echo "Нотаризован и застейплен: ./$DMG — готово к раздаче."
