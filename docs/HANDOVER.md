# Tippi — Handover-Dokumentation

Stand: Mai 2026 · Version: 1.0.0
Autor: Michael Wildenauer

Dieses Dokument ist die **vollständige technische und betriebliche Übergabe** für das Projekt Tippi. Es ist primär für deinen eigenen Vault gedacht und dient als Referenz wenn du nach Monaten zurückkommst oder das Projekt jemandem übergibst.

---

## 1. Was ist Tippi?

Tippi ist ein systemweiter KI-Schreibassistent für macOS. In jeder beliebigen Mac-App (Mail, Safari, Notes, Slack, VS Code, ...) markiert der Nutzer Text, drückt einen konfigurierbaren Hotkey (Standard: `⌥⌘T`), wählt aus einem Cursor-Popup eine Aktion (Verbessern, Übersetzen, Grammatik, ...), sieht das KI-Ergebnis im Vorschau-Fenster und entscheidet: Ersetzen, Anhängen, Kopieren, Neu generieren.

**Konzeptueller Kern:** App-agnostisch via macOS Accessibility API. BYOK (Bring Your Own Key) Modell für LLM-Provider. Daten verlassen den Mac nur zum aktiven gewählten Provider. Keine Telemetrie.

**Inspirationsquelle:** Pismo (kostenpflichtig auf Mac App Store). Tippi ist die Open-Source-Variante mit mehr Providern und vollständig BYOK.

---

## 2. Repository

- **GitHub:** https://github.com/miwixyz/Tippi (privat)
- **Lokal:** `/Users/michaelwildenauer/-Coding/Tippi/`
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
| Distribution | DMG via `hdiutil` | Standard macOS-Paket |

**Bewusst nicht verwendet:**
- ❌ Mac Catalyst (iPad-Origin, schlechtere Mac-UX)
- ❌ Electron / Tauri (System-Integration nicht tief genug)
- ❌ Storyboards (SwiftUI-First)
- ❌ Sandbox (verhindert systemweiten Text-Capture)
- ❌ Drittabhängigkeiten (außer evtl. Sparkle 2 für v1.1 Auto-Updates)

---

## 4. Modul-Struktur

```
Tippi/
├── App/
│   ├── TippiApp.swift              @main, leere Settings-Scene
│   └── AppDelegate.swift           Menubar, Hotkey-Wiring, Window-Controller, Permission-Observer
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
│   └── CustomPrompt.swift          User-Prompts + JSON-Persistierung
├── LLM/
│   ├── LLMProvider.swift           Protocol + LLMError
│   ├── OpenAIProvider.swift        gpt-5-mini, /v1/chat/completions
│   ├── AnthropicProvider.swift     claude-haiku-4-5, /v1/messages
│   ├── GeminiProvider.swift        gemini-2.5-flash, generativelanguage.googleapis.com
│   ├── MistralProvider.swift       mistral-small-latest, OpenAI-kompatibel
│   ├── OllamaProvider.swift        llama3.3, localhost:11434
│   └── LLMRouter.swift             Provider-Reihenfolge, Fallthrough-Logik
├── UI/
│   ├── WelcomeView.swift           5-Schritt-Setup-Wizard + Demo-Sheet
│   ├── SettingsView.swift          5 Tabs (General, Hotkeys, Providers, Prompts, About)
│   ├── HotkeyRecorderField.swift   Tap-to-record Hotkey-Feld via NSEvent local monitor
│   ├── PromptPopup/
│   │   ├── DemoPrompt.swift        Eingebaute + benutzerdefinierte Prompts (kombinierte all-Liste)
│   │   ├── PromptPopupView.swift   SwiftUI-Popup-Inhalt
│   │   └── PromptPopupController.swift  NSPanel, Positionierung am Cursor
│   └── Preview/
│       ├── PreviewView.swift       Original | Suggestion Side-by-Side
│       └── PreviewWindowController.swift  NSWindow, Floating-Level
└── Resources/
    ├── Info.plist                  LSUIElement=true, NSAppleEventsUsageDescription
    ├── Tippi.entitlements          app-sandbox=false, network.client=true
    ├── Assets.xcassets             AppIcon (10 macOS-Größen), AccentColor (warm orange)
    ├── en.lproj/Localizable.strings
    └── de.lproj/Localizable.strings
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

---

## 6. LLM-Provider — aktuelle Default-Modelle (Mai 2026)

| Provider | Default Modell | API Endpoint | Auth | Notes |
|----------|----------------|--------------|------|-------|
| OpenAI | `gpt-5-mini` | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer <key>` | Schnell, günstig, gute deutsche Sprache |
| Anthropic | `claude-haiku-4-5` | `https://api.anthropic.com/v1/messages` | `x-api-key: <key>` + `anthropic-version: 2023-06-01` | Beste Prosa-Qualität |
| Google | `gemini-2.5-flash` | `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key=<key>` | Query-Param | Großzügiges Free-Tier |
| Mistral | `mistral-small-latest` | `https://api.mistral.ai/v1/chat/completions` | `Authorization: Bearer <key>` | EU-Hosting möglich |
| Ollama | `llama3.3` | `http://localhost:11434/api/chat` | Keine | Lokal, gratis, voll privat |

