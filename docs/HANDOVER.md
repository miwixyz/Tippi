# Tippi — Handover-Dokumentation

Stand: 5. Oktober 2026 · Version: **2.23.0** (`docs/HANDOFF-CLAUDE.md` ist ein historischer Stand von v1.7.3, keine aktuelle Anleitung)
Autor: Michael Wildenauer

Dieses Dokument ist der **operative Einstieg und die technische Übergabe** für Tippi. Der aktuelle Stand steht oben und in §7; ältere Fachabschnitte sind Hintergrundwissen und müssen vor einer Änderung gegen den Code geprüft werden.

### Aktueller Übergabestand nach v2.21.0

- **v2.21.0:** Tag `v2.21.0` auf `95fa4a2`, Appcast und Build 473 in `302e625`. Diktat-Layout rein regelbasiert in `Core/DictationLayout.swift` (Anrede, ein Satz pro Zeile, Grußformel, Doppelpunkt nach „folgende“; `DictationSource` + Weiche `layoutWanted`: nie in Terminals und Apps mit „Enter nach dem Diktat“), Schalter `DictationSettings.layoutEnabled` (ab Werk aus). „Diktat für Mails“ in `Core/MailDictation.swift` (`MailDictationSettings`, ab Werk ⌃⌥⌘B, Konfliktprüfung `takenCombos`), Carbon-Hotkey id 7 in `AppDelegate.restartMailDictationHotkey` (nur bei eingeschaltetem Diktat und bereiter Engine, drückt nie Enter), UI `MailDictationHotkeyControls` in `UI/DictationHotkeySection.swift`. Autovervollständigung: nur aktuelle Zeile, mindestens 10 Zeichen und 2 fertige Wörter, keine Anfrage nach „?“ (`AutocompleteContext.requestLine`), Wiederholungsfilter `AutocompleteSanitizer.repeatsContext`, Kleben nur bei unfertigem letztem Wort. Währungsrechner: `CurrencyResultMode` (Standard `.copy`), `CurrencyOutcome`, Hinweis per `ToastWindowController.show(message:anchor:seconds:)` an der Markierung. Notizen: Seitenleiste per Menübefehl ⌃⌘S (`TippiApp.swift`, `.toggleNotesSidebar`), Zustand in `NotesSettings`. 609 Tests.
- **unreleased (Branch `live-diktat-vorschau`):** `Voice/AudioRecorder.swift` läuft auf `AVAudioEngine` (Tap → 16 kHz mono im Speicher via `Voice/AudioCapture.swift`, WAV erst in `stop()`; Mikrofonwechsel wird abgefangen). Live-Text: `Voice/LiveTranscriptionPreview.swift` erkennt jede Sekunde `recorder.snapshot()` mit `ParakeetTranscriber.transcribe(samples:)`, Takt streckt sich bei langsamen Durchläufen; Anzeige in `RecordingIndicatorWindow` (`IndicatorContainer`/`LiveTextBox`, feste Fenstergröße 480×150). Schalter `DictationSettings.livePreviewEnabled` (Standard aus, nur Parakeet). Schriftgröße `DictationSettings.liveTextSize` (`LiveTextSize`: 13/17/22 pt, Fenster 480×150/580×185/720×235, Test misst Passform mit echter Schrift). Position: `DictationSettings.IndicatorPosition` jetzt 6 Fälle (Deklaration in `RecordingIndicatorWindow.swift`, weil DictationController am 750-Zeilen-Limit), Mitte behält Rohwerte `top`/`bottom` → alte Einstellungen bleiben; `RecordingIndicatorWindowController.origin(for:size:in:)` getestet. **Gerätewechsel mitten im Diktat (AirPods):** Bluetooth schaltet für einige Sekunden auf 24 kHz um; ein Tap mit altem 48-kHz-Format löst in AVAudioEngine eine Objective-C-Exception aus, die Swift nicht fangen kann (gemessen 02.10., Pille blieb hängen). Daher `AudioCapture.formatsMatch` vor jedem `installTap` und Neustart mit *frischer* Engine, alle 0,4 s bis 6 s lang; gelingt es nie, bleibt das bisher Aufgenommene erhalten. **Review 02.10. (nach 2.22.0):** Der Recorder ist geteilt — `stop(ifStartedBy:)` stoppt nur die eigene Aufnahme; übernimmt ein anderer Besitzer, parkt `start()` die fertige WAV in `displaced`, der ursprüngliche Besitzer holt sie mit `stop(ifStartedBy:)` oder löscht sie mit `discard(ifStartedBy:)`; beim Beenden `discardAll()`. `stop()` wartet bis 150 ms auf die nächste Tap-Lieferung (Takt ~100 ms) und leert den Resampler (`flush`), sonst fehlte das Ende des letzten Worts; Messwert im Log (`com.tippi.app`/`recorder`, „stop: waited … ms“). Eine Aufnahme ist auf 30 Minuten begrenzt (`SampleStore.maxSamples`). Indikator- und Toast-Fenster haben einen transparenten Rand für den Schatten (`shadowRoom`). Spike: `docs/spikes/2026-10-02-live-diktat/`. 621 Tests.
- **v2.20.1:** `Core/InputAnchor.swift` setzt Prompt-Pop-up und Diktat-Pop-up an Markierung bzw. Schreibmarke, Maus nur als Rückfall (AX-Abfrage höchstens 150 ms). Eigene Wörter gehen nur noch passend ans Modell (`AutocompleteRequest.relevantGlossary`). `scripts/record-demo.sh`; `scripts/docs-drift-check.sh` prüft auch die Website. 575 Tests.
- **v2.20.0:** Design der App-Familie: `UI/FamilyTheme.swift` (Schiefer, Plus Jakarta Sans als gebündelte Schrift), Website mit gemeinsamem `docs/style.css`. 558 Tests.

Ältere Stände unten sind historisch und beschreiben den Code zum jeweiligen Zeitpunkt.

#### Stand v2.19.0

- **v2.19.0:** Währungsrechner (`Core/CurrencyConversion.swift`: `CurrencyParser`, `ExchangeRateTable`, `ExchangeRateService` mit fester URL, Cache in `Application Support/Tippi/exchange-rates.json`, Abrufregel `decide()`; Favoriten `UI/CurrencyFavoritesSection.swift`), Passwort (`Core/PasswordGenerator.swift`, Einfügen über `TextInsertion.insertSecret`: `.currentHostOnly` + Concealed, 60 s Zwischenablage). Neue Schnellaktionen in `LocalTextAction` (Kategorie `.enclose`), Auswahlleiste zweireihig, Popup-Knöpfe in `UI/PromptPopup/LocalActionButtons.swift`. Markieren = reine Formatänderung → `TextInsertion.pasteFormatting` (Markierung wiederherstellen, dann Rich-Paste, nie vorher AX-Klartext). Leiste ignoriert Neuaufbau, solange der Zeiger auf ihr steht. Design: `docs/SECURE-DESIGN-currency-password.md`. 558 Tests.

#### Stand v2.18.0

- **v2.18.0:** Reiter „Berechtigungen“ (`UI/PermissionsSettingsTab.swift`, Status aus `Core/PermissionsManager.swift` inkl. Bildschirmaufnahme + Mitteilungen). Eigene Snippets in der „:“-Liste (`Core/Emoji/InlineSuggestion.swift`, `SnippetStore.suggestions(forTypedTrigger:limit:)`; importierte Shell-Snippets bewusst ausgenommen, Einfügen geht über `action(forTrigger:)`). Caret in Obsidian/Electron: `TextCapture.boundsForSelectedTextMarkerRange` als dritter Fallback in `AutocompleteController.caretRect`, nur bei Breite ≤ 2 pt (`AutocompleteGeometry.isCollapsedCaret`) — ein leeres Feld liefert sonst die ganze Zeile.

