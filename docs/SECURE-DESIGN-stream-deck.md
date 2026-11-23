# Secure Design — Stream-Deck-Plugin „TippiDeck“

Stand: 2026-11-17 · Status: **entschieden vor dem Code**, Messwerte unten ergänzt nach dem Bau.
Durchlauf nach `rafter-secure-design`: `ingestion` + `threat-modeling`. Vorbild: Gnotchi **G59**
(`~/Coding/Gnotchi/docs/SECURE-DESIGN.md`, Spezifikation `specs/2026-11-17-gnotchi-stream-deck-plus.md`, am Gerät gemessen
M1–M7). Eigene Datei statt `docs/SECURE-DESIGN.md`, weil Tippi je Funktion eine `SECURE-DESIGN-*.md` führt.

Michaels Auswahl (17.11.): **alle Funktionsgruppen** als Tasten (Diktat, KI auf Auswahl, Werkzeuge, Schalter), am
Stream Deck + zusätzlich **Prompt-Regler und Diktat-Regler**, **alle Prompts inkl. eigener** wählbar, Diktat-Taste **je Taste
wählbar** (Start/Stopp oder Halten).

## D1 – Was gebaut wird

```
[Stream Deck App] ⇄ WebSocket 127.0.0.1 ⇄ [TippiDeck, Kindprozess] ⇄ Unix-Socket deck.sock ⇄ [Tippi]
  Elgato-signiert       Stream-Deck-Protokoll   LTKJ6Z2VYB-signiert     feste JSON-Befehle       prüft Peer + Eltern
```

- **Natives Plugin in Swift** (`TippiDeck/`, Kennung `dev.mwlr.tippi.deck`), mit Michaels Developer ID signiert, liegt in
  `Tippi.app/Contents/Resources/dev.mwlr.tippi.deck.sdPlugin`. **Kein JavaScript:** alle JS-Plugins laufen in Elgatos
  gemeinsamer Node-Laufzeit (Gnotchi M1: über 20 Plugins in einem `node`) – Tippi könnte sie am Socket nicht unterscheiden.
- **Tippi behält die Logik.** Das Plugin übersetzt Tasten, Regler und Leiste in Befehle und zeigt Tippis Zustand. Es hat
  keine Freigaben, kein Mikrofon, keine Bedienungshilfen, kein Netz außer Elgatos lokalem WebSocket.
- **Einstellung „Stream Deck“ ab Werk aus.** Aus = Socket gar nicht offen. Taste „Plugin installieren“ übergibt das Paket
  an Stream Deck, das selbst nachfragt. Tippi schreibt nie in Elgatos Ordner.

## D2 – Vertrauensgrenzen

1. Stream Deck → Plugin: Elgatos lokaler WebSocket. Das Plugin prüft beim Start, dass sein **Elternprozess** Elgatos
   Stream Deck ist (`identifier "com.elgato.StreamDeck"`, Team `Y93VXCB8Q5`), sonst beendet es sich still.
2. Plugin → Tippi (`~/Library/Application Support/Tippi/deck.sock`): **vor dem ersten gelesenen Byte** prüft Tippi
   (a) das Audit-Token des Peers gegen `identifier "dev.mwlr.tippi.deck"` + Developer ID + Team `LTKJ6Z2VYB` und
   (b) dessen Elternprozess gegen Elgatos Anforderung. Ohne (b) könnte jedes Programm das echte, signierte Plugin
   selbst starten und fernsteuern (Gnotchi M2: aus der Shell gestartet → Eltern `/bin/zsh` → abgelehnt).
3. Tippi → Plugin: Das Plugin prüft vor dem ersten Befehl, dass der lauschende Prozess Tippi ist
   (`identifier "com.tippi.app"`, Developer ID, Team `LTKJ6Z2VYB`), und wartet auf Tippis `ok`.

Ordner `Application Support/Tippi` 0700, Socket 0600, eine veraltete Socket-Datei wird nur entfernt, wenn sie ein Socket ist.

## D3 – Befehle (Plugin → Tippi): Allowlist, kein Parser für Freitext