**Modell-Override:** Settings → Providers → pro Provider „Modell"-Feld füllen. Leer = Default.

**Wenn Modelle veraltet sind** (z.B. nach 6-12 Monaten): Aktualisiere die `defaultModel`-Property in jedem `*Provider.swift` und die Hint-Strings in `Localizable.strings`. Kein anderer Code muss angefasst werden.

---

## 7. Build & Release

### 7.1 Lokal entwickeln

```bash
cd /Users/michaelwildenauer/-Coding/Tippi
brew install xcodegen          # einmalig
make open                      # generiert Xcode-Projekt und öffnet
# → in Xcode auf ▶ klicken
```

### 7.2 Debug-Build via CLI

```bash
xcodebuild -project Tippi.xcodeproj -scheme Tippi -configuration Debug \
    CODE_SIGNING_ALLOWED=NO build
```

### 7.3 Release-Build (signiert + notarisiert)

**Setup einmalig:**

```bash
# 1. Developer ID Application cert via developer.apple.com erstellen → in Keychain installieren
# 2. App-Specific Password unter appleid.apple.com erstellen
# 3. Notarytool credentials profile speichern:
xcrun notarytool store-credentials tippi-notary \
    --apple-id miwimail@icloud.com \
    --team-id 54PMA7GFAN \
    --password "<app-spec-pwd>"
# 4. release.env vorbereiten:
cp release.env.example release.env
# DEVELOPER_ID muss exakt den Namen aus `security find-identity -v -p codesigning` enthalten
```

**Release ausführen:**

```bash
make release
```

`scripts/release.sh` macht:
1. Clean + xcodegen generate
2. Release-Build mit `CODE_SIGN_IDENTITY=$DEVELOPER_ID` + `OTHER_CODE_SIGN_FLAGS="--options=runtime --timestamp"`
3. `codesign --verify --deep --strict` zum Sanity-Check
4. DMG via `hdiutil create -volname "Tippi $VERSION" -srcfolder $STAGING -format UDZO`
5. DMG signieren mit selbem Identity
6. `xcrun notarytool submit ... --wait` (3-10 Min)
7. Status aus JSON parsen — wenn nicht "Accepted" → abort
8. `xcrun stapler staple` → Notarisierungs-Ticket ins DMG einbetten
9. `spctl --assess` zum finalen Gatekeeper-Check
10. Output: `dist/Tippi-<version>.dmg`

**Auf GitHub veröffentlichen:**

```bash
gh release create v1.0.0 dist/Tippi-1.0.0.dmg \
    --title "Tippi 1.0.0" \
    --notes-file CHANGELOG.md
```

### 7.4 Versions-Bump

In `release.env` `VERSION` setzen, `scripts/release.sh` übernimmt das via `MARKETING_VERSION=$VERSION` ans xcodebuild. Auch `CHANGELOG.md` updaten und `gh release create v<neue-version>`.

---

## 8. Bekannte Eigenheiten / Stolpersteine

### 8.1 TCC bei ad-hoc-signierten Builds

Bei jedem `xcodebuild` ohne stabile Code-Signatur ändert sich die Designated Requirement. macOS sieht jeden Build als „neue App" und kann TCC-Einträge für Accessibility / Input Monitoring „verlieren".

**Lösung:** Mit Developer ID signieren. Dann ist die Signatur stabil, TCC-Einträge persistieren über Rebuilds.

### 8.2 NSEvent global monitor + selbst-signierte Builds

`NSEvent.addGlobalMonitorForEvents` gibt für selbst-signierte Builds manchmal non-nil zurück, liefert aber keine Events. Symptom: `isActive == true` aber Hotkey feuert nie.

**Workaround dokumentiert in:** Settings → Hotkeys → „macOS-Tastatur-Einstellungen öffnen". Nutzer bindet die Tastenkombi via macOS System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts → Menütitel `Tippi auslösen…` an Tippi. macOS feuert dann direkt den Menüpunkt.

Mit korrekt signierter Version sollte der in-App-Recorder funktionieren.

### 8.3 Apple Developer Account & Nachfolge

Apple Developer Account: `miwimail@icloud.com`, Team-ID: `54PMA7GFAN`.

Bei Verlängerung jährlich automatisch. **Wenn Account ausläuft**: keine neuen Versionen signierbar, alte Versionen funktionieren weiter (eingefroren). Nutzer bekommen keine Warnungen.

### 8.4 macOS-Versions-Inkompatibilität

`onKeyPress`, `SMAppService`, `ScrollView` mit dem aktuellen Styling und `LocalizedStringResource` brauchen macOS 14+. Min-Target ist 15.0. Bei Bedarf auf 14.0 senken via `project.yml` → `deploymentTarget`.

### 8.5 Sandbox

Tippi läuft **außerhalb der Sandbox** (`com.apple.security.app-sandbox` = false in entitlements). Erforderlich für cross-app Text-Capture. Bedeutet: **kein** Mac App Store-Vertrieb möglich, ausschließlich Direkt-Distribution via Developer ID.

