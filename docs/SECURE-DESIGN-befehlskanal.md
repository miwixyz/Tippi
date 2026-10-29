# Secure Design — Bild-Testkopie mit Befehlskanal (nur Debug)

Stand: 2026-10-29 · Status: **Entwurf vor dem Code**, Messwerte unten ergänzt nach dem Bau.
Durchlauf nach `rafter-secure-design`: `ingestion` + `threat-modeling`. Übertragen von Kalli **K1**
(`~/Coding/Kalli/docs/SECURE-DESIGN.md`, Commit `f38140c`) und Gnotchi **G45**. Entscheidungen von Michael:
Aufgabe „Debug-Befehlskanal und Fensterbilder für eigene Mac-Apps“ (28.10.), Skill `app-befehlskanal`.
Eigene Datei statt `docs/SECURE-DESIGN.md`, weil Tippi je Funktion eine `SECURE-DESIGN-*.md` führt.

## B1 – Was gebaut wird

Ein Debug-Build mit **eigener Kennung `dev.mwlr.tippi.bild`** unter `~/Applications/Tippi Bild.app`. Er startet
nur Fenster und einen lokalen Befehlskanal (`debug.sock`). Das Developer-ID-signierte Steuerprogramm
`build-dev/tippictl` schickt drei feste Befehle: `status`, `snapshot einstellungen|hilfe|ueber`,
`appearance light|dark|system`. Das Bild macht die Kopie aus sich heraus per ScreenCaptureKit, nur vom eigenen
Fenster – das Claude-Terminal darf keine Bildschirmfotos machen. Wozu: Claude prüft Tippis Einstellungsfenster hell
und dunkel selbst, statt die Optik Michael zu übergeben.

## B2 – Nie ausgeliefert

Kanal, Bild-Kennung, Steuerkennung und Ersatzordner stehen nur in `#if DEBUG` (`Tippi/Debug/*`, Zweige in
`Tippi/Core/BildKopie.swift`). `BildKopie.isActive` ist im Release-Build immer `false`. Nachweis am Release-Build
(gebaut nach der letzten Änderung, `stat`) per `strings`: `debug.sock`, `dev.mwlr.tippi.bild`, `dev.mwlr.tippi.ctl`,
„Befehlskanal“ je 0×; Gegenprobe am Debug-Build je ≥ 1×. ScreenCaptureKit ist anders als bei Kalli **kein**
Unterscheidungsmerkmal: Tippis Bildschirm-OCR linkt es auch im Release.

## B3 – Tippi-Besonderheiten: was die Kopie NICHT startet

Tippi ist keine Fenster-App, sondern ein systemweiter Eingriff. Jede dieser Funktionen würde mit dem echten Tippi
um Tasten und Freigaben kämpfen. Die Kopie verlässt `applicationDidFinishLaunching` **als erstes**, nach Schrift
und Hell/Dunkel, und startet nur den Kanal – derselbe Mechanismus wie der vorhandene Ausstieg für den Testlauf
(`isRunningUnitTests`), nur früher.

