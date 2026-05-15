# Changelog

All notable changes to Tippi will be documented in this file.

## [1.5.5] — 2026-05-15

### Added
- **6 more built-in prompts**, bringing the total to 22:
  - **Explain like I'm 10** — for a 10-year-old, one everyday analogy, no jargon
  - **Email reply** — friendly professional reply, matched formality, neutral closing (no hard-coded name)
  - **LinkedIn post** — first-person hook, short paragraphs, 2–3 hashtags, no "Thoughts?" cliché
  - **Instagram caption** — emotional, max 150 words, hook works after the "...more" truncation, 3–5 hashtags
  - **Facebook post** — conversational storytelling, sparing hashtags, no marketing-speak
  - **Translate → ES** — natural modern Spanish

## [1.5.4] — 2026-05-15

### Added
- **5 new built-in prompts**:
  - **Humanize** — strips AI tells (corporate buzzwords, hedge phrases, em-dash flow, bombastic adjectives) so text reads like a human wrote it
  - **TL;DR** — 1–2 plain-prose sentences, no labels, no bullets
  - **Bullet points** — converts every distinct thought into its own bullet, no condensing
  - **Key points** — extracts max 5 short essence-bullets (verdichtet)
  - **Action items** — pulls every to-do, each bullet starts with an action verb

### Changed
- **All 11 existing built-in prompts rewritten** for sharper, more reliable output on smaller local models:
  - Explicit negative instructions (no `Here is the improved text:` intros, no quote-wrapping, no commentary)
  - Hard `{language}` enforcement to prevent accidental English translation
  - Concrete thresholds where vague before (`max 5 points`, `1–2 sentences`, `roughly 30% shorter`)
  - Tighter `Return ONLY …` clauses for single-block parseable output
- **`Adapt for App` renamed to `Für App anpassen` (DE) / `Adapt for App` (EN)** for clarity; expanded its built-in app list (Slack/WhatsApp/Telegram/Discord/iMessage · Mail/Outlook/Gmail/Spark · Notes/Notion/Obsidian/Bear · LinkedIn).

### Total
16 curated built-in prompts. Custom prompts in the Prompts tab are unaffected.

## [1.5.3] — 2026-05-15

### Changed
- **MLX model presets expanded from 3 to 6**, all instruct (no chain-of-thought reasoning), spread across the three RAM tiers:
  - 8 GB Mac: **Llama 3.2 3B** ⭐ fast · **Phi-4-mini 3.8B** (Microsoft, 23 languages)
  - 16 GB Mac: **Gemma 3 4B** (Google, 140+ languages) · **Llama 3.1 8B** ⭐ recommended · **Qwen 2.5 7B** (multilingual, strong German)
  - 32 GB Mac: **Qwen 2.5 14B** ⭐ premium
- Each tier has at least one specialist alternative (multilingual coverage, Microsoft license) so users can match the model to their workflow without leaving the curated picker.

## [1.5.2] — 2026-05-15

### Changed
- **MLX model presets curated for text rewrites**: removed 4 presets that emit chain-of-thought "reasoning" tokens before any usable content (Qwen3.5 0.8B/2B/9B, DeepSeek-R1) — these are unsuitable for Tippi's "fix this text, return only the result" interaction. Kept 3 presets, one per RAM tier:
  - Llama 3.2 3B (8 GB Mac, fast)
  - Llama 3.1 8B ⭐ (16 GB Mac, recommended default)
  - Qwen2.5 14B (32 GB Mac, best quality)
- The Custom field is still available for power users who want a different model.

### Note
- If you previously selected one of the removed presets (e.g. Qwen3.5 0.8B), Settings will fall back to "Custom" with your old repo ID. Switch to one of the curated presets above for better results.

## [1.5.1] — 2026-05-15

### Fixed
- **MLX transformations hung at "AI is thinking…"** when more than one model existed in the HuggingFace cache:
  - `MLXProvider` was deriving the request's `model` field from `/v1/models[0].id`, which mlx_lm.server populates with *every* cached model in arbitrary order — not the model we explicitly launched the server with. The fix sends `MLXServerManager.model` (the configured HF repo ID) directly, so requests always match the loaded model.