Rahmen wie Gnotchi: 4 Byte Länge (big endian) + JSON. Befehl ≤ 512 Byte, `v` muss die Zahl 1 sein, unbekannter `cmd`
oder falscher Typ → **Verbindung zu**, Zähler im Protokoll, nie der Inhalt.

```json
{"v":1,"hello":"2.41.0"}
{"v":1,"watch":true}
{"v":1,"cmd":"dictation","do":"toggle|holdStart|holdEnd","mode":"standard|shift|control|command|option"}
{"v":1,"cmd":"run","action":"mailDictation|voiceNote|reply|popup|translate|emoji|notes|quickNotes|screenText|password|lastDictation|pause|autocomplete|language"}
{"v":1,"cmd":"prompt","id":"improve"}
```

- `action`, `do`, `mode`: feste Aufzählungen im Code, sonst abgelehnt.
- `id`: Muster `^[A-Za-z0-9._-]{1,64}$` **und** zur Ausführungszeit in `DemoPrompt.all` vorhanden (gelöschter eigener
  Prompt → nichts passiert, Hinweis-Toast). Der Prompt-Text kommt immer aus Tippi, nie aus dem Befehl.
- `mode`: Diktat-Modus über den **Slot** (Shift/Control/Command/Option), aufgelöst gegen Tippis Zuordnung – wie die
  Zusatztaste beim Diktat. Leerer Slot → normales Diktat.
- Es gibt keinen Befehl, der Text einfügt, eine URL/Datei öffnet, eine Einstellung schreibt (außer den zwei
  Schaltern Pause und Autovervollständigung, die auch im Menü stehen), einen Prompt anlegt oder einen Anbieter wählt.

## D4 – Rückmeldung (Tippi → Plugin): nur Zustand, bewusst mit Prompt-Namen

```json
{"v":1,"dictation":"idle|recording|transcribing","ready":true,"level":7,"paused":false,"autocomplete":false,
 "language":"de","prompts":[{"id":"improve","title":"Verbessern"}],"modes":[{"slot":"shift","title":"Verbessern"}]}
```

- **Nie** Auswahltext, Transkript, Live-Vorschau, KI-Ergebnis, Notizinhalt, Passwort, App-Namen oder Fenstertitel.
- **Prompt-Titel gehen an Elgatos Stream-Deck-App** (Michael 17.11.: „Alle, auch eigene“). Eigene Titel können private
  Wörter enthalten; begrenzt auf 40 Zeichen, höchstens 60 Prompts, Steuerzeichen entfernt. Gnotchi M6: Stream Deck
  schreibt `setTitle`/`setFeedback` nicht in seine Protokolle, legt aber je Plugin eine Protokolldatei für stdout/stderr
  an → **das Plugin schreibt nie auf stdout/stderr**, nur `os_log` mit festen Texten.
- `level`: Mikrofonpegel 0–20 (ganzzahlig, nur während der Aufnahme), für den Balken am Regler. Kein Ton, keine Rohwerte.
- Rahmen ≤ 8 KB (60 Prompts × 40 Zeichen × bis 4 Byte). Gedrosselt: Zustand nur bei Änderung, Pegel ≤ 10/s.

## D5 – Grenzen und Verhalten

- Eine Verbindung gleichzeitig; eine neue geprüfte ersetzt die alte. Höchstens 20 Befehle/s, darüber verworfen.
- **KI-Befehle** (`prompt`, `popup`): höchstens einer je 1,5 s, und Tippis vorhandene Sperre „schon in Arbeit“
  (`isHandlingTrigger`, offene Vorschau) gilt unverändert. Ergebnis geht in die Vorschau zum Bestätigen bzw. in die
  App vorne – **nie an das Plugin**.
- **Pause** (`TippiPause`): Die Pause hält nur die automatischen Funktionen an (Snippets, Auswahlleiste,
  Autovervollständigung), Kürzel bleiben aktiv (`applyPause`). Stream-Deck-Tasten sind ausdrückliche Tastendrücke wie
  Kürzel und wirken deshalb auch in der Pause. (Erster Entwurf sagte das Gegenteil – beim Lesen von `applyPause` korrigiert.)
