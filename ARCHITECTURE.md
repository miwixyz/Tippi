# Tippi — Architecture Document

**Version:** 1.0-draft
**Datum:** 2026-05-12
**Begleitdokument zu:** PRD.md

---

## 1. Tech-Stack

| Schicht | Technologie | Begründung |
|---------|-------------|------------|
| Sprache | **Swift 5.10+** | Native, Apple-First, beste Performance |
| UI | **SwiftUI** (mit AppKit-Bridges) | Modern, Apple HIG, Dark Mode out-of-box |
| Min OS | **macOS 15 Sequoia** | SwiftUI-Maturity, neueste AppKit-APIs |
| Arch | **Apple Silicon only** | arm64 single-arch, schlankes Binary |
| Build | **Xcode 16+** | Standard Apple Toolchain |
| Tests | **Swift Testing** (neues Framework) + XCTest für UI | Apple-empfohlen |
| Distribution | **DMG + Developer ID + Notarization** | Außerhalb App Store, volle Permissions |

**Bewusst nicht verwendet:**
- ❌ Catalyst / Mac Catalyst (iPad-Origin, schlechtere Mac-UX)
- ❌ Electron / Tauri (System-Integration nicht tief genug)
- ❌ Storyboards (SwiftUI-First)
- ❌ Drittabhängigkeiten außer dem absoluten Minimum

---

## 2. Modul-Struktur

```
Tippi/
├── App/
│   ├── TippiApp.swift              # @main, NSApplication-Setup
│   └── AppDelegate.swift           # Permissions, MenuBar
├── Core/
│   ├── HotkeyManager.swift         # Carbon + CGEventTap
│   ├── TextCapture.swift           # Accessibility + Pasteboard-Fallback
│   ├── TextInsertion.swift         # Replace / Append / Copy
│   ├── KeychainStore.swift         # API-Keys
│   └── PermissionsManager.swift    # Accessibility, Input Monitoring
├── LLM/
│   ├── LLMProvider.swift           # Protocol
│   ├── OpenAIProvider.swift
│   ├── AnthropicProvider.swift
│   ├── GeminiProvider.swift
│   ├── MistralProvider.swift
│   ├── OllamaProvider.swift
│   └── LLMRouter.swift             # Routing + Fehlerbehandlung
├── Prompts/
│   ├── Prompt.swift                # Struct
│   ├── DefaultPrompts.swift        # P1..P6 fix codiert
│   └── PromptRenderer.swift        # {selected_text}-Injection
├── UI/
│   ├── PopupWindow/
│   │   ├── PopupView.swift
│   │   └── PopupController.swift   # NSPanel, positioniert am Cursor
│   ├── PreviewWindow/
│   │   ├── PreviewView.swift
│   │   └── PreviewController.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── HotkeyTab.swift
│   │   ├── ProvidersTab.swift
│   │   └── …
│   └── MenuBarItem.swift
├── Localization/
│   ├── en.lproj/Localizable.strings
│   └── de.lproj/Localizable.strings
└── Resources/
    └── Assets.xcassets             # Icon, Symbole
```

---

## 3. macOS-Permissions (kritisch!)

Tippi braucht **drei** Berechtigungen. Setup-Wizard führt Nutzer durch alle.

### 3.1 Accessibility (AXIsProcessTrusted)

- **Wofür:** Markierten Text aus Fremd-App lesen, simulierte Tasteneingaben (Paste)
- **Prüfung:** `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])`
- **Setup:** System Settings → Privacy & Security → Accessibility
- **Failure-Modus:** Tippi zeigt persistenten Banner mit "Open System Settings"-Button

### 3.2 Input Monitoring

- **Wofür:** Global Hotkey-Detection, insbesondere Double-Tap & Hold via CGEventTap
- **Prüfung:** `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`
- **Setup:** System Settings → Privacy & Security → Input Monitoring

### 3.3 Apple Events (optional, bessere Text-Capture in einzelnen Apps)

- **Wofür:** Vereinzelt Apps wie Mail.app via AppleScript-Bridge
- **Setup:** automatisch beim ersten Versuch via TCC-Prompt

---

## 4. Hotkey-Mechanik

### 4.1 Normal Combo

- API: **Carbon `RegisterEventHotKey`** (älter, aber stabilster Weg für global hotkeys)
- Vorteil: Funktioniert auch ohne Input Monitoring
- Mapping: NSEvent.modifierFlags + UInt32 keyCode → Carbon-Tabelle

### 4.2 Double-Tap-Modifier

- API: **CGEventTap** auf `kCGEventFlagsChanged`
- Logik:
  ```
  on FlagsChanged(modifier):
      if matches target modifier AND was released:
          if time since last tap < 300 ms:
              trigger()
          last_tap = now
  ```
- Default-Schwelle: **300 ms** zwischen den zwei Taps

### 4.3 Hold-Modifier

