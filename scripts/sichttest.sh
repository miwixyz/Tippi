#!/bin/bash
# Baut eine abgeschottete Testversion "Tippi Test" für Sichttests und startet sie.
#
# Warum Sandbox und nicht nur "ohne iCloud": Ohne iCloud schreibt Tippi Notizen nach
# ~/Library/Application Support/Tippi/Notes — und genau diesen Ordner liest das echte
# Tippi bei jedem Refresh und verschiebt alles daraus in iCloud (NotesStore,
# migrateLocalNotesIfNeeded). Erst die Sandbox lenkt die Kopie in ihren eigenen
# Container: ~/Library/Containers/com.tippi.app.sichtpruefung/Data/…
# Eigene Kennung = eigene Einstellungen; das echte Tippi muss vorher beendet sein
# (gleicher Prozessname, gleiche globalen Kürzel).
#
# Nutzung: ./scripts/sichttest.sh [name]   → build/testbuild-<datum>-<name>/Tippi Test.app
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:-sicht}"
OUT="build/testbuild-$(date +%Y-%m-%d)-$NAME"
APP="$OUT/Tippi Test.app"
BUNDLE_ID="com.tippi.app.sichtpruefung"
ENT="$(mktemp -t tippi-sicht).entitlements"

if pgrep -f "/Applications/Tippi.app/Contents/MacOS/Tippi" >/dev/null; then
  echo "❌ Das echte Tippi läuft — erst beenden: osascript -e 'quit app \"Tippi\"'"; exit 1
fi

xcodegen generate --quiet >/dev/null
xcodebuild build -project Tippi.xcodeproj -scheme Tippi -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/dd-sicht CODE_SIGNING_ALLOWED=NO \
  > /tmp/tippi-sicht.log 2>&1 || { echo "❌ Build fehlgeschlagen → /tmp/tippi-sicht.log"; exit 1; }

# Laufende Testversion beenden, sonst startet `open` die alte Kopie.
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
for _ in 1 2 3 4 5; do pgrep -f "$APP/Contents/MacOS" >/dev/null || break; sleep 1; done

mkdir -p "$OUT"
[ -d "$APP" ] && mv "$APP" "$(mktemp -d)/"   # alte Kopie beiseite, nicht löschen
ditto build/dd-sicht/Build/Products/Debug/Tippi.app "$APP"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "Tippi Test" "$APP/Contents/Info.plist"
# Kein Update-Check aus der Testkopie.
plutil -replace SUEnableAutomaticChecks -bool NO "$APP/Contents/Info.plist" 2>/dev/null || true
cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
codesign --force --deep -s - --entitlements "$ENT" "$APP" 2>&1 | grep -v "replacing existing signature" || true

# Abschottung messen, nicht annehmen.
if codesign -d --entitlements - "$APP" 2>&1 | grep -qi "ubiquity\|icloud"; then
  echo "❌ Testversion hat iCloud-Berechtigung — NICHT starten."; exit 1
fi
codesign -d --entitlements - "$APP" 2>&1 | grep -q "app-sandbox" \
  || { echo "❌ Testversion ist nicht in der Sandbox — NICHT starten."; exit 1; }
open "$APP"
sleep 4
PID=$(pgrep -f "$APP/Contents/MacOS" | head -1 || true)
if [ -z "$PID" ]; then
  echo "❌ Testversion läuft nicht (Absturz beim Start?) → ls -t ~/Library/Logs/DiagnosticReports/ | grep Tippi"
  exit 1
fi
ICLOUD=$(lsof -p "$PID" 2>/dev/null | grep -c "Mobile Documents" || true)
# Absoluter Pfad: Der Container-Ordner der Kopie enthält dieselbe Endung.
REAL=$(lsof -p "$PID" 2>/dev/null | grep -cF "$HOME/Library/Application Support/Tippi/Notes" || true)
echo "✅ $APP läuft (PID $PID), offene iCloud-Dateien: $ICLOUD, offene Dateien im echten Notizordner: $REAL"
echo "   Notizen der Kopie: ~/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/Tippi/Notes"
[ "$ICLOUD" = "0" ] && [ "$REAL" = "0" ] || { echo "❌ Zugriff auf echte Notizen gemessen — sofort beenden!"; exit 1; }
