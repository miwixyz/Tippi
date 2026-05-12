# Tippi

**Tippi** is a system-wide AI writing assistant for macOS. Select text in any app, hit a hotkey, let AI transform it — improve writing, fix grammar, translate, shorten, lengthen, or run your own custom prompts. Results land back in your original app with one click.

> Mark text anywhere. Hit ⌥⌘T. Let AI do the rest.

---

## Features

- **Works everywhere** — Mail, Safari, Notes, Slack, VS Code, Pages, every text field on macOS
- **6 built-in prompts** — Improve, Fix Grammar, Translate → DE, Translate → EN, Shorten, Lengthen
- **Custom prompts** — write your own AI instructions for repeatable tasks (e.g. "Rewrite as Slack message", "Translate to Bavarian", "Convert to bullet list")
- **5 AI providers** — choose any combination, switch freely:
  - **OpenAI** (default: `gpt-5-mini`)
  - **Anthropic Claude** (default: `claude-haiku-4-5`)
  - **Google Gemini** (default: `gemini-2.5-flash`)
  - **Mistral** (default: `mistral-small-latest`, EU hosting available)
  - **Ollama** (local, fully offline)
- **Preview before applying** — side-by-side original vs. AI suggestion, then Replace / Append / Copy / Regenerate
- **Configurable global hotkey** — record any combination in Settings, or use macOS's built-in keyboard shortcut binding
- **Autostart at login**
- **DE + EN UI**
- **Privacy-first**:
  - **BYOK** (bring your own API key) — keys stored in macOS Keychain only
  - **No telemetry, no analytics, no crash reporting**
  - **No request history saved** — your text never leaves your Mac except to the AI provider you chose
  - **Open source** under MIT

---

## Requirements

