#!/bin/bash
# Developer-ID-Testbuild — für alles, was die Bedienungshilfen-Berechtigung braucht
# (Auswahlleiste, Snippets, Textersetzung). Auszug aus scripts/release.sh: Archive +
# Export + whisper-cli + Re-Sign, ohne Tag-Check, ohne project.yml, ohne Notarisierung,
# ohne Veröffentlichung. Warum: `make build` signiert mit Apple Development; macOS
# führt pro Bundle-ID nur EINEN Bedienungshilfen-Eintrag, und der gehört der
# installierten Developer-ID-Release. Dieser Build erfüllt dieselbe Signatur-Anforderung
# und läuft deshalb mit der bestehenden Freigabe. Start: open "$OUT/export/Tippi.app"
set -euo pipefail
cd "$(dirname "$0")/.."
DEVELOPER_ID="Developer ID Application: Michael Wildenauer (LTKJ6Z2VYB)"
OUT="${OUT:-/tmp/tippi-devid}"
if [ -e "$OUT/export" ] || [ -e "$OUT/Tippi.xcarchive" ]; then
    echo "✗ $OUT enthält noch einen alten Testbuild — erst wegräumen oder OUT=<neuer Pfad> setzen."
    exit 1
fi
mkdir -p "$OUT"
xcodegen generate >/dev/null

echo "▶ archive"
xcodebuild -project Tippi.xcodeproj -scheme Tippi -configuration Release \
    -derivedDataPath "$OUT/dd" -archivePath "$OUT/Tippi.xcarchive" \
    -allowProvisioningUpdates archive >"$OUT/archive.log" 2>&1 || { tail -20 "$OUT/archive.log"; exit 1; }

echo "▶ export"
xcodebuild -exportArchive -archivePath "$OUT/Tippi.xcarchive" -exportPath "$OUT/export" \
    -exportOptionsPlist scripts/exportOptions-developer-id.plist \
    -allowProvisioningUpdates >"$OUT/export.log" 2>&1 || { tail -20 "$OUT/export.log"; exit 1; }

APP_PATH="$OUT/export/Tippi.app"
test -f "$APP_PATH/Contents/embedded.provisionprofile" || { echo "✗ kein Profil eingebettet"; exit 1; }

echo "▶ whisper-cli + Re-Sign (innen → außen)"
cp Tippi/Helpers/whisper-cli "$APP_PATH/Contents/MacOS/whisper-cli"
chmod +x "$APP_PATH/Contents/MacOS/whisper-cli"
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_PATH/Contents/MacOS/whisper-cli"
for bin in "$SPARKLE_FW/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
           "$SPARKLE_FW/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
           "$SPARKLE_FW/Autoupdate" "$SPARKLE_FW/Updater.app/Contents/MacOS/Updater"; do
    [ -f "$bin" ] && codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$bin"
done
for bundle in "$SPARKLE_FW/XPCServices/Installer.xpc" "$SPARKLE_FW/XPCServices/Downloader.xpc" "$SPARKLE_FW/Updater.app"; do
    [ -d "$bundle" ] && codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$bundle"
done
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_PATH/Contents/Frameworks/Sparkle.framework"
ENT="$OUT/effective.entitlements"
codesign -d --entitlements "$ENT" --xml "$APP_PATH" 2>/dev/null
test -s "$ENT" || { echo "✗ Entitlements nicht lesbar"; exit 1; }
codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$DEVELOPER_ID" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH" && echo "✓ Signatur gültig"
codesign -d -r- "$APP_PATH" 2>&1 | grep designated
echo "APP=$APP_PATH"