- **Mikrofon nie hängen lassen:** Trennt das Plugin (Absturz, Stream Deck beendet, Taste beim Gerätewechsel nie
  losgelassen) während eines Haltens-Diktats, beendet Tippi die Aufnahme wie beim Loslassen. Ein Start/Stopp-Diktat
  läuft weiter wie per Kürzel (sichtbar in Pille/Insel, stoppbar per Kürzel oder Esc).
- Unit-Tests und `Tippi Bild` öffnen den Socket nie.

## D6 – Plugin installieren

Taste in Einstellungen → Stream Deck. Tippi prüft die Plugin-Datei in seinen Resources gegen die Anforderung aus D2 (2a),
packt den Ordner mit `/usr/bin/ditto -c -k --keepParent` (feste Argumente, kein Shell-Aufruf) in einen neuen
Temp-Ordner (0700) als `Tippi.streamDeckPlugin` und öffnet die Datei. Stream Deck fragt selbst nach.

## D7 – STRIDE je Grenze

| | Bedrohung | Antwort |
|---|---|---|
| **S** | Fremder Prozess gibt sich als Plugin aus | Audit-Token-Prüfung vor dem ersten Byte (D2.2a) |
| **S** | Fremder Prozess startet echtes Plugin mit eigenem Port | Eltern-Prüfung, Plugin + Tippi (D2.1, D2.2b) |
| **S** | Fremder Prozess gibt sich als Tippi aus (Socket-Datei ersetzt) | Plugin prüft den Server (D2.3) |
| **S** | Anderes Stream-Deck-Plugin steuert unsere Aktionen | Stream Deck stellt Ereignisse nur dem Plugin der Aktion zu; die Einstellungsseite hat nur Auswahlfelder |
| **T** | Plugin-Datei in Elgatos Ordner verändert | Signatur bricht → D2.2a lehnt ab |
| **T** | Befehl mit Pfad, Skript, Prompt-Text | Gibt es nicht; Allowlist (D3) |
| **R** | Wer hat diktiert/umgeschrieben? | Lokale Einzelperson; Protokoll „Befehl angenommen: <Aktion>“ (Aktionsname ist fest, kein Inhalt) |
| **I** | Text verlässt Tippi Richtung Elgato | Keine Inhalte im Rückkanal (D4); bewusst: Prompt-Titel |
| **I** | Protokolle | Tippi: nie Prompt-IDs eigener Prompts, nie Titel; Plugin: nie stdout/stderr |
| **D** | Befehlsflut, Kosten-DoS über KI-Anbieter | 20/s, KI ≤ 1 je 1,5 s, Sperre „in Arbeit“ (D5) |
| **D** | Mikrofon bleibt offen | Halten endet beim Trennen (D5) |
| **E** | Plugin nutzt Tippis Freigaben (Mikrofon, Bedienungshilfen, Cloud-Schlüssel) als Hebel | Nur Aktionen, die auch per Kürzel/Menü gehen, auf die App vorne; keine Ergebnisse zurück |

## D8 – Missbrauchsfälle

- „Taste startet Prompt auf meine Auswahl“ → „Ein Angreifer löst Prompts aus, um markierten Text an den Cloud-Anbieter zu
  schicken.“ Er bräuchte Elgatos signierte App als Elternprozess plus unser signiertes Plugin; das Ergebnis landet nur in
  Tippis Vorschau auf dem Bildschirm. Wer schon Code als Michael ausführt, kann dasselbe per synthetischem ⌥⌘T – neu ist
  nur, dass es ohne Tastendruck geht. Restrisiko angenommen.
- „Taste startet Diktat“ → „Mikrofon wird heimlich eingeschaltet.“ macOS zeigt den orangen Punkt, Tippi Pille/Insel; das
  Transkript geht an die App vorne, nie ans Plugin. Restrisiko angenommen (gleich wie Kürzel).
