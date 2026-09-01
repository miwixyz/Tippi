# Tippi — Handover-Dokumentation

Stand: Mai 2026 · Version: **1.6.0** (siehe auch `docs/HANDOFF-CLAUDE.md` für die aktuelle Agenten-Übergabe)
Autor: Michael Wildenauer

Dieses Dokument ist die **vollständige technische und betriebliche Übergabe** für das Projekt Tippi. Es ist primär für deinen eigenen Vault gedacht und dient als Referenz wenn du nach Monaten zurückkommst oder das Projekt jemandem übergibst.

---

## 1. Was ist Tippi?

Tippi ist ein systemweiter KI-Schreibassistent für macOS. In jeder beliebigen Mac-App (Mail, Safari, Notes, Slack, VS Code, ...) markiert der Nutzer Text, drückt einen konfigurierbaren Hotkey (Standard: `⌥⌘T`), wählt aus einem Cursor-Popup eine Aktion (Verbessern, Übersetzen, Grammatik, ...), sieht das KI-Ergebnis im Vorschau-Fenster und entscheidet: Ersetzen, Anhängen, Kopieren, Neu generieren.

Ab v1.1.0 kommt Voice Input dazu: Push-to-Talk-Mikrofon-Button im Popup für Diktat (ohne Selektion) und Sprach-Befehle (mit Selektion).

**Konzeptueller Kern:** App-agnostisch via macOS Accessibility API. BYOK (Bring Your Own Key) Modell für LLM-Provider. Daten verlassen den Mac nur zum aktiven gewählten Provider. Keine Telemetrie.

**Inspirationsquelle:** Pismo (kostenpflichtig auf Mac App Store). Tippi ist die Open-Source-Variante mit mehr Providern, vollständig BYOK und lokalem Voice-Input via Whisper.

---

## 2. Repository

- **GitHub:** https://github.com/miwixyz/Tippi (public, Open-Source)
- **Lokal:** `~/-Coding/Tippi/`
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
│   └── TippiColors.swift           Color.tippiNavy / .tippiSurface / .tippiMist Extensions
├── LLM/
│   ├── LLMProvider.swift           Protocol + LLMError
│   ├── OpenAIProvider.swift        gpt-5-mini, /v1/chat/completions
│   ├── AnthropicProvider.swift     claude-haiku-4-5, /v1/messages
│   ├── GeminiProvider.swift        gemini-3.5-flash, generativelanguage.googleapis.com
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
│   └── Preview/
│       ├── PreviewView.swift       Original | Suggestion Side-by-Side
│       └── PreviewWindowController.swift  NSWindow, Floating-Level; CloseDelegate wired
├── Helpers/
│   └── whisper-cli                 Statischer Binary (gitignored), via `make prepare-binary`
└── Resources/
    ├── Info.plist                  LSUIElement=true, NSAppleEventsUsageDescription,
    │                               SUFeedURL, SUPublicEDKey
    ├── Tippi.entitlements          app-sandbox=false, network.client=true
    ├── Assets.xcassets/
    │   ├── AppIcon.appiconset      10 macOS-Größen (CoreGraphics, kein third-party)
    │   ├── AccentColor.colorset    Signal Blue #3B8CFF — treibt .tint / .accentColor app-weit
    │   ├── BrandNavy.colorset      #10192B (fix, kein Dark-Variant — Logo-Farbe)
    │   ├── BrandSurface.colorset   Soft White / Dark Navy (adaptiv Light/Dark)
    │   └── BrandMistBlue.colorset  Mist Blue / Deep Navy-Blue (adaptiv Light/Dark)
    ├── en.lproj/Localizable.strings
    └── de.lproj/Localizable.strings

scripts/
├── release.sh                      Vollautomatische Build-Notarisierungs-Release-Pipeline
└── prepare-binary.sh               Build-Skript für whisper-cli (whisper.cpp v1.7.4, statisch)

docs/
├── HANDOVER.md                     Dieses Dokument
├── BRANDKIT.md                     Farbpalette, adaptive Mappings, Typografie, Ikonografie
├── demo.gif                        Demo-GIF für README (Text-Verbesserung + Voice Instruction)
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

**TCC-Falle:** Selbst-signierte Builds (ad-hoc) haben oft TCC-Probleme — macOS erkennt jeden Build als „andere App" wegen wechselnder Signatur. **Lösung:** Mit Developer ID signiert, bleibt TCC stabil über Rebuilds.

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
- **Appcast-Generierung:** `~/Developer/sparkle-tools/bin/generate_appcast` — nach `make release` ausführen, Ergebnis als `appcast.xml` committen + pushen
- **DMG-Hosting:** GitHub Releases (Gist kann keine Binaries liefern). `generate_appcast` mit `--download-url-prefix https://github.com/miwixyz/Tippi/releases/download/v<version>/` aufrufen
- **Signierung der Updates:** `sign_update`-Tool aus sparkle-tools, Output-Key gehört in `SUPublicEDKey`

