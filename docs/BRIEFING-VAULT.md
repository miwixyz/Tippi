---
tags: [projekt, mac, app, swift, ki]
projekt: Tippi
status: v1.0.0 released
created: 2026-05-12
github: https://github.com/miwixyz/Tippi
---

# Tippi — Projekt-Briefing

> [!info] Stand 12. Mai 2026
> Version 1.0.0 ist signiert, notarisiert und auf GitHub veröffentlicht. App läuft stabil aus `/Applications/Tippi.app`. Repo aktuell privat. Bereit für Eigenbedarf oder Veröffentlichung.

## 🎯 Was Tippi ist

System-weiter KI-Schreibassistent für macOS. Vergleichbar mit der App **Pismo**, aber Open-Source, mit **5 KI-Anbietern** statt nur einem, vollständig BYOK (Bring Your Own Key), keine Telemetrie.

**Workflow:**
1. In beliebiger Mac-App Text markieren (Mail, Safari, Notes, Slack, ...)
2. Hotkey drücken (Standard: ⌥⌘T)
3. Aus Cursor-Popup eine Aktion wählen (Verbessern, Übersetzen, Grammatik, eigene Prompts, ...)
4. Vorschau prüfen, **Ersetzen** klicken
5. Text in der Original-App ist ersetzt

## 🔗 Live-Zugänge

| Was | Wo |
|-----|-----|
| GitHub Repo | https://github.com/miwixyz/Tippi (privat) |
| Erstes Release | https://github.com/miwixyz/Tippi/releases/tag/v1.0.0 |
| Lokale App | `/Applications/Tippi.app` |
| Quellcode | `/Users/michaelwildenauer/-Coding/Tippi/` |
| Apple Developer Account | miwimail@icloud.com |
| Team-ID (Developer ID) | `LTKJ6Z2VYB` |
| Bundle-ID | `com.tippi.app` |
| Notarytool Profile | `tippi-notary` (im macOS-Schlüsselbund) |

## ✅ Was funktioniert

**Vollständig fertig — Tippi 1.0.0:**

- [x] Globaler Hotkey via macOS-Tastatur-Einstellungen (App-Kurzbefehle → "Tippi auslösen…")
- [x] In-App-Hotkey-Recorder mit `NSEvent.addGlobalMonitorForEvents` (Standard ⌥⌘T)
- [x] Cursor-positioniertes Auswahl-Menü mit 6 eingebauten Prompts
- [x] Vorschau-Fenster: Original | KI-Vorschlag Side-by-Side mit Replace / Append / Copy / Regenerate
- [x] 5 KI-Anbieter integriert: OpenAI, Anthropic, Google Gemini, Mistral, Ollama
- [x] Eigene Prompts mit SF-Symbol-Icons, JSON-persistiert
- [x] Per-Provider-Modell-Override
- [x] Autostart beim Anmelden via `SMAppService`
- [x] Deutsch + Englisch UI
- [x] API-Keys im macOS-Schlüsselbund
- [x] Setup-Wizard mit Permission-Prompts
- [x] Settings-Fenster mit 5 Tabs (Allgemein, Hotkeys, Provider, Prompts, Über)
- [x] Signierter + notarisierter Build mit Developer ID
- [x] DMG-Distribution via GitHub Releases

## 🛠 Technik im Überblick

| Schicht | Wahl |
|---------|------|
| Sprache | Swift 5.10+ |
| UI | SwiftUI + AppKit-Bridges (NSStatusItem, NSPanel, NSHostingController) |
| Min macOS | 15.0 Sequoia |
| Architektur | Apple Silicon only (arm64) |
| Build | XcodeGen (`project.yml`) |
| Signing | Developer ID Application + Hardened Runtime + Apple-Notarisierung |
| Sandbox | **AUS** (nötig für cross-app Text-Capture) |
| Distribution | DMG, eigene Distribution (kein App Store) |
| LSUIElement | true (Menüleisten-App ohne Dock-Icon) |
| Drittabhängigkeiten | **Keine** — nur Apple-Frameworks |

## 🤖 Modelle (Stand Mai 2026)

| Provider | Default-Modell | Auth | Endpoint |
|----------|----------------|------|----------|
| OpenAI | `gpt-5-mini` | `Authorization: Bearer <key>` | `api.openai.com/v1/chat/completions` |
| Anthropic | `claude-haiku-4-5` | `x-api-key: <key>` + Version-Header | `api.anthropic.com/v1/messages` |
| Google | `gemini-2.5-flash` | `?key=<key>` Query-Param | `generativelanguage.googleapis.com/v1beta` |
| Mistral | `mistral-small-latest` | `Authorization: Bearer <key>` | `api.mistral.ai/v1/chat/completions` |
| Ollama | `llama3.3` | Keine | `localhost:11434/api/chat` |

**Updates:** Modelle veraltet? Nur die `defaultModel`-Property in jedem `*Provider.swift` + die Localizable-Strings updaten. Kein anderer Code muss angefasst werden.

