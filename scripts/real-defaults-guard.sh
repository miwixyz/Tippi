#!/bin/bash
# Waechter: Tests duerfen die echten Einstellungen der installierten App NIE aendern.
#
# Der Test-Host IST die installierte App (gleiche Bundle-ID com.tippi.app, gleiche
# Einstellungsdatei). Ein Test, der `UserDefaults.standard` beschreibt, ueberschreibt
# also Michaels echte Einstellungen. Real 2026-09-25: `DictationInputModeTests` loeschte
# bei jedem `make test` — also vor jedem Release — den Diktat-Modus; nach jedem Update
# stand „Einzelne Sondertaste" wieder auf „Tastenkombination".
#
# `make test` ruft `snapshot` davor und `compare` danach. Verglichen werden die
# Einstellungen der Funktionen (Praefixe unten), nicht Fensterpositionen o. ae., die
# macOS beim Start des Test-Hosts selbst schreibt.
#
#   bash scripts/real-defaults-guard.sh snapshot|compare
# Exit: 0 = unveraendert · 1 = ein Test hat echte Einstellungen geaendert
set -euo pipefail
DOMAIN="${TIPPI_DEFAULTS_DOMAIN:-com.tippi.app}"   # Umgebungsvariable nur fuer den Selbsttest
SNAP="${TMPDIR:-/tmp}/tippi-real-defaults.json"
PREFIXES='dictation. voice. screenOCR. appearance. tippi. notes. translate. emoji. snippets. selection. mlx. defaultModel.'

auszug() {
    # plistlib statt `plutil -convert json`: Hotkey-Kombinationen sind Binaerdaten, an
    # denen die JSON-Umwandlung still scheitert — der erste Entwurf verglich dadurch
    # ein leeres Objekt mit einem leeren Objekt und meldete immer „unveraendert".
    defaults export "$DOMAIN" - | /usr/bin/python3 -c '
import json, plistlib, sys, base64
praefixe = sys.argv[1].split()
d = plistlib.loads(sys.stdin.buffer.read())
def roh(v):
    return base64.b64encode(v).decode() if isinstance(v, (bytes, bytearray)) else v
auszug = {k: roh(v) for k, v in sorted(d.items()) if any(k.startswith(p) for p in praefixe)}
if not auszug:
    sys.exit("✗ real-defaults-guard: keine Tippi-Einstellungen gefunden — Pruefung waere wertlos")
print(json.dumps(auszug, sort_keys=True, default=str))
' "$PREFIXES"
}

case "${1:-}" in
  snapshot) auszug > "$SNAP" ;;
  compare)
    [ -f "$SNAP" ] || { echo "✗ real-defaults-guard: kein Schnappschuss — erst 'snapshot'"; exit 1; }
    NACHHER=$(auszug)
    if [ "$NACHHER" = "$(cat "$SNAP")" ]; then
      echo "✓ echte Tippi-Einstellungen unveraendert"
    else
      echo "✗ Ein Test hat die ECHTEN Einstellungen der installierten App geaendert:"
      /usr/bin/python3 - "$SNAP" "$NACHHER" <<'PY'
import json, sys
vorher = json.load(open(sys.argv[1])); nachher = json.loads(sys.argv[2])
for k in sorted(set(vorher) | set(nachher)):
    if vorher.get(k, "<fehlt>") != nachher.get(k, "<fehlt>"):
        print(f"    {k}: {vorher.get(k, '<fehlt>')!r} → {nachher.get(k, '<fehlt>')!r}")
PY
      echo "  → ZU TUN: den Test auf ThrowawayDefaults / Settings.store umstellen; nie UserDefaults.standard."
      echo "    (Oder: die laufende App hat waehrend der Tests selbst etwas gespeichert — dann einfach wiederholen.)"
      exit 1
    fi ;;
  *) echo "Aufruf: $0 snapshot|compare"; exit 2 ;;
esac