| Funktion im echten Tippi | Wo gestartet | In der Kopie |
|---|---|---|
| Globale Hotkeys (Carbon, ids 1–8, 99) | `startHotkey`, `restart*Hotkey`, `registerSafetyHotKey` | nie aufgerufen |
| `GlobalKeyMonitor`, `SnippetKeystrokeMonitor` (Event-Taps), Emoji/Emoticons | `startGlobalKeyMonitor`, `startSnippetEngine` | nie aufgerufen |
| Autovervollständigung (aktiver Tap ⇥), MLX-Modell | `restartAutocomplete`, `MLXServerManager.autoStartIfPreferred` | nie aufgerufen; `autocomplete` bleibt `lazy` unberührt |
| Diktat-Taste (rechte option), Mail-Diktat, Mikrofon, Whisper/Parakeet | `restartDictationHotkey`, `restartMailDictationHotkey` | nie aufgerufen; leere Entitlements → kein Mikrofon (Hardened Runtime lehnt ohne `audio-input` ab) |
| Auswahlleiste (Bedienungshilfen-Beobachter) | `restartSelectionPopupEngine` | nie aufgerufen |
| Bildschirm-OCR-Hotkey | `restartScreenOCRHotkey` | nie aufgerufen |
| Live-Text an Gnotchi (`Gnotchi/live.sock`), Aufnahme-Meldung (distnoted `com.tippi.app.aufnahme`) | nur während eines Diktats | kein Diktat; zusätzlich zeigt der Socket-Pfad in den Ersatzordner (B4) |
| Sparkle | `SPUStandardUpdaterController` | nie erzeugt; `SUFeedURL`, `SUEnableAutomaticChecks`, `SUPublicEDKey` aus der Info.plist der Kopie entfernt |
| iCloud-Einstellungen (`SyncedPreferences`, KVS) | `SyncedPreferences.shared.start()` | nie aufgerufen; ohne Entitlement ohnehin wirkungslos |
| Menüleisten-Symbol, Willkommensfenster, Modellprüfung im Netz | `setupMenuBar`, `showWelcomeWindow`, `ModelAvailabilityChecker` | nie aufgerufen |
| Aufräumen beim Start/Ende (temp. WAVs, Ton wieder an, MLX-Server stoppen) | Start bzw. `applicationWillTerminate` | Start: nie; Ende: früher Ausstieg – das Aufräumen könnte sonst Dateien oder den MLX-Server des **echten** Tippi treffen (gemeinsames `$TMPDIR`, gleicher Port) |
| Dock-Klick / zweites Öffnen → Notizen | `applicationShouldHandleReopen` | früher Ausstieg |
| „Einstellungen…“ (command + ,) → volles Einstellungsfenster | `showSettingsWindow` | früher Ausstieg (sonst alle Reiter, siehe B5) |

Vor `applicationDidFinishLaunching` laufen die Initialisierer der `AppDelegate`-Eigenschaften. Geprüft: die
Hotkey-Manager und `GlobalKeyMonitor` speichern nur Werte, `AudioRecorder` erzeugt erst beim Aufnehmen eine
`AVAudioEngine`. **`PermissionsManager()` erzeugt zur Prüfung der Eingabeüberwachung einen echten Event-Tap**
(beim Messen gefunden, B9) – in der Kopie steigt sein Initialisierer sofort aus; `status` liest die Freigaben
selbst, ohne Tap. **`SnippetStore()` liest beim Erzeugen Dateien**
(`Tippi/snippets…json`, Espanso-Ordner `~/Library/Application Support/espanso/match`) – deshalb B4.

## B4 – Geteilte Pfade, Schlüsselbund, iCloud: umgelenkt

Alle fest „Tippi“ heißenden Orte gehen über **einen** zentralen Namen, `BildKopie.applicationSupport`: im echten
Tippi `~/Library/Application Support`, in der Kopie `~/Library/Application Support/Tippi Bild/Daten` (leer).

