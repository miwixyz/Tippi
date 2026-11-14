#!/bin/bash
# unregister-build-copies.sh — meldet jede Tippi-Kopie außerhalb von /Applications bei LaunchServices ab.
#
# Warum (2026-11-14): Jeder Build (make test, make build, make release, devid-testbuild.sh) meldet seine
# Fassung als Besitzer von `tippi:` und `com.tippi.app` an. Dann kann `tippi://schnellnotiz` oder „Öffnen
# mit“ eine Build-Kopie starten statt der installierten App. An einem Tag dreimal von Hand abgemeldet –
# zweite Wiederholung = Script fällig.
#
# Nutzung: ./scripts/unregister-build-copies.sh   (läuft am Ende von scripts/release.sh mit)
# Exit: 0 = danach nur noch /Applications/Tippi.app angemeldet · 1 = es bleibt eine fremde Kopie übrig
set -u

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
BUNDLE_ID="com.tippi.app"
INSTALLED="/Applications/Tippi.app"

registered_copies() {
    "$LSREGISTER" -dump 2>/dev/null | /usr/bin/python3 -I -c '
import re, sys
bundle = sys.argv[1]
path = None
for line in sys.stdin:
    if line.startswith("-" * 20):
        path = None
    m = re.match(r"path:\s+(.*?) \(0x[0-9a-f]+\)\s*$", line)
    if m:
        path = m.group(1)
    elif path and re.match(r"identifier:\s+" + re.escape(bundle) + r"\s*$", line):
        print(path)
        path = None
' "$BUNDLE_ID" | sort -u
}

removed=0
while IFS= read -r copy; do
    [ -n "$copy" ] || continue
    [ "$copy" = "$INSTALLED" ] && continue
    "$LSREGISTER" -u "$copy" 2>/dev/null
    echo "  abgemeldet: $copy"
    removed=$((removed + 1))
done < <(registered_copies)

# Wirkung prüfen, nicht nur Ausführung (Vault-Regel 7).
left=$(registered_copies | grep -vxF "$INSTALLED" || true)
if [ -n "$left" ]; then
    echo "  ⚠ noch angemeldet (Datei existiert evtl. nicht mehr oder lsregister verweigert):"
    printf '    %s\n' "$left"
    echo "  → ZU TUN: $LSREGISTER -u \"<Pfad>\" von Hand, dann dieses Skript erneut"
    exit 1
fi
echo "  ✓ LaunchServices: nur noch $INSTALLED als $BUNDLE_ID angemeldet ($removed Kopie(n) abgemeldet)"