- API: gleicher CGEventTap
- Logik: Timer (default 500 ms) startet bei Modifier-Down, feuert wenn nicht vorher released

### 4.4 Konflikt-Detection

- Beim Setzen: Carbon-Status nach `eventHotKeyExists` checken
- Bekannte System-Combos hardcoded blacklisten (⌘+Tab, ⌘+Space, …)

---

## 5. Text-Capture (Herzstück)

**Zwei-Stufen-Strategie für maximale App-Kompatibilität:**

### Stufe 1: Accessibility API (bevorzugt, sauber)

```swift
func captureSelectedText() -> String? {
    let systemWide = AXUIElementCreateSystemWide()
    var focused: AnyObject?
    AXUIElementCopyAttributeValue(systemWide,
        kAXFocusedUIElementAttribute as CFString, &focused)

    var selectedText: AnyObject?
    AXUIElementCopyAttributeValue(focused as! AXUIElement,
        kAXSelectedTextAttribute as CFString, &selectedText)

    return selectedText as? String
}
```

### Stufe 2: Pasteboard-Trick (Fallback für Apps ohne AX-Support)

```
1. Pasteboard-Snapshot speichern (incl. Typ-Info)
2. Cmd+C simulieren via CGEvent
3. Kurz warten (max 200 ms, polling)
4. Pasteboard auslesen
5. Pasteboard restaurieren
```

**Wichtig:** Schritt 5 ist Pflicht — sonst zerstört Tippi den Clipboard-Inhalt des Users.

### Text-Insertion (zurück zur App)

- **Replace:** Pasteboard setzen → `kVK_ANSI_V` mit ⌘ simulieren → Pasteboard restaurieren
- **Append:** Cursor an Selection-Ende setzen via AX, dann insert
- **Copy:** Nur Pasteboard, kein Paste

---

## 6. LLM-Layer

### 6.1 Provider-Protocol

```swift
protocol LLMProvider {
    var id: String { get }
    var displayName: String { get }
    var availableModels: [LLMModel] { get }

    func complete(
        prompt: String,
        model: LLMModel,
        timeout: TimeInterval
    ) async throws -> String
}
```

### 6.2 Provider-Endpoints

| Provider | Endpoint | Auth |
|----------|----------|------|
| OpenAI | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer <key>` |
| Anthropic | `https://api.anthropic.com/v1/messages` | `x-api-key: <key>` |
| Gemini | `https://generativelanguage.googleapis.com/v1/models/<model>:generateContent` | `?key=<key>` |
| Mistral | `https://api.mistral.ai/v1/chat/completions` | `Authorization: Bearer <key>` |
| Ollama | `http://localhost:11434/api/generate` | none (lokal) |

### 6.3 Request-Strategie

- **Kein Streaming** im MVP (User-Entscheidung) — `stream: false`
- **Timeout:** 30 s default, in Settings einstellbar
- **Retry:** keine automatischen Retries; bei Fehler "Retry"-Button im Vorschau-Fenster
- **Concurrency:** max 1 Request gleichzeitig; neuer Request canceled den alten

### 6.4 Fehler-Mapping

| HTTP / Symptom | UI-Meldung |
|----------------|------------|
| 401 / 403 | „API-Key ungültig — bitte in Settings prüfen" |
| 429 | „Rate-Limit erreicht — bitte später erneut versuchen" |
| 5xx | „Provider-Fehler — Retry oder anderen Provider wählen" |
| Network / Timeout | „Keine Verbindung — Internet prüfen" |
| Local: Ollama unreachable | „Ollama nicht erreichbar — läuft `ollama serve`?" |

---

## 7. Keychain-Storage

```swift
enum KeychainStore {
    static let service = "com.tippi.app"

    static func setAPIKey(_ key: String, for provider: String) throws { … }
    static func getAPIKey(for provider: String) throws -> String? { … }
    static func deleteAPIKey(for provider: String) throws { … }
}
```

- Generic Password Item, `kSecAttrAccessibleAfterFirstUnlock`
- **Kein iCloud-Sync** für Keys (Konsistenz mit Privacy-Versprechen)

---

## 8. UI-Komponenten

### 8.1 Popup-Window

- **NSPanel** mit `.borderless`, `.nonactivatingPanel`, level `.statusBar`
- Positioning: `NSEvent.mouseLocation` oder via AX caret rect
- Width: 280 pt, Height: dynamisch (~280 pt bei 6 Prompts)
- Translucent background (`.hudWindow`-Style)

### 8.2 Preview-Window

- **NSWindow**, `.titled`, `.closable`, level `.modalPanel`
- Width: 640 pt, Height: dynamisch min 320 pt
- TwoColumn-Layout: Original | Vorschlag
- Diff-Highlighting v1.1, erstmal Plain

### 8.3 Settings-Window