- macOS 15 Sequoia or later
- Apple Silicon Mac (M1, M2, M3, M4)
- At least one AI provider:
  - An API key for OpenAI, Anthropic, Google Gemini, or Mistral, **or**
  - [Ollama](https://ollama.com) installed locally (free, no key required)

---

## Installation

### From the latest release

1. Download **Tippi-x.y.z.dmg** from [Releases](https://github.com/miwixyz/Tippi/releases)
2. Open the DMG, drag **Tippi.app** to `/Applications`
3. Launch Tippi from your Applications folder
4. Follow the in-app setup wizard (grant Accessibility permission, optionally enter an API key)

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

### 2. Add an AI provider

Menu bar ✏️ → **Settings → Providers** tab. Enter at least one API key. Recommended starting point:

- **Easiest cloud setup**: [platform.openai.com → API keys](https://platform.openai.com/api-keys), creates `sk-…`, paste into the OpenAI field
- **Free + private**: install [Ollama](https://ollama.com), then `ollama pull llama3.3` in Terminal — Tippi picks it up automatically with no key

### 3. Use it

In any app: select some text → press **⌥⌘T** (the default global hotkey).

Tippi's prompt menu appears at your cursor. Pick a transformation. The preview window shows your original and the AI suggestion side by side. Click **Ersetzen** (Replace) or press Enter — done.

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

### Autostart

Settings → General → "Launch Tippi at login". Wired through `SMAppService`, no login items entry needed.

---

## AI provider notes

| Provider  | Cost       | Speed   | German quality | Notes |
|-----------|------------|---------|----------------|-------|
| OpenAI    | $          | Fast    | ★★★★           | Most popular. `gpt-5-mini` is the right balance. |
| Anthropic | $          | Fast    | ★★★★★          | Excellent prose quality. `claude-haiku-4-5` for fast tier. |
| Gemini    | Free tier  | Fast    | ★★★            | Generous free tier at `aistudio.google.com/apikey`. |
| Mistral   | $          | Fast    | ★★★★           | EU-hosted option for data-residency requirements. |
| Ollama    | **Free**   | ⚡ Hardware-dependent | ★★ to ★★★★ depending on model | Fully local. Privacy-best. Hardware-dependent. |

API keys are stored exclusively in the macOS Keychain (account `provider.<name>`, service `com.tippi.app`), not in plaintext anywhere on disk.

---

## Building a release

A signed and Apple-notarized DMG is required for stable distribution and TCC permission persistence.

### Prerequisites

- Apple Developer Program membership ($99/year)
- "Developer ID Application" certificate installed in Keychain
- App-specific password from [appleid.apple.com](https://appleid.apple.com) → "Sign-In and Security → App-Specific Passwords"
- `notarytool` credential profile:

  ```bash
  xcrun notarytool store-credentials tippi-notary \
      --apple-id you@example.com \
      --team-id YOURTEAMID \
      --password "xxxx-xxxx-xxxx-xxxx"
  ```

- A `release.env` file (copy from `release.env.example`):

  ```bash
  DEVELOPER_ID="Developer ID Application: Your Name (YOURTEAMID)"
  NOTARY_PROFILE="tippi-notary"
  VERSION="1.0.0"
  ```

### Build

```bash
make release
```

This runs `scripts/release.sh`, which:

1. Generates the Xcode project from `project.yml`
2. Builds Release with hardened runtime + your Developer ID signing
3. Verifies the signature
4. Wraps the `.app` in a DMG with `/Applications` symlink
5. Signs the DMG
6. Submits to Apple's notary service (3–10 min)
7. Staples the notarization ticket
8. Outputs `dist/Tippi-<version>.dmg`

### Publish on GitHub

```bash
gh release create v1.0.0 dist/Tippi-1.0.0.dmg \
    --title "Tippi 1.0.0" \
    --notes-file CHANGELOG.md
```

---

## Architecture (short version)

- **Swift 5.10 / SwiftUI / AppKit bridges**, native macOS app, no third-party runtime dependencies
- **Menu-bar-only** (`LSUIElement = true`), no Dock icon, settings + welcome windows shown on demand
- **Hardened Runtime, no Sandbox** — required for cross-app text capture
- **Text capture**: Accessibility API first (`AXUIElementCopyAttributeValue` on focused element), Pasteboard ⌘C round-trip as fallback (with snapshot/restore to keep clipboard intact)
- **Hotkey**: `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` plus a Carbon `RegisterEventHotKey` backup. For self-signed builds, the macOS-native keyboard shortcut binding to the "Trigger Tippi…" menu item is the most reliable path.
- **LLM layer**: a `LLMProvider` protocol with five implementations; `LLMRouter` picks the preferred configured provider with automatic fallthrough

Full technical handover doc: [`docs/HANDOVER.md`](docs/HANDOVER.md).

---

## Privacy

Tippi is designed so your text never reaches anything except the AI provider you actively configured.

- **No telemetry, ever** — no analytics endpoint, no crash reporter
- **No request history persisted** — once a response is rendered, neither the input nor the output is written to disk
- **API keys**: macOS Keychain, accessible only to Tippi (no iCloud sync)
- **Logs**: only crash-level logs to `~/Library/Logs/Tippi/`, content strings redacted
- **App-container excluded from Spotlight indexing**

Provider-specific privacy varies — review each provider's data policy if you handle sensitive content. **Ollama** runs entirely locally for the strictest privacy posture.

---

## Roadmap

| Version | Highlights |
|---------|------------|
| 1.0     | Current — system-wide hotkey, popup, preview, 5 providers, custom prompts, autostart |
| 1.1     | Voice input (push-to-talk + auto-stop, Whisper.cpp local), Sparkle auto-updates |
| 1.2     | Prompt variables (`{clipboard}`, `{language}`, `{app_name}`), prompt chains |
| 1.3     | Encrypted local history (opt-in, SQLite + SQLCipher) |
| 2.0     | Cross-platform consideration |

---

## License

MIT — see [LICENSE](LICENSE).

## Credits

Built with Swift + SwiftUI + AppKit. AI provider APIs by OpenAI, Anthropic, Google, Mistral, and the [Ollama](https://ollama.com) project. Icon hand-rendered with CoreGraphics, no third-party graphics.