#### Stand v2.17.0

- **v2.17.0:** `8c17672` — eingebaute Prompts bearbeitbar (`Core/PromptLibrary.swift`: `BuiltInPromptEditStore`, `PromptOrderStore`, beide iCloud-synchron), gemeinsame Reihenfolge per Drag & Drop (`UI/PromptsSettingsTab.swift`), importierte Snippets bearbeitbar (`UI/SnippetEditorSheet.swift`, Freigabe fällt bei Änderung weg), zwei frei belegbare Übernahmetasten (`AutocompleteKeyRules`/`AutocompleteKeyBindings` in `AutocompleteLogic.swift`), Kapsel-Pop-up, eigener Bereich `UI/AutocompleteSettingsTab.swift`, Diktat-Hotkey in `UI/DictationHotkeySection.swift`. Prüfstand `scripts/autocomplete-pruefstand.py` (Blindvergleich; Rohfortsetzung mit dem Chat-Modell und die Gemma-Grundmodelle gemessen und verworfen). 516 Tests.

#### Stand v2.16.3

- **v2.16.3:** `3c0e421` ersetzt die Bundle-ID-Listen in den Einstellungen (Ausschlussliste Autovervollständigung, Enter nach Diktat) durch das gemeinsame `Tippi/UI/AppListEditor.swift`: Symbol + Name, Hinzufügen per Menü (laufende Apps, `NSOpenPanel` für andere). `TippiTests/AppInfoTests.swift` prüft Namensauflösung und Rückfall. 474 Tests.

#### Stand v2.16.2

