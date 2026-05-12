# Tippi

System-wide AI writing assistant for macOS. Mark text anywhere, hit a hotkey, transform via LLM.

**Status:** Phase 1 — Project skeleton, permissions wizard, Keychain layer.

## Requirements

- macOS 15 Sequoia or later
- Apple Silicon
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- Apple Developer Account (for signing/notarization)

## Build

```bash
make open      # generate project and open in Xcode
make build     # CLI Release build
make clean     # remove generated project
```

## Testing the hotkey (Phase 2 / 3)

The global hotkey is **double-tap right Option (`⌥⌥`)** and needs two macOS permissions:

1. **Accessibility** — to read selected text and paste back
2. **Input Monitoring** — to detect the global hotkey via `CGEventTap`

**Important quirks when developing in Xcode:**

- macOS tracks permissions per-binary-identity. Each `xcodebuild` rebuild **may invalidate the Input Monitoring grant** for the Debug binary in DerivedData. If the hotkey suddenly stops working, re-grant Input Monitoring.
- After granting any permission, the app **must restart** for the `CGEventTap` to be created with the new authorization. Tippi auto-restarts the hotkey listener as soon as the permission flips to granted (via a Combine observer), so quitting/reopening is usually not required — but if events still don't fire, quit Tippi (menubar → Beenden) and re-run from Xcode.
- The cleanest dev flow is **Release build copied to `/Applications/Tippi.app`**: stable signed identity → permissions persist across rebuilds.

**If the hotkey doesn't fire, use the manual trigger:**

- Menubar: ✏️ → **Tippi auslösen… (⇧⌘T)**
- Welcome wizard, Try-It step: **„Tippi jetzt auslösen"**-Button
- Works without Input Monitoring permission — only Accessibility is needed for that path.

## Phase 1 Scope

- [x] XcodeGen project definition (`project.yml`)
- [x] Menubar app skeleton (LSUIElement, no Dock icon)
- [x] Welcome / Setup Wizard (5 steps: intro → accessibility → input monitoring → API key → try-it)
- [x] Accessibility permission check + deep-link to System Settings
- [x] Input Monitoring permission check + deep-link
- [x] Keychain-based API key storage (`KeychainStore`)
- [x] DE + EN localization
- [x] Demo "Probier-Modus" als letzter Wizard-Schritt

## Phase 2 Scope (done)

- [x] HotkeyManager — CGEventTap for double-tap/hold, Carbon `RegisterEventHotKey` for normal combos
- [x] Default trigger: double-tap Right-Option (⌥⌥), 300 ms threshold
- [x] TextCapture: AX-API first, Pasteboard fallback with snapshot/restore
- [x] TextInsertion: replace / append / copy via simulated ⌘V
- [x] Frontmost-app tracking — paste back into the originating app
- [x] Auto-restart hotkey on Input Monitoring permission grant (Combine observer)
- [x] Manual trigger via menubar (⇧⌘T) and Welcome wizard test button

## Phase 3 Scope (in progress)

- [x] Cursor-positioned popup (NSPanel `.nonactivatingPanel`, `.popUpMenu` level)
- [x] 6 default prompts: Improve, Fix Grammar, Translate→DE, Translate→EN, Shorten, Lengthen
- [x] Keyboard navigation: ↑↓ + Enter, 1–6 direct, Esc to dismiss
- [x] Mouse hover + click selection
- [x] Click outside / app deactivation closes popup
- [x] Phase 3 transformations are **local placeholders** — Phase 4 replaces them with real LLM calls
- [ ] Preview window with Original / Suggestion side-by-side (deferred to Phase 3.5)

## Next Phases

| Phase | Inhalt |
|-------|--------|
| **3.5** | Preview-Window mit Replace/Append/Copy/Retry/Regenerate-with-other-model |
| **4**   | LLM-Provider-Integration (OpenAI, Anthropic, Gemini, Mistral, Ollama) — ersetzt die Demo-Transformationen in `DemoPrompt.swift` |
| **5**   | Polish, Notarization, GitHub-Release-Pipeline (Sparkle 2 optional in 5.5) |

## Architecture

See [PRD.md](PRD.md) and [ARCHITECTURE.md](ARCHITECTURE.md).

## License

TBD — see PRD.