| Stelle | Echt | Kopie |
|---|---|---|
| `SnippetStore` (Snippets, importierte Snippets, Espanso-Standardordner) | `…/Tippi/`, `…/espanso/match` | `Tippi Bild/Daten/Tippi/`, `…/Daten/espanso/match` |
| `HistoryStore` (Verlauf `history.db`) | `…/Tippi/history.db` | `Tippi Bild/Daten/Tippi/history.db` |
| `NotesStore` lokal | `…/Tippi/Notes` | `Tippi Bild/Daten/Tippi/Notes` |
| `NotesStore` iCloud (`iCloud~dev~mwlr~Tippi`) | Ubiquity-Container | **ausdrücklich übersprungen** (zusätzlich: keine iCloud-Entitlements → `nil`) |
| `CurrencyConversion` (Kurs-Zwischenspeicher) | `…/Tippi/exchange-rates.json` | `Tippi Bild/Daten/Tippi/…` |
| `WhisperTranscriber.appModelDirectory` (Wörterbuch-/Diktatmodelle) | `…/com.tippi.app/Models` | `Tippi Bild/Daten/com.tippi.app/Models` |
| `GnotchiLiveText.socketPath` | `…/Gnotchi/live.sock` | `Tippi Bild/Daten/Gnotchi/live.sock` (gibt es nicht) |
| Schlüsselbund-Dienste `com.tippi.app` (API-Schlüssel, Verlaufsschlüssel), `com.tippi.app.snippet-approval` | wie genannt | `dev.mwlr.tippi.bild.<dienst>` – nie ein Eintrag des echten Tippi, also auch nie ein Schlüsselbund-Dialog |
| Einstellungen (`UserDefaults.standard`, Wörterbuch, eigene Prompts, Diktatmodus) | Domäne `com.tippi.app` | automatisch Domäne `dev.mwlr.tippi.bild` (eigene Kennung); kein `suiteName` im Code |

Nicht umgelenkt, weil in der Kopie nicht erreichbar (Diktat/MLX/Autovervollständigung starten nie):
`~/.cache/whisper`, `~/.cache/huggingface/hub`, FluidAudio-Modellordner, `~/.local/bin/uv`. Gemessen wird das
an der laufenden Kopie (B9: offene Dateien, Änderungen in Tippis Ordnern).

Info.plist der Kopie: `NSUbiquitousContainers` und die Sparkle-Schlüssel entfernt. Tippi hat kein `NSServices`,
keine URL-Schemata, keine Dokumenttypen; Login-Item nur auf Klick (Reiter Allgemein, nie per Befehl).
Entitlements der Kopie: **leer** (kein iCloud, kein Mikrofon, kein Netz-Entitlement nötig ohne Sandbox, keine
Apple Events). `embedded.provisionprofile` entfernt (Entwicklungsprofil für `com.tippi.app`).

## B5 – Welche Fenster (Information disclosure)

`SettingsView` hält **alle elf Reiter gleichzeitig geladen** (ZStack, nur Deckkraft wechselt – absichtlich, siehe
Kommentar dort). Wer das normale Einstellungsfenster öffnet, lädt also auch Anbieter (API-Schlüssel aus dem
Schlüsselbund), Snippets, Verlauf, Diktat (Modellordner), Autovervollständigung (`MLXServerManager`). Deshalb:

- `SettingsView` bekommt einen Parameter `mountedTabs` (Standard: alle – echtes Tippi unverändert). Die Kopie
  öffnet ein **eigenes** Fenster mit genau **einem** geladenen Reiter. Die Seitenleiste zeigt weiter alle Namen
  (nur Beschriftungen); ein Klick auf einen anderen Reiter zeigt eine leere Fläche.
- **Erlaubt** (`snapshot`-Liste):
  - `einstellungen` → Reiter **Allgemein**: Darstellung, Autostart-Status der Kopie, Schalter für lokale
    Schnellaktionen/Auswahlleiste – nur Einstellungen der eigenen Domäne, keine Inhalte.
  - `hilfe` → Reiter **Hilfe**: fester Hilfetext aus `Localizable.strings`, Suchfeld leer.
  - `ueber` → Reiter **Über**: Name, Version, Links.
- **Gesperrt**, mit Grund: Anbieter (API-Schlüssel-Felder), Prompts (eigene Prompts = Nutzerinhalt), Wörterbuch &
  Snippets (Snippets, Espanso-Import), Verlauf (diktierte/umgeschriebene Texte), Diktat (Modelle, Wörterbuch,
  Mikrofonliste), Autovervollständigung (MLX-Status, Modellordner), Kurzbefehle und Berechtigungen (keine Inhalte,
  aber Recorder-Felder bzw. Freigabe-Knöpfe – nicht nötig, lieber zu wenig), Notizen, Übersetzen, Emoji,
  Auswahlleiste, Vorschau, Willkommen. In der Kopie wären die meisten leer – die Liste bleibt trotzdem fest (wie
  K1/G45): sie schützt auch, falls die Kopie doch einmal Daten sieht.
