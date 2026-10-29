#!/bin/sh
# Bild-Testkopie (docs/SECURE-DESIGN-befehlskanal.md): Debug-Build mit EIGENER Kennung dev.mwlr.tippi.bild, ohne
# Berechtigungen, ohne Hotkeys/Event-Taps/Diktat, ohne Updater, ohne iCloud, ohne Gnotchi-Verbindung, mit
# Befehlskanal – dazu das signierte Steuerprogramm build-dev/tippictl.
#
# Warum eigene Kennung: Die Bildschirmaufnahme-Freigabe hängt an Kennung + Signatur. Mit der echten Kennung
# hätte auch das veröffentlichte Tippi die Freigabe. Das echte Tippi (/Applications) läuft währenddessen
# einfach weiter und wird nicht angefasst.
#
# NICHT `make build`: das beendet per `pkill -x Tippi` auch das echte Tippi. Hier wird xcodebuild direkt gerufen.
#
#   sh scripts/bild-test.sh                → bauen, signieren, nach ~/Applications installieren, starten
#   build-dev/tippictl status              → Zustand (nur Zahlen/Kennungen)
#   build-dev/tippictl snapshot einstellungen|hilfe|ueber
#   build-dev/tippictl appearance light|dark|system
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
BUNDLE_ID="dev.mwlr.tippi.bild"

mkdir -p build-dev
LOG=$(mktemp "build-dev/bild-build.XXXXXX")
if ! { xcodegen generate && xcodebuild -project Tippi.xcodeproj -scheme Tippi -configuration Debug \
        -derivedDataPath build-dev build; } >"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -8
    echo "✗ Build fehlgeschlagen — Log: $LOG" >&2
    exit 1
fi
SRC="build-dev/Build/Products/Debug/Tippi.app"
DEST_DIR=$(mktemp -d /tmp/tippi-bild.XXXXXX)
APP="$DEST_DIR/Tippi Bild.app"
ditto "$SRC" "$APP"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Tippi Bild" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :CFBundleDisplayName" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Tippi Bild" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$PLIST"
# Kein iCloud-Container, kein Sparkle-Feed (B4). Ohne `|| true`: fehlt ein Schlüssel, ist die Info.plist anders
# als gedacht – dann lieber anhalten und nachsehen.
/usr/libexec/PlistBuddy -c "Delete :NSUbiquitousContainers" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :SUEnableAutomaticChecks" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$PLIST"
# Entwicklungsprofil für com.tippi.app (iCloud) gehört nicht zur Kopie.
[ -e "$APP/Contents/embedded.provisionprofile" ] && mv "$APP/Contents/embedded.provisionprofile" "$DEST_DIR/"

IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "✗ Kein Developer-ID-Zertifikat im Schlüsselbund" >&2; exit 1; }

# Eingebettete Teile einzeln (innen nach außen), ohne eigene Berechtigungen.
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$SPK"/XPCServices/*.xpc "$SPK/Autoupdate" "$SPK/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --preserve-metadata=entitlements --sign "$IDENTITY" "$part"
done
for part in "$APP"/Contents/Frameworks/*; do
    [ -e "$part" ] || continue
    [ "$part" = "$APP/Contents/Frameworks/Sparkle.framework" ] && continue
    codesign --force --options runtime --sign "$IDENTITY" "$part"
done
for part in "$APP"/Contents/MacOS/*.dylib; do
    [ -e "$part" ] || continue
    codesign --force --options runtime --sign "$IDENTITY" "$part"
done

# App: KEINE Berechtigungen (B4). Kein iCloud, kein Mikrofon (Hardened Runtime lehnt ohne audio-input ab),
# keine Apple Events.
ENT="$DEST_DIR/TippiBild.entitlements"
cat > "$ENT" <<'PLISTEND'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
PLISTEND
codesign --force --options runtime --entitlements "$ENT" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

# Steuerprogramm: nur mit dieser Kennung + Developer ID nimmt die Kopie Befehle an.
swiftc -O tools/tippictl.swift -o build-dev/tippictl
codesign --force --options runtime -i dev.mwlr.tippi.ctl --sign "$IDENTITY" build-dev/tippictl

# Fester Ort ~/Applications statt /tmp (Gnotchi, gemessen 28.10.): Apps unter /tmp findet macOS nicht über ihre
# Kennung, die Systemeinstellungen zeigen den Schalter dann nie. Gleiche Kennung + gleiche Signatur am selben Ort
# → die Freigabe bleibt über Neubauten erhalten.
INSTALLED="$HOME/Applications/Tippi Bild.app"
# Alte Bild-Kopie beenden – nur sie, über ihre PID aus dem vollen Programmpfad. Nie nach Prozessnamen und nie per
# AppleScript: Das echte Tippi heißt genauso („Tippi“).
for pid in $(pgrep -f "^$INSTALLED/Contents/MacOS/Tippi\$" || true); do
    kill "$pid"
done
i=0
while pgrep -f "^$INSTALLED/Contents/MacOS/Tippi\$" >/dev/null && [ "$i" -lt 30 ]; do
    sleep 0.1
    i=$((i + 1))
done
mkdir -p "$HOME/Applications"
[ -d "$INSTALLED" ] && mv "$INSTALLED" "$DEST_DIR/alt.app"
ditto "$APP" "$INSTALLED"
codesign --verify --deep --strict "$INSTALLED"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED"
open "$INSTALLED"
echo "✓ Bild-Testkopie gestartet: $INSTALLED"
echo "  Erster Lauf auf einem Mac: Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- & Systemaudioaufnahme"
echo "  → „Tippi Bild“ einschalten (nicht „Tippi“), dann dieses Skript erneut starten."
echo "  Steuern: build-dev/tippictl status | snapshot einstellungen|hilfe|ueber | appearance light|dark|system"