## 📜 Bauphasen (Chronologie)

Wie das Projekt entstanden ist, falls man zurückblickt:

1. **Phase 1: Skeleton** — Xcode-Projekt-Struktur, Menubar-App, Setup-Wizard, Keychain-Layer
2. **Phase 2: Capture-Pipeline** — Hotkey-Manager (CGEventTap), Text-Capture (AX + Pasteboard), Text-Insertion
3. **Phase 3: Popup-UI** — Cursor-positioniertes NSPanel mit Prompt-Menü
4. **Phase 4: LLM-Integration** — OpenAI zuerst, dann Anthropic + Gemini + Mistral + Ollama, Provider-Router
5. **Phase B: Vorschau-Fenster** — Original/Vorschlag-Vergleich + Aktions-Buttons
6. **Phase C: Provider-Settings** — In-App Key-Management, Default-Provider-Picker
7. **Phase D: Polish** — Hotkey-Recorder, Custom-Prompts, Autostart, eigenes Settings-Fenster
8. **Phase E: Hotkey-Stabilisierung** — TCC-Probleme bei selbst-signierten Builds erkannt; macOS-Tastatur-Einstellungen-Workaround dokumentiert
9. **Phase F: Release** — Apple Developer ID, Notarisierung, GitHub-Release, signiertes DMG

## ⚠️ Wichtigste Erkenntnisse (Lessons Learned)

> [!warning] TCC + selbst-signierte Apps
> macOS' Privacy-System (TCC) ist bei nicht-Apple-signierten Apps unzuverlässig. Bei jedem ad-hoc-Build ändert sich die Designated Requirement, und macOS „vergisst" gewährte Berechtigungen. **Lösung:** Mit Developer ID signieren → stabile Identity → TCC bleibt. Tippi 1.0.0 ist signiert, das Problem ist Geschichte.

> [!warning] `get-task-allow` blockt Notarisierung
> Apple lehnt Notarisierung ab wenn das Binary `com.apple.security.get-task-allow=true` hat (für Debug). Lösung: in den entitlements explizit auf `false` setzen + im Release-Skript nach `xcodebuild` einmal manuell mit `codesign --force --entitlements ...` neu signieren. Im `scripts/release.sh` schon implementiert.

> [!warning] NSEvent global monitor + unsigned
> `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` gibt für unsigned Builds manchmal non-nil zurück, liefert aber keine Events. **Fallback:** macOS-Tastatur-Einstellungen → App-Kurzbefehle → bindet Hotkey direkt an "Tippi auslösen…"-Menüpunkt.

> [!info] Caps Lock & Fn-Taste
> Bei Modifier-Vergleich nur `.command`, `.shift`, `.option`, `.control` matchen — `.deviceIndependentFlagsMask` enthält auch Caps Lock und Function, was zu Fehl-Matches führt.

> [!info] Carbon Hotkeys
> Carbon `RegisterEventHotKey` braucht **keine** TCC-Permissions und funktioniert auch für Background-Apps. War ein Backup, aber `NSEvent`-Pfad ist Standard geworden.

## 🚀 Release-Pipeline

**Vorgehen für neue Version:**

```bash
cd /Users/michaelwildenauer/-Coding/Tippi
# 1. Code-Änderungen committen
git add -A && git commit -m "Feature XY"

# 2. release.env editieren — VERSION="1.0.1" etc.
$EDITOR release.env

# 3. CHANGELOG.md updaten
$EDITOR CHANGELOG.md

# 4. Build + Notarize + DMG (3-5 Min)
make release

# 5. GitHub Release publizieren
gh release create v1.0.1 dist/Tippi-1.0.1.dmg \
    --title "Tippi 1.0.1" \
    --notes-file CHANGELOG.md

# 6. Lokal installieren
osascript -e 'tell application "Tippi" to quit'
sleep 1
rm -rf /Applications/Tippi.app
hdiutil attach dist/Tippi-1.0.1.dmg -quiet -nobrowse
cp -R "/Volumes/Tippi 1.0.1/Tippi.app" /Applications/
hdiutil detach "/Volumes/Tippi 1.0.1" -quiet
open /Applications/Tippi.app
```

**Was hinter `make release` passiert:** xcodegen generate → xcodebuild Release → re-sign mit Developer ID + Entitlements + Hardened Runtime → DMG erstellen → DMG signieren → an Apple Notary submitten → warten → Stapler-Ticket einbetten → spctl-Check.

## 💾 Speicherorte

| Was | Wo |
|-----|-----|
| API-Keys | macOS Schlüsselbund (Service: `com.tippi.app`, Account: `provider.<id>`) |
| Custom Prompts | `~/Library/Preferences/com.tippi.app.plist` (Key: `tippi.customPrompts.v1`) |
| Hotkey-Combo | Selbe plist (Key: `tippi.hotkeyCombo.v1`) |
| Default Provider | Selbe plist (Key: `defaultProvider`) |
| Pro-Provider-Modell | Selbe plist (Keys: `defaultModel.<provider>`) |
| Crash Logs | `~/Library/Logs/Tippi/` |