- Aufgenommen wird **nur das eigene Fenster** (`SCContentFilter(desktopIndependentWindow:)`, gesucht über die eigene
  Fensternummer). Das Fenster öffnet die Kopie auch ohne Freigabe, damit `status` zeigt, dass es sich ohne Absturz
  aufbaut; ohne Freigabe kommt eine Fehlerantwort, kein Bild.

## B6 – Ingestion: feste Befehle

- **Vertrauensgrenze:** `debug.sock` – Bytes von einem anderen Prozess desselben Nutzers.
- **Schema:** `{"v":1,"id":"…","cmd":"status"|"snapshot"|"appearance", "window"|"mode": …}`. `v` Zahl 1 (kein
  Wahrheitswert). `id` 1–32 Zeichen A–Z/a–z/0–9 – wird Dateiname, kein Pfad-Ausbruch. `window` nur aus der festen
  Liste (B5), `mode` nur light/dark/system. Alles andere: verworfen, **keine Antwort**, Verbindung zu.
- **Parser:** `JSONSerialization` (Daten, kein Code-Pfad), kein `Codable` mit Typ-Auswahl, kein Shell-Aufruf.
- **Größe:** Rahmen = 4 Byte Länge + JSON, höchstens 4 KB; Länge 0 oder größer → Verbindung zu.
- **Kein Pfad aus der Nachricht** außer der geprüften `id`; keine Fetcher, keine Uploads, kein Rendering
  fremder Inhalte.

## B7 – Threat-Modeling (STRIDE je Grenze)

Datenfluss: `tippictl` → (Grenze 1: Socket, gleicher Nutzer) → `DebugSocketServer` → `DebugBridge` (Hauptthread)
→ eigenes Fenster → ScreenCaptureKit → `Bilder/<id>-<fenster>.png`, `Antworten/<id>.json` (Grenze 2: Dateien im
0700-Ordner) → `tippictl` liest und löscht die Antwort.

- **S – Spoofing (Grenze 1):** Ordner `Tippi Bild` 0700 (echter Ordner, gehört dem Nutzer, kein Link), Socket 0600,
  alte Socket-Datei nur entfernt, wenn sie ein Socket des Nutzers ist. Jede Verbindung wird **vor dem ersten
  gelesenen Byte** über das Audit-Token (nicht die PID) gegen Developer ID + Kennung `dev.mwlr.tippi.ctl` + Team
  LTKJ6Z2VYB geprüft. Nicht nur `anchor apple generic`: Apple-Development-Builds tragen `get-task-allow`.
  Umgekehrt prüft `tippictl` die Gegenseite (Developer ID + `dev.mwlr.tippi.bild`), bevor es sendet.
- **T – Tampering (Grenze 2):** Schreiben `.atomic` in 0700-Ordnern (ersetzt einen untergeschobenen Link, folgt ihm
  nicht). Dateinamen nur aus geprüfter `id` + fester Fensterliste.
- **R – Repudiation:** nicht relevant (ein Nutzer, eigene Testkopie); Protokoll nur „Befehl ausgeführt“, ohne Inhalt.
- **I – Information disclosure:** B4 (keine echten Daten erreichbar) + B5 (feste Fensterliste, nur eigenes
  Fenster). `status` liefert nur Zahlen/Kennungen: Version, Kennung, Freigaben (Bildschirmaufnahme,
  Bedienungshilfen, Eingabeüberwachung, Mikrofon), Darstellung, offene erlaubte Fenster mit Größe. Keine Titel,
  keine Inhalte, nichts davon ins Protokoll.
