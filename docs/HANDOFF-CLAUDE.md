# Tippi — Übergabe an Claude Code

**Stand:** 2026-05-22 · **Version:** 1.6.0 (Build 95) · **Branch:** `main`  
**Repo:** https://github.com/miwixyz/Tippi · **Lokal:** `~/Coding/Tippi/`

Dieses Dokument fasst die Session **v1.6 PopClip-Ersatz / lokale Schnellaktionen** und alle Folge-Fixes für Texterfassung zusammen. Es ist die Einstiegslektüre für Claude Code (oder einen anderen Agenten) beim Weitermachen.

---

## 1. Was in v1.6 geliefert wurde

### Feature: Lokale Schnellaktionen

PopClip-ähnliche Aktionen **im Tippi-Popup** (nicht automatisch beim Markieren):

| Kategorie | Aktionen |
|-----------|----------|
| Formatierung | Fett, Kursiv, Unterstrichen, Durchgestrichen (RTF + Markdown-Fallback) |
| Transform | Großbuchstaben, Kleinbuchstaben, Wörter groß, Underscore, Bindestrich, Klammern, Zeilen verbinden |
| Info | Zeichen zählen, Wörter zählen (nur Anzeige im Popup) |

**Auslösung:** Text markieren → **⌥⌘T** (oder Menüleiste → „Tippi auslösen…“). **Nicht** wie PopClip bei reiner Markierung.

### Neue / geänderte Dateien

| Datei | Rolle |
|-------|--------|
| `Tippi/Core/LocalTextAction.swift` | Modelle, Transformer, RichTextFormatter, `LocalQuickActionSettings` |
| `Tippi/App/AppDelegate.swift` | `runLocalAction`, Capture + Selektions-Range vor Popup, Hotkey-Default `combo` |
| `Tippi/Core/TextCapture.swift` | Mehrstufige Erfassung (Pasteboard zuerst, AX-Baum, System Events) + `captureFocusedSelectionRange` |
| `Tippi/Core/TextInsertion.swift` | `replaceViaElement` (AX re-select + replace), AX-Suche, dual-tap ⌘V Fallback |
| `Tippi/UI/ToastWindow.swift` | Bestätigungs-Toast nach Schnellaktion (nahe Cursor, 1,5s + Fade) |
| `Makefile` | `make build` signiert mit Developer ID (stabile TCC-Identität) |
| `Tippi/UI/PromptPopup/PromptPopupView.swift` | Sektion Schnellaktionen, async Handler |
| `Tippi/UI/PromptPopup/PromptPopupController.swift` | async `onLocalAction` |
| `Tippi/UI/SettingsView.swift` | Toggle + Help |
| `Tippi/Resources/*/Localizable.strings` | EN+DE Strings |

### Dokumentation (dieser Commit)

- `README.md` — Abschnitte Quick actions, Permissions für Test-Builds
- `CHANGELOG.md` — v1.6.0 Added/Changed/Fixed
- `project.yml` — `MARKETING_VERSION: 1.6.0`, `CURRENT_PROJECT_VERSION: 95`
- In-App Help (EN+DE) — erweitert unter Local quick actions + Troubleshooting
- `.cursor/rules/project.mdc` — Modul + Release-Hinweise

---

## 2. Architektur-Flow (Schnellaktionen)

```
Hotkey / Menü „Tippi auslösen…“
  → handleTriggered()
  → TextCapture.captureSelectedText(sourceApp)        // VOR Popup, VOR Mic-Permission
  → TextCapture.captureFocusedSelectionRange(in:)      // AX-Element + CFRange, Selektion noch live
      → speichern in lastSelectionElement / lastSelectionRange
  → popupController.show(localActions, captured?, onLocalAction async)

Klick Schnellaktion
  → runLocalAction()
  → popup.close()
  → TextInsertion.replaceViaElement(el, range, text)   // re-selektieren + ersetzen via AX
      → fallback: TextInsertion.replace(in: app)        // AX-Suche, dann dual-tap ⌘V
  → ToastWindowController.show(action.title)
```

**Wichtig:** Das Popup ruft `NSApp.activate` → Tippi wird aktiv → Quell-App-Selektion **kollabiert**. Deshalb wird die `CFRange` **vor** dem Popup gegriffen (Selektion noch live) und nach der Aktion via `kAXSelectedTextRangeAttribute` re-selektiert, dann via `kAXSelectedTextAttribute` ersetzt. AX-Set läuft cross-app **ohne** frontmost — kein Focus-Wechsel, kein ⌘V nötig im Erfolgsfall.

