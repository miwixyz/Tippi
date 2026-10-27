#!/bin/bash
# Parakeet v3 gegen Parakeet Ultra: Wortfehlerrate und Rechenzeit an eigenen Aufnahmen.
#
#   bash scripts/parakeet-vergleich.sh <ordner> [--modelle v3,ultra] [--sprache de|auto] [--laden] [--texte]
#   bash scripts/parakeet-vergleich.sh --eichsatz <ordner>
#
# <ordner> enthaelt Paare name.wav + name.txt (Referenztext). Fehlende Modelle werden nur
# mit --laden heruntergeladen (v3 ≈ 470 MB, Ultra ≈ 630 MB; Ablage wie bei Tippi unter
# ~/Library/Application Support/FluidAudio/Models).
#
# --eichsatz erzeugt synthetische deutsche Testsaetze mit der Systemstimme „Anna“ (say +
# afconvert, 16 kHz mono WAV). NUR zum Eichen des Werkzeugs: Eine Computerstimme spricht
# sauber, ohne Raumhall, Dialekt oder Zoegern — das Ergebnis sagt nichts darueber, welches
# Modell bei echten Diktaten besser ist. Entscheiden nur an eigenen Aufnahmen.
#
# Eigene Aufnahmen: in Tippi liegt die Aufnahme nach dem Diktat nicht mehr vor (wird
# geloescht). Also z. B. mit QuickTime/Sprachmemos aufnehmen, dann:
#   afconvert -f WAVE -d LEI16@16000 -c 1 aufnahme.m4a name.wav
# und den gesprochenen Text als name.txt danebenlegen (so geschrieben, wie er dastehen soll).
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
PAKET="$HIER/parakeet-vergleich"

eichsatz() {
    local ziel="$1"
    command -v say >/dev/null && command -v afconvert >/dev/null || { echo "✗ say/afconvert fehlen (macOS-Bordmittel)"; exit 1; }
    say -v '?' | /usr/bin/grep -q '^Anna ' || { echo "✗ Stimme „Anna“ nicht installiert (Systemeinstellungen → Bedienungshilfen → Gesprochene Inhalte)"; exit 1; }
    mkdir -p "$ziel"
    local i=0
    while IFS= read -r satz; do
        [ -n "$satz" ] || continue
        i=$((i + 1))
        local name; name=$(printf 'eich-%02d' "$i")
        printf '%s\n' "$satz" > "$ziel/$name.txt"
        say -v Anna -o "$ziel/$name.aiff" "$satz"
        afconvert -f WAVE -d LEI16@16000 -c 1 "$ziel/$name.aiff" "$ziel/$name.wav"
        rm -f "$ziel/$name.aiff"
    done <<'SAETZE'
Hallo Patrik, kurz zum Stand beim neuen Kinoprogramm für nächste Woche.
Bitte schick mir die Liste mit den Vorstellungen bis morgen Mittag.
Ich habe die Datei gestern Abend noch einmal überarbeitet und hochgeladen.
Der Termin mit dem Kinobetreiber verschiebt sich leider auf Donnerstag.
Können wir die Trailer für den Familienfilm schon am Wochenende zeigen?
Die Spracherkennung läuft komplett auf dem Mac, ohne Verbindung ins Internet.
Danach öffnest du die Einstellungen und schaltest die Vorschau ein.
Vielen Dank für die schnelle Rückmeldung, das hilft mir sehr weiter.
Wir brauchen noch ein Plakat, ein paar Bilder für Instagram und einen kurzen Text.
Liebe Grüße aus München und bis bald.
SAETZE
    echo "✓ $i synthetische Paare in $ziel — nur zum Eichen, keine Entscheidungsgrundlage"
}

if [ "${1:-}" = "--eichsatz" ]; then
    [ -n "${2:-}" ] || { echo "Aufruf: $0 --eichsatz <ordner>"; exit 2; }
    eichsatz "$2"
    exit 0
fi

# Release-Build: Debug rechnet auf der CPU-Seite (Vorverarbeitung, Decoder-Schleife)
# deutlich langsamer und verfaelscht die Zeitspalte.
exec swift run --quiet -c release --package-path "$PAKET" parakeet-vergleich "$@"
