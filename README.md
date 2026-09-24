<p align="center">
  <img src="docs/mascot.png" width="140" alt="Tippi mascot">
</p>

# Tippi

[![Latest Release](https://img.shields.io/github/v/release/miwixyz/Tippi)](https://github.com/miwixyz/Tippi/releases/latest)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-brightgreen)](#requirements)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**🌐 Website:** [miwixyz.github.io/Tippi](https://miwixyz.github.io/Tippi/) (EN / DE) · **📄 One-pager:** [docs/ONE-PAGER.md](docs/ONE-PAGER.md)

**Tippi** is a system-wide AI writing assistant for macOS. Select text in any app, hit a hotkey, let AI transform it — improve writing, fix grammar, translate, shorten, lengthen, or run your own custom prompts. Results land back in your original app with one click. No text selected? Trigger the hotkey to record voice — Whisper transcribes locally, then optionally applies an AI prompt. It's grown into more than an AI tool since: on-device dictation, a translation panel, text snippets, an emoji picker, and iCloud-synced quick notes all live in the same menu-bar app.

> Mark text anywhere. Hit ⌥⌘T. Let AI do the rest.

![Tippi in action](docs/demo.gif)

---

## One app instead of eight

Tippi started as an AI writing assistant. Since v2.1 it also covers the small
utilities most people bolt onto macOS one by one — each with its own menu bar
icon, its own Accessibility and Input Monitoring grants, its own update
mechanism, and its own hotkeys to keep out of each other's way.

| What you want | The usual separate app | In Tippi |
|---|---|---|
| Pick an emoji without the system palette | Rocket | **⌥⌘E picker + `:name:` shortcodes** (v2.1) |
| Text shortcuts that expand while typing | Espanso, TextExpander | **Text Snippets** — reads existing Espanso files as-is (v2.0) |
| Action bar next to any text selection | PopClip | **Selection action bar**, position configurable (v2.0) |
| Dictation that runs on-device | Superwhisper · Wispr Flow (cloud, subscription) | **Dictation mode**, Whisper/Parakeet **on your Mac** — no account, no subscription, audio never leaves the machine (v1.7) |
| Quick translation window | DeepL app | **Translate Quick Panel**, 5 languages (v1.15) |
| Quick notes synced across Macs | Apple Notes, a separate notes app | **Notes window** (⌥⌘N), plain `.txt` files synced via iCloud, favorites, choosable font (v2.3–v2.7) |
| Pull text off the screen (OCR) | TextSniper, CleanShot X | **Screen OCR** (⌥⌘2) — local, via Apple Vision; freezes the screen, so pop-ups are captured too (v2.12) |
| AI rewriting, grammar, tone | Grammarly · the copy-paste round trip into a chat app | **24 built-in prompts + your own**, 11 providers — in place, no app switch, your own keys |
| Text case/formatting one-offs (bold, UPPERCASE, join lines, word count) | TextSoap, a word-count widget | **Local Quick Actions** — instant, no AI call, works offline (v2.0) |

The point isn't only cost — Rocket and Espanso are free or cheap. It's that
eight background apps mean eight sets of permissions to grant and re-grant
after every macOS update, eight things to keep current, and eight places a
hotkey can collide. Tippi is one process, one permission set, one update
path, and — because it's BYOK and open source — no vendor between you and
your text for anything that touches AI.

---

## Features

- **Works everywhere** — Mail, Safari, Notes, Slack, VS Code, Pages, every text field on macOS
- **It tells you what broke and what to do (v2.11.5)** — the menu bar used to say only "Fehler". It now names the cause, puts the next step on its own clickable row that opens the right place in Settings, and announces a failure on its own — once per new problem, silently. If notifications are denied the menu still carries everything. A stale local server holding the MLX port is cleared automatically (v2.11.7); a *foreign* program holding it is named with its pid rather than killed
- **24 built-in prompts** — Improve, Fix Grammar, Shorten, Lengthen, Make Formal, Make Casual, Simplify, Humanize, Add Emojis, Defuse, Summarize, TL;DR, Bullet points, Key points, Action items, Explain like I'm 10, Email reply, LinkedIn post, Instagram caption, Facebook post, Adapt for App, Translate → DE, Translate → EN, Translate → ES; language-aware prompts use `{language}`
- **Per-prompt provider override** (Settings → Prompts → Built-in, or "Switch provider" right in the result) — pin any built-in prompt to a specific AI provider/model, independent of your global default. Useful when a fast local model is right for most tasks but too small for one specific prompt on long or fact-dense text; the preview also flags a result that came back identical to the input
- **Ambient prompt filtering** — the prompt list narrows live while you type, no shortcut or mode switch. With text selected the instruction field feeds the filter behind the scenes (Return still runs your instruction verbatim, `↓` then Return picks from the pre-filtered list). Without a selection you just type at the popup — query appears in the header, `⌫` shrinks it, `⎋` first clears the query then closes the popup, digit shortcuts `1–9` still work when nothing is typed
- **Custom prompts** — write your own AI instructions for repeatable tasks (e.g. "Rewrite as Slack message", "Translate to Bavarian", "Convert to bullet list"); supports `{clipboard}`, `{app_name}`, `{language}`, `{selected_text}` variables resolved at trigger time
- **Prompt chains** — link several prompts into one hotkey; each step's output feeds the next (e.g. built-in "Cleanup → English" fixes grammar, then translates). The preview shows the current step; if a step fails, the last good result stays editable
- **Verifiable hot keys (v2.9)** — every hot key (main trigger, Translate, Emoji, Notes) shows its real registration state in Settings → Hotkeys: active with the current combination, or the actual reason it is not — including when another app already owns that combination, which `RegisterEventHotKey` reports but Tippi used to discard. **Reset to default** and **Test trigger** sit next to each one, so a hot key can be verified without pressing a key at all. Changing a combination now takes effect **immediately** instead of on the next launch, and a missing Accessibility permission is one button away instead of a sentence pointing at System Settings
- **Text from a screen selection (v2.12)** — press ⌥⌘2, drag a rectangle over anything that can't be copied (a screenshot, an image-only PDF, a video still) and the text lands in your clipboard. Recognition runs locally via Apple's Vision framework (German + English); the captured image never touches disk and there is no history. **Ships off** — it needs the Screen Recording permission, which is permanent once granted, so you only grant it if you want the feature. The result is deliberately **not** handed off to iPhone or iPad: a selection may contain a password. Optional "hide from clipboard history" for confidential captures. Design notes: `docs/SECURE-DESIGN-screen-ocr.md`
- **Freeze-first screen capture (v2.12.3)** — the screen is frozen the instant you press the shortcut, and the selection happens on that still. A pop-up, dialog or tooltip that would close the moment focus moves is therefore still in the picture. You also see exactly what was captured. True menus stay out of reach: they run their own event loop and swallow global shortcuts
- **Join wrapped lines (v2.12.2)** — OCR returns one entry per screen line; this reassembles paragraphs while keeping bullets, numbered lists and sentence breaks intact. Hyphenated line breaks are joined without a space. On by default, off for code or tables
- **Import / Export custom prompts** — share prompt collections as `.tippipack` files; merge or replace on import
- **Local quick actions** — instantly format or transform selected text without an AI call: Bold, Italic, Underline, Strikethrough, Uppercase, Lowercase, Capitalize Words, Underscore, Hyphenate, Convert Umlauts (ä→ae, ö→oe, ü→ue, ß→ss — also applied automatically by Underscore/Hyphenate so filename-style output is actually web-safe), Brackets, Join Lines, Character Count, and Word Count. Available in the hotkey popup, or — opt-in — as an **auto-popup that appears next to any text selection, PopClip-style** (Settings → General; position below/above/left/right, auto-flips to the opposite side if the preferred one doesn't fit)
- **Text Snippets (v2.0)** — type a trigger anywhere (`:mlg`, `:nl`, …) and it expands instantly, no hotkey. Reads real [Espanso](https://espanso.org) match files directly (existing setups migrate with zero file changes) or create simple triggers in Settings → Snippets. Dynamic values (today's date, a weekday this week ± N days, the current calendar week) are built with an "Insert Variable" picker — no shell syntax ever typed or seen. Every match file needs one-time approval before its triggers go live
- **Notes window (v2.3, pin in v2.4, AI titles + Finder-visible folder in v2.5, more in v2.6/v2.7/v2.8, live sync in v2.11.6)** — **Notes written on your other Mac appear by themselves** while the window stays open, and the note you are typing in is never overwritten: an external change waits, the footer says one is waiting, and it applies the moment you leave that note. Nothing is deleted through that path — in an iCloud container a file that has not downloaded yet looks exactly like a deleted one, and notes have no trash. **Favorite a note** (v2.8) from its context menu or a star button on the row; favorites sort into their own section above the rest, synced the same way as other window prefs. **Tippi's own AI/formatting tools now work inside Notes** (v2.8.3) — select text in a note and the same selection popup and ⌥⌘T local actions/prompts that work in every other app now replace correctly in Notes too, via a direct native path instead of the Accessibility APIs meant for other apps. A sparkles button asks your configured AI provider for a short title and inserts it above your text, never replacing anything. A dedicated hotkey (default **⌥⌘N**, configurable in Settings → Hotkeys, same enable-toggle-plus-remap pattern as Translate and the emoji picker) opens a resizable window: a note list on the left, a plain-text editor on the right, standard Mac titlebar with a solid window body and translucent sidebar (v2.9). **Appears in ⌘Tab while open** (v2.6) — Tippi is normally a menu-bar-only app with no Dock icon, invisible to the app switcher entirely, so a temporary Dock icon appears while Notes is open and disappears when it closes. A toolbar pin button keeps it floating above every other app regardless — switch apps, Spaces, or into a full-screen app, and it stays visible instead of getting buried like a normal window. **Font + size are choosable** (v2.6) via the standard macOS Font Panel and **persist across sessions**. Pasting anything with formatting (an email, a web page, a styled document) lands as clean plain text automatically, with a quiet "Formatting removed" toast confirming it — no menu, no extra step (that toast can no longer get stuck on screen, v2.7). Native spell check and a live word/character counter are built in, with comfortable padding around the text (v2.7). **Export any note as `.txt`** (v2.7) via a toolbar button — a save panel for sending a copy somewhere outside iCloud Drive. Each note is its own plain `.txt` file, named after its title (v2.6) and visible as `iCloud Drive → Tippi → Notes` in Finder — synced across your Macs via iCloud, with a local fallback (and automatic migration into iCloud once it becomes available) when you're signed out. Window size/position, sort order, pin state, and font sync too, via a separate small iCloud key-value store — note content and API keys never touch it
- **Emoji picker + `:name:` shortcodes (v2.1)** — a dedicated hotkey (default **⌥⌘E**) opens a Spotlight-style picker: type to filter, arrow keys to move, Return inserts at your cursor in whatever app you were in; recently used emoji come first. Or skip the picker entirely and type `:rakete:` — it becomes 🚀 instantly, anywhere, no hotkey. **Search and shortcodes work in German and English** (`:rakete:` = `:rocket:`, `kino` finds 🍿), backed by 1906 emoji from pinned Unicode data plus 135 hand-picked everyday shortcuts (`:daumen:` 👍, `:herz:` ❤️, `:danke:` 🙏). Unknown names are left exactly as typed — Tippi never guesses — and a shortcode must contain a letter, so `12:30:` or `10:1:` can't turn into an emoji mid-sentence. **Text emoticons** (`:-)`, `;-)`, `:(`, `<3`, `XD`, …) convert too, on their own toggle; they only fire after whitespace, so `a[:(b)]` and `http://` stay untouched. From `:e` onwards a **live suggestion list** appears next to the cursor — Space takes the top match, a click takes any, Escape dismisses. It never steals keyboard focus, so arrow keys and Return keep belonging to the app you're writing in
- **11 AI providers** — choose any combination, switch freely:
  - **OpenAI** (default: `gpt-5.6-luna`)
  - **Anthropic Claude** (default: `claude-haiku-4-5`)
  - **Google Gemini** (default: `gemini-flash-latest`, auto-updating alias)
  - **Mistral** (default: `mistral-small-latest`, EU hosting)
  - **Scaleway** (default: `llama-3.1-8b-instruct`, EU/Paris)
  - **Groq** (default: `openai/gpt-oss-20b`, LPU-accelerated)
  - **Kimi / Moonshot** (default: `kimi-k2`, 1T-MoE, SWE-Bench #1, ~15× cheaper than Opus)
  - **Nebius** (default: `meta-llama/Llama-3.3-70B-Instruct`, EU/Amsterdam, DSGVO)
  - **OpenRouter** (default: `openai/gpt-5.6-luna`) — unified gateway, 300+ models behind one key, `vendor/model` id format, pass-through pricing
  - **Ollama** (local, fully offline)
  - **MLX** (local, Apple-Silicon-native, ~1.5–2× faster than Ollama) — Tippi manages a local `mlx_lm.server` on demand, defaults to the faster Qwen 3.5 2B (4-bit) preset, keeps larger quality presets available, auto-starts on launch when MLX is your preferred provider, and shows generation time in the preview badge.
- **Proactive model-retirement warning** — Tippi checks each configured provider's live model catalogue in the background at launch and flags in Settings if your selected model has been retired, instead of only finding out when a real task 404s.
- **Voice Input** — trigger the hotkey with no text selected: a popup with a mic button appears, hold to record (push-to-talk), Whisper transcribes locally, the popup shows the transcript with AI prompt options and an "Insert directly" button
- **Free-form instruction — typed or spoken** — select text, trigger the hotkey, then type an instruction in the popup's input field (e.g. "reply to this email politely", "translate to Spanish") and press Return, or press the mic button and speak it. Tippi follows it literally: transform instructions (translate, summarize, shorten) operate on the text as-is, reaction instructions (reply, respond) produce an answer. The field auto-focuses; press ↓ to jump back to the prompt list
- **Dictation mode (v1.7+)** — a dedicated hotkey (default **⌃⌥⌘M**) starts recording, press again to stop; Whisper transcribes locally and inserts the text at the cursor — no popup, no text selection. A floating pill shows recording (live waveform), transcribing, and AI-cleanup state with the actual provider name (e.g. "· ✨ Groq")
- **Translate Quick Panel** — a dedicated hotkey (default **⌥⌘L**) opens a Spotlight-style window anywhere; if text is selected it's pre-filled automatically, otherwise type, paste, or dictate it. Source/target language pickers (German, English, Spanish, French, Japanese; source defaults to auto-detect) with a one-click swap button. Input grows with multi-line text and the result scrolls, so a long selection is never clipped. **Replace (⌘⏎)** writes the translation back over the text it came from — shown only when you opened the panel on a selection; otherwise the result is yours to copy (⌘C) and nothing is inserted automatically
- **Local Whisper transcription** — speech never leaves your Mac; model downloaded in-app (Settings → Voice); choose Tiny / Base / Small in English or multilingual
- **Streaming preview** — the AI result streams in token by token instead of appearing all at once after a wait (real streaming for OpenAI, Mistral, Scaleway, Groq, Kimi, Nebius; other providers show it in one piece)
- **Iterative refine** — once a result is ready, type a follow-up in the Refine field ("shorter", "more formal", "add a greeting") to rewrite it in place; chain as many refinements as you like
- **Preview before applying** — side-by-side original vs. AI suggestion, then Replace / Append / Copy / Regenerate, with keyboard shortcuts (Return = Replace, ⌘C = Copy, ⌘Return = Append, ⌘R = Regenerate, Esc = Cancel). A result that hits the model's length limit is kept and flagged "Cut off" rather than discarded
- **Optional provider fallback** — Providers tab → if your chosen provider fails (rate limit, server or network error), Tippi can retry the next configured provider; off by default since it sends your text to a second provider
- **Auto-updates via Sparkle 2** — menu bar → "Check for Updates…", automatic check at launch
- **Configurable global hotkey** — record any combination in Settings, or use macOS's built-in keyboard shortcut binding
- **Autostart at login**
- **Liquid Glass where it belongs (v2.5, scoped in v2.9)** — floating panels (cursor popup, selection action bar, emoji picker, Translate panel, preview, toast, recording indicator) use Apple's Liquid Glass on macOS 26 and later. Window bodies deliberately do not: any full-window translucency blurs the wallpaper down to its average colour, so a coloured desktop turns the window into fog — `glassEffect` and `.regularMaterial` look identical in that role. Settings, Notes and Welcome keep a solid window body with a translucent sidebar, the same split Finder, Mail and Notes.app use
- **Dark Mode + Light Mode** — fully adaptive UI; all surfaces use macOS semantic materials and system colors; brand palette has explicit dark-mode variants
- **DE + EN UI**
- **Encrypted local History (opt-in, v1.9+)** — turn it on in Settings → History to keep a searchable log of every AI transformation. The `input` and `output` fields are encrypted at rest with AES-GCM via CryptoKit; the 256-bit key lives in your macOS Keychain (no iCloud sync). Browse entries side-by-side in a detail sheet, export the full set as JSON or CSV, or wipe everything with a confirmation. Default **OFF** — nothing is written to disk until you opt in.
- **Privacy-first**:
  - **BYOK** (bring your own API key) — keys stored in macOS Keychain only
  - **No telemetry, no analytics, no crash reporting**
  - **No request history by default** — opt-in encrypted local History (AES-GCM, Keychain key, no cloud). When off (default) your text never leaves your Mac except to the AI provider you chose.
  - **Voice processing fully local** — Whisper runs on-device, no audio sent anywhere
  - **Open source** under MIT

---

## Requirements

- macOS 15 Sequoia or later
- Apple Silicon Mac (M1, M2, M3, M4)
- At least one AI provider:
  - An API key for OpenAI, Anthropic, Google Gemini, or Mistral, **or**
  - [Ollama](https://ollama.com) installed locally (free, no key required), **or**
  - **MLX** — no manual install needed; Settings → Providers → MLX → "Install MLX…" handles everything (`uv` + `mlx-lm`) from the app
- **Voice features** (optional): a Whisper model downloaded via Settings → Voice (in-app download, no manual install)

---

## Installation

### From the latest release

1. Download the DMG from **[the latest release](https://github.com/miwixyz/Tippi/releases/latest)** (or pick an older version from [Releases](https://github.com/miwixyz/Tippi/releases))
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

For a local command-line build, `make build` writes to `build/Build/Products/Release/` and signs the app with your **Apple Development** certificate (Developer ID is reserved for notarised releases — a Developer-ID-signed local build gets killed at launch because the embedded development profile doesn't match):

```bash
make build
open build/Build/Products/Release/Tippi.app
```

> Launch via `open` (or Finder), not by running the inner `Contents/MacOS/Tippi` binary directly — on macOS 26 a direct-binary launch breaks the bundle's TCC identity and Accessibility reads as not-granted.

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

**Important:** Tippi is **not** PopClip — marking text alone does **not** open the menu. You must press the hotkey (or use the menu bar → **Trigger Tippi…**).

### 3b. Local quick actions (v1.6+)

With text selected, the popup shows **Quick actions** above the AI prompts — instant, local transforms (no API call):

| Action | Effect |
|--------|--------|
| Bold / Italic / Underline / Strike | Rich text where supported; Markdown-style fallback in plain-text apps |
| Uppercase / Lowercase / Capitalize | Case changes |
| Underscore / Hyphenate / Brackets | `hello world` → `hello_world`, `hello-world`, `(hello world)` |
| Join Lines | Multi-line selection → single line |
| Characters / Words | Count only (inline message, text unchanged) |

A short confirmation toast appears near the cursor after a quick action runs. Toggle visibility: **Settings → General → Show local quick actions**.

**Best results:** native editors (**TextEdit**, **Notes**, Mail compose). Spotlight/search fields and some web inputs may not expose selection to Accessibility — use **TextEdit** to verify permissions.

### 4. Voice Input (bonus)

Press **⌥⌘T** with no text selected. A small popup with a mic button appears. Hold the button to record, release to transcribe. Whisper processes your audio locally. The popup shows the transcript — pick an AI prompt to transform it, or click "Insert directly" to paste as-is.

**Voice Instruction:** select text first, then hold the mic button in the popup and speak your instruction (e.g. "translate this to English"). Tippi applies it via AI — no prompt menu step.

To enable voice, download a Whisper model first: Settings → Voice → Download Model.

### 4b. Dictation mode (v1.7+)

A faster path for pure dictation, with no popup. Enable it in **Settings → Voice → Dictation Mode** and pick a hotkey (default **⌃⌥⌘M**). Then, in any text field: press the hotkey to start recording — a floating pill appears with a live waveform driven by your mic level — press again to stop. Tippi transcribes locally (Parakeet v3 or Whisper) and inserts the text at the cursor.

**Optional AI cleanup** (Settings → Voice → Post-process): Tippi sends the raw transcript through your active LLM provider to remove filler words in whatever language you dictated in (German/English/Spanish/French/Japanese) without stripping words that carry real meaning (e.g. English "also"), remove stutter-style word repeats, add punctuation and correct capitalization (including German noun capitalization), and fix self-corrections. Only runs on inputs ≥ 50 characters; adds 1–3 s latency. If the model responds conversationally instead of cleaning, Tippi detects this and inserts the raw transcript with a toast — dictation never breaks.

**Mute system audio while recording** (Settings → Voice → System Audio, off by default): mutes your Mac's speakers/output for the duration of any recording (dictation, the voice-command popup, or the translate panel) and restores the exact previous state afterward — if your speakers were already muted, they stay muted. Useful when music or a video is playing while you dictate.

Avoid combos macOS reserves (e.g. ⌥⌘D toggles the Dock) — Tippi can't receive a system-claimed shortcut.

### 4c. Translate Quick Panel (v1.15+)

A Spotlight-style translator, independent of the "select text" flow. Press **⌥⌘L** anywhere — nothing needs to be selected — and a floating window opens centered near the top of the screen. Type or paste text, press Return, and Tippi auto-detects whether it's German or Spanish and translates to the other language. No language picker.

- **Speak instead of typing** — the mic button records locally (same Whisper/Parakeet engine as dictation) and auto-translates the transcript.
- **Hear the result** — the speaker button reads the translation aloud with a natural macOS voice, automatically picking a German or Spanish voice to match. Install an Enhanced/Premium system voice (System Settings → Accessibility → Spoken Content) for the most natural output.
- **Read-only** — the result is shown for manual copy (⌘C or the Copy button); nothing is auto-pasted or auto-copied, so it never touches your clipboard unexpectedly.
- Matches the system light/dark appearance and switches live. Change the hotkey in Settings → Hotkeys; a menu bar **Translate…** entry works too.

Runs through your configured AI provider, same as everything else. The default direction (German ⇄ Spanish) is built in; for other language pairs, use a custom prompt with the main hotkey.

### App compatibility

Tippi reads and writes text via the Accessibility API, falling back to a clipboard (⌘C/⌘V) round-trip. This covers native macOS apps (Mail, Notes, Safari, TextEdit, Pages) and Microsoft Office fully. **Dictation (insert at cursor) and text capture work everywhere, including Electron/Chromium apps** such as Obsidian, Claude, ChatGPT, Slack, and VS Code. One limitation: **transforming and replacing a *selection* in Electron/Chromium apps cannot be done in place** — those editors drop the live selection when the picker appears and ignore Accessibility text writes. Tippi detects this and, instead of appending, copies the result to the clipboard and shows a "Copied — press ⌘V to insert" toast. Use dictation there, or transform in a native app for in-place replacement.

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

**Safety hotkey:** **⌃⌥⌘T** (Control + Option + Command + T) always registers via Carbon and does not require Input Monitoring.

### Local build permissions (test builds)

`make build` signs with your Apple Development certificate. The Accessibility grant is stable across rebuilds — but macOS keeps **one** entry per bundle ID (`com.tippi.app`) and checks it against the certificate. A local build and an installed Developer-ID release therefore **push each other out**: the one granted last wins, the other runs without the permission.

**Testing next to an installed release:** use `scripts/devid-testbuild.sh` instead. It produces a Developer-ID-signed build in `/tmp/tippi-devid/export/` that satisfies the existing grant — no toggling in System Settings.

On **macOS 27** the Accessibility pane is called **Device Control and Data Access** (German: *Gerätesteuerung und Datenzugriff*).

1. **System Settings → Privacy & Security → Accessibility** → enable **Tippi**. If Tippi is not listed, add it via **+** → `build/Build/Products/Release/Tippi.app`.
2. Make sure only **one** `Tippi.app` with bundle ID `com.tippi.app` exists. A second copy (e.g. an old release in `/Applications`) creates a LaunchServices conflict that can bind the grant to the wrong bundle. Remove duplicates.
3. Launch via `open` / Finder, **not** the inner `Contents/MacOS/Tippi` binary — a direct-binary launch breaks the bundle's TCC identity on macOS 26.
4. If quick actions still fail in TextEdit: grant **Automation** → Tippi may control **System Events** (AppleScript fallback).
5. Restart Tippi after toggling permissions (`pkill -x Tippi` then reopen).
6. Reset if stuck: `tccutil reset Accessibility com.tippi.app`

### Default AI model

Settings → Providers → "Default Provider" picker. Tippi tries the chosen provider first. If it has no key, it falls through to the next configured one. Each provider also has a "Model" field — leave blank for the default (recommended in Sep 2026: `gpt-5.6-luna`, `claude-haiku-4-5`, `gemini-flash-latest`, `mistral-small-latest`, `llama3.3`).

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

#### Prompt chains (multi-step)

A prompt can run **several prompts in a row** instead of one. Each step's output becomes the next step's input — one hotkey, one preview.

In the prompt editor switch the **Type** from *Single step* to *Chain*, then add at least two steps. Any built-in or custom prompt can be a step (chains can't nest). Reorder with ↑/↓, remove with the trash icon.

- **Built-in example** — "Cleanup → English" fixes grammar, then translates the corrected text to English. Try it without building anything.
- **Progress** — the preview header shows "Step 2/3: …" while the chain runs.
- **Failure** — if a step errors (or references a deleted prompt), the chain stops and the last good intermediate result stays editable, with a red note explaining what broke.
- **Needs a provider** — chains run through your configured AI provider; there's no local-only fallback for a chain.
- Chains export/import inside `.tippipack` like any prompt. Steps that point at *custom* prompts by id won't survive an import into a different vault (built-in steps always do).

#### Import / Export custom prompts

Share your custom prompts with teammates or between devices using `.tippipack` files (JSON under the hood):

- **Export all** — Settings → Prompts → "Export All" → saves `Tippi-Prompts.tippipack`
- **Export single** — click the ↑ icon next to any prompt → saves `Tippi-[Title].tippipack`
- **Import** — "Import" button → choose a `.tippipack` → pick **Merge** (keep existing) or **Replace** (overwrite); imported prompts always get fresh IDs to avoid conflicts

### Built-in prompts

Tippi ships with 24 built-in prompts — all language-aware via `{language}`. A few of the most-used ones (full list lives in the app's prompt popup):

| Prompt | What it does |
|--------|-------------|
| **Improve** | Cuts filler and redundant phrases, tightens wordy constructions, fixes awkward phrasing, varies sentence length, sharpens vague word choices — same meaning, trimming filler is fine |
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
| OpenAI    | $          | Fast    | ★★★★   | Most popular. `gpt-5.6-luna` is the cheapest of the current gpt-5.6 trio. |
| Anthropic | $          | Fast    | ★★★★★  | Excellent prose quality. `claude-haiku-4-5` for fast tier. |
| Gemini    | Free tier  | Fast    | ★★★    | Generous free tier at `aistudio.google.com/apikey`. |
| Mistral   | $          | Fast    | ★★★★   | EU-hosted (Paris). Great German/French. |
| Scaleway  | $          | ⚡ Fast | ★★★    | EU-hosted (Paris). Llama 3.x on European infra. |
| Groq      | $          | ⚡⚡ sub-second | ★★★★ | LPU-accelerated. Fastest hosted option for dictation polish. Llama models retired June 2026 → now GPT-OSS. |
| Kimi      | $          | Fast    | ★★★★★  | Moonshot Kimi K2 — SWE-Bench #1, 256K context, ~15× cheaper than Opus. `platform.moonshot.cn` |
| Nebius    | $          | ⚡ Fast | ★★★★   | 100% EU (Amsterdam). DSGVO-compliant. Very cheap. `studio.nebius.ai` |
| OpenRouter | $ (pass-through) | Depends on routed model | Depends on routed model | 300+ models behind one key. `vendor/model` id format, e.g. `openai/gpt-4o-mini`. `openrouter.ai` |
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
- **LLM layer**: a `LLMProvider` protocol with ten implementations (OpenAI, Anthropic, Gemini, Mistral, Scaleway, Groq, Kimi, Nebius, Ollama, MLX); `LLMRouter` picks the preferred configured provider with automatic fallthrough. OpenAI-compatible providers (OpenAI, Mistral, Scaleway, Groq, Kimi, Nebius) share a single `openAIChatComplete()` / `openAIChatStream()` helper. The MLX provider additionally drives `MLXServerManager`, which spawns and supervises a local `mlx_lm.server` process and resolves the active model ID via `/v1/models`.
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
| v2.12.4 | ✅ Done | **Selection bar closes when you move on** — the pointer moving well away from the bar *and* the selected text (measured from both together, so the end of a long selected line stays in reach) or switching to another app now closes it at once, instead of waiting out the 5-second timer · **no more flash on a click elsewhere** — the bar re-checks on every mouse-up, and clicks on the menu bar, Dock or a toolbar leave the selection intact, so the bar popped back up. A selection whose bar was dismissed now only brings it back when the mouse goes up on the text itself, i.e. a deliberate re-selection. Apps that report no selection bounds keep the old behaviour · docs: `make build` signs with Apple Development, and `scripts/devid-testbuild.sh` gives a Developer-ID test build that shares the installed release's Accessibility grant |
| v2.12.3 | ✅ Done | **Freeze-first screen capture** — the selection overlay calls `NSApp.activate(ignoringOtherApps:)`, which closes every pop-up, menu and tooltip. Since the capture happened *after* the selection, anything focus-sensitive was already gone; images worked because they don't disappear. The screen is now frozen on keypress and the selection runs on that still, so the pop-up is in the picture regardless. Side benefit: a missing Screen Recording permission now surfaces *before* you drag, not after. 11 tests cover the coordinate flip that was wrong once before (AppKit counts Y from the bottom, a CGImage from the top) — removing the flip fails 5 of them. Trade-off recorded in `docs/SECURE-DESIGN-screen-ocr.md`: one full-screen buffer per display now lives briefly in memory instead of just the crop |
| v2.12.2 | ✅ Done | **Join wrapped lines** (on by default) — recognition returns one entry per *screen line*, which is a property of the layout, not the text, so pasted results broke mid-sentence. Deliberately not a blanket strip of every newline: blank lines, sentence endings, colons, bullets and numbered lists start a new block, everything else becomes flowing text. A hyphen at the end of a line is joined without a space, and an abbreviation like "z. B." does not create a false paragraph. Switch it off for code or tables |
| v2.12.1 | ✅ Done | **Screen OCR captured the wrong region** — the selection rectangle comes from AppKit (origin bottom-left), while `sourceRect` expects CoreGraphics (origin top-left). Without the conversion a vertically mirrored area was captured: select at the top, get the bottom. It never surfaced as an error, only as "no text found", because the mirrored spot is usually empty · **a missing permission looked like missing text** — ScreenCaptureKit does not report a denied Screen Recording permission, it returns a black image. A blank capture is now detected and explained, including the restart that macOS requires |
| v2.12.0 | ✅ Done | **Text from a screen selection** — ⌥⌘2, drag a rectangle over anything that can't be copied and the text lands in the clipboard. Recognition is local (Apple Vision, DE+EN); the captured image never touches disk, there is no history, and the recognised text is never logged. **Ships off** — the Screen Recording permission is permanent once granted, so it is only requested on first use · **the result is not handed off to iPhone or iPad**: macOS syncs the clipboard over Handoff by default, which would have carried a captured password off the device although the feature contains no network code at all. Designed with `rafter-secure-design` before the first line of code |
| v2.11.9 | ✅ Done | **Documentation catch-up** — the in-app Help had fallen five versions behind. Notes now explains cross-Mac syncing and why the note you are typing in is never overwritten; Troubleshooting explains the new menu-bar readout and the notification; MLX explains a stale server holding the port; Voice explains how conservative dictation cleanup is and why. Website, README, ARCHITECTURE and CONTRIBUTING brought to the same state |
| v2.11.8 | ✅ Done | **Selecting text in the Notes window shows the action bar again** — the exception for Notes already existed one layer down and was never reached · **dictation cleanup now samples at 0.1 instead of 0.3** — it had been running at a creative-writing default for the one task whose job is to change as little as possible. Per-task, so rewriting and translating are untouched, and models that reject a custom temperature still get none |
| v2.11.7 | ✅ Done | **"Start server" kept failing whatever model was selected** — the model was never the variable. A server left behind by an earlier crash held the port: it accepted connections and never answered, because it logs every request to a stderr pipe pointing at its dead parent. A second server could not bind, which surfaced as a timeout blaming the download. Tippi now clears a stale MLX server off the port and verifies the port is free by looking again; a *foreign* program holding it is named with its pid instead of being killed · **the MLX messages are localized** — they were English inside a German UI |
| v2.11.6 | ✅ Done | **Emergency fix for 2.11.5** — the new failure notification crashed Tippi at launch, and only when there was a failure to announce: the app started fine while everything was well, and quit before the menubar icon appeared when it was not. A completion handler from the notification system was assumed to run on the main actor when it does not. Verified against the running app, not only the test suite |
| v2.11.5 | ✅ Done | **The menubar says what broke and what to do about it** — it used to say only "Fehler", with the actual cause written into a settings pane nobody had open. A second, clickable row now carries the next step and opens Settings · **a notification announces a failure** instead of waiting to be discovered, once per new problem, silent · **the MLX message stopped blaming the connection for a model that is already on disk** — a fully cached model prints one line and then goes quiet while several GB load, and that silence was read as a stalled download; Tippi now distinguishes whether bytes actually moved · **notes from your other Mac appear on their own** while the window stays open, without ever overwriting the note you are typing in and without treating a not-yet-downloaded file as a deletion |
| v2.11.4 | ✅ Done | **Snippets expand in the Notes window again** — typing `:trigger` there was suppressed along with everything else while a Tippi window was frontmost. That guard exists for the snippet editor in Settings, where a trigger is being *defined* and must not expand itself; it now applies to that window only · **notes written on your other Mac show up when you focus the window** — they were syncing over iCloud the whole time, the list simply never re-read them while it stayed open. It now reloads on window focus, on app activation, and on reopening |
| v2.11.3 | ✅ Done | **A crash nobody had seen, surfaced while merging three copies of the same code** — Tippi remembers which passage to replace when you trigger it. Shorten the text in that note while the AI is still working and the remembered position pointed past the end, which ended the app on the spot; the replacement is now skipped instead · **the emoji suggestion list looks like the rest of the app again** — the transparency fix from 2.9.1 had landed in only one of two identical copies, so it rendered as a flat light slab · **the menu-bar activity indicator lights up during streamed answers**, which is the default path and had never switched it on · internally the three copies of the replacement chain (own Notes window → accessibility → clipboard) became one, so changing where a result goes is one edit instead of three. The same duplication had produced the same bug twice before |
| v2.11.2 | ✅ Done | **Full-codebase audit before the next major version** — eleven findings, all fixed. Custom prompts sync again (a type guard added for the words silently blocked them in 2.11.1) · capture no longer hands the LLM a stale clipboard when an app acknowledges a copy without performing one · holding right Shift while typing no longer opens the microphone · overlapping saves can no longer delete a note from disk · translating inside Notes writes back into Notes instead of the app that was in front · the accessibility walk is time-bounded, so wide trees no longer freeze the menu bar · per-click logging dropped from the persistent system log · both remaining compiler warnings cleared, one of which would have broken the build under Swift 6 |
| v2.11.1 | ✅ Done | **Custom words that predate the sync now actually travel** — uploading only ever fired on a *change*, so a Mac whose words were already there never sent them; they looked synced and reached no one. The first sync of a key now **merges** both Macs' lists instead of letting the one that starts second lose its own, and a value of an unexpected type from iCloud is refused rather than written over the words this Mac still holds · **Tippi checks once more right after an update installs**, so a second release published minutes after the first no longer goes unnoticed |
| v2.11.0 | ✅ Done | **Settings sync across your Macs** — custom words and custom prompts travel over iCloud with nothing to set up. API keys stay in the Keychain (Apple syncs that channel itself), shell-snippet approvals stay device-bound on purpose, and hardware-bound settings like the local model choice and the MLX port stay local — a 6 GB model is not the same choice on a smaller Mac. Simultaneous edits resolve to the newer value rather than the last one written · **Model list says what its error count refers to**, and the text above it no longer names models removed in 2.10.0 |
| v2.10.0 | ✅ Done | **Custom words** — a list of terms that keep the spelling you give them (brands, product and proper names, jargon); enforced wherever they appear, never inserted and never applied to other words · **Import Espanso snippets** into Tippi's own store instead of reading files in place, with per-snippet consent for anything that runs a shell command, bound cryptographically to that exact command · **Local models measured, not guessed** — the MLX presets were measured against real German dictations with Tippi's own cleanup prompt; the list now shows results and real download sizes, and the default changed accordingly · **Settings is a sidebar and resizable** · **Security**: a local-only provider no longer falls through to the cloud when its server is down; shell snippets run with a pinned PATH so approvals authorise a binary and not just a string; the forgeable file-approval path was removed in favour of import; an unreadable snippet file can no longer overwrite itself |
| v2.9.1  | ✅ Done | **Selection bar fixes** — the bar could stay gone for a whole session (only one of three Accessibility consumers was not restarted when the permission arrived) · replacing a selection could **append a second copy** in apps that decline to restore the captured range, and the success check could not tell appending from replacing · a transform that changes nothing appended a copy too, now reports *Nothing to change* · the bar landed in the screen's bottom-left corner in Obsidian and other Electron apps, which answer the bounds query with an all-zero rect · the **underscore button was invisible since it shipped** (`underscore` is not an SF Symbol; the test checked uniqueness, not existence) — case and separator actions now use typographic labels. **New**: split underscores, lowercase + underscores in one click, five-second auto-hide. **Build**: `make build` was unusable and the release pipeline would have shipped an app that could not launch on any other Mac (no embedded provisioning profile since iCloud entitlements arrived in v2.3.0) |
| v1.0.x  | ✅ Done | System-wide hotkey, popup, preview, 5 providers, custom prompts, autostart |
| v1.1.x  | ✅ Done | Voice Input, Voice Instruction, in-app Whisper download, Sparkle 2 auto-updates, brand refresh (mascot icon, `#3070F0` accent, `#020B1D` navy, adaptive dark/light bg) |
| v1.2    | ✅ Done | Prompt variables — `{clipboard}`, `{app_name}`, `{language}`, `{selected_text}` |
| v1.3    | ✅ Done | New built-in prompts (Formal, Casual, Simplify, Summarize, Adapt for App); Import/Export custom prompts as `.tippipack` |
| v1.4.x  | ✅ Done | MLX provider — local `mlx_lm.server`, ~1.5–2× faster than Ollama on Apple Silicon; auto-start + temperature tuning; Help/About drift check |
| v1.5.x  | ✅ Done | In-app MLX installer (one-click `uv` + `mlx_lm.server` from Settings); broader built-in prompt catalogue |
| v1.6    | ✅ Done | Voice mode refinements + dictation hotkey stabilisation |
| v1.7.x  | ✅ Done | Provider routing improvements, completion result metadata (`providerID`/`model`) |
| v1.8.x  | ✅ Done | Settings polish + multi-provider quality-of-life fixes |
| v1.9    | ✅ Done | Encrypted local **History** (opt-in, GRDB + CryptoKit AES-GCM field encryption, Keychain-backed 256-bit key, JSON/CSV export) — pivot away from SQLCipher |
| v1.10.x | ✅ Done | Defuse + Add-Emojis modes from Blitztext-App (v1.10.0); HotkeyRecorder TabView-race fix + Carbon-trigger persistence fix (v1.10.1); atomic `isHandlingTrigger`-flag against triple-trigger race that caused 2–5 s UI freeze (v1.10.2); 16-fix review hardening + faster Whisper (v1.10.3) |
| v1.11.x | ✅ Done | Parakeet v3 speech engine, beta (v1.11.0); paste in non-AppKit apps via non-activating panels + universal prompt role-boundary (v1.11.1) |
| v1.12.x | ✅ Done | Type **or** speak a free-form instruction; streaming preview; iterative refine; preview keyboard shortcuts; optional provider fallback; smarter default provider; provider de-dup + truncation guards + ~22 review fixes (v1.12.0); Parakeet v3 as the default speech engine (v1.12.1) |
| v1.13.x | ✅ Done | Provider name shown live in the dictation indicator; menubar icon pulses while any LLM request is in flight |
| v1.14.x | ✅ Done | Kimi (Moonshot) + Nebius (EU) providers — now 10 providers (8 cloud BYOK + 2 local) |
| v1.15.0 | ✅ Done | **Translate Quick Panel** (⌥⌘L) — Spotlight-style window with auto German ⇄ Spanish, local voice input, spoken output, live light/dark |
| v1.16.0 | ✅ Done | **Ambient prompt filtering** — prompt list narrows live while typing, from both input paths (instruction field on selected text via bridge callback; direct type at the popup without selection). Match count in header, `⌫` shrinks query, `⎋` two-stage clear-then-close, digit shortcuts 1–9 preserved |
| v1.17.0 | ✅ Done | **Prompt chains (multi-step pipelines)** — link several prompts behind one hotkey, each step's output feeds the next; live "Step 2/3" progress with a streaming final step, failed steps keep the last good result editable. Built-in "Cleanup → English" chain. Plus stale-Nebius-model-preset 404 fixes + launch migration, and a "Custom…" model-picker snap-shut fix |
| v1.18.0 | ✅ Done | **Faster local default — Qwen 3.5 2B (4-bit)** as the MLX default (~0.6 s warm, most faithful German); real server warm-up before the first request; `enable_thinking=false` fix so thinking models (Qwen 3.x) return usable text |
| v1.18.1 | ✅ Done | **Maintenance** — full-codebase audit fixes: working history delete/reset, reliable Accessibility-permission check for the global hotkey, correct MLX model targeting, no UI freeze on text capture, no false "Saved", plus clipboard-restore, download-race, prompt-loss, MLX-port-safety and deprecated-API fixes |
| v1.19.0 | ✅ Done | **Menu-bar readiness status** — a colored dot on the icon (green ready / yellow loading / red unreachable) plus a worded status in the menu; MLX now tracks true model *warmth* (not just "server up") with self-heal, and a "What's New" Help section |
| v1.20.0 | ✅ Done | **Mute system audio while recording** (opt-in, Settings → Voice → System Audio) — mutes/restores your Mac's output around dictation, popup and translate takes, with crash recovery; sharper built-in **Improve** prompt (concrete edits instead of vague guidance) |
| v1.20.1 | ✅ Done | **Sharper dictation cleanup prompt** — language-aware filler removal (DE/EN/ES/FR/JA) instead of a mixed list that stripped meaningful words (English "also"), hesitation-repeat removal, reliable German noun capitalization |
| v1.20.2 | ✅ Done | **Per-prompt AI provider override** (Settings → Prompts → Built-in) — pin any built-in prompt to a specific provider/model independent of the global default, for cases where a fast local model is right for most tasks but too small for a specific one (e.g. rewriting a long, fact-dense document); preview now flags a result that comes back identical to the input instead of showing it as a normal success |
| v1.20.3 | ✅ Done | **"Switch provider" right in the result** — the preview footer got a provider picker so a disappointing result can be re-run with a different provider without leaving the window; persists as that prompt's override, same storage as the Settings picker |
| v1.20.4 | ✅ Done | **Gemini model IDs updated** — `gemini-2.5-flash`/`gemini-2.5-flash-lite` started returning HTTP 404 ("no longer available to new users") ahead of Google's official Oct 2026 retirement; default and fastest-preset now point to the confirmed `gemini-3.5-flash`/`gemini-3.5-flash-lite` replacements |
| v1.21.0 | ✅ Done | **OpenRouter provider (now 11)** — one key, 300+ models; **proactive model-retirement warning** — Tippi checks each configured provider's live catalogue at launch and flags a stale selection in Settings before a real task fails on it; retirement migration generalized from a Nebius-only table to a shared list that also reaches per-prompt provider overrides |
| v1.21.1 | ✅ Done | The v1.21.0 launch-time model check now runs at explicit background task priority so it can never contend with a hotkey press right after launch |
| v1.24.2 | ✅ Done | **Dictation cleanup no longer cold-starts after transcription** — the local MLX server now warms while you're still speaking (same as the speech engine already did) whenever dictation polish resolves to MLX, instead of only auto-starting at launch when MLX is the global default provider |
| v1.24.1 | ✅ Done | **Icon polish** — the copy-toast checkmark and the two success checkmarks in the local-model (MLX) setup sheet now use SF Symbols' `.symbolEffect(.bounce)` instead of appearing static |
| v1.24.0 | ✅ Done | **Update window now actually comes to the front** — in a menu-bar-only app it could open behind a full-screen window and never be seen; now forced forward with `orderFrontRegardless()` once it exists. Plus a **one-click "Switch to <model>"** button on the retired-model warning, with the replacement verified against the live catalogue |
| v1.23.0 | ✅ Done | **Model catalogue audit** — four of nine cloud providers were on stale or deprecated defaults: OpenAI's entire gpt-4o/gpt-5 line is gone (→ gpt-5.6 trio), Groq deprecated both shipped Llama models in June 2026 (→ gpt-oss), two Anthropic presets were a generation behind (→ Sonnet 5 / Opus 5). Gemini moved to the auto-updating `gemini-flash-latest` alias; all dead ids registered for automatic migration |
| v1.22.1 | ✅ Done | **Fixed false "model may be outdated" warnings** — the v1.21.0 check didn't set a page size, so Anthropic's 20-result default hid working models like `claude-haiku-4-5`; now requests the full catalogue, never warns on a partial one, and tolerates alias-vs-pinned-version naming. Plus a new **"Which model for what?"** Help section with concrete recommendations |
| v1.22.0 | ✅ Done | **Language-detection confidence gate** — short inputs like "LG Michael" were detected as Polish and the prompt then ordered the model to stay in that wrong language (and rendered "Stay in ." when nothing was detected); now requires 0.85 confidence with a valid fallback. Plus **few-shot examples** for Shorten/Summarize/Email reply/Make Formal/Humanize, and a `{clipboard}` privacy warning in Help |
| v2.1.0  | ✅ Done | **Emoji, three ways** — picker (⌥⌘E) with arrow keys and recents · `:name:` shortcodes in German *and* English (1906 emoji, Emoji 16.0 + CLDR 48.2.1, 135 curated aliases) · live suggestion list from `:e` onwards, Space accepts · text emoticons (`:-)` → 🙂) on their own toggle. Unknown names left untouched; guards keep timestamps, score lines, URLs and code from expanding. Plus **Translate panel fixes**: multi-line input no longer clipped, result scrolls, new Replace button (⌘⏎). With this, Tippi covers what usually needs six separate menu-bar apps |
| v2.2.0  | ✅ Done | **Dictation on a single key** — double-tap the key to toggle, hold it to record only while held (right Shift by default, any modifier). The key combination stays the default, so no configured hot key changes. A hold that never sees a release stops itself after five minutes. Plus a **running timer** in the recording pill, a **top/bottom position** for it, and **Liquid Glass** on every floating surface on macOS 26+ (unchanged below — deployment target stays macOS 15). Settings now says when Input Monitoring is missing instead of the hot key silently doing nothing |
| v2.0.1  | ✅ Done | **Critical fix**: the v2.0.0 selection action bar could make ⌘C/⌘V/⌘X/Delete/typing/Escape stop working in whatever app you'd selected text in — it was becoming the system's one key window despite having no text field to need one. Never becomes key now; clicks work via `acceptsFirstMouse`, Escape closes it directly |
| v2.0.0  | ✅ Done | **Text Snippets** — Espanso-style live-typing expansion, built in, reads real Espanso match files directly, dynamic date/weekday variables via a no-shell-syntax picker, per-file approval gate. **Auto-popup on text selection** (PopClip-style, configurable position with auto-flip). **Translate Quick Panel**: source/target language pickers + selection pre-fill. **Umlaut transliteration** local action. **Help tab** restructured into searchable categories |
| v2.3.0  | ✅ Done | **Notes window** (⌥⌘N, remappable) — resizable list + editor, plain `.txt` files synced via iCloud with local fallback, window prefs synced separately via key-value store. Paste always lands as clean text with a "Formatting removed" toast, native spell check, live word/character counter |
| v2.8.4  | ✅ Done | **Toast pill could still get stuck** even after the v2.7.0 fix — a hard-deadline safety net now force-hides it regardless of whether `NSAnimationContext`'s fade completion handler fired |
| v2.8.3  | ✅ Done | **Fixed Tippi's own AI/formatting tools not working inside its own Notes editor** — the selection popup and ⌥⌘T local actions/prompts now use a direct native path for Notes instead of resolving to the wrong app or appending instead of replacing |
| v2.8.2  | ✅ Done | **Fixed choosing a font in Notes silently doing nothing** — the "Aa" toolbar button now focuses the editor before opening the Font Panel, since `changeFont(_:)` needs the text view to already be first responder |
| v2.8.1  | ✅ Done | **Fixed a note appearing twice** (most visibly in Favorites) — a rename-on-title-change bug could leave the old filename behind on disk; already-affected notes self-heal on next Notes window open |
| v2.8.0  | ✅ Done | **Favorite notes** (star + Favorites section), **menu bar icons + colored status header**, **redesigned Local Quick Actions popup** (colored icon badges per category) |
| v2.7.0  | ✅ Done | Notes polish from real feedback: **export as `.txt`** via a toolbar button, a **stuck-toast fix** (fast second toast could race an earlier one's fade-out), titlebar reverted to a **standard Mac titlebar**, and more **breathing room** around text/counter |
| v2.6.0  | ✅ Done | Notes: file names show the **title** in Finder, **choosable font + size** via the Font Panel, and the window now **appears in ⌘Tab** while open (temporary Dock icon) |
| v2.5.0  | ✅ Done | **Liquid Glass on every window** (Settings, Welcome, Preview, Notes) — one consistent look, not just the floating panels. Plus **AI-generated note titles**: a sparkles button inserts a short title above your text |
| v2.4.1  | ✅ Done | Notes now show up as a visible **`iCloud Drive → Tippi → Notes`** folder in Finder, not just a synced-but-invisible app container |
| v2.4.0  | ✅ Done | **Pin the Notes window** — toolbar toggle keeps it floating above every other app, visible across app switches, Spaces, and full-screen apps instead of getting buried |
| v2.3.1  | ✅ Done | **Fixes**: letter-ending emoticons (`:o`, `:O`, `:p`, `:P`) no longer convert mid-word — was destroying real snippet triggers like `:ot` before they could match; the "Insert Variable" weekday picker now renders month names in German (`LC_TIME=de_DE.UTF-8`) instead of whatever locale the shell inherited |
| v3.0+   | Planned | Cross-platform (Windows port, likely Rust/Tauri) — unscheduled |

Full version history → [CHANGELOG.md](CHANGELOG.md) (single source of truth).

---

## License

MIT — see [LICENSE](LICENSE).

## Credits

Built with Swift + SwiftUI + AppKit. AI provider APIs by OpenAI, Anthropic, Google, Mistral, the [Ollama](https://ollama.com) project, and [Apple's MLX](https://github.com/ml-explore/mlx-lm) framework via `mlx_lm.server`. Voice transcription via [whisper.cpp](https://github.com/ggerganov/whisper.cpp). Auto-updates via [Sparkle 2](https://sparkle-project.org). Tippi mascot and brand assets by Michael Wlr.

© 2026 Michael Wlr — MIT License