- **Veröffentlicht:** [GitHub-Release v2.16.2](https://github.com/miwixyz/Tippi/releases/tag/v2.16.2), signiertes und von Apple notarisiertes DMG, Sparkle-Appcast im Gist auf 2.16.2 verifiziert. Das Tag zeigt auf `6a7b030` (gebauter Stand, Build 427); der nachgelagerte Appcast-/Buildnummer-Commit ist `eec316e` auf `main`. Die Arbeitskopie war nach dem Release sauber und mit `origin/main` synchron.
- **Letzte Korrekturen:** `0e6a922` behebt sieben Audit-Funde in `TextInsertion`, `TextCapture`, `PasteboardSnapshot`, `NotesStore`, `HistoryStore` und `LLMProvider`; `TippiTests/AuditFollowupTests.swift` enthält 16 neue Regressionstests. Einzelheiten stehen in `CHANGELOG.md` unter 2.16.2.
- **Geprüft:** `make test` (472 Tests, keine Fehler, echte App-Einstellungen unverändert), `make lint`, `scripts/docs-drift-check.sh`, `scripts/docs-release-gate.sh`, `git diff --check`, Signatur, kurzer App-Start, Apple-Notarisierung, Gatekeeper, GitHub-Asset und Gist-Appcast. `rafter run` prüfte den veröffentlichten Code auf `main` (Scan `89daa0ae-29c1-49ac-a299-738ecb5d04bd`); die drei Meldungen betreffen unveränderte Stellen und sind Fehlalarme: `SelectionSignature` ist keine geheime Signatur, `/api/v1/models` in zwei Kommentaren keine veraltete API.
- **Nicht manuell nachgewiesen:** ein echter Konflikt zwischen zwei Macs in iCloud, die vollständige App-Matrix für Einfügen/Bedienungshilfen sowie ein Sparkle-Update auf einem zweiten Mac. Die Notiz-Konflikte wurden mit isolierten Testverzeichnissen geprüft. Diese manuellen Prüfungen bleiben für eine spätere Qualitätsrunde offen; sie wurden nicht als bestanden verbucht.
- **Nächster Einstieg:** erst `git status`, `git log -5 --oneline`, `CHANGELOG.md`, `ARCHITECTURE.md` und dieses Dokument lesen. Für Release-Befehle gilt §7 unten; die alte Datei `docs/HANDOFF-CLAUDE.md` nicht als Runbook verwenden.

---

## 1. Was ist Tippi?

Tippi ist ein systemweiter KI-Schreibassistent für macOS. In jeder beliebigen Mac-App (Mail, Safari, Notes, Slack, VS Code, ...) markiert der Nutzer Text, drückt einen konfigurierbaren Hotkey (Standard: `⌥⌘T`), wählt aus einem Cursor-Popup eine Aktion (Verbessern, Übersetzen, Grammatik, ...), sieht das KI-Ergebnis im Vorschau-Fenster und entscheidet: Ersetzen, Anhängen, Kopieren, Neu generieren.

Ab v1.1.0 kommt Voice Input dazu: Push-to-Talk-Mikrofon-Button im Popup für Diktat (ohne Selektion) und Sprach-Befehle (mit Selektion).

**Konzeptueller Kern:** App-agnostisch via macOS Accessibility API. BYOK (Bring Your Own Key) Modell für LLM-Provider. Daten verlassen den Mac nur zum aktiven gewählten Provider. Keine Telemetrie.

**Inspirationsquelle:** Pismo (kostenpflichtig auf Mac App Store). Tippi ist die Open-Source-Variante mit mehr Providern, vollständig BYOK und lokalem Voice-Input via Whisper.

---

## 2. Repository

- **GitHub:** https://github.com/miwixyz/Tippi (public, Open-Source)
- **Lokal:** `~/Coding/Tippi/`
- **Branch:** `main`
- **Lizenz:** MIT

---

## 3. Tech-Stack

| Schicht | Wahl | Begründung |
|---------|------|------------|
| Sprache | Swift 5.10+ | Native Apple-Toolchain, höchste Performance |
| UI | SwiftUI + AppKit-Bridges | Modern für Settings/Wizard, AppKit wo Low-Level nötig (NSStatusItem, NSPanel) |
| Min macOS | 15.0 Sequoia | Aktuelles macOS, neueste SwiftUI-APIs (z.B. `onKeyPress`) |
| Architektur | arm64 only (Apple Silicon) | Schlankes Bundle, keine Intel-Last |
| Build | XcodeGen (`project.yml`) → Xcode 16+ | Project-Datei im Repo unnötig, einfach reproduzierbar |
| Signing | Developer ID Application + Hardened Runtime + Notarisierung | Erforderlich für Distribution außerhalb App Store |
| Distribution | DMG via `hdiutil` + GitHub Releases | Standard macOS-Paket, direkt downloadbar |
| Auto-Updates | Sparkle 2 (SPM) | Appcast via GitHub Releases, EdDSA-signiert |
| Voice Input | whisper.cpp (statischer Binary `whisper-cli`) | Lokal, kein Abo, kein Netz, GGML Metal |

**Bewusst nicht verwendet:**
- Mac Catalyst (iPad-Origin, schlechtere Mac-UX)
- Electron / Tauri (System-Integration nicht tief genug)
- Storyboards (SwiftUI-First)
- Sandbox (verhindert systemweiten Text-Capture)
- Homebrew-Whisper (zu viele transitive Deps, statischer Binary sauberer)

---

## 4. Modul-Struktur

Historischer Grundriss aus der Anfangszeit. Den aktuellen Baum (Stand v2.22.1) führt `ARCHITECTURE.md` §2.

```
Tippi/
├── App/
│   ├── TippiApp.swift              @main, leere Settings-Scene
│   └── AppDelegate.swift           Menubar, Hotkey-Wiring, Window-Controller,
│                                   Permission-Observer, SPUStandardUpdaterController
├── Core/
│   ├── PermissionsManager.swift    AX + Input Monitoring Status & Prompts
│   ├── KeychainStore.swift         BYOK-Speicherung (Service: com.tippi.app)
│   ├── HotkeyManager.swift         CGEventTap + Carbon-Backup (Legacy, weiterhin im Code)
│   ├── HotkeyTrigger.swift         ModifierKey enum + Trigger types
│   ├── GlobalKeyMonitor.swift      NSEvent.addGlobalMonitorForEvents — primärer Hotkey-Pfad
│   ├── KeyCombo.swift              Codable Tasten-Kombi + display strings + UserDefaults-Speicherung
│   ├── PasteboardSnapshot.swift    Capture/Restore für Clipboard-Roundtrip
│   ├── TextCapture.swift           AX-API zuerst, Pasteboard-Fallback
│   ├── TextInsertion.swift         Replace / Append / Copy via simuliertem ⌘V
│   ├── CustomPrompt.swift          User-Prompts + JSON-Persistierung
│   ├── TippiColors.swift           Color.tippiMist Extension (BrandNavy/BrandSurface nur als Asset)
│   └── Notes/                      (ab v2.3.0)
│       ├── Note.swift              Model — id/content/createdAt/modifiedAt, nicht Codable
│       ├── NotesStore.swift        iCloud-Ubiquity-Container + lokaler Fallback, NSFileCoordinator
│       └── NotesSettings.swift     Hotkey-Enable/Combo, UserDefaults — Muster von TranslateSettings
├── LLM/
│   ├── LLMProvider.swift           Protocol + LLMError
│   ├── OpenAIProvider.swift        gpt-6-luna (reasoning_effort none), /v1/chat/completions
│   ├── AnthropicProvider.swift     claude-haiku-4-5, /v1/messages
│   ├── GeminiProvider.swift        gemini-flash-latest, generativelanguage.googleapis.com
│   ├── MistralProvider.swift       mistral-small-latest, OpenAI-kompatibel
│   ├── OllamaProvider.swift        llama3.3, localhost:11434
│   └── LLMRouter.swift             Provider-Reihenfolge, Fallthrough-Logik
├── Voice/
│   ├── AudioRecorder.swift         AVAudioRecorder-Wrapper, Push-to-Talk, WAV-Output in temp dir
│   ├── WhisperTranscriber.swift    Subprocess: whisper-cli --output-txt → liest .wav.txt Sidecar
│   └── WhisperModelManager.swift   Model-Download (URLSession), Progress-Tracking,
│                                   Speicherort: ~/Library/Application Support/Tippi/Models/
├── UI/
│   ├── WelcomeView.swift           5-Schritt-Setup-Wizard + Demo-Sheet
│   ├── SettingsView.swift          5 Tabs (General, Hotkeys, Providers, Prompts, About)
│   ├── HotkeyRecorderField.swift   Tap-to-record Hotkey-Feld via NSEvent local monitor
│   ├── PromptPopup/
│   │   ├── DemoPrompt.swift        Eingebaute + benutzerdefinierte Prompts (kombinierte all-Liste)
│   │   ├── PromptPopupView.swift   SwiftUI-Popup-Inhalt; enthält VoiceMode enum (.dictate /
│   │   │                           .voicePrompt), VoiceSection, DirectInsertRow
│   │   └── PromptPopupController.swift  NSPanel, Positionierung am Cursor
│   ├── Preview/
│   │   ├── PreviewView.swift       Original | Suggestion Side-by-Side
│   │   └── PreviewWindowController.swift  NSWindow, Floating-Level; CloseDelegate wired
│   └── Notes/                      (ab v2.3.0)
│       ├── NotesWindowController.swift  Resizable NSWindow (aktivierend, kein Panel — anders als
│       │                           Preview/Translate: Notes ist ein eigenständiges Editier-Fenster)
│       ├── NotesRootView.swift     Split View, refresh() bei .onAppear
│       ├── NotesListView.swift     Liste + Neu/Löschen (Löschen nur mit Bestätigungsdialog)
│       ├── NotesEditorView.swift   Autosave debounced, Wort-/Zeichen-/Zeilenzähler
│       └── PlainTextEditor.swift   NSViewRepresentable — Paste-Erkennung + Rechtschreibprüfung
├── Helpers/
│   └── whisper-cli                 Statischer Binary (gitignored), via `make prepare-binary`
└── Resources/
    ├── Info.plist                  LSUIElement=true, NSAppleEventsUsageDescription,
    │                               SUFeedURL, SUPublicEDKey
    ├── Tippi.entitlements          app-sandbox=false, network.client=true
    ├── Assets.xcassets/
    │   ├── AppIcon.appiconset      10 macOS-Größen (CoreGraphics, kein third-party)
    │   ├── AccentColor.colorset    Schieferblau #3E5998 / dunkel #98AEE1 (ab 2.20.0, Design der App-Familie; vorher stand hier #3B8CFF, das Asset war aber #083077) — treibt .tint / .accentColor app-weit
    │   ├── BrandNavy.colorset      #10192B (fix, kein Dark-Variant — Logo-Farbe)
    │   ├── BrandSurface.colorset   Soft White / Dark Navy (adaptiv Light/Dark)
    │   └── BrandMistBlue.colorset  Mist Blue / Deep Navy-Blue (adaptiv Light/Dark)
    ├── en.lproj/Localizable.strings
    └── de.lproj/Localizable.strings

scripts/
├── release.sh                      Vollautomatische Build-Notarisierungs-Release-Pipeline
├── modell-pruefstand.py            Prüfstand vor jedem Wechsel des Anthropic-Standardmodells: eingebaute Prompts aus DemoPrompt.swift, 12 Steuer- + 8 verdeckte Abnahmefälle (modell-pruefstand-abnahme.json), Exit 0/1
└── prepare-binary.sh               Build-Skript für whisper-cli (whisper.cpp v1.7.4, statisch)

docs/
├── HANDOVER.md                     Dieses Dokument
├── BRANDKIT.md                     Farbpalette, adaptive Mappings, Typografie, Ikonografie
├── demo.gif                        Demo-GIF für README (DE/EN zweisprachig, 65 s, 30.09.2026)
├── tippi-demo.mp4                  Demo-Video für die Website (DE/EN zweisprachig, mit Ton, selbst gehostet), Poster tippi-demo-poster.png
└── mascot.png                      Tippi-Maskottchen (Navy-Kreis, weißer Bot, Signal-Blue-Blase)
```

---

## 5. Schlüssel-Mechaniken

### 5.1 Text-Capture (das Herzstück)

`TextCapture.captureSelectedText(sourceApp:)` versucht zwei Pfade:

1. **Accessibility API**: `AXUIElementCreateSystemWide()` → focused element → `kAXSelectedTextAttribute`. Funktioniert mit nativen Apps und manchen Cross-Platform-Apps.
2. **Pasteboard-Fallback**: Pasteboard snapshot → simuliertes `⌘C` via CGEvent.post → poll bis changeCount sich ändert → restore. Funktioniert in Apps ohne AX-Support (manche Electron-Apps).

Beide Pfade brauchen die **Accessibility-Berechtigung**. Der Pasteboard-Pfad ist immer ein letzter Strohhalm.

### 5.2 Hotkey-Erkennung

Drei parallel registrierte Hotkey-Pfade — jeder hat eigene macOS-Berechtigungs-Anforderungen:

| Pfad | API | Permission | Status |
|------|-----|------------|--------|
| **`HotkeyManager`** (Legacy) | `CGEventTap` für `.flagsChanged` (Double-Tap/Hold) | Input Monitoring | Für ⌥⌥-Style-Trigger, oft unzuverlässig bei selbst-signierten Builds |
| **Safety Hotkey** | Carbon `RegisterEventHotKey` | Keine | Hardcoded ⌃⌥⌘T als Notlösung |
| **`GlobalKeyMonitor`** (primär) | `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` | Accessibility | Primärer in-App-Hotkey, lädt Combo aus UserDefaults |

**TCC-Falle:** Ad-hoc-signierte Builds haben oft TCC-Probleme. `make build` signiert lokale Builds mit **Apple Development**, die veröffentlichte App mit **Developer ID**. Beide nutzen dieselbe Bundle-ID, aber unterschiedliche Signatur-Identitäten und können einander die Bedienungshilfen-Freigabe verdrängen. Für einen Test neben der installierten Release-App `scripts/devid-testbuild.sh` verwenden; Details in `README.md` und `CONTRIBUTING.md`.

**Fallback für Endnutzer:** Settings → Hotkeys → „macOS-Tastatur-Einstellungen öffnen" → bindet eine beliebige Tasten-Kombi an den Menüpunkt „Tippi auslösen…". macOS macht das Routing — funktioniert garantiert.

### 5.3 Text-Insertion

`TextInsertion.replace(with: text)`:

1. Pasteboard-Snapshot anfertigen
2. Pasteboard löschen + neuen Text setzen
3. 30 ms warten (Clipboard sich setzen lassen)
4. Simuliertes `⌘V` via CGEvent.post
5. 250 ms warten (Paste durchläuft)
6. Pasteboard auf Snapshot restaurieren

`append` ist Phase-2-äquivalent zu replace mit `"<original> <suggestion>"` als Eingabe. Phase 3.5 (zukünftig) wird via AX die Cursor-Position ans Selection-Ende setzen.

`copy` setzt nur das Pasteboard, kein Paste.

### 5.4 LLM-Routing

`LLMRouter.complete(systemPrompt:userText:)`:

1. Lade `preferredProviderID` aus `UserDefaults` (Default: `openai`)
2. Sortiere Provider-Array mit Preferred zuerst
3. Iteriere: wenn Provider Key braucht und keiner gespeichert → continue. Sonst: complete() aufrufen.
4. Bei `LLMError.noAPIKey` → fall through zum nächsten Provider
5. Wenn niemand funktioniert → `LLMError.noProviderConfigured`

Im Demo-Sheet und Preview-Window wird bei `.noProviderConfigured` / `.noAPIKey` auf den lokalen `DemoPrompt.transform`-Fallback umgeschaltet (Text wird per simpler Heuristik verändert, mit „Lokale Demo"-Markierung).

### 5.5 Custom Prompts

`CustomPromptStore` (Singleton, `@MainActor`) speichert benutzerdefinierte Prompts als JSON in UserDefaults (Key: `tippi.customPrompts.v1`).

Eigenschaften pro Prompt:
- `id: UUID`
- `title: String` — angezeigt im Popup
- `symbol: String` — SF Symbol Name
- `systemPrompt: String` — wird als System-Message an das LLM gegeben

`DemoPrompt.all` kombiniert `builtIn` + `customPromptStore.prompts.map { $0.asDemoPrompt() }`. Das Popup zeigt alle, der Nutzer wählt.

### 5.6 Voice Input (ab v1.1.0)

Voice Input hat zwei Modi, gesteuert durch `VoiceMode` enum in `PromptPopupView.swift`:

**`VoiceMode.dictate`** — kein Text ist markiert:
1. Nutzer drückt Mic-Button im Popup
2. `AudioRecorder` nimmt auf (WAV in temp dir)
3. `WhisperTranscriber` transkribiert via `whisper-cli`
4. Transkript erscheint im Popup mit allen AI-Prompts + „Direkt einfügen"-Button (`DirectInsertRow`)
5. Direkt einfügen: Text landet ohne LLM-Aufruf an der Cursor-Position

**`VoiceMode.voicePrompt`** — Text ist markiert + Mic gedrückt:
1. Nutzer spricht einen Befehl (z.B. „mach das formeller")
2. Transkript wird als `systemPrompt` in einen dynamischen `DemoPrompt` eingesetzt
3. Direkt weiter zu `PreviewWindow` — kein zweiter Prompt-Picker

**whisper-cli — Technisches:**
- Statischer Binary (kein Homebrew): gebaut mit `GGML_BACKEND_DL=OFF`, `GGML_METAL_EMBED_LIBRARY=ON` aus whisper.cpp v1.7.4
- Wird per `make prepare-binary` (→ `scripts/prepare-binary.sh`) in `Tippi/Helpers/whisper-cli` abgelegt
- `release.sh` kopiert den Binary in `Contents/MacOS/whisper-cli` des App-Bundles
- Binary ist gitignored; Nutzer des Repos müssen `make prepare-binary` einmalig ausführen

**Ausgabe-Pfad-Bug (dokumentiert):** `whisper-cli --output-txt` schreibt `<input>.wav.txt` (nicht `<input>.txt`). `WhisperTranscriber` liest daher explizit den `.wav.txt`-Sidecar.

**Models:** Liegen in `~/Library/Application Support/Tippi/Models/` (nicht im Bundle). `WhisperModelManager` übernimmt Download (URLSession) + Progress-Tracking. Standard: `ggml-base.en.bin` (~150 MB).

### 5.7 Sparkle Auto-Updates (ab v1.0.1)

- **SPM-Abhängigkeit:** `Sparkle`, from: `2.0.0`
- **AppDelegate:** `SPUStandardUpdaterController` initialisiert beim App-Start
- **Info.plist Keys:**
  - `SUFeedURL`: `https://gist.githubusercontent.com/miwixyz/595ce79e698bb6a98008dc061f1f4a78/raw/appcast.xml`
  - `SUPublicEDKey`: EdDSA Public Key für Update-Signatur-Verifikation
- **Versionierung:** Sparkle vergleicht `CFBundleVersion` (Build-Nummer), nicht `CFBundleShortVersionString` (Marketing-Version). Build-Nummer wird automatisch berechnet: `git rev-list --count HEAD` → monoton steigend, kein manuelles Tracking nötig
- **Appcast-Generierung:** `scripts/release.sh` ruft `~/Developer/sparkle-tools/bin/generate_appcast` auf, aktualisiert den Gist und prüft dessen Inhalt. Danach `appcast.xml` zusammen mit der tatsächlichen Buildnummer in `project.yml` committen und pushen.
- **DMG-Hosting:** GitHub Releases (Gist kann keine Binaries liefern). `generate_appcast` mit `--download-url-prefix https://github.com/miwixyz/Tippi/releases/download/v<version>/` aufrufen
- **Signierung der Updates:** `sign_update`-Tool aus sparkle-tools, Output-Key gehört in `SUPublicEDKey`

### 5.8 Systemweite Tipp-Expansion (ab v2.0, erweitert in v2.1)

Ein einziger Keystroke-Watcher (`SnippetKeystrokeMonitor`) bedient inzwischen **vier** Pfade. Das ist die wichtigste Regel dieses Bereichs: **niemals einen zweiten globalen Monitor registrieren** — jeder Tastendruck käme doppelt im Matcher an. Start/Stop ausschließlich über `AppDelegate.applyKeystrokeMonitorState()`, das die Feature-Schalter verodert; wird dort einer vergessen, feuert das betroffene Feature stillschweigend nie.

Technik: `NSEvent.addGlobalMonitorForEvents` — braucht nur Accessibility, **kein** Input Monitoring, weil nie Tastenanschläge unterdrückt werden. Getippte Zeichen erreichen immer zuerst die Ziel-App und werden danach per synthetischer Backspaces zurückgenommen (`SnippetTextInjector`). Diese Eigenschaft bestimmt das gesamte Bedienkonzept.

Reihenfolge der Prüfung pro Tastendruck (spezifisch vor unspezifisch):

1. **Snippet-Trigger** — nutzerdefiniert, gewinnt immer
2. **`:name:`-Emoji** — braucht beide Doppelpunkte; mindestens ein Buchstabe im Namen, sonst würden `12:30:` und `10:1:` expandieren
3. **Emoticons** — `:-)` → 🙂; nur nach Leerzeichen/Zeilenanfang, sonst träfe es `a[:(b)]` und `http://`
4. **Leertaste-Übernahme** aus der Vorschlagsliste

Warum die Leertaste und nicht Tab oder Return: Da nichts unterdrückt werden kann, muss das Abschlusszeichen nachträglich zurücknehmbar sein. Ein Leerzeichen fügt überall genau ein Zeichen ein. Tab wechselt in Mail und Slack das Feld — die Backspaces landeten dann im falschen Feld. Return sendet die Nachricht.

Die Vorschlagsliste (`EmojiSuggestionPanel`) darf **nie** Key-Window werden (`canBecomeKey = false`), sonst erreichen die Tastenanschläge des Nutzers die App nicht mehr, in der er schreibt — der v2.0.1-Showstopper. Deshalb hat sie bewusst keine Pfeiltasten-Navigation. Der Picker (`EmojiPickerPanel`, ⌥⌘E) **muss** dagegen Key-Window werden: Er hat ein echtes Suchfeld. Gleiche Regel, gegensätzliches Ergebnis — pro Panel entscheiden, nie das Muster kopieren.

Emoji-Daten: `Tippi/Resources/emoji-data.json`, generiert von `scripts/generate-emoji-data.py` aus gepinnten Unicode-Quellen (Emoji 16.0 + CLDR 48.2.1). `--check` verifiziert, dass die committete Datei zum Generator passt; `release.sh` bricht ab, wenn nicht.

### 5.9 Notizen + iCloud-Sync (ab v2.3.0)

Zwei getrennte Sync-Mechanismen, nicht einer — bewusst, weil sie unterschiedliche Anforderungen haben:

- **Notiz-Inhalt** → iCloud-Ubiquity-Container (`FileManager.url(forUbiquityContainerIdentifier: nil)`, Container-ID `iCloud.dev.mwlr.Tippi`). Eine reine `.txt`-Datei pro Notiz (Dateiname = `<uuid>.txt`), kein JSON-Wrapper — `createdAt`/`modifiedAt` kommen aus den Dateisystem-Attributen, nicht eingebettet. Lesen/Schreiben/Löschen laufen **immer** durch `NSFileCoordinator` — ohne Koordinator race'd jeder Zugriff mit dem iCloud-Sync-Daemon und kann Daten korrumpieren oder verlieren.
- **Fenster-Settings** (Größe/Position, Sortierung) → `NSUbiquitousKeyValueStore` (`NotesPreferences.swift`) — bewusst getrennt vom Inhalt, weil dieser Store auf 1 MB/1024 Keys begrenzt ist und für genau solche kleinen Key-Value-Daten gebaut ist. **Enthält nie** Notiz-Text, API-Keys oder sonstige Credentials.
- **Kein Live-Sync.** Die Liste aktualisiert nur beim Öffnen des Fensters (`NotesStore.refresh()`), kein dauerhafter `NSMetadataQuery`. Eine Notiz, die gerade erst auf dem anderen Mac erstellt wurde, kann beim ersten Öffnen noch als iCloud-Platzhalter vorliegen — `startDownloadingUbiquitousItem` wird angestoßen, die Datei erscheint dann beim nächsten Öffnen. Konfliktauflösung ist Last-Write-Wins über `modifiedAt` — für eine Einzelnutzer-Notizliste ausreichend, kein CloudKit-Aufwand nötig.
- **Fallback ohne iCloud:** Ist kein iCloud-Account aktiv, schreibt `NotesStore` lokal nach `~/Library/Application Support/Tippi/Notes/` — Feature funktioniert immer, Sync ist Bonus. Einmalige Migration lokal→iCloud sobald der Container verfügbar wird, mit echtem Fehler-Handling (kein `try?`, das Original wird nur nach verifiziertem Kopiererfolg gelöscht).
- **Entitlement-Voraussetzung:** `com.apple.developer.icloud-container-identifiers` + `icloud-services: [CloudDocuments]` + `ubiquity-kvstore-identifier` in `Tippi.entitlements` — via Xcode → Signing & Capabilities → „+ iCloud" gesetzt (Portal-Capability + Provisioning-Profil legt Xcode dabei selbst an). App bleibt unsandboxed (siehe 8.6) — CloudKit/Ubiquity funktioniert trotzdem, das Entitlement bestimmt nur, wohin iCloud schreibt.
- **Hotkey:** fünfter Carbon-Hotkey (`hotKeyID = 5`), Default ⌥⌘N, remappbar über `NotesSettings` (gleiches Muster wie `TranslateSettings`/`EmojiSettings`) — Settings → Hotkeys.

---

## 6. LLM-Provider — aktuelle Default-Modelle (Stand 2026-09-02, 11 Provider)

| Provider | Default Modell | API Endpoint | Auth | Notes |
|----------|----------------|--------------|------|-------|
| OpenAI | `gpt-6-luna` | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer <key>` | Schnell, günstig, gute deutsche Sprache |
| Anthropic | `claude-haiku-4-5` | `https://api.anthropic.com/v1/messages` | `x-api-key: <key>` + `anthropic-version: 2023-06-01` | Beste Prosa-Qualität |
| Google | `gemini-flash-latest` | `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` | Header `x-goog-api-key: <key>` (nicht Query-Param — Tabelle war hier veraltet) | Großzügiges Free-Tier. 2.5-Generation seit 2026-09 teils HTTP 404 („no longer available to new users") |
| Mistral | `mistral-small-latest` | `https://api.mistral.ai/v1/chat/completions` | `Authorization: Bearer <key>` | EU-Hosting (Paris) |
| Scaleway | `llama-3.1-8b-instruct` | `https://api.scaleway.ai/v1/chat/completions` | `Authorization: Bearer <key>` | EU-Hosting (Paris), Groq-Klasse Speed |
| Groq | `openai/gpt-oss-20b` | `https://api.groq.com/openai/v1/chat/completions` | `Authorization: Bearer <key>` | LPU-Hardware, ~270-800 tok/s |
| Kimi/Moonshot | `kimi-k2` | `https://api.moonshot.cn/v1/chat/completions` | `Authorization: Bearer <key>` | 1T-MoE, 256K context |
| Nebius | `Qwen/Qwen3-30B-A3B-Instruct-2507` | `https://api.studio.nebius.ai/v1/chat/completions` | `Authorization: Bearer <key>` | EU-Hosting (Amsterdam) |
| **OpenRouter** | `openai/gpt-6-luna` | `https://openrouter.ai/api/v1/chat/completions` | `Authorization: Bearer <key>` | Unified Gateway, 300+ Modelle, Modell-IDs im Format `vendor/model` |
| Ollama | `llama3.3` | `http://localhost:11434/api/chat` | Keine | Lokal, gratis, voll privat |
| MLX | `mlx-community/Qwen3.5-2B-MLX-4bit` | `http://localhost:8080/v1/chat/completions` (lokaler `mlx_lm.server`) | Keine | Lokal, Apple-Silicon-nativ |

**Modell-Override:** Settings → Providers → pro Provider „Modell"-Feld füllen. Leer = Default.

**Wenn Modelle veraltet sind (Stand seit 2026-09-02, nach dem Gemini-2.5-404-Vorfall — diese Anleitung ist NEU, ersetzt die alte "kein anderer Code muss angefasst werden"-Aussage, die sich als falsch herausstellte):**

1. `defaultModel` in `*Provider.swift` + betroffene Presets in `ProviderModelPresets.swift` aktualisieren
2. **Zusätzlich Pflicht:** Eintrag in `ProviderModelPresets.retiredModels` ergänzen (alte ID → neue ID) — sonst bleibt jede **bereits gespeicherte** explizite Nutzerauswahl (UserDefaults `defaultModel.<provider>`, Diktat-Override, Prompt-Override) stumm auf der toten ID hängen. `migrateRetiredModels()` läuft bei jedem Start und räumt das automatisch auf, aber nur für Einträge, die in dieser Liste stehen.
3. `Localizable.strings` Hint-Strings (beide Sprachen) aktualisieren
4. Seit v1.21.0 gibt es zusätzlich `ModelAvailabilityChecker` — prüft bei jedem Start live gegen die `/models`-Endpoints der konfigurierten Provider und markiert in Settings ein „Modell evtl. veraltet"-Badge, falls die eingestellte ID nicht mehr auftaucht. Ersetzt manuelles Nachschauen nicht vollständig (Fetch kann fehlschlagen, wird dann still übersprungen), reduziert aber das Risiko, ein Retirement erst über einen echten Nutzerfehler zu bemerken.

---

## 7. Build & Release

### 7.1 Lokal entwickeln

```bash
cd ~/Coding/Tippi
brew install xcodegen          # einmalig
make prepare-binary            # einmalig: baut whisper-cli in Tippi/Helpers/
make open                      # generiert Xcode-Projekt und öffnet
# → in Xcode auf ▶ klicken
```

### 7.2 Debug-Build via CLI

```bash
xcodebuild -project Tippi.xcodeproj -scheme Tippi -configuration Debug \
    CODE_SIGNING_ALLOWED=NO build
```

### 7.3 Release-Build (vollautomatisch, signiert + notarisiert)

**Setup einmalig:**

```bash
# 1. Developer ID Application cert via developer.apple.com erstellen → in Keychain installieren
# 2. App-Specific Password unter appleid.apple.com erstellen
# 3. Notarytool credentials profile speichern:
xcrun notarytool store-credentials tippi-notary \
    --apple-id YOUR_APPLE_ID@example.com \
    --team-id YOUR_TEAM_ID \
    --password "<app-spec-pwd>"
# 4. sparkle-tools einrichten (einmalig):
#    Download: https://github.com/sparkle-project/Sparkle/releases
#    Entpacken nach ~/Developer/sparkle-tools/
# 5. release.env vorbereiten (nur DEVELOPER_ID / NOTARY_PROFILE, nie VERSION):
cp release.env.example release.env
# DEVELOPER_ID muss exakt den Namen aus `security find-identity -v -p codesigning` enthalten
# Zugangsdaten nur in Keychain/release.env — NICHT committen!
```

**Release ausführen:**

```bash
./scripts/bump-version.sh X.Y.Z   # project.yml + CHANGELOG-Abschnitt vorbereiten
# Release-Notizen, README, Website und beide In-App-Hilfe-Sprachen aktualisieren;
# Tests, Lint, Doku-Gates prüfen und alle Vorbereitungen committen + pushen.
make release                      # Standard: nach dem Appcast alte Releases bereinigen
# Alternativ ohne Löschung älterer Releases: make lint prepare-binary && ./scripts/release.sh --no-prune
```

`scripts/release.sh` macht vollautomatisch:
1. `prepare-binary` — whisper-cli in `Tippi/Helpers/` bereitstellen
2. Clean + xcodegen generate
3. xcodebuild-Archiv und Export mit `MARKETING_VERSION` aus `project.yml` + `CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD)`
4. whisper-cli in App-Bundle injizieren (`Contents/MacOS/whisper-cli`)
5. Sparkle Nested-Signing (inside-out): XPC-Binaries → XPC-Bundles → Sparkle.framework → App
6. DMG erstellen + signieren via `hdiutil`
7. Apple Notarisierung (`xcrun notarytool submit --wait`, 3–10 Min)
8. Status aus JSON parsen — wenn nicht "Accepted" → abort
9. `xcrun stapler staple` → Notarisierungs-Ticket ins DMG einbetten
10. `spctl --assess` zum finalen Gatekeeper-Check
11. GitHub Release erstellen (`gh release create`, CHANGELOG.md-Extrakt per awk)
12. `generate_appcast` + Gist-Update mit API-Rückleseprüfung
13. Output: `dist/Tippi-<version>.dmg`

**Nach dem Release:**

```bash
git add appcast.xml project.yml
git commit -m "release: v<version> appcast and shipped build"
git push origin main
```

### 7.4 Versions-Bump

1. `./scripts/bump-version.sh X.Y.Z` ausführen; `project.yml` ist die einzige Versionsquelle. **`release.env` darf kein `VERSION` enthalten** — die Pipeline bricht sonst ab.
2. Den neuen Abschnitt in `CHANGELOG.md` ausformulieren. `release.sh` nutzt ihn als GitHub-Release-Notes. README, Website, In-App-Hilfe (DE/EN) und Versionsüberschriften mitziehen; die Release-Gates prüfen das.
3. Vorbereitung committen und nach `origin/main` pushen; `release.sh` verweigert einen lokalen Stand vor oder hinter dem Remote-Branch.
4. `make release` ausführen. Die Buildnummer (`CFBundleVersion`) wird aus `git rev-list --count HEAD` berechnet und nach dem Build in `project.yml` zurückgeschrieben. `gh release create --target` taggt genau den gebauten Commit. Zum Schluss `appcast.xml` und `project.yml` committen und pushen.

**Wichtig:** Sparkle vergleicht `CFBundleVersion` (Build-Nummer), nicht `CFBundleShortVersionString`. Solange die Build-Nummer monoton steigt, werden Updates korrekt ausgeliefert.

### 7.5 Wenn Tippi einmal verkauft werden soll — die Reihenfolge ist nicht beliebig

Der naheliegende erste Schritt — das Repository auf privat schalten — ist der **falsche erste Schritt**, und der Fehler fällt erst Wochen später auf.

Grund: Sparkle lädt die Updates nicht aus dem Appcast, sondern aus den GitHub-**Releases dieses Repositories**:

```
SUFeedURL (Info.plist)  →  Gist mit appcast.xml
   └── <enclosure url>  →  github.com/miwixyz/Tippi/releases/download/vX.Y.Z/Tippi-X.Y.Z.dmg
```

Der Appcast liegt in einem Gist und bliebe erreichbar. Die DMG-Dateien liegen im Repo. Wird es privat, verlangen die Release-Assets eine Authentifizierung, die Sparkle nicht mitschickt — **jede installierte Kopie kann sich ab diesem Moment nicht mehr aktualisieren**, und der Nutzer sieht nur einen Download-Fehler.

Richtige Reihenfolge:

1. **Öffentliches Release-Repository anlegen** (z. B. `miwixyz/Tippi-releases`) — nur Binaries, kein Quellcode
2. `scripts/release.sh` und den Appcast-Gist auf die neuen URLs umstellen
3. Ein Release dorthin schieben und **einen echten Update-Durchlauf testen**, nicht nur die URL prüfen
4. **Erst danach** das Quellcode-Repository privat schalten

Alte Assets müssen nicht mitwandern: Wer auf einer älteren Version sitzt, bekommt aus dem Appcast ohnehin die neueste, und die liegt dann bereits am neuen Ort.

**Zweiter Punkt, unabhängig davon:** Jede bereits veröffentlichte Version bleibt MIT-lizenziert — das lässt sich nicht rückwirkend ändern. Eine Umlizenzierung wirkt ab der nächsten Version. Praktisch entschärft dadurch, dass es aktuell null Forks gibt und der Autor alleiniger Urheber ist; rechtlich bleibt es trotzdem eine Entscheidung, die vor dem ersten Verkauf getroffen sein muss, nicht danach.

---

## 8. Bekannte Eigenheiten / Stolpersteine

### 8.1 TCC bei ad-hoc-signierten Builds

Bei jedem `xcodebuild` ohne stabile Code-Signatur ändert sich die Designated Requirement. macOS sieht jeden Build als „neue App" und kann TCC-Einträge für Accessibility / Input Monitoring „verlieren".

**Aktueller Weg:** `make build` nutzt Apple Development; für einen Test mit derselben Berechtigung wie die installierte Developer-ID-App `scripts/devid-testbuild.sh` verwenden. Nicht annehmen, dass beide Builds gleichzeitig eine stabile TCC-Freigabe haben.

**Historisches Symptom** (2026-09-09): `xcodebuild test` brach nach ~5 Minuten mit `The test runner hung before establishing connection` ab, bevor ein Test lief. Damals fehlte dem Test-Host ein TCC-Grant; das war kein Beleg für einen fehlerhaften Test. Heute zuerst `make test` und dessen Einstellungs-Wächter verwenden, dann Signatur/TCC des tatsächlich gestarteten Builds prüfen. Die damalige Zahl von 121 Tests ist kein aktueller Sollwert (v2.16.2: 472).

### 8.2 Diktat-Geste „antippen oder halten" — nur manuell testbar

Der `.tapOrHold`-Modus (Settings → Voice → Diktat, Einzeltaste, Standard rechte
Umschalttaste) liegt hinter einem `CGEventTap` plus `Timer` in
`HotkeyManager.handleFlagsChanged`. Die **Timing-Logik** — drücken → Schwelle →
`holdBegan` → loslassen → `holdEnded` — lässt sich ohne Extraktion in einen reinen
Typ nicht aus einem Unit-Test heraus antreiben. `DictationInputModeTests` deckt
deshalb nur die persistierte Hälfte ab (Defaults, Round-Trip, Rückwärtskompatibilität
gespeicherter Hotkeys).

**Gemessene Tastendruck-Dauern (Michael, Magic Keyboard, 2026-09-10):**

Die Schwellen sind nicht geraten, sondern an echten Werten geprüft:

| Geste | gemessen |
|---|---|
| Tap-Dauer | 107 · 108 · 116 · 117 · 144 · 181 ms |
| Abstand zwischen zwei Taps | 179 · 187 · 204 ms |

Daraus: **Halte-Schwelle 400 ms** (weit über dem längsten Tap von 181 ms) und
**Doppel-Tap-Fenster 400 ms** (weit über dem größten Abstand von 204 ms). Beide
Grenzen haben mehr als den doppelten Sicherheitsabstand.

Die ursprüngliche Halte-Schwelle von 250 ms lag dagegen nur ~70 ms über dem
längsten gemessenen Tap — zu knapp. Wer diese Werte ändert, sollte vorher neu
messen statt zu schätzen.

**Kombination vs. Antippen — der Fall, der das Feature sonst unbrauchbar macht:**

Ein Modifier, der *mit* einer anderen Taste gedrückt wird (⇧A, ⌘C), ist kein Antippen.
Ohne diese Unterscheidung würde **jeder Großbuchstabe eine Aufnahme starten** — Shift runter,
Buchstabe, Shift hoch sieht für die Gestenerkennung exakt aus wie ein Tap. Der Event-Tap
beobachtet deshalb bei `.tapOrHold` zusätzlich `keyDown` und setzt `otherKeyWhileHeld`.
Ein bereits begonnenes Halten wird trotzdem immer beendet — sonst bliebe bei einem
Tastendruck während der Aufnahme das Mikrofon an.

Verifiziert mit synthetischen CGEvents (2026-09-10): Control+A → 0 Aufnahmen,
Control allein → 1 Aufnahme.

**Manuelle Testfälle vor jedem Release, das diesen Pfad anfasst:**

1. Rechte Umschalttaste **antippen** → Aufnahme startet · erneut antippen → Text wird eingefügt
2. Rechte Umschalttaste **halten** → Aufnahme startet nach ~250 ms · loslassen → Text wird eingefügt
3. Sehr kurzer Tipper (< 250 ms) darf **nicht** als Halten zählen
4. Moduswechsel in den Einstellungen während einer laufenden Aufnahme → kein hängender Recorder
5. Umschalten auf „Tastenkombination" und zurück → Hotkey bleibt in beiden Richtungen funktionsfähig
   (`HotkeyManager.update(trigger:)` muss den zum **neuen** Trigger passenden Callback
   restaurieren — wird nur `onTrigger` gerettet, ist der Hotkey scheinbar registriert und tut nichts)

**Bekannte Grenze:** Sind beide Umschalttasten gleichzeitig gedrückt und man lässt nur
eine los, bleibt `maskShift` gesetzt — das Loslassen wird nicht erkannt. Gleiche Schwäche
hat der bestehende `.hold`-Pfad; der Fünf-Minuten-Wächter in `DictationController`
fängt den Extremfall ab.

### 8.3 NSEvent global monitor + selbst-signierte Builds

`NSEvent.addGlobalMonitorForEvents` gibt für selbst-signierte Builds manchmal non-nil zurück, liefert aber keine Events. Symptom: `isActive == true` aber Hotkey feuert nie.

**Workaround:** Settings → Hotkeys → „macOS-Tastatur-Einstellungen öffnen". Nutzer bindet die Tastenkombi via macOS System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts → Menütitel `Tippi auslösen…` an Tippi. macOS feuert dann direkt den Menüpunkt. Mit korrekt signierter Version funktioniert der in-App-Recorder.

### 8.4 Apple Developer Account & Nachfolge

Sensible Daten (Apple ID, Team ID) ausschließlich in `release.env` (gitignored) — nicht in Code, Docs oder Commits, da das Repo public ist.

Bei Verlängerung jährlich automatisch. **Wenn Account ausläuft**: keine neuen Versionen signierbar, alte Versionen funktionieren weiter (eingefroren). Nutzer bekommen keine Warnungen.

### 8.5 macOS-Versions-Inkompatibilität

`onKeyPress`, `SMAppService`, `ScrollView` mit dem aktuellen Styling und `LocalizedStringResource` brauchen macOS 14+. Min-Target ist 15.0. Bei Bedarf auf 14.0 senken via `project.yml` → `deploymentTarget`.

### 8.6 Sandbox

Tippi läuft **außerhalb der Sandbox** (`com.apple.security.app-sandbox` = false in entitlements). Erforderlich für cross-app Text-Capture. Bedeutet: **kein** Mac App Store-Vertrieb möglich, ausschließlich Direkt-Distribution via Developer ID.

### 8.7 PreviewWindowController — isOpen-Bug (v1.1.7, kritisch, behoben)

**Problem:** `PreviewWindowController` hatte keinen `NSWindowDelegate`. Der rote X-Button schloss das Fenster, ohne `window = nil` zu setzen. Folge: `isOpen` blieb `true`, jeder weitere `handleTriggered`-Aufruf wurde geblockt — Tippi scheinbar eingefroren.

**Fix:** `CloseDelegate: NSWindowDelegate` implementiert, auf `window.delegate` verdrahtet. `windowWillClose` setzt `window = nil` + ruft Cancel-Callback auf.

### 8.8 `head -n -1` auf macOS (BSD head)

BSD `head` unterstützt keine negativen Zeilenzahlen (`head -n -1` = "alle außer die letzte Zeile" in GNU head). In `scripts/release.sh` durch `awk 'NR>1{print prev} {prev=$0}'` ersetzt.

### 8.9 Dark / Light Mode — Design-Entscheidungen

Die App ist vollständig Dark/Light-Mode-konform:

- Popup: `.regularMaterial` — adaptiert automatisch, kein manueller Override nötig
- Alle Farben: semantische System-Colors (`.primary`, `.secondary`, `.tint`, `.accentColor`) oder Assets mit Dark-Varianten (`BrandMistBlue`, `BrandSurface`)
- `BrandNavy` hat bewusst **keine** Dark-Variante — es ist immer die Marken-Tinte (#10192B). Stand 2026-09-27 nutzt kein Code das Asset (Audit), es bleibt als Palettenreferenz
- Kein `window.appearance`-Lock irgendwo — alle Fenster übernehmen das System-Appearance

**Stolperstein beim Auswahlzustand im Popup:** Wenn eine Zeile ausgewählt ist (AccentColor-Hintergrund), muss der Text ablesbar bleiben. Statt `Color.white` (hardcoded) wird `Color(nsColor: .selectedMenuItemTextColor)` verwendet — der macOS-Systemtoken für Text auf einem ausgewählten Menüelement. Aktuell weiß, aber semantisch korrekt und zukunftssicher gegen Theme-Änderungen. **Ab 2.20.0** ist der Zeilenhintergrund `FamilyTheme.accentFill` statt `Color.accentColor`: Der helle Dunkelmodus-Akzent `#98AEE1` hätte mit Weiß nur 2,2 : 1, die Füllung hält ≥ 4,6 : 1.

### 8.10 whisper-cli Ausgabe-Pfad

`whisper-cli --output-txt` schreibt die Ausgabe als `<inputfile>.wav.txt` (nicht `<inputfile>.txt`). `WhisperTranscriber` liest daher explizit den `.wav.txt`-Sidecar. Nicht verwechseln — stilles Fehlschlagen wenn falscher Pfad.

### 8.11 Sparkle Build-Nummer war hardcoded `1`

In früheren Builds war `CURRENT_PROJECT_VERSION` hardcoded `1` in `project.yml`. Updates wurden nie ausgeliefert, weil Sparkle keine höhere Build-Nummer sah. Fix: Build-Nummer per `git rev-list --count HEAD` dynamisch in `release.sh` gesetzt.

### 8.12 Sparkle DMG-Hosting

Gist kann keine Binaries liefern (HTTP 406 / Redirect). Daher: GitHub Releases als Hosting. `generate_appcast` mit `--download-url-prefix https://github.com/miwixyz/Tippi/releases/download/v<version>/` aufrufen.

---

## 9. Erweiterungs-Punkte (zukünftige Phasen)

| Phase | Was | Impact |
|-------|-----|--------|
| 1.2 — Prompt-Variablen | `{clipboard}`, `{language}`, `{app_name}`, `{date}` in Custom-Prompts auflösen | `PromptRenderer.swift` neu, ersetzt vor LLM-Call. |
| 1.2 — Prompt-Chains | Mehrere Prompts hintereinander, Output von Schritt 1 = Input für Schritt 2 | Datenmodell: `CustomPrompt` bekommt `chainedTo: UUID?`. UI: Liste mit Stufen. |
| 1.3 — History | Verschlüsselte lokale History via SQLite + SQLCipher. Opt-in. | Neues Tab in Settings. Suchbar. Export. |
| 1.3 — Mic-Hotkey | Konfigurierbarer Mic-Hotkey separat vom Text-Hotkey | `KeyCombo` um `voiceCombo`-Variant erweitern. |
| 1.4 — Whisper-Modell-Auswahl | In Settings: tiny / base / small / medium wählen | `WhisperModelManager` + Settings-Tab ergänzen. |
| 2.0 — Cross-Platform | Windows-Port. Code-Kern in Rust extrahieren? Tauri-Wrapper? Diskussion offen. | Größter Eingriff. Ggf. komplette Neu-Architektur. |

---

## 10. Operatives

### Speicherorte

- **API-Keys:** macOS Schlüsselbund, Service `com.tippi.app`, Account `provider.<openai|anthropic|gemini|mistral|ollama>`
- **Custom Prompts:** `~/Library/Preferences/com.tippi.app.plist` (UserDefaults Key: `tippi.customPrompts.v1`)
- **Hotkey-Combo:** Selbe plist, Key: `tippi.hotkeyCombo.v1`
- **Default Provider:** Selbe plist, Key: `defaultProvider`
- **Per-Provider-Modell:** Selbe plist, Keys: `defaultModel.<provider-id>`
- **Whisper Models:** `~/Library/Application Support/Tippi/Models/` (z.B. `ggml-base.en.bin`)
- **Notizen:** iCloud-Container `iCloud.dev.mwlr.Tippi` (Documents/Notes/`<uuid>.txt`), lokaler Fallback `~/Library/Application Support/Tippi/Notes/` ohne iCloud
- **Notizen-Fenster-Settings:** `NSUbiquitousKeyValueStore`, Key `notes.window.frame.v1` — nicht in der lokalen plist
- **Crash-Logs:** `~/Library/Logs/Tippi/` (falls aktiviert)

### Permissions löschen / zurücksetzen

```bash
# Permissions vollständig löschen (Tippi muss zu)
tccutil reset Accessibility com.tippi.app
tccutil reset ListenEvent com.tippi.app

# UserDefaults nuken (Custom Prompts, Hotkey, Provider-Settings — Keychain bleibt!)
defaults delete com.tippi.app

# Vollständig deinstallieren (inkl. Keychain + Whisper Models)
rm -rf /Applications/Tippi.app
rm -rf ~/Library/Application\ Support/Tippi/
defaults delete com.tippi.app 2>/dev/null
security delete-generic-password -s com.tippi.app 2>/dev/null
# Keychain-Einträge unter `com.tippi.app` einzeln über Schlüsselbundverwaltung löschen falls mehrere
```

### Lokale Tippi-App neu installieren (nach Rebuild)

```bash
cd ~/Coding/Tippi
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
mkdir -p dist
test -f "dist/Tippi-${VERSION}.dmg" || gh release download "v${VERSION}" -p "Tippi-${VERSION}.dmg" -D dist
osascript -e 'tell application "Tippi" to quit' 2>/dev/null; sleep 1
rm -rf /Applications/Tippi.app
hdiutil attach "dist/Tippi-${VERSION}.dmg" -quiet
cp -R "/Volumes/Tippi ${VERSION}/Tippi.app" /Applications/
hdiutil detach "/Volumes/Tippi ${VERSION}" -quiet
open /Applications/Tippi.app
```

---

## 11. Kontakte / Konten

- **Apple Developer Account:** YOUR_APPLE_ID@example.com — sensible Details nur in `release.env` (gitignored, nicht committen)
- **GitHub:** miwixyz, Repo `Tippi` (public, MIT)
- **Sparkle Appcast:** https://gist.githubusercontent.com/miwixyz/595ce79e698bb6a98008dc061f1f4a78/raw/appcast.xml
- **Domain (falls geplant):** —

---

## 12. Wiederaufnahme-Checkliste

Wenn ich nach 6+ Monaten zurückkomme und Tippi weitermachen will:

- [ ] `cd ~/Coding/Tippi`
- [ ] `git pull` (falls remote Changes da sind)
- [ ] `brew install xcodegen` falls nicht da
- [ ] `make prepare-binary` — whisper-cli in `Tippi/Helpers/` bauen (falls nicht vorhanden)
- [ ] `make open` → Xcode öffnet
- [ ] Tippi.app im Dock testen — läuft sie noch?
- [ ] In Settings → Providers nachschauen — sind die Default-Modelle noch aktuell? (Stand prüfen für: gpt-?, claude-?-?, gemini-?-?, mistral-?-?, llama?)
- [ ] Falls Modelle veraltet: in den 5 `*Provider.swift` `defaultModel` updaten + Localizable.strings Hints
- [ ] Falls Apple-Cert abgelaufen: developer.apple.com → Renew, neuer Cert in Keychain, `release.env` ggf. updaten
- [ ] Sparkle-Tools noch aktuell? `~/Developer/sparkle-tools/bin/generate_appcast --version` prüfen
- [ ] Whisper-Modell noch aktuell? whisper.cpp Releases prüfen auf neuere ggml-Modelle
- [ ] CHANGELOG für nächste Version anfangen
- [ ] Bei Feature-Arbeit: Phase aus Roadmap (§9) wählen, los

---

*Übergabestand aktualisiert am 28. September 2026 für v2.17.0. Ältere Fachabschnitte vor einer Änderung gegen den aktuellen Code prüfen.*