---

## 6. LLM-Provider — aktuelle Default-Modelle (Mai 2026)

| Provider | Default Modell | API Endpoint | Auth | Notes |
|----------|----------------|--------------|------|-------|
| OpenAI | `gpt-5-mini` | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer <key>` | Schnell, günstig, gute deutsche Sprache |
| Anthropic | `claude-haiku-4-5` | `https://api.anthropic.com/v1/messages` | `x-api-key: <key>` + `anthropic-version: 2023-06-01` | Beste Prosa-Qualität |
| Google | `gemini-3.5-flash` | `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key=<key>` | Query-Param | Großzügiges Free-Tier |
| Mistral | `mistral-small-latest` | `https://api.mistral.ai/v1/chat/completions` | `Authorization: Bearer <key>` | EU-Hosting möglich |
| Ollama | `llama3.3` | `http://localhost:11434/api/chat` | Keine | Lokal, gratis, voll privat |

**Modell-Override:** Settings → Providers → pro Provider „Modell"-Feld füllen. Leer = Default.

**Wenn Modelle veraltet sind** (z.B. nach 6-12 Monaten): Aktualisiere die `defaultModel`-Property in jedem `*Provider.swift` und die Hint-Strings in `Localizable.strings`. Kein anderer Code muss angefasst werden.

---

## 7. Build & Release

### 7.1 Lokal entwickeln

```bash
cd ~/-Coding/Tippi
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
# 5. release.env vorbereiten:
cp release.env.example release.env
# DEVELOPER_ID muss exakt den Namen aus `security find-identity -v -p codesigning` enthalten
# Sensible Daten (Apple ID, Team ID) nur in release.env — NICHT in Code oder Docs committen!
```

**Release ausführen:**

```bash
make release
```

`scripts/release.sh` macht vollautomatisch:
1. `prepare-binary` — whisper-cli in `Tippi/Helpers/` bereitstellen
2. Clean + xcodegen generate
3. xcodebuild Release mit `MARKETING_VERSION=$VERSION` + `CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD)`
4. whisper-cli in App-Bundle injizieren (`Contents/MacOS/whisper-cli`)
5. Sparkle Nested-Signing (inside-out): XPC-Binaries → XPC-Bundles → Sparkle.framework → App
6. DMG erstellen + signieren via `hdiutil`
7. Apple Notarisierung (`xcrun notarytool submit --wait`, 3–10 Min)
8. Status aus JSON parsen — wenn nicht "Accepted" → abort
9. `xcrun stapler staple` → Notarisierungs-Ticket ins DMG einbetten
10. `spctl --assess` zum finalen Gatekeeper-Check
11. GitHub Release erstellen (`gh release create`, CHANGELOG.md-Extrakt per awk)
12. `generate_appcast` + Gist-Update
13. Output: `dist/Tippi-<version>.dmg`

**Nach dem Release:**

```bash
git add appcast.xml && git commit -m "release: v<version>" && git push
```

### 7.4 Versions-Bump

1. In `release.env` `VERSION` setzen (z.B. `VERSION=1.2.0`)
2. `CHANGELOG.md` updaten — `release.sh` extrahiert den passenden Abschnitt per awk für die GitHub-Release-Notes
3. `make release` — Build-Nummer (`CFBundleVersion`) wird automatisch per `git rev-list --count HEAD` berechnet, kein manuelles Tracking

**Wichtig:** Sparkle vergleicht `CFBundleVersion` (Build-Nummer), nicht `CFBundleShortVersionString`. Solange die Build-Nummer monoton steigt, werden Updates korrekt ausgeliefert.

---

## 8. Bekannte Eigenheiten / Stolpersteine

### 8.1 TCC bei ad-hoc-signierten Builds

Bei jedem `xcodebuild` ohne stabile Code-Signatur ändert sich die Designated Requirement. macOS sieht jeden Build als „neue App" und kann TCC-Einträge für Accessibility / Input Monitoring „verlieren".

**Lösung:** Mit Developer ID signieren. Dann ist die Signatur stabil, TCC-Einträge persistieren über Rebuilds.

### 8.2 NSEvent global monitor + selbst-signierte Builds

`NSEvent.addGlobalMonitorForEvents` gibt für selbst-signierte Builds manchmal non-nil zurück, liefert aber keine Events. Symptom: `isActive == true` aber Hotkey feuert nie.