---

## 3. Texterfassung (`TextCapture`)

Reihenfolge (Phase 1 ohne Activate, Phase 2 mit Activate):

1. `⌘C` via `cghidEventTap` + `cgAnnotatedSessionEventTap` (Pasteboard zuerst)
2. AX pro App-PID + `kAXWindowsAttribute` Baum-Suche
3. AppleScript / System Events (`AXSelectedText` auf focused text area)
4. Activate Quell-App → AX / AXCopy / Pasteboard erneut

Logging: `Tippi: TextCapture …` in Konsole.app filtern.

---

## 4. Bekannte Einschränkungen

| Thema | Detail |
|-------|--------|
| Kein PopClip-Modus | Kein Auto-Popup bei Markierung — by design |
| Test-Build TCC | `make build` = **Developer ID signiert** (Team `LTKJ6Z2VYB`) → stabile TCC-Identität, Grant bleibt über Builds. Nur **eine** `com.tippi.app` darf existieren (Duplikat in `/Applications` → LaunchServices-Konflikt). Via `open` starten, nicht raw-Binary (bricht TCC auf macOS 26). |
| Spotlight / Suchfelder | Oft keine zuverlässige AX-Selection — **TextEdit** zum Testen |
| Automation | System-Events-Fallback kann **Automation → System Events** brauchen |
| Veröffentlichung | v1.6.0 ist im Repo, Release/DMG/Appcast ggf. noch nicht ausgerollt |

---

## 5. Test-Checkliste (manuell)

```bash
cd ~/Coding/Tippi
make build
pkill -x Tippi
open build/Build/Products/Release/Tippi.app
```

1. [ ] Bedienungshilfen für `build/.../Tippi.app` **an**
2. [ ] TextEdit: „Hallo Welt“ markieren → **⌥⌘T** → Popup mit **Schnellaktionen**
3. [ ] **Großbuchstaben** → Text wird `HALLO WELT`, Popup schließt
4. [ ] **Zeichen** → Meldung „N Zeichen“, Text unverändert
5. [ ] Einstellungen → Allgemein → Schnellaktionen aus → Sektion weg
6. [ ] Konsole: `TextCapture AX ok` oder `pasteboard ok`, kein `failed`

---

## 6. Nächste sinnvolle Schritte (optional)

- [ ] **Release:** `VERSION=1.6.0 make release` (nach Test in TextEdit/Notes/Mail)
- [ ] **Vault:** `~/MWs2ndBrain/02 Projekte/Tippi.md` aktualisieren falls vorhanden
- [ ] UX: Visuelles Feedback nach erfolgreichem Paste (kurzer Toast?)
- [ ] Selection-Cache beim Hotkey-Down (vor MainActor) für noch stabilere Erfassung
- [ ] Unit-Tests für `LocalTextTransformer` (rein string-basiert, leicht testbar)

---

## 7. Build & Release (Kurzreferenz)

```bash
make open      # XcodeGen + Xcode
make build     # Release nach build/Build/Products/Release/ + ad-hoc sign
make release   # Nur wenn release.env + Notary bereit; VERSION muss project.yml entsprechen
```

**Nie** `.xcodeproj` von Hand editieren — nur `project.yml` + `make generate`.

---

## 8. Git / dieser Push

Enthält v1.6 Feature + alle Capture/Insert-Fixes aus der Debug-Session, vollständige Doku und `docs/HANDOFF-CLAUDE.md`.

**Commit-Message (Vorschlag):** siehe Git-Log nach Push.

---

## 9. Prompt für Claude Code (Copy-Paste)

```
Kontext: Tippi macOS App, v1.6.0 auf main. PopClip-style lokale Schnellaktionen sind implementiert.
Lies zuerst: docs/HANDOFF-CLAUDE.md, CHANGELOG.md [1.6.0], README Abschnitte „Local quick actions“ und „Local build permissions“.

Offen aus Nutzer-Test: Schnellaktionen in TextEdit nach make build + Bedienungshilfen verifizieren.
Bei „Kein Text erkannt“: TextCapture.swift Logging prüfen, nicht erneut PopClip-Verhalten einbauen.

Regeln: project.yml für Version, EN+DE Localizable.strings sync, kein .xcodeproj direkt editieren.
```
