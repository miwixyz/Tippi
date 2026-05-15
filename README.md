<p align="center">
  <img src="docs/mascot.png" width="140" alt="Tippi mascot">
</p>

# Tippi

[![Latest Release](https://img.shields.io/github/v/release/miwixyz/Tippi)](https://github.com/miwixyz/Tippi/releases/latest)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-brightgreen)](#requirements)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Tippi** is a system-wide AI writing assistant for macOS. Select text in any app, hit a hotkey, let AI transform it — improve writing, fix grammar, translate, shorten, lengthen, or run your own custom prompts. Results land back in your original app with one click. No text selected? Trigger the hotkey to record voice — Whisper transcribes locally, then optionally applies an AI prompt.

> Mark text anywhere. Hit ⌥⌘T. Let AI do the rest.

![Tippi in action](docs/demo.gif)

---

## Features

- **Works everywhere** — Mail, Safari, Notes, Slack, VS Code, Pages, every text field on macOS
- **11 built-in prompts** — Improve, Fix Grammar, Translate → DE, Translate → EN, Shorten, Lengthen, Make Formal, Make Casual, Simplify, Summarize, Adapt for App; all language-aware via `{language}`
- **Custom prompts** — write your own AI instructions for repeatable tasks (e.g. "Rewrite as Slack message", "Translate to Bavarian", "Convert to bullet list"); supports `{clipboard}`, `{app_name}`, `{language}`, `{selected_text}` variables resolved at trigger time
- **Import / Export custom prompts** — share prompt collections as `.tippipack` files; merge or replace on import
- **6 AI providers** — choose any combination, switch freely:
  - **OpenAI** (default: `gpt-5-mini`)
  - **Anthropic Claude** (default: `claude-haiku-4-5`)
  - **Google Gemini** (default: `gemini-2.5-flash`)
  - **Mistral** (default: `mistral-small-latest`, EU hosting available)
  - **Ollama** (local, fully offline)
  - **MLX** (local, Apple-Silicon-native, ~1.5–2× faster than Ollama) — Tippi manages a local `mlx_lm.server` on demand, with 7 RAM-tiered model presets (8 / 16 / 32 GB) and auto-start on launch when MLX is your preferred provider
- **Voice Input** — trigger the hotkey with no text selected: a popup with a mic button appears, hold to record (push-to-talk), Whisper transcribes locally, the popup shows the transcript with AI prompt options and an "Insert directly" button
- **Voice Instruction** — select text, trigger the hotkey, then press the mic button in the popup and speak a command (e.g. "make this shorter"); Tippi applies it via AI directly — no prompt picker needed
- **Local Whisper transcription** — speech never leaves your Mac; model downloaded in-app (Settings → Voice); choose Tiny / Base / Small in English or multilingual
- **Preview before applying** — side-by-side original vs. AI suggestion, then Replace / Append / Copy / Regenerate
- **Auto-updates via Sparkle 2** — menu bar → "Check for Updates…", automatic check at launch
- **Configurable global hotkey** — record any combination in Settings, or use macOS's built-in keyboard shortcut binding
- **Autostart at login**
- **Dark Mode + Light Mode** — fully adaptive UI; all surfaces use macOS semantic materials and system colors; brand palette has explicit dark-mode variants
- **DE + EN UI**
- **Privacy-first**:
  - **BYOK** (bring your own API key) — keys stored in macOS Keychain only
  - **No telemetry, no analytics, no crash reporting**
  - **No request history saved** — your text never leaves your Mac except to the AI provider you chose
  - **Voice processing fully local** — Whisper runs on-device, no audio sent anywhere
  - **Open source** under MIT

---

## Requirements

- macOS 15 Sequoia or later
- Apple Silicon Mac (M1, M2, M3, M4)
- At least one AI provider:
  - An API key for OpenAI, Anthropic, Google Gemini, or Mistral, **or**
  - [Ollama](https://ollama.com) installed locally (free, no key required), **or**
  - [MLX](https://github.com/ml-explore/mlx-lm) installed locally via `uv tool install mlx-lm` — Tippi will start and manage the server itself
- **Voice features** (optional): a Whisper model downloaded via Settings → Voice (in-app download, no manual install)

---

## Installation

### From the latest release

1. Download **Tippi-x.y.z.dmg** from [Releases](https://github.com/miwixyz/Tippi/releases)
2. Open the DMG, drag **Tippi.app** to `/Applications`
3. Launch Tippi from your Applications folder
4. Follow the in-app setup wizard (grant Accessibility permission, optionally enter an API key)

Tippi checks for updates automatically at launch. You can also trigger a check manually via the menu bar icon → "Check for Updates…".

### From source

```bash
git clone https://github.com/miwixyz/Tippi.git
cd Tippi
brew install xcodegen
make open
```

Then build and run in Xcode (⌘R). Note: an unsigned build will have TCC permission quirks. For a stable signed build see [Building a release](#building-a-release) below.

---

## Quick start

### 1. Grant permissions

Tippi needs **Accessibility** permission to read selected text from other apps and paste results back. The wizard guides you to System Settings → Privacy & Security → Accessibility. Toggle **Tippi** on.

For Voice Input, macOS will also prompt for **Microphone** access on first use.

### 2. Add an AI provider

Menu bar ✏️ → **Settings → Providers** tab. Enter at least one API key. Recommended starting point:

- **Easiest cloud setup**: [platform.openai.com → API keys](https://platform.openai.com/api-keys), creates `sk-…`, paste into the OpenAI field
- **Free + private**: install [Ollama](https://ollama.com), then `ollama pull llama3.3` in Terminal — Tippi picks it up automatically with no key

### 3. Use it

In any app: select some text → press **⌥⌘T** (the default global hotkey).

Tippi's prompt menu appears at your cursor. Pick a transformation. The preview window shows your original and the AI suggestion side by side. Click **Ersetzen** (Replace) or press Enter — done.

### 4. Voice Input (bonus)

Press **⌥⌘T** with no text selected. A small popup with a mic button appears. Hold the button to record, release to transcribe. Whisper processes your audio locally. The popup shows the transcript — pick an AI prompt to transform it, or click "Insert directly" to paste as-is.

**Voice Instruction:** select text first, then hold the mic button in the popup and speak your instruction (e.g. "translate this to English"). Tippi applies it via AI — no prompt menu step.

To enable voice, download a Whisper model first: Settings → Voice → Download Model.

---

## Configuration

### Global hotkey

**In-app** (Settings → Hotkeys): click the hotkey field, press your desired combination. Saved automatically.

If the in-app hotkey doesn't fire on your machine (self-signed builds can hit macOS TCC quirks), use the **macOS-native fallback** offered in Settings → Hotkeys → "Open macOS Keyboard Shortcuts":

1. macOS Settings → Keyboard → Keyboard Shortcuts → App Shortcuts → **+**
2. Application: **Tippi.app**
3. Menu title: exactly `Trigger Tippi…` (the `…` is one character, type Option+`.`)
4. Shortcut: your choice

This route always works because macOS does the binding, not Tippi.

### Default AI model

Settings → Providers → "Default Provider" picker. Tippi tries the chosen provider first. If it has no key, it falls through to the next configured one. Each provider also has a "Model" field — leave blank for the default (recommended in May 2026: `gpt-5-mini`, `claude-haiku-4-5`, `gemini-2.5-flash`, `mistral-small-latest`, `llama3.3`).

### Custom prompts

Settings → Prompts → "New prompt":

- **Title** — what appears in the popup menu (e.g. "Rewrite as Slack message")
- **SF Symbol** — icon next to the title (find names at [developer.apple.com/sf-symbols](https://developer.apple.com/sf-symbols))
- **Instructions for the AI** — system prompt sent to the model along with your selected text

Custom prompts appear in the popup alongside the built-ins. They use the same default provider.

#### Prompt variables

Use `{placeholders}` in your prompt instructions — Tippi resolves them at trigger time:

| Variable | Resolves to |
|----------|-------------|
| `{clipboard}` | Current clipboard content |
| `{app_name}` | App you triggered Tippi in (e.g. `Mail`, `Safari`, `Slack`) |
| `{language}` | Detected language of your selected text (e.g. `German`, `English`) |
| `{selected_text}` | The selected text itself — useful when you need to reference it explicitly inside the system prompt |

**App-aware tone** — one prompt, adapts to where you're writing:
```
Rewrite the following text for {app_name}.
In Slack: casual, max 2 sentences.
In Mail: formal with greeting.
Return only the result.
```

**Clipboard as style reference** — copy a sample text first, then select what you want to rewrite:
```
Match the tone and style of this reference from my clipboard:
{clipboard}

Rewrite the selected text in that style. Return only the result.
```

**Always stay in the right language** — works for any language, no hardcoding:
```
Improve the following text. Stay in {language}. Return only the improved version.
```

**Context-aware reply** — copy an email/message, then select your draft:
```
Context from clipboard: {clipboard}

This is a draft reply. Polish it so it fits the context above. Return only the improved reply.
```

#### Import / Export custom prompts

Share your custom prompts with teammates or between devices using `.tippipack` files (JSON under the hood):

- **Export all** — Settings → Prompts → "Export All" → saves `Tippi-Prompts.tippipack`
- **Export single** — click the ↑ icon next to any prompt → saves `Tippi-[Title].tippipack`
- **Import** — "Import" button → choose a `.tippipack` → pick **Merge** (keep existing) or **Replace** (overwrite); imported prompts always get fresh IDs to avoid conflicts

### Built-in prompts

Tippi ships with 11 ready-to-use prompts — all language-aware via `{language}`:

| Prompt | What it does |
|--------|-------------|
| **Improve** | Rewrites for better quality, same length and meaning |
| **Fix Grammar** | Corrects spelling, punctuation, grammar only — no rewording |
| **Shorten** | Trims ~30%, keeps all key information |
| **Lengthen** | Expands ~50% with relevant context and detail |
| **Make Formal** | Professional tone, no filler words |
| **Make Casual** | Conversational, natural language |
| **Simplify** | Short sentences, no jargon, no passive voice |
| **Summarize** | 3 concise bullet points with key info |
| **Adapt for App** | Tone adapts to `{app_name}` — casual for Slack/WhatsApp, formal for Mail, bullets for Notes |
| **Translate → DE** | German translation, preserves tone and formatting |
| **Translate → EN** | English translation, preserves tone and formatting |

### Voice / Whisper model

Settings → Voice → Download Model. Three sizes available:

| Model | Size | Speed | Notes |
|-------|------|-------|-------|
| Tiny  | ~75 MB | Fastest | Good for short commands, EN-only variant available |
| Base  | ~145 MB | Fast | Balanced accuracy/speed, recommended default |
| Small | ~465 MB | Slower | Best accuracy for long dictation or noisy environments |

Each size comes in an English-only or multilingual variant. English-only is faster if you only dictate in English.

### Autostart

Settings → General → "Launch Tippi at login". Wired through `SMAppService`, no login items entry needed.

---

## AI provider notes

| Provider  | Cost       | Speed   | Quality | Notes |
|-----------|------------|---------|---------|-------|
| OpenAI    | $          | Fast    | ★★★★   | Most popular. `gpt-5-mini` is the right balance. |
| Anthropic | $          | Fast    | ★★★★★  | Excellent prose quality. `claude-haiku-4-5` for fast tier. |
| Gemini    | Free tier  | Fast    | ★★★    | Generous free tier at `aistudio.google.com/apikey`. |
| Mistral   | $          | Fast    | ★★★★   | EU-hosted option for data-residency requirements. |
| Ollama    | **Free**   | ⚡ Hardware-dependent | ★★–★★★★ | Fully local. Privacy-best. Quality depends on model. |
| MLX       | **Free**   | ⚡⚡ ~1.5–2× faster than Ollama on Apple Silicon | ★★–★★★★ | Fully local, Apple-Silicon-native via Metal. Tippi manages the `mlx_lm.server` process. Auto-starts on launch when set as default. |

API keys are stored exclusively in the macOS Keychain (account `provider.<name>`, service `com.tippi.app`), not in plaintext anywhere on disk.

---

## Contributing

Bug reports and pull requests are welcome. For significant changes, please open an issue first.

**Building a signed release** (Apple Developer account required) is documented in [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## Architecture (short version)

- **Swift 5.10 / SwiftUI / AppKit bridges**, native macOS app, no third-party runtime dependencies
- **Menu-bar-only** (`LSUIElement = true`), no Dock icon, settings + welcome windows shown on demand
- **Hardened Runtime, no Sandbox** — required for cross-app text capture
- **Text capture**: Accessibility API first (`AXUIElementCopyAttributeValue` on focused element), Pasteboard ⌘C round-trip as fallback (with snapshot/restore to keep clipboard intact)
- **Hotkey**: `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` plus a Carbon `RegisterEventHotKey` backup. For self-signed builds, the macOS-native keyboard shortcut binding to the "Trigger Tippi…" menu item is the most reliable path.
- **LLM layer**: a `LLMProvider` protocol with six implementations (OpenAI, Anthropic, Gemini, Mistral, Ollama, MLX); `LLMRouter` picks the preferred configured provider with automatic fallthrough. The MLX provider additionally drives `MLXServerManager`, which spawns and supervises a local `mlx_lm.server` process and resolves the active model ID via `/v1/models`.
- **Voice layer**:
  - `AudioRecorder` — AVFoundation-based push-to-talk capture
  - `WhisperTranscriber` — wraps a statically linked `whisper-cli` binary bundled in the app; runs out-of-process, no dynamic library dependencies
  - `WhisperModelManager` — handles in-app model download, verification, and storage in Application Support
- **Auto-updates**: Sparkle 2 framework; appcast hosted on GitHub Gist, checked at launch and on demand

Full technical handover doc: [`docs/HANDOVER.md`](docs/HANDOVER.md).

---

## Privacy

Tippi is designed so your text never reaches anything except the AI provider you actively configured.

- **No telemetry, ever** — no analytics endpoint, no crash reporter
- **No request history persisted** — once a response is rendered, neither the input nor the output is written to disk
- **API keys**: macOS Keychain, accessible only to Tippi (no iCloud sync)
- **Logs**: only crash-level logs to `~/Library/Logs/Tippi/`, content strings redacted
- **App-container excluded from Spotlight indexing**
- **Voice processing fully local** — audio is passed directly to the bundled `whisper-cli` binary; nothing is sent to any network endpoint

Provider-specific privacy varies — review each provider's data policy if you handle sensitive content. **Ollama** and **MLX** run entirely locally for the strictest privacy posture — no text ever leaves your Mac.

---

## Roadmap

| Version | Status | Highlights |
|---------|--------|------------|
| v1.0.x  | ✅ Done | System-wide hotkey, popup, preview, 5 providers, custom prompts, autostart |
| v1.1.x  | ✅ Done | Voice Input, Voice Instruction, in-app Whisper download, Sparkle 2 auto-updates, brand refresh (mascot icon, `#3070F0` accent, `#020B1D` navy, adaptive dark/light bg), bug fixes through v1.1.11 |
| v1.2    | ✅ Done | Prompt variables — `{clipboard}`, `{app_name}`, `{language}`, `{selected_text}` in custom prompts |
| v1.3    | ✅ Done | 5 new built-in prompts (Formal, Casual, Simplify, Summarize, Adapt for App); Import/Export custom prompts as `.tippipack`; all built-ins use `{language}` |
| v1.4    | ✅ Done | MLX provider — Tippi manages a local `mlx_lm.server`; ~1.5–2× faster than Ollama on Apple Silicon; 7 RAM-tiered model presets; auto model-ID resolution |
| v1.4.1  | ✅ Done | MLX auto-start (on app launch, provider switch, settings save); temperature 0.3 for more consistent rewrites |
| v1.4.2  | ✅ Done | In-app Help and About reflect all 6 providers; new MLX help section; release-time drift check between code and Help/About strings |
| v1.5    | Planned | In-app MLX installer — one-click setup for `uv` + `mlx_lm.server` from Settings, no Terminal required; makes the local MLX provider usable by non-technical users |
| v1.6    | Planned | Encrypted local history (opt-in, SQLite + SQLCipher) |
| v2.0    | Planned | Cross-platform (Windows) |

---

## License

MIT — see [LICENSE](LICENSE).

## Credits

Built with Swift + SwiftUI + AppKit. AI provider APIs by OpenAI, Anthropic, Google, Mistral, the [Ollama](https://ollama.com) project, and [Apple's MLX](https://github.com/ml-explore/mlx-lm) framework via `mlx_lm.server`. Voice transcription via [whisper.cpp](https://github.com/ggerganov/whisper.cpp). Auto-updates via [Sparkle 2](https://sparkle-project.org). Tippi mascot and brand assets by Michael Wlr.

© 2026 Michael Wlr — MIT License