**Workaround:** Settings → Hotkeys → „macOS-Tastatur-Einstellungen öffnen". Nutzer bindet die Tastenkombi via macOS System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts → Menütitel `Tippi auslösen…` an Tippi. macOS feuert dann direkt den Menüpunkt. Mit korrekt signierter Version funktioniert der in-App-Recorder.

### 8.3 Apple Developer Account & Nachfolge

Sensible Daten (Apple ID, Team ID) ausschließlich in `release.env` (gitignored) — nicht in Code, Docs oder Commits, da das Repo public ist.

Bei Verlängerung jährlich automatisch. **Wenn Account ausläuft**: keine neuen Versionen signierbar, alte Versionen funktionieren weiter (eingefroren). Nutzer bekommen keine Warnungen.

### 8.4 macOS-Versions-Inkompatibilität

`onKeyPress`, `SMAppService`, `ScrollView` mit dem aktuellen Styling und `LocalizedStringResource` brauchen macOS 14+. Min-Target ist 15.0. Bei Bedarf auf 14.0 senken via `project.yml` → `deploymentTarget`.

### 8.5 Sandbox

Tippi läuft **außerhalb der Sandbox** (`com.apple.security.app-sandbox` = false in entitlements). Erforderlich für cross-app Text-Capture. Bedeutet: **kein** Mac App Store-Vertrieb möglich, ausschließlich Direkt-Distribution via Developer ID.

### 8.6 PreviewWindowController — isOpen-Bug (v1.1.7, kritisch, behoben)

**Problem:** `PreviewWindowController` hatte keinen `NSWindowDelegate`. Der rote X-Button schloss das Fenster, ohne `window = nil` zu setzen. Folge: `isOpen` blieb `true`, jeder weitere `handleTriggered`-Aufruf wurde geblockt — Tippi scheinbar eingefroren.

**Fix:** `CloseDelegate: NSWindowDelegate` implementiert, auf `window.delegate` verdrahtet. `windowWillClose` setzt `window = nil` + ruft Cancel-Callback auf.

### 8.7 `head -n -1` auf macOS (BSD head)

BSD `head` unterstützt keine negativen Zeilenzahlen (`head -n -1` = "alle außer die letzte Zeile" in GNU head). In `scripts/release.sh` durch `awk 'NR>1{print prev} {prev=$0}'` ersetzt.

### 8.8 Dark / Light Mode — Design-Entscheidungen

Die App ist vollständig Dark/Light-Mode-konform:

- Popup: `.regularMaterial` — adaptiert automatisch, kein manueller Override nötig
- Alle Farben: semantische System-Colors (`.primary`, `.secondary`, `.tint`, `.accentColor`) oder Assets mit Dark-Varianten (`BrandMistBlue`, `BrandSurface`)
- `BrandNavy` hat bewusst **keine** Dark-Variante — es ist immer die Marken-Tinte (#10192B), z.B. für den Logo-Kreis im About-Tab
- Kein `window.appearance`-Lock irgendwo — alle Fenster übernehmen das System-Appearance

**Stolperstein beim Auswahlzustand im Popup:** Wenn eine Zeile ausgewählt ist (AccentColor-Hintergrund), muss der Text ablesbar bleiben. Statt `Color.white` (hardcoded) wird `Color(nsColor: .selectedMenuItemTextColor)` verwendet — der macOS-Systemtoken für Text auf einem ausgewählten Menüelement. Aktuell weiß, aber semantisch korrekt und zukunftssicher gegen Theme-Änderungen.

### 8.8 whisper-cli Ausgabe-Pfad

`whisper-cli --output-txt` schreibt die Ausgabe als `<inputfile>.wav.txt` (nicht `<inputfile>.txt`). `WhisperTranscriber` liest daher explizit den `.wav.txt`-Sidecar. Nicht verwechseln — stilles Fehlschlagen wenn falscher Pfad.

### 8.9 Sparkle Build-Nummer war hardcoded `1`

In früheren Builds war `CURRENT_PROJECT_VERSION` hardcoded `1` in `project.yml`. Updates wurden nie ausgeliefert, weil Sparkle keine höhere Build-Nummer sah. Fix: Build-Nummer per `git rev-list --count HEAD` dynamisch in `release.sh` gesetzt.

### 8.10 Sparkle DMG-Hosting

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
cd ~/-Coding/Tippi
make release   # signed + notarisiert (vorausgesetzt Apple-Setup ist da)
osascript -e 'tell application "Tippi" to quit' 2>/dev/null; sleep 1
rm -rf /Applications/Tippi.app
VERSION=$(grep '^VERSION=' release.env | cut -d= -f2)
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

- [ ] `cd ~/-Coding/Tippi`
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

*Stand: 13. Mai 2026 · Aktualisiert auf v1.1.7 mit Claude Code.*
