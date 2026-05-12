# Tippi — Product Requirements Document

**Version:** 1.0-draft
**Datum:** 2026-05-12
**Plattform:** macOS (Apple Silicon, ab macOS 15 Sequoia)
**Lizenz:** Kostenlos (BYOK — Bring Your Own Key)

---

## 1. Vision

**Tippi** ist ein systemweiter KI-Schreibassistent für macOS. Der Nutzer markiert
Text in **beliebiger** App (Mail, Safari, Pages, Slack, VS Code, …), drückt
einen konfigurierbaren Hotkey, wählt aus einem kompakten Cursor-Popup einen
Prompt, sieht das LLM-Ergebnis in einem Vorschau-Fenster und entscheidet:
**Ersetzen / Anhängen / Kopieren / Neu generieren**.

**Kernprinzipien:**

- **Privacy first** — keine Telemetry, keine History, eigene API-Keys im Keychain
- **App-agnostisch** — funktioniert überall via macOS Accessibility API
- **Lokal-optional** — Ollama-Unterstützung für komplett offline Workflows
- **Schnell & minimalistisch** — kein Bloat, kein Abo, kein Konto

---

## 2. Zielgruppe

- **Knowledge Worker:** schnellere Mails, Reports, Slack-Antworten
- **Bilinguale Schreiber (DE↔EN):** Hotkey-Translate ohne Browser-Wechsel
- **Privacy-Bewusste:** Ollama lokal, optional gar kein Cloud-Zugriff
- **Mac-Power-User:** Hotkey-First-Workflows, Apple-HIG-konforme UX

---

## 3. MVP-Scope (v1.0)

### 3.1 Must-have

| # | Feature | Beschreibung |
|---|---------|--------------|
| F1 | **Global Hotkey** | Konfigurierbar: normale Combo, Double-Tap, Hold |
| F2 | **Text-Capture** | Markierten Text aus jeder App lesen |
| F3 | **Prompt-Popup** | Kompaktes Menü direkt am Cursor mit 6 Default-Prompts |
| F4 | **LLM-Verarbeitung** | OpenAI, Anthropic, Google Gemini, Mistral, Ollama |
| F5 | **Vorschau-Fenster** | Replace / Append / Copy / Retry / Regenerate-with-other-model |
| F6 | **Settings-UI** | Provider-Keys, Hotkeys, Modell-Auswahl, Sprache |
| F7 | **Keychain-Storage** | API-Keys sicher im macOS Keychain |
| F8 | **Cloud-Hinweis** | Setup-Dialog + permanentes Status-Icon im Popup |
| F9 | **DE + EN UI** | Vollständige Lokalisierung beider Sprachen |

### 3.2 Out of Scope (v1.1+)

- Voice-Input (Push-to-Talk + Auto-Stopp via Whisper.cpp lokal)
- Custom-Prompts erstellen/bearbeiten
- Pro-Prompt-Modell-Auswahl
- Prompt-Variablen jenseits `{selected_text}`
- Prompt-Chains
- History / Versionsverwaltung
- Weitere Sprachen jenseits DE/EN
- App Store Distribution

---

## 4. User Flow

```
[1] Nutzer markiert Text in beliebiger App
        ↓
[2] Hotkey-Trigger (z.B. Double-Tap ⌥)
        ↓
[3] Tippi liest markierten Text (Accessibility API + Clipboard-Fallback)
        ↓
[4] Kompaktes Popup erscheint am Cursor:
    ┌──────────────────────┐
    │ ⚡ Improve           │
    │ ✓  Fix Grammar       │
    │ 🇩🇪 Translate → DE   │
    │ 🇬🇧 Translate → EN   │
    │ ⏬ Shorten           │
    │ ⏫ Lengthen          │
    │ ──────────────────── │
    │ ☁️ GPT-4o-mini       │
    └──────────────────────┘
        ↓
[5] Nutzer wählt Prompt (Pfeiltasten + Enter oder Maus)
        ↓
[6] LLM-Request läuft (Spinner)
        ↓
[7] Vorschau-Fenster zeigt Ergebnis:
    ┌──────────────────────────────────────┐
    │ Original                             │
    │ ───────────────────────────────────  │
    │ <markierter Text>                    │
    │                                      │
    │ Tippi-Vorschlag (GPT-4o-mini)        │
    │ ───────────────────────────────────  │
    │ <LLM-Ergebnis>                       │
    │                                      │
    │ [Replace] [Append] [Copy] [↻ Retry] │
    │ [Regenerate with: Claude Sonnet ▾]   │
    └──────────────────────────────────────┘
        ↓
[8] Nutzer wählt Aktion → Tippi fügt Text in Ursprungs-App ein
```