- **D – Denial of service:** ein Client gleichzeitig, höchstens 10 Befehle/s, Rest fällt weg; 4-KB-Rahmen.
- **E – Elevation:** Die Kopie hat keine Rechte (leere Entitlements, keine Freigaben außer ggf. Bildschirmaufnahme
  für sich selbst), keinen Shell-Aufruf. Ein Befehl kann nichts anderes als ein erlaubtes Fenster öffnen, ein Bild
  davon schreiben und Hell/Dunkel der Kopie umstellen.

**Missbrauchsfälle (abuse twins):**
- `snapshot verlauf` / `snapshot anbieter` → nicht in der Liste, keine Antwort.
- Fremdes Programm verbindet sich (ad-hoc signiert, gleiche Kennung) → Audit-Token-Prüfung scheitert, kein `ok`.
- Michael klickt in der Kopie auf „Einstellungen…“ oder öffnet sie ein zweites Mal → früher Ausstieg, nichts lädt.
- Kopie wird beendet → `applicationWillTerminate` räumt nichts auf, was dem echten Tippi gehört.

**Negative space – Annahmen:** Wir vertrauen dem eigenen Nutzerkonto. Schlimmster Einzelfall: ein Prozess des
gleichen Nutzers mit eigener Developer-ID-Signatur von Team LTKJ6Z2VYB und Kennung `dev.mwlr.tippi.ctl` – also nur
Michael selbst. Steuerung der Kopie nie über System Events / AppleScript per Namen (beide heißen „Tippi“, Gnotchi
28.10.); beendet wird nur die PID zum vollen Pfad der Kopie. `make build` ist für die Kopie tabu: es beendet per
`pkill -x Tippi` auch das echte Tippi – `scripts/bild-test.sh` ruft `xcodebuild` selbst auf.

**Restrisiko (hingenommen):** Ein Prozess des gleichen Nutzers kann den Socket löschen (Kanal fällt aus) und die
PNGs lesen; sie zeigen nur Allgemein/Hilfe/Über einer Kopie ohne Daten. Die Freigabe „Tippi Bild“ bleibt in den
Systemeinstellungen stehen; entfernen per `tccutil reset ScreenCapture dev.mwlr.tippi.bild`. Der Prozess der Kopie
heißt wie das echte Tippi (`Tippi`) – Werkzeuge, die nach Namen zählen, sehen zwei.

## B8 – Ort und Ablauf

`~/Applications/Tippi Bild.app` – unter `/tmp` finden die Systemeinstellungen eine App nicht über die Kennung
(Gnotchi 28.10.). Gleiche Kennung + gleiche Signatur am selben Ort → die Freigabe bleibt über Neubauten erhalten.
Das echte `/Applications/Tippi.app` wird nicht angefasst. `sh scripts/bild-test.sh` baut (`xcodebuild`, Debug,
`build-dev/`), passt Kennung und Info.plist an, signiert innen nach außen mit Developer ID ohne Entitlements,
baut und signiert `tippictl`, beendet nur die alte Kopie (PID zum vollen Pfad), installiert, startet.

## B9 – Prüfung (gemessen 2026-10-29)

Kopie PID 65051 neben dem echten Tippi PID 19552, das vorher und nachher lief (Bundle-Datum unverändert 28.10. 11:23).

- **Gefunden beim Messen, behoben:** `PermissionsManager.checkInputMonitoring` erzeugt zur Prüfung einen echten
  Event-Tap – schon im Initialisierer des `AppDelegate`, also vor jedem frühen Ausstieg, 10× beim Start. Jetzt
  steigt `PermissionsManager.init` in der Kopie sofort aus. Danach `CGGetEventTapList`: Kopie **0** Taps, echtes
  Tippi 3 (Gegenprobe).
- `tippictl status` → Kennung `dev.mwlr.tippi.bild`, Bildschirmaufnahme/Bedienungshilfen `false`, Mikrofon 0 (nie
  gefragt). `eingabeueberwachung` meldet `true` (`IOHIDCheckAccess`), ohne dass die Kopie je gefragt hat – Ursache
  **unklar** (Freigabe-Datenbank fürs Terminal nicht lesbar). Die einzige `ListenEvent`-Anfrage beim Start kommt
  vor der ersten Fensterserver-Verbindung und ist Systemverhalten: `log`, `spindump`, `ibtoold`, `1Password`
  stellen sie genauso.