- „Taste erzeugt Passwort“ → „Passwort wird abgegriffen.“ Es geht wie im Menü nur in die App vorne, nie zurück.
- „Taste „Letztes Diktat“ (2.46)“ → „Ein Schadplugin liest das Diktat.“ Nein: Der Befehl heißt nur `lastDictation`, der Text liegt im Arbeitsspeicher von Tippi (30 Minuten, `docs/SECURE-DESIGN-letztes-diktat.md`) und geht nie zum Plugin. Er wird wie beim Kürzel ⌃⌥⌘V in die App vorne geschrieben, nie in ein Passwortfeld, in Terminals einzeilig ohne Return. Eine Schadtaste kann also nur „noch einmal einfügen“ auslösen, nichts lesen.

## D9 – Restrisiken (bewusst angenommen)

- Elgatos Stream-Deck-App ist Teil der Vertrauenskette; kompromittiert kann sie im Befehlsumfang D3 steuern.
- Prompt-Titel (auch eigene) liegen im Speicher von Elgatos App (Michael, 17.11.).
- PID-Wiederverwendung zwischen Peer-Token und Elternabfrage (wie G59): bräuchte ohnehin Code-Ausführung als Michael.

## Abgelehnt

- **JavaScript-Plugin (Elgato SDK):** am Socket nicht unterscheidbar von über 20 anderen Plugins.
- **URL-Schema erweitern (`tippi://diktat`):** jeder Prozess und jede Webseite könnte es aufrufen, kein Absender prüfbar
  (SECURE-DESIGN-url-schema U2).
- **Synthetische Tastenkürzel aus dem Plugin:** bräuchte Bedienungshilfen für das Plugin, trifft je nach Belegung andere
  Apps, und Tippi wüsste nicht, wer drückt.
- **Live-Transkript auf der Leiste:** wäre diktierter Text bei Elgato. Nur Pegel.

## Messwerte (nach dem Bau, 17.11., Mac mini, Stream Deck 7.6.1, Developer-ID-Testbuild)

- **Signaturen:** Plugin `tippideck` erfüllt `DeckWire.pluginRequirement`, der Testbuild erfüllt `DeckWire.tippiRequirement`
  (`codesign --verify -R`). Socket `deck.sock` 0600, Ordner 0700.
- **Peer-Prüfung:** Unit-Test `testSocketRefusesPeerThatIsNotThePlugin`: der Testprozess (weder Plugin noch von Stream Deck
  gestartet) wird vor dem ersten Byte abgelehnt (OSStatus −67050), kein Ack, kein Befehl zugestellt.
- **Am Gerät (Michael):** Stream Deck startet `tippideck` als Kindprozess, Plugin prüft Tippi und verbindet. Diktat-Taste,
  Prompt-Taste, Seitenwechsel, Diktat- und Prompt-Regler funktionieren. Profile für Stream Deck + und Neo (je zwei Seiten)
  importiert.
- **Fund 1 – Layout abgelehnt:** Stream Deck verweigert Layouts mit überlappenden Feldern
  (`element 'value' overlaps with element 'name'`, nur im `StreamDeck.log`) und zeigt dann nur Name + Symbol – die Regler
  wirkten tot. Behoben, Test `testStripLayoutItemsDoNotOverlapAndFit`.
- **Fund 2 – fehlgeschlagenes Layout klebt am Regler:** Regler, die mit dem abgelehnten Layout angelegt wurden, behielten das
  Ersatz-Layout auch nach Plugin-Update, neuem Dateinamen und `setFeedbackLayout`. Frisch gezogene Regler zeigten das volle
  Layout. Abhilfe: Profil löschen und neu importieren. Ein gültiges, nur geändertes Layout übernahm Stream Deck dagegen bei
  bestehenden Reglern sofort (Leiste vergrößert, Michael: „gut lesbar“). Für Nutzer ohne den kaputten Zwischenstand irrelevant.
- **Plugin-Update:** gleiche Manifest-Version → `AlreadyInstalled`, Stream Deck übernimmt nichts. Neue Version → Dialog,
  Profile werden bei Updates **nicht** neu angelegt (nur bei Erstinstallation).
- **Protokolle:** Stream Deck legt `~/Library/Logs/ElgatoStreamDeck/dev.mwlr.tippi.deck0.log` an, Inhalt nur
  „Process started“ – das Plugin schreibt nichts auf stdout/stderr.
