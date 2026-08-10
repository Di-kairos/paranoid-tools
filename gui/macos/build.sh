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
#   --dmg                               — + собрать ParanoidBar-X.Y.Z.dmg (.app + симлинк на /Applications,
#                                         фон со стрелкой, иконки 128px, фиксированное окно).
#                                         Образ подписывается тем же ID и нотаризуется отдельным заходом:
#                                         Gatekeeper проверяет САМ dmg при открытии, тикета вложенного
#                                         .app для этого недостаточно.
#                                         Раскладку пишет Finder через Automation — в headless-сессии
#                                         (CI/ssh) шаг отваливается с предупреждением, образ остаётся валиден.
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
BACKGROUND="dmg-background.tiff"   # 640×400 @1x+@2x, фон окна образа

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
# Том снимается и по аварийному выходу: иначе оборванная сборка (в т.ч. Ctrl-C на запросе
# Automation) оставит смонтированный RW-образ висеть в /Volumes.
MOUNTED=""
cleanup() {
  [[ -n "$MOUNTED" ]] && hdiutil detach "$MOUNTED" -force -quiet 2>/dev/null
  rm -rf "$STAGE" "$STAGE.rw.dmg"
  return 0
}
trap cleanup EXIT

cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-n-drop: перетащить .app в папку рядом
mkdir "$STAGE/.background"
cp "$BACKGROUND" "$STAGE/.background/"

# Раскладку окна хранит .DS_Store тома, а его умеет писать только Finder — поэтому
# образ собирается сначала записываемым (UDRW), монтируется, оформляется и лишь затем
# сжимается в UDZO. Готовый UDZO read-only, задним числом оформить его нельзя.
RW="$STAGE.rw.dmg"
MNT="/Volumes/$APP"
# Finder адресуется к тому по ИМЕНИ (disk "ParanoidBar"), поэтому второй том с тем же именем
# делает раскладку неоднозначной, а слепой detach снял бы чужой образ или соседнюю сборку.
# Fail-closed: просим освободить имя, ничего не размонтируя сами.
if [[ -e "$MNT" ]]; then
  echo "ошибка: том $MNT уже смонтирован (чужой образ или прошлая сборка) — отмонтируй его" >&2
  exit 1
fi
rm -f "$RW"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDRW -quiet "$RW"
hdiutil attach "$RW" -quiet
MOUNTED="$MNT"

# Finder управляется через Automation — на первом запуске система спросит разрешение,
# в headless-сессии (CI, ssh) откажет. Оформление косметическое: не вышло — образ
# всё равно валиден, просто откроется дефолтным списком.
if osascript >/dev/null <<APPLESCRIPT
  tell application "Finder"
    tell disk "$APP"
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {200, 120, 840, 520}
      set opts to the icon view options of container window
      set arrangement of opts to not arranged
      set icon size of opts to 128
      set text size of opts to 12
      set background picture of opts to file ".background:$(basename "$BACKGROUND")"
      set position of item "$BUNDLE" of container window to {160, 190}
      set position of item "Applications" of container window to {480, 190}
      update without registering applications
      delay 1
      close
    end tell
  end tell
APPLESCRIPT
then
  echo "Окно образа оформлено (фон, иконки 128, drag-n-drop)."
else
  echo "⚠ Finder не дал оформить окно (нет Automation-доступа?) — образ собран без раскладки." >&2
fi

rm -rf "$MNT/.fseventsd"   # журнал FS-событий тома незачем раздавать вместе с образом
sync
# Finder ещё держит том сразу после записи .DS_Store — вторая попытка с -force
hdiutil detach "$MNT" -quiet || { sleep 2; hdiutil detach "$MNT" -force -quiet; }
MOUNTED=""
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -o "$DMG" -quiet
rm -f "$RW"
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
