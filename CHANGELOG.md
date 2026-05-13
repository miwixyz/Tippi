# Changelog

All notable changes to Tippi will be documented in this file.

## [1.1.10] — 2026-05-14

### Changed
- **Über-Tab Icon** — zeigt jetzt das Tippi-Maskottchen statt des SF Symbols

## [1.1.9] — 2026-05-14

### Changed
- **Neues App-Icon** — Tippi-Maskottchen (Roboter mit Sprechblase)
- **Neues Menübar-Icon** — Custom Tippi-Icon statt SF Symbol, Template Image (passt sich automatisch an Light/Dark Mode an)

## [1.1.8] — 2026-05-14

### Changed
- **Brand Kit** — Signal Blue Akzentfarbe, überarbeiteter About-Header, neue Brand Color Assets
- **Popup selection color** — selektierter Eintrag nutzt jetzt `selectedMenuItemTextColor` (korrekte Systemfarbe)
- **Texte poliert** — alle UI-Texte für Public Release überarbeitet
- **Copyright** korrigiert

## [1.1.7] — 2026-05-13

### Fixed
- **App unresponsive after one use** — when the preview window was closed via the native close button (red ✕ or Cmd-W), the internal `isOpen` flag stayed `true` permanently, blocking every subsequent trigger. Fixed by wiring `NSWindowDelegate.windowWillClose` to reset state regardless of how the window is closed.

## [1.1.6] — 2026-05-13

### Fixed
- **Dictation prompt picker** — after dictating, the popup now highlights the first AI prompt by default (not "Insert directly"). Pick any AI prompt to process the transcript, or click "Direkt einfügen" explicitly to paste as-is.

## [1.1.5] — 2026-05-13

### Fixed
- **Sparkle updates not delivered** — `CFBundleVersion` (build number) was hardcoded to `1` in every release. Sparkle compares the build number to decide if an update is available, so all versions looked identical. Build number now derives from `git rev-list --count HEAD` and increments automatically with every release.

## [1.1.4] — 2026-05-13

### New
- **Direkt einfügen** — after dictation, the popup now shows an "Insert directly" row at the top (default, press Return). Dictated text is pasted immediately without going through an AI prompt.
- **Voice instructions for selected text** — when text is selected, the mic button changes to "Speak your instruction…". Speak a custom command (e.g., "make this shorter and more formal") and Tippi applies it directly via AI — no prompt picker needed.

## [1.1.3] — 2026-05-13

### Fixed
- **About tab version display** — version was hardcoded to "1.0.0" instead of reading from the app bundle. Now displays the real installed version via `CFBundleShortVersionString`.

## [1.1.2] — 2026-05-13

### Fixed
- **Whisper model crash fixed** — root cause: Homebrew's whisper-cpp 1.8.4 uses GGML 0.11.1 which loads GPU/CPU backends as separate `.so` plugins from a hardcoded Homebrew path. With Hardened Runtime, macOS blocks these plugins (Team ID mismatch). whisper-cli was crashing with `GGML_ASSERT(device) failed` before even processing audio. Fix: whisper-cli is now built from source (whisper.cpp v1.7.4) with all backends compiled in statically (`GGML_BACKEND_DL=OFF`, `GGML_METAL_EMBED_LIBRARY=ON`). The binary is fully self-contained — no Homebrew, no external `.so` files, no runtime plugin lookup.
- **Whisper output file path fixed** — `whisper-cli --output-txt` writes `<input>.wav.txt`, not `<input>.txt`. The transcriber now reads the correct sidecar filename. (Was silently producing no output even on successful runs.)
- `libwhisper.1.dylib`, `libggml.0.dylib`, `libggml-base.0.dylib` removed from the app bundle — superseded by the static build.

## [1.1.1] — 2026-05-13

### Fixed
- **Welcome screen on every launch** — setup wizard now appears only once; completing it sets a persistent flag so it is never shown again on subsequent launches.
- **Hotkey inactive on first launch** — root cause was the welcome screen being shown every time; after one-time setup the hotkey activates normally. The wizard's final step now shows the correct localized message ("restart required") instead of a raw internal error string when Input Monitoring requires an app restart.
- **API key "lost" on every launch** — not actually lost; the welcome wizard was re-opening and showing an empty key field. The API-key step now displays a "Key already saved" badge on open when a key is already in the Keychain.
- **Whisper model download silently saves HTML** — the download completion handler now validates the HTTP status code and file size. Downloads that return a CDN error page (< 10 MB) are rejected with a clear error message instead of saving a corrupt model file.

## [1.1.0] — 2026-05-13

### New
- **Voice Input** — dictate text instead of selecting it. Tap the mic button in the popup, speak, and Tippi transcribes locally using Whisper. No internet needed, no cloud, runs on-device.
- **In-app model download** — Settings → Voice → choose a model (Tiny/Base/Small, English or Multilingual), click Download. Progress bar, no Terminal required.
- **Accessibility permission survives restarts** — startup polling + auto-observer ensure Tippi picks up its Accessibility permission after a reboot without needing to re-grant it manually.
- **Microphone permission** managed in Settings → Voice alongside all other voice setup.

### Improved
- Hotkey with no text selected now opens the popup with a mic button instead of a dead-end alert — start dictating immediately.
- Popup shown even when no text is selected (mic entry point).

### Fixed
- Accessibility permission lost after Mac restart (TCC timing race at login, no retry logic).
- Popup sizing fix committed (was described in v1.0.1 but missing from that commit).

## [1.0.1] — 2026-05-13

### New
- **Auto-Updates via Sparkle** — check for updates from the menu bar icon (✏️ → Nach Updates suchen…)
- **Help tab** in Settings — quick reference for hotkey, custom prompts, providers, and troubleshooting
- **Close button** (✕) in the prompt popup header
- **Expanded About tab** — description, feature highlights

### Improved
- Custom prompts now sortable via **Drag & Drop** in Settings → Prompts
- Hotkey settings: added restart hint for cases where new hotkey needs an app restart
- Popup window now positions correctly when cursor is near the bottom of the screen
- Removed outdated "Phase 3 Demo" footer text from popup

## [1.0.0] — 2026-05-12

First public release.

### Highlights

- System-wide AI writing assistant — mark text in any app, hit a hotkey, transform via AI
- Cursor-positioned popup menu with 6 built-in prompts: Improve, Fix Grammar, Translate→DE, Translate→EN, Shorten, Lengthen
- Custom prompts with SF Symbol icons and per-prompt AI instructions
- Preview window with Replace / Append / Copy / Regenerate
- 5 AI providers (defaults as of May 2026):
  - OpenAI — `gpt-5-mini`
  - Anthropic Claude — `claude-haiku-4-5`
  - Google Gemini — `gemini-2.5-flash`
  - Mistral — `mistral-small-latest`
  - Ollama — `llama3.3` (local, no key)
- Per-provider model override
- Default global hotkey: ⌥⌘T (configurable in Settings)
- Autostart at login
- DE + EN UI
- API keys stored in macOS Keychain (BYOK — bring your own key)
- No telemetry, no history, no cloud storage

### Requirements

- macOS 15 Sequoia or later
- Apple Silicon (M1+)
- API key for at least one AI provider (or local Ollama)
