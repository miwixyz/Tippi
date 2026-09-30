#!/usr/bin/env bash
# record-demo.sh - nimmt ein echtes Tippi-Demo auf (TextEdit + ⌥⌘T „Improve“ + ⌥⌘E Emoji).
#
# Start im Terminal:   bash scripts/record-demo.sh
# Ergebnis:            ~/Downloads/tippi-demo-<zeit>.mov  (+ .json mit Fensterposition für den Schnitt)
#
# Voraussetzungen (macOS fragt beim ersten Lauf, danach Terminal neu starten):
#   - Terminal darf den Bildschirm aufnehmen   (Datenschutz & Sicherheit → Bildschirm- & Systemaudioaufnahme)
#   - Terminal darf den Mac steuern            (Datenschutz & Sicherheit → Bedienungshilfen)
#   - Tippi läuft, „Improve“ hat einen funktionierenden Anbieter
# Während der Aufnahme Maus und Tastatur nicht anfassen (~30 s).
set -euo pipefail

STAMP=$(date +%Y%m%d-%H%M%S)
OUT="${1:-$HOME/Downloads/tippi-demo-$STAMP.mov}"
META="${OUT%.mov}.json"
X=240; Y=160; W=900; H=520          # TextEdit-Fenster in Punkten
TEXT="hey team, quick update: the launch moves to thursday bc the designs arent final yet. sorry for the short notice, lets sync tomorow"

say_step() { printf '▶ %s\n' "$1"; }
fail() { printf '✗ %s\n' "$1" >&2; exit 1; }

# ── Vorprüfungen ──────────────────────────────────────────────────────────────
say_step "Prüfe Bildschirmaufnahme-Recht"
if ! screencapture -x /tmp/tippi-demo-permcheck.png 2>/dev/null; then
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
  fail "Terminal darf den Bildschirm nicht aufnehmen. In den geöffneten Einstellungen Terminal einschalten, Terminal beenden (⌘Q), neu öffnen, Skript erneut starten."
fi
rm -f /tmp/tippi-demo-permcheck.png

say_step "Prüfe Bedienungshilfen-Recht"
if ! osascript -e 'tell application "System Events" to key code 56' >/dev/null 2>&1; then
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  fail "Terminal darf den Mac nicht steuern. In den geöffneten Einstellungen Terminal einschalten, Terminal neu starten, Skript erneut starten."
fi

pgrep -qf "Tippi.app/Contents/MacOS/Tippi" || fail "Tippi läuft nicht. Bitte Tippi starten und das Skript erneut ausführen."

# Die echten Tastenkürzel aus Tippis Einstellungen lesen (jeder kann sie ändern,
# z. B. auf ⌃⌥⇧⌘T). Ergebnis: AppleScript-Fragment „key code N using {…}“.
hotkey_as() {
  python3 - "$1" "$2" <<'PY'
import json, plistlib, subprocess, sys
key, fallback = sys.argv[1], sys.argv[2]
try:
    d = plistlib.loads(subprocess.run(["defaults", "export", "com.tippi.app", "-"],
                                      capture_output=True, check=True).stdout)
    combo = json.loads(d[key].decode())
except Exception:
    combo = json.loads(fallback)
flags, mods = combo["modifiersRaw"], []
for bit, name in ((0x40000, "control down"), (0x80000, "option down"),
                  (0x20000, "shift down"), (0x100000, "command down")):
    if flags & bit:
        mods.append(name)
print(f'key code {combo["keyCode"]}' + (f' using {{{", ".join(mods)}}}' if mods else ""))
PY
}
TIPPI_KEY=$(hotkey_as "tippi.hotkeyCombo.v1" '{"modifiersRaw":1572864,"keyCode":17}')   # Standard ⌥⌘T
EMOJI_KEY=$(hotkey_as "emoji.hotkeyCombo.v1" '{"modifiersRaw":1572864,"keyCode":14}')   # Standard ⌥⌘E
# Filterwort für den Prompt „Improve“ in Tippis Oberflächensprache
LANG_PREF=$(defaults read com.tippi.app AppleLanguages 2>/dev/null | /usr/bin/grep -o '"[a-z][a-z]' | head -1 | tr -d '"')
[ -n "$LANG_PREF" ] || LANG_PREF=$(defaults read -g AppleLanguages 2>/dev/null | /usr/bin/grep -o '"[a-z][a-z]' | head -1 | tr -d '"')
case "$LANG_PREF" in de) FILTER="verb" ;; *) FILTER="impr" ;; esac
FILTER_KEYS=$(printf '"%s", ' $(echo "$FILTER" | fold -w1) | sed 's/, $//')
say_step "Tippi-Kürzel: $TIPPI_KEY · Emoji-Kürzel: $EMOJI_KEY · Filter: $FILTER"

# ── Szene vorbereiten ─────────────────────────────────────────────────────────
say_step "Öffne TextEdit mit Beispieltext"
osascript <<APPLESCRIPT
tell application "TextEdit"
  activate
  make new document with properties {text:"$TEXT"}
  set size of text of front document to 22
  set bounds of front window to {$X, $Y, $((X + W)), $((Y + H))}
end tell
APPLESCRIPT
sleep 1.5

# Pixel-Maßstab des Hauptbildschirms für den späteren Zuschnitt
SCREEN_PT=$(osascript -e 'tell application "Finder" to get bounds of window of desktop')
printf '{"x":%d,"y":%d,"w":%d,"h":%d,"screen_points":"%s"}\n' "$X" "$Y" "$W" "$H" "$SCREEN_PT" > "$META"

# ── Aufnahme ──────────────────────────────────────────────────────────────────
say_step "Aufnahme läuft - bitte nichts anfassen"
screencapture -v -x "$OUT" &
REC=$!
sleep 2

osascript <<APPLESCRIPT
tell application "System Events"
  -- Szene 1: Text markieren, ⌥⌘T, „Improve“ wählen, Ergebnis ersetzen
  keystroke "a" using command down
  delay 1.0
  $TIPPI_KEY
  delay 1.4
  repeat with c in {$FILTER_KEYS}
    keystroke c
    delay 0.18
  end repeat
  delay 0.8
  key code 125 -- Pfeil runter: obersten Treffer wählen
  delay 0.3
  key code 36  -- Return: Prompt ausführen
  delay 6.0    -- KI-Antwort abwarten
  key code 36  -- Return: Original ersetzen
  delay 2.0

  -- Szene 2: ans Ende, ⌥⌘E, Emoji suchen und einfügen
  key code 125 using command down
  delay 0.4
  keystroke " "
  $EMOJI_KEY
  delay 1.2
  repeat with c in {"r", "o", "c", "k", "e", "t"}
    keystroke c
    delay 0.18
  end repeat
  delay 0.9
  key code 36
  delay 2.5
end tell
APPLESCRIPT

kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true

# ── Aufräumen ─────────────────────────────────────────────────────────────────
osascript -e 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1 || true

[ -s "$OUT" ] || fail "Keine Aufnahme entstanden ($OUT fehlt oder ist leer)."
printf '✓ Fertig: %s\n  Zuschnitt-Daten: %s\n' "$OUT" "$META"