- Standard `SettingsLink` via SwiftUI Scene
- Tabs als `TabView`

### 8.4 Menubar

- `NSStatusItem` mit SF Symbol „pencil.and.outline"
- Popover statt Menu für moderne UX

---

## 9. State & Persistence

| Daten | Wo |
|-------|-----|
| Settings (Hotkeys, Modell, Sprache) | `UserDefaults` |
| API-Keys | Keychain (siehe §7) |
| Anfragen / Ergebnisse | **NICHT gespeichert** |
| Logs | `~/Library/Logs/Tippi/` (nur Crashes, ohne Inhalts-Strings) |

**Spotlight-Exclusion:** App-Container via `.metadata_never_index` Marker.

---

## 10. Build & Distribution

### 10.1 Build

```bash
xcodebuild archive \
  -scheme Tippi \
  -configuration Release \
  -archivePath build/Tippi.xcarchive \
  -destination 'generic/platform=macOS'
```

### 10.2 Signing

- **Developer ID Application** Zertifikat (kein App-Store-Cert!)
- Hardened Runtime an, mit Entitlements:
  - `com.apple.security.cs.allow-jit` aus
  - `com.apple.security.cs.disable-library-validation` aus
  - Network: client-only, kein Server

### 10.3 Notarization

```bash
xcrun notarytool submit Tippi.dmg \
  --apple-id "$APPLE_ID" \
  --password "$APP_SPECIFIC_PWD" \
  --team-id "$TEAM_ID" \
  --wait

xcrun stapler staple Tippi.dmg
```

### 10.4 DMG-Erstellung

- Tool: `create-dmg` (Homebrew) oder hdiutil
- Layout: App-Icon links, Applications-Symlink rechts, Drag-Drop-Hint

---

## 11. Performance-Budget

| Metrik | Ziel | Strategie |
|--------|------|-----------|
| Cold-Start bis Popup | ≤ 100 ms | Lazy-Loading von Provider-SDKs, minimale `main`-Logic |
| First-Byte LLM | ≤ 800 ms (Cloud) | direkter URLSession-Call, kein Wrapper-Overhead |
| Popup-Schließen | ≤ 50 ms | NSPanel close, kein Animation-Block |
| RAM idle | ≤ 80 MB | Settings-Window nur lazy laden, kein Background-Polling |

---

## 12. Test-Strategie

| Layer | Tools | Was wird getestet |
|-------|-------|-------------------|
| Unit | Swift Testing | PromptRenderer, KeychainStore, LLMProvider-Mocks |
| Integration | XCTest | Hotkey → Capture → LLM → Insertion (mit Mock-LLM) |
| Manual / Smoke | Checkliste | Top-20-Apps-Kompatibilitäts-Matrix |
| Permissions | Manual | Erst-Setup-Wizard auf frischem User-Account |

**Manuelle Top-20-App-Matrix (Smoke-Test vor Release):**
Mail, Safari, Chrome, Firefox, Pages, Numbers, Keynote, TextEdit, Notes, Slack,
Notion, Obsidian, VS Code, Xcode, iTerm, Tot, Things, Reminders, Bear, Spark.

---

## 13. Bekannte Limitierungen / Risiken

| Risiko | Mitigation |
|--------|------------|
| App ohne AX-Support (z.B. einige Electron-Apps) | Pasteboard-Fallback |
| App fängt Cmd+V ab (z.B. Terminal mit eigenem Mapping) | Dokumentation, AX-Insertion bevorzugen wenn verfügbar |
| User vergisst Accessibility-Permission | Persistent Banner, Setup-Wizard |
| LLM-Provider ändert API | Versioniertes Provider-Layer, klare Fehler |
| Apple ändert TCC-Prompt-Verhalten | macOS-Version-Pinning, Release Notes lesen |
| Ollama läuft nicht | Klare Fehlermeldung mit Setup-Link |

---

## 14. Code-Konventionen

- **Swift Style:** Apple Swift API Design Guidelines
- **SwiftLint** mit `.swiftlint.yml` als Hard Gate im CI
- **Async/Await** für alle Netzwerk-Calls — kein Completion-Handler-Mix
- **Keine Drittabhängigkeiten** außer:
  - **Sparkle 2** (Auto-Update, v1.1)
- **Lokalisierung:** alle UI-Strings via `String(localized:)` + Genstrings-Workflow

---

## 15. Roadmap technisch (was kommt nach v1.0)

| Version | Technische Erweiterung |
|---------|------------------------|
| v1.1 | Whisper.cpp eingebettet (~80 MB Modell-Download separat), Sparkle 2, Custom-Prompts via Property-List |
| v1.2 | Prompt-Variablen-Engine, Prompt-Chain-Runtime |
| v1.3 | Verschlüsselte History via SQLite + SQLCipher |
| v2.0 | Architektur-Review für Cross-Platform: ggf. Kern in Rust extrahieren |