---

## 5. Default-Prompts (MVP)

| ID | Name DE | Name EN | System-Prompt (intern) |
|----|---------|---------|------------------------|
| P1 | Verbessern | Improve | "Improve the writing quality of the following text. Keep meaning, language and length similar." |
| P2 | Rechtschreibung | Fix Grammar | "Fix only spelling and grammar errors. Do not change wording, tone or style." |
| P3 | Übersetzen → DE | Translate → DE | "Translate the following text to German. Keep tone and formatting." |
| P4 | Übersetzen → EN | Translate → EN | "Translate the following text to English. Keep tone and formatting." |
| P5 | Kürzen | Shorten | "Make the following text about 30 % shorter while keeping all key information." |
| P6 | Verlängern | Lengthen | "Expand the following text with relevant detail and context. About 50 % longer." |

**Prompt-Variable:** ausschließlich `{selected_text}` (an Prompt-Ende angehängt).

**Hinweis:** Im MVP sind diese 6 Prompts fix codiert. Custom-Prompts kommen in v1.1.

---

## 6. Hotkey-System

### 6.1 Drei Trigger-Modi (alle konfigurierbar)

| Modus | Beispiel | Anwendung |
|-------|----------|-----------|
| **Normal Combo** | `⌃ + Space` | klassischer Shortcut |
| **Double-Tap** | `⇧⇧` (Shift × 2) | schnell, hands-on-keyboard |
| **Hold** | `⌥` 500 ms | nutzergesteuert |

### 6.2 Defaults bei Erstinstallation

- **Aktivierung:** Double-Tap Right-Option (⌥⌥)
- **Schließen:** Escape
- **Direktauswahl:** 1–6 für Prompts P1–P6

### 6.3 Konflikt-Detection

- App prüft beim Setzen, ob Combo bereits von macOS oder anderer App belegt ist
- Warnung wenn ja, mit Vorschlag eines freien Slots

---

## 7. LLM-Provider

### 7.1 Unterstützte Provider (MVP)

| Provider | Empf. Standard-Modelle | Geschwindigkeit | Qualität | Hinweis |
|----------|------------------------|-----------------|----------|---------|
| **OpenAI** | gpt-4o-mini, gpt-4o | ⚡⚡⚡ | ★★★ / ★★★★★ | Default Empfehlung |
| **Anthropic** | claude-haiku-4-5, claude-sonnet-4-6 | ⚡⚡⚡ / ⚡⚡ | ★★★★ / ★★★★★ | Sehr stark bei DE |
| **Google Gemini** | gemini-1.5-flash, gemini-1.5-pro | ⚡⚡⚡ | ★★★ / ★★★★ | Großes Free-Tier |
| **Mistral** | mistral-small-latest, mistral-large-latest | ⚡⚡⚡ | ★★★ / ★★★★ | EU-Hosting möglich |
| **Ollama** | llama3.1:8b, qwen2.5:7b, phi3:medium | ⚡⚡ (Hardware-abhängig) | ★★ / ★★★★ | Komplett lokal |

### 7.2 Default-Empfehlung beim Setup-Wizard

1. **Schnell + kostenlos:** „Du hast schon Ollama installiert?" → llama3.1:8b lokal
2. **Schnell + Cloud (günstig):** GPT-4o-mini als ausgewogene Standardwahl
3. **Maximale Qualität:** Claude Sonnet 4.6

### 7.3 API-Key-Verwaltung

- Eingabe in Settings je Provider
- Speicherung als `kSecClassGenericPassword` im macOS Keychain (Service: `com.tippi.app`, Account: `provider.<name>`)
- Keys werden **niemals** geloggt, **niemals** in Plain-Text-Files geschrieben
- "Test Connection"-Button pro Provider

### 7.4 Modell-Auswahl

- **Ein globales Default-Modell** wird in Settings gewählt
- Im Vorschau-Fenster kann der Nutzer per Dropdown ad-hoc auf ein anderes Modell wechseln und „Regenerate" klicken
- Pro-Prompt-Modell-Wahl: **v1.1**

---

## 8. Privacy & Daten