- **Zombie mlx_lm.server processes** from previous Tippi sessions could survive an app quit and silently block port 8080 for the next launch. `MLXServerManager.start()` now runs `pkill -f mlx_lm.server` before spawning, so each new session begins with a clean server bound to the user's currently configured model.

## [1.5.0] — 2026-05-15

### Added
- **In-app MLX installer** — MLX is no longer Terminal-only. When you pick MLX as your provider in Settings and the toolchain isn't installed yet, Tippi shows a prominent "Install MLX…" button. A guided sheet handles the rest:
  - Phase 1: installs `uv` (Astral's Python tool installer) via the official installer if missing
  - Phase 2: installs `mlx-lm` via `uv tool install mlx-lm`
  - Live log, status indicators per phase, copyable fallback command if anything fails
  - No Terminal required for the typical happy path

Makes the fastest local AI backend on Apple Silicon (~1.5–2× faster than Ollama) accessible to non-technical users.

## [1.4.2] — 2026-05-15

### Changed
- **In-app Help** — Settings → Help now has a dedicated MLX section and the AI providers list mentions all 6 providers (was: 5)
- **About tab** — feature line corrected to "6 AI providers (4 cloud + 2 local)" (was: 5)

### Internal
- `scripts/release.sh` now runs a pre-build drift check: refuses to release when shipped providers don't appear in Help / About strings (EN + DE). Prevents future "the app says 5 providers but ships 6" type drift.

## [1.4.1] — 2026-05-15

### Changed
- **MLX server now auto-starts** — no more manual start required:
  - Pre-warmed on app launch when MLX is your preferred provider — first transformation is instant instead of waiting 30–60s
  - Auto-starts when you switch to MLX in Settings
  - Auto-restarts with new settings when you change model or port and save
- **Temperature 0.3** for MLX completions — more consistent rewrites, less creative drift
- Manual Start / Stop button in Settings remains for power users (e.g. to free RAM)

## [1.4.0] — 2026-05-15

### Added
- **MLX provider** — 6th AI backend: Tippi manages a local `mlx_lm.server` process on-demand
  - No Ollama required, ~1.5–2× faster than Ollama on Apple Silicon
  - OpenAI-compatible API to localhost
  - 7 RAM-tiered model presets (8 / 16 / 32 GB) plus a custom field
  - Configurable port, status indicator, manual Start / Stop in Settings
  - Model ID resolved automatically from the running server via `/v1/models` — works with both HuggingFace repo IDs and local cache paths
  - Fallback decoding for thinking-style models that return `reasoning` instead of `content`
  - Default model: `Meta-Llama-3.1-8B-Instruct-4bit` (no chain-of-thought overhead, fast on M2 Pro 16 GB and up)

## [1.3.0] — 2026-05-15

### Added
- **5 new built-in prompts** — Make Formal, Make Casual, Simplify, Summarize, Adapt for App
- **Import / Export for custom prompts** — share your prompts as `.tippipack` files; import merges or replaces; export all or a single prompt; fresh UUIDs on import to avoid collisions
- All built-in prompts now use `{language}` variable to stay in the detected language of the selected text

## [1.2.0] — 2026-05-15

### Added
- **Prompt Variables** — Custom prompts can now include dynamic placeholders that are resolved at trigger time:
  - `{clipboard}` — current clipboard content
  - `{app_name}` — name of the source application (e.g. Mail, Safari)
  - `{language}` — detected language of the selected text (e.g. German, English)
  - `{selected_text}` — the captured text itself (useful when building context-aware system prompts)
- **Variable hint** in Settings → Prompts editor — available variables are shown below the instruction field

## [1.1.11] — 2026-05-14

### Changed
- **Brand Colors** — Accent `#3070F0`, Navy `#020B1D`, Surface `#E5DEDA` (aus Brand Guide extrahiert)
- **Fenster-Hintergrund** — adaptiv: `#020B1D` im Dark Mode, System-Standard im Light Mode
- **Sparkle Update-Fenster** — liegt jetzt immer im Vordergrund (LSUIElement-Fix via `SPUStandardUserDriverDelegate`)
- **Swift Concurrency** — Timer-Closure in `AudioRecorder` und `FileManager`-Capture in `WhisperModelManager` gefixt

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