- `appearance dark` → `darstellung` light → dark; `appearance system` → zurück.
- Ad-hoc-signierte Kopie von `tippictl` (gleiche Kennung) → kein `ok` (Exit 4), Protokoll „Verbindung abgelehnt
  (OSStatus -67050)“.
- `snapshot verlauf|anbieter|snippets`, `appearance rot` → keine Antwort (15 s), 0 Antwortdateien, Protokoll
  „ungültiger Befehl“.
- `snapshot einstellungen|hilfe|ueber` ohne Freigabe, je hell und dunkel → 6/6 `{"ok":false,"fenster_offen":true,
  "fehler":"Bildschirmaufnahme nicht freigegeben …"}`, `status` zeigt alle drei Fenster (860 × 672), kein Absturz,
  kein Bild.
- Gesamtes `com.tippi.app`-Protokoll der Kopie: 6 Zeilen (Snippet-Speicher sucht im **Ersatzordner**
  `Tippi Bild/Daten/espanso/match`, Kanal bereit, Befehl ausgeführt, Ablehnung, 2× ungültig). Keine Meldung zu
  Hotkeys, Monitoren, Sparkle, iCloud, Mikrofon, MLX, Gnotchi, Schlüsselbund.
- `lsof` der Kopie: 0 Netz-Sockets, einziger Unix-Socket `debug.sock` (0600, Ordner 0700), 0 offene Dateien in
  Tippis, Gnotchis, Espansos oder dem iCloud-Ordner. Entitlements leer, Sparkle-/iCloud-Schlüssel aus der
  Info.plist entfernt, kein Profil.
- Echte Einstellungen `com.tippi.app` (67 Schlüssel) vorher/nachher: einzige Abweichung `SULastCheckTime`
  (15:25:38) – im Zeitfenster stammen alle 61 Protokollzeilen vom echten Tippi, keine von der Kopie (Sparkle des
  echten Tippi). Domäne der Kopie enthält nur `appearance.mode.v1`. Geänderte Dateien in Tippis echten Ordnern:
  nur `.tippai-authorship.json` im iCloud-Notizordner – schreibt TippAI (lief), in Tippis Code nicht vorhanden.
- Tests 822 → 828 (6 neue in `DebugCommandTests`), 0 Fehler, `real-defaults-guard` grün. SwiftLint strikt,
  `concurrency-lint`, `docs-drift-check` grün.
- Release-Build (`xcodebuild … -configuration Release`, Binary 15:30:20, keine Quelldatei jünger): `debug.sock`,
  `dev.mwlr.tippi.bild`, `dev.mwlr.tippi.ctl`, „Befehlskanal“, „Tippi Bild“ je 0×. Debug-Build: 2/2/1/6/2.
- **`rafter-code-review`** lokal (CWE-Top-25 + `rafter secrets .`): keine Funde. Kein Shell-Aufruf in der App;
  Dateinamen nur aus geprüfter `id` und fester Fensterliste; `.atomic` in 0700-Ordnern; Peer-Prüfung beidseitig
  vor dem ersten Byte; Rahmen ≤ 4 KB; alle Änderungen an echten Pfaden/Diensten sind im Release
  Identitätsfunktionen (Test `testTestRunIsNotTheBildKopie`). **Kein `rafter run`** (Kontingent leer bis 26.11.).
- **Noch nicht gemessen:** ein echtes Fensterbild (braucht Michaels Freigabe für „Tippi Bild“) und die Drossel
  (10/s) im Lauf. Nebenbefund: vier gleichzeitige Verbindungen → die vierte wird abgewiesen (Rückstau 2) – gewollt.
