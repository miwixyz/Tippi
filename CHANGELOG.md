# Changelog

All notable changes to Tippi will be documented in this file.

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