| Aspekt | Verhalten |
|--------|-----------|
| Telemetry | **Komplett aus** — keine Analytics, kein Crash-Tracking |
| History | **Keine Speicherung** der Anfragen oder Ergebnisse |
| API-Keys | Keychain-only, niemals geloggt |
| Logs | Nur Crash-Logs lokal, ohne Inhalts-Strings, Redaktion sensibler Felder |
| Netzwerk | Nur direkte Aufrufe zu User-konfigurierten Provider-Endpoints |
| Cloud-Warnung | Einmaliger Setup-Dialog **+** permanentes Icon (☁️ Cloud / 🏠 Lokal) im Popup |
| Spotlight | App-Daten von Spotlight-Indexierung ausgeschlossen |
| Update-Check | Nur wenn User in Settings aktiviert |

---

## 9. UI & UX

### 9.1 Popup-Verhalten

- Erscheint **direkt unterhalb des Text-Cursors**
- Wenn kein Cursor: zentriert auf aktivem Bildschirm
- Schließt bei Escape, Klick außerhalb, oder Fokus-Verlust
- Tastatur-Navigation: ↑↓ + Enter, oder 1–6 für direkte Auswahl

### 9.2 Vorschau-Fenster

- Modal über aktiver App
- Original (Read-only) + Vorschlag (editierbar)
- Buttons: **Replace** (Default, Enter) / **Append** / **Copy** / **Retry** / **Cancel** (Esc)
- Footer: Modell-Switcher + „Regenerate"

### 9.3 Design

- macOS-15-Stil: vibrancy, materials, SF Symbols
- Dark + Light Mode (System-Setting folgen)
- Keine Custom-Fonts — System-Font (SF Pro)
- Minimale Animationen, max 150 ms

### 9.4 Menüleisten-Icon

- Permanentes Status-Item in Menubar
- Klick öffnet Mini-Menü: "Open Settings", "Quit Tippi", aktuelles Modell

---

## 10. Lokalisierung

- **MVP:** Deutsch + Englisch
- Beide Sprachen vollständig — UI-Strings, Settings, Tooltips, Setup-Wizard
- Sprache folgt System-Sprache, in Settings manuell überschreibbar
- Prompts laufen unabhängig — der LLM-Prompt selbst bleibt Englisch (bessere LLM-Performance), das Ergebnis ist in der Sprache des Eingabetextes

---

## 11. Settings-UI (Tabs)

1. **General** — Sprache, Autostart, Update-Check, Theme
2. **Hotkeys** — Aktivierungs-Hotkey + Prompt-Direktwahl
3. **Providers** — API-Keys, Test-Connection, Modell-Auswahl pro Provider
4. **Model** — globales Default-Modell
5. **About** — Version, Lizenzhinweis, Privacy Statement

---

## 12. Distribution

- **Eigene Distribution** (kein App Store)
- DMG mit signiertem `.app`-Bundle
- **Developer ID Application** Zertifikat
- **Notarization** via `xcrun notarytool`
- **Auto-Update:** Sparkle 2 (optional, opt-in) — v1.0 manuell, Sparkle in v1.1
- Hosting: GitHub Releases oder eigene Website

---

## 13. Erfolgskriterien für v1.0

| Kriterium | Schwelle |
|-----------|----------|
| Cold-Start bis Popup | ≤ 100 ms |
| LLM-Response visible (gpt-4o-mini, kurzer Text) | ≤ 2 s |
| App-Größe `.app` | ≤ 25 MB |
| RAM-Footprint idle | ≤ 80 MB |
| Funktioniert in Top-20-Mac-Apps | 100 % (Mail, Safari, Chrome, Pages, Slack, Notion, Notes, …) |
| Crash-frei in 1-h-Smoke-Test | Pflicht |

---

## 14. Roadmap v1.1+

| Version | Features |
|---------|----------|
| **v1.1** | Voice-Input (Push-to-Talk + Auto-Stopp, Whisper.cpp lokal), Custom-Prompts, Pro-Prompt-Modell, Sparkle Auto-Update |
| **v1.2** | Prompt-Variablen (`{clipboard}`, `{language}`, `{app_name}`), Prompt-Chains |
| **v1.3** | History (verschlüsselt, lokal), weitere UI-Sprachen |
| **v2.0** | Windows-Port (Tauri-Rewrite optional) |

---

## 15. Geklärte Punkte (Stand 2026-05-12)

- [x] Apple Developer Account: **vorhanden** → Notarization möglich
- [x] Icon-Variante: **A — stilisierte Tastenkappe mit Sparkle, minimalistisch monochrom**
- [x] Default-Hotkey: **Double-Tap Right-Option (⌥⌥)**
- [x] Release-Hosting: **GitHub Releases**
- [x] Setup-Wizard mit Probier-Modus: **ja** (Demo-Text + Live-Test als letzter Wizard-Schritt)