---

## 9. Erweiterungs-Punkte (zukünftige Phasen)

| Phase | Was | Impact |
|-------|-----|--------|
| 1.1 — Voice | Push-to-Talk Hotkey, Whisper.cpp lokal eingebettet, Audio → Transkript → bei vorhandenem Selection-Text als Prompt-Eingabe verwendet, sonst als KI-Aufgabe interpretiert | Whisper.cpp ~80 MB Modell-Download separat. CocoaPods/SPM oder XCFramework. |
| 1.1 — Sparkle | Auto-Updates via Sparkle 2. Appcast.xml im Repo, Tippi prüft beim Start. | Sparkle 2 als XCFramework. Public Key in Info.plist. EdDSA-signierte Updates. |
| 1.2 — Prompt-Variablen | `{clipboard}`, `{language}`, `{app_name}`, `{date}` in Custom-Prompts auflösen | `PromptRenderer.swift` neu, ersetzt vor LLM-Call. |
| 1.2 — Prompt-Chains | Mehrere Prompts hintereinander, Output von Schritt 1 = Input für Schritt 2 | Datenmodell: `CustomPrompt` bekommt `chainedTo: UUID?`. UI: Liste mit Stufen. |
| 1.3 — History | Verschlüsselte lokale History via SQLite + SQLCipher. Opt-in. | Neues Tab in Settings. Suchbar. Export. |
| 2.0 — Cross-Platform | Windows-Port. Code-Kern in Rust extrahieren? Tauri-Wrapper? Diskussion offen. | Größter Eingriff. Ggf. komplette Neu-Architektur. |

---

## 10. Operatives

### Speicherorte

- **API-Keys:** macOS Schlüsselbund, Service `com.tippi.app`, Account `provider.<openai|anthropic|gemini|mistral|ollama>`
- **Custom Prompts:** `~/Library/Preferences/com.tippi.app.plist` (UserDefaults Key: `tippi.customPrompts.v1`)
- **Hotkey-Combo:** Selbe plist, Key: `tippi.hotkeyCombo.v1`
- **Default Provider:** Selbe plist, Key: `defaultProvider`
- **Per-Provider-Modell:** Selbe plist, Keys: `defaultModel.<provider-id>`
- **Crash-Logs:** `~/Library/Logs/Tippi/` (falls aktiviert)

### Permissions löschen / zurücksetzen

```bash
# Permissions vollständig löschen (Tippi muss zu)
tccutil reset Accessibility com.tippi.app
tccutil reset ListenEvent com.tippi.app

# UserDefaults nuken (Custom Prompts, Hotkey, Provider-Settings — Keychain bleibt!)
defaults delete com.tippi.app

# Vollständig deinstallieren (inkl. Keychain)
rm -rf /Applications/Tippi.app
defaults delete com.tippi.app 2>/dev/null
security delete-generic-password -s com.tippi.app 2>/dev/null
# Keychain-Einträge unter `com.tippi.app` einzeln über Schlüsselbundverwaltung löschen falls mehrere
```

### Lokale Tippi-App neu installieren (nach Rebuild)

```bash
cd /Users/michaelwildenauer/-Coding/Tippi
make release   # signed + notarisiert (vorausgesetzt Apple-Setup ist da)
osascript -e 'tell application "Tippi" to quit' 2>/dev/null; sleep 1
rm -rf /Applications/Tippi.app
hdiutil attach dist/Tippi-1.0.0.dmg -quiet
cp -R "/Volumes/Tippi 1.0.0/Tippi.app" /Applications/
hdiutil detach "/Volumes/Tippi 1.0.0" -quiet
open /Applications/Tippi.app
```

---

## 11. Kontakte / Konten

- **Apple Developer Account:** miwimail@icloud.com, Team-ID `54PMA7GFAN`
- **GitHub:** miwixyz, Repo `Tippi` (privat)
- **Domain (falls geplant):** —

---

## 12. Wiederaufnahme-Checkliste

Wenn ich nach 6+ Monaten zurückkomme und Tippi weitermachen will:

- [ ] `cd /Users/michaelwildenauer/-Coding/Tippi`
- [ ] `git pull` (falls remote Changes da sind)
- [ ] `brew install xcodegen` falls nicht da
- [ ] `make open` → Xcode öffnet
- [ ] Tippi.app im Dock testen — läuft sie noch?
- [ ] In Settings → Providers nachschauen — sind die Default-Modelle noch aktuell? (Stand prüfen für: gpt-?, claude-?-?, gemini-?-?, mistral-?-?, llama?)
- [ ] Falls Modelle veraltet: in den 5 `*Provider.swift` `defaultModel` updaten + Localizable.strings Hints
- [ ] Falls Apple-Cert abgelaufen: developer.apple.com → Renew, neuer Cert in Keychain, `release.env` ggf. updaten
- [ ] CHANGELOG für nächste Version anfangen
- [ ] Bei Feature-Arbeit: Phase aus Roadmap (§9) wählen, los

---

*Stand: 12. Mai 2026 · Generiert während der Initial-Implementierung mit Claude Code.*
