#!/usr/bin/env bash
# Build and distribution of ParanoidBar — the native menu-bar agent (Phase B).
# Command Line Tools suffice for COMPILING, SIGNING (codesign) and NOTARIZATION (notarytool/stapler).
# Real distribution requires an Apple Developer account (Developer ID Application cert) — see ../README.md.
#
#   ./build.sh                          — build the executable ./ParanoidBar
#   ./build.sh --bundle                 — + build ParanoidBar.app (LSUIElement → agent with no Dock icon)
#   ./build.sh --bundle --sign ID       — + sign the .app. ID = "Developer ID Application: Name (TEAMID)"
#                                         or "-" for an ad-hoc signature (local mechanics test, NOT distribution)
#   ./build.sh --bundle --sign ID --notarize PROFILE
#                                       — + notarize via notarytool and staple (needs a real ID + a notarytool
#                                         keychain profile: `xcrun notarytool store-credentials PROFILE …`)
#   --dmg                               — + build ParanoidBar-X.Y.Z.dmg (.app + a symlink to /Applications,
#                                         background with an arrow, 128px icons, fixed window frame).
#                                         The image is signed with the same ID and notarized in a separate
#                                         pass: Gatekeeper checks the dmg ITSELF on open; the embedded
#                                         .app's ticket is not enough for that.
#                                         The layout is written by Finder via Automation — in a headless
#                                         session (CI/ssh) that step bails with a warning, the image stays valid.
#   --version X.Y.Z                     — bundle version (otherwise taken from $VERSION or the default below)
#
# Distribution ORDER: --bundle → --sign "Developer ID Application: …" → --notarize <profile>.
# Ad-hoc (--sign -) passes codesign but does NOT pass Gatekeeper or notarytool (no TeamIdentifier) —
# it is a pipeline smoke test, not a release.
set -euo pipefail
cd "$(dirname "$0")"

APP="ParanoidBar"
BUNDLE="$APP.app"
VERSION="${VERSION:-0.1.0}"
BACKGROUND="dmg-background.tiff"   # 640×400 @1x+@2x, image window background
ICON="ParanoidBar.icns"            # mark from assets/logo.svg, 16…1024 (@1x+@2x)

# --- argument parsing ---
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

# --sign/--notarize/--dmg imply the bundle
[[ -n "$SIGN_ID" || -n "$NOTARY_PROFILE" || "$DO_DMG" == "1" ]] && DO_BUNDLE=1
# notarization without signing is meaningless
if [[ -n "$NOTARY_PROFILE" && -z "$SIGN_ID" ]]; then
  echo "ошибка: --notarize требует --sign с реальным Developer ID (ad-hoc не нотаризуется)" >&2
  exit 2
fi

# --- 1. compilation ---
swiftc -O -o "$APP" "$APP.swift"
echo "Built ./$APP"
[[ "$DO_BUNDLE" == "0" ]] && exit 0

# --- 2. bundle ---
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$APP" "$BUNDLE/Contents/MacOS/$APP"
cp "$ICON" "$BUNDLE/Contents/Resources/$ICON"
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
  <key>CFBundleIconFile</key><string>${ICON}</string>
  <key>NSHumanReadableCopyright</key><string>Di-kairos · MIT</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
echo "Bundled ./$BUNDLE (v$VERSION)"

# --- 3. signing (opt.) ---
if [[ -z "$SIGN_ID" ]]; then
  echo
  echo "Не подписано. Для дистрибуции:"
  echo "  ./build.sh --bundle --sign \"Developer ID Application: Имя (TEAMID)\" --notarize <profile>"
  echo "  (нужен Apple Developer аккаунт — см. ../README.md)"
else
  # hardened runtime (--options runtime) is mandatory for notarization
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$BUNDLE"
  codesign --verify --strict --verbose=2 "$BUNDLE"
  if [[ "$SIGN_ID" == "-" ]]; then
    echo "Подписано ad-hoc (дымовой тест механики; НЕ пройдёт Gatekeeper/notarytool)."
  else
    echo "Подписано: $SIGN_ID"

    # --- 4. notarization + staple (opt.) ---
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

# --- 5. dmg (opt.) ---
# Gatekeeper checks the image as a standalone artifact: the user opens the dmg
# FIRST, and the embedded .app's ticket is not read at that stage yet. Hence the dmg
# is signed and notarized in its own pass rather than inheriting the bundle's status.
DMG="$APP-$VERSION.dmg"
STAGE="$(mktemp -d)"
# The volume is detached on abnormal exit too: otherwise an interrupted build (incl.
# Ctrl-C at the Automation prompt) would leave the mounted RW image hanging in /Volumes.
MOUNTED=""
cleanup() {
  [[ -n "$MOUNTED" ]] && hdiutil detach "$MOUNTED" -force -quiet 2>/dev/null
  rm -rf "$STAGE" "$STAGE.rw.dmg"
  return 0
}
trap cleanup EXIT

cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-n-drop: drag the .app into the folder next to it
mkdir "$STAGE/.background"
cp "$BACKGROUND" "$STAGE/.background/"

# The window layout is stored in the volume's .DS_Store, and only Finder can write it —
# so the image is first built writable (UDRW), mounted, decorated, and only then
# compressed to UDZO. A finished UDZO is read-only; it cannot be decorated after the fact.
RW="$STAGE.rw.dmg"
MNT="/Volumes/$APP"
# Finder addresses the volume by NAME (disk "ParanoidBar"), so a second volume with the same
# name makes the layout ambiguous, and a blind detach could unmount someone else's image or a
# neighboring build. Fail-closed: ask to free the name, unmounting nothing ourselves.
if [[ -e "$MNT" ]]; then
  echo "ошибка: том $MNT уже смонтирован (чужой образ или прошлая сборка) — отмонтируй его" >&2
  exit 1
fi
rm -f "$RW"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDRW -quiet "$RW"
hdiutil attach "$RW" -quiet
MOUNTED="$MNT"

# Finder learns about the volume via DiskArbitration, while hdiutil attach returns earlier: on
# a fast machine the layout step manages to ask Finder before the volume has appeared for it,
# and fails with -1728 ("Can't get disk") — the image comes out valid but undecorated. Wait for
# the volume to appear IN Finder specifically: /Volumes/... already exists by then and proves nothing.
for _ in $(seq 20); do
  [[ "$(osascript -e "tell application \"Finder\" to exists disk \"$APP\"" 2>/dev/null)" == "true" ]] && break
  sleep 0.5
done

# Finder is driven via Automation — on first run the system will ask for permission,
# and in a headless session (CI, ssh) it will refuse. The decoration is cosmetic: if it
# fails, the image is still valid — it just opens in the default list view.
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

rm -rf "$MNT/.fseventsd"   # no reason to ship the volume's FS-events journal with the image
sync
# Finder still holds the volume right after writing .DS_Store — second attempt with -force
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
# for a dmg it is the image's own signature that is checked, not its contents' executability
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG" || true
echo "Нотаризован и застейплен: ./$DMG — готово к раздаче."