**Reset-Befehle:**

```bash
# TCC-Permissions zurücksetzen
tccutil reset Accessibility com.tippi.app
tccutil reset ListenEvent com.tippi.app

# UserDefaults zurücksetzen (Custom Prompts, Settings — Keychain bleibt!)
defaults delete com.tippi.app

# Komplett deinstallieren
rm -rf /Applications/Tippi.app
defaults delete com.tippi.app 2>/dev/null
# Keychain-Einträge einzeln in Schlüsselbundverwaltung löschen
```

## 🗺 Roadmap

| Version | Inhalt | Aufwand |
|---------|--------|---------|
| **1.1** | Voice-Input (Push-to-Talk + Whisper.cpp lokal), Sparkle 2 Auto-Updates | mittel |
| **1.2** | Prompt-Variablen (`{clipboard}`, `{language}`, `{app_name}`), Prompt-Chains | mittel |
| **1.3** | Verschlüsselte Local History (opt-in, SQLite + SQLCipher) | klein |
| **2.0** | Cross-Platform (Windows-Port — Rust-Kern? Tauri?) | groß |

## 🔄 Wiederaufnahme-Checkliste (nach langer Pause)

Wenn ich nach ein paar Monaten zurückkomme:

- [ ] `cd /Users/michaelwildenauer/-Coding/Tippi && git pull`
- [ ] `brew install xcodegen` (falls weg)
- [ ] `make open` → Xcode öffnet
- [ ] Tippi.app im Dock testen — läuft sie noch?
- [ ] **Modelle aktuell?** Pro Provider in den 5 `*Provider.swift` `defaultModel` checken. Bei Bedarf updaten + Localizable.strings Hints
- [ ] Apple-Cert noch gültig? `security find-identity -v -p codesigning` — sollte Developer ID Application zeigen. Sonst auf developer.apple.com renewen
- [ ] Bei neuer Feature-Arbeit: Roadmap-Phase oben aussuchen, los

## 📚 Referenz-Dokumente im Repo

- [`README.md`](https://github.com/miwixyz/Tippi/blob/main/README.md) — öffentliches GitHub-Profil
- [`docs/HANDOVER.md`](https://github.com/miwixyz/Tippi/blob/main/docs/HANDOVER.md) — vollständige technische Übergabe (sehr ausführlich)
- [`CHANGELOG.md`](https://github.com/miwixyz/Tippi/blob/main/CHANGELOG.md) — Versions-Historie
- [`LICENSE`](https://github.com/miwixyz/Tippi/blob/main/LICENSE) — MIT
- [`scripts/release.sh`](https://github.com/miwixyz/Tippi/blob/main/scripts/release.sh) — Build & Release Pipeline
- [`project.yml`](https://github.com/miwixyz/Tippi/blob/main/project.yml) — XcodeGen-Definition (Xcode-Projekt-Datei wird daraus generiert, nicht im Repo)

## 🔐 Sensible Daten — NICHT auf GitHub

- `release.env` (lokal, gitignored)
- App-Specific Password aus `appleid.apple.com` (im Schlüsselbund unter `tippi-notary`)
- API-Keys für die Provider (im Schlüsselbund, Service `com.tippi.app`)

## 💡 Eigene Prompt-Vorschläge zum Übernehmen

Aus den Sessions hängen geblieben — direkt in Settings → Prompts → Neuer Prompt eintragen:

**E-Mail-Antwort:**
```
Du bekommst eine eingehende E-Mail. Schreibe eine freundliche, professionelle 
Antwort auf Deutsch. Halte sie kurz (3-5 Sätze). Beginne mit einer passenden 
Anrede, schließe mit „Viele Grüße, Michael". Gib nur die Antwort zurück.
```

**Slack-Nachricht:**
```
Schreibe den folgenden Text als knappe, direkte Slack-Nachricht um. 
Locker im Ton aber respektvoll. Maximal 2-3 Sätze. Gib nur die Nachricht zurück.
```

**Bayrisch:**
```
Übersetze den folgenden Text ins Bayrische, sehr kumpelhaft, mit Wörtern wie 
„a bissl", „pfiati", „mei". Gib nur die Übersetzung zurück.
```

## 🎁 Schmankerl

- **Icon:** komplett programmatisch mit CoreGraphics gerendert ([icons/generate-icon.swift](https://github.com/miwixyz/Tippi/blob/main/icons/generate-icon.swift)) — keine Drittabhängigkeiten, keine externe KI nötig
- **Build-Time** total: ~30 Sek auf M2/M3
- **Binary-Größe:** 2.1 MB DMG (komprimiert)
- **RAM idle:** ~70 MB
- **First-Response (gpt-5-mini, kurzer Text):** ~1.5 Sek

---

*Briefing erstellt: 12. Mai 2026 · Diese Datei kannst du beliebig in deinen Vault verschieben oder umbenennen.*
