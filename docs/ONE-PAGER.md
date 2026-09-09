# Tippi

**Mark text · Hit ⌥⌘T · AI fixes it · Right where you are.**

A system-wide AI writing assistant for macOS that doesn't pull you out of whatever app you're in. Open-source, MIT, no telemetry.

![Tippi mascot](mascot.png)

---

## The 30-second pitch

You're writing in Mail. Slack. Notes. Safari. Anywhere. You select your text, press **⌥⌘T**, pick "Improve" — and the AI's rewrite appears right where your cursor was. No copy-paste, no switching to ChatGPT, no losing flow.

That's it. That's the product.

---

## Why Tippi

| Most AI assistants | Tippi |
|---|---|
| Open a new tab, paste your text, copy the answer back | Works in every app, right at your cursor |
| Locked to one provider | **11 providers** — pick what works for you |
| Cloud-only, your data leaves your Mac | **Two local engines** (MLX, Ollama) — fully offline option |
| Subscription | **Free, open-source (MIT)**, bring your own key |
| Telemetry, analytics, "anonymized" data | **Zero telemetry**, no analytics, no crash reports |
| One utility per menu-bar icon | **One app instead of six** — see below |

---

## One app instead of six

Most Macs accumulate a row of small utilities that each do one thing. Tippi now
covers that whole row:

| What you want | Usually a separate app | In Tippi |
|---|---|---|
| Emoji without the system palette | Rocket | **⌥⌘E picker + `:name:` shortcodes** |
| Text shortcuts while typing | Espanso · TextExpander | **Text Snippets** (reads Espanso files as-is) |
| Action bar at your text selection | PopClip | **Selection action bar** |
| On-device dictation | MacWhisper · Superwhisper | **Dictation mode** (Whisper / Parakeet) |
| Quick translation window | DeepL app | **Translate Quick Panel** (5 languages) |
| AI rewriting, grammar, tone | Grammarly · ChatGPT desktop | **24 prompts + your own**, 11 providers |

Several of those are cheap or free — the saving isn't mainly money. It's six
sets of Accessibility and Input Monitoring permissions to grant and re-grant
after every macOS update, six background processes, six update mechanisms, six
chances for a hotkey collision, and six vendors with a view of what you type.
Tippi is one process, one permission set, one update path — and BYOK, so no
vendor sits between you and your text.

---

## What's in the box

- **24 curated built-in prompts** — Improve · Fix grammar · Shorten · Lengthen · Make formal · Make casual · Simplify · Explain like I'm 10 · Humanize · Add emojis · Defuse · Summarize · TL;DR · Bullet points · Key points · Action items · Email reply · Adapt for App · LinkedIn / Instagram / Facebook post · Translate (DE/EN/ES)
- **Type or speak a free-form instruction** — select text, then type ("reply to this email", "translate to Spanish") or speak it; Tippi applies it via AI directly
- **Text Snippets (v2.0)** — type a trigger anywhere and it expands instantly, no hotkey; reads real Espanso match files directly, or create simple ones in Settings. Dynamic date/weekday values via a picker, no shell syntax
- **Auto-popup on text selection (v2.0)** — PopClip-style quick-actions bar that appears next to any selection, position configurable, off by default
- **Emoji picker + shortcodes (v2.1)** — ⌥⌘E opens a Spotlight-style picker (type to filter, arrows to move, Return inserts at your cursor, recents first), or type `:rakete:` and get 🚀 instantly without any hotkey. German *and* English names — `:rakete:` works as well as `:rocket:`, `kino` finds 🍿 — from pinned Unicode data, plus 135 curated everyday shortcuts. Classic text emoticons (`:-)`, `<3`, `XD`) convert too, on a separate toggle. Unknown names are never guessed at
- **Translate Quick Panel** — press ⌥⌘L anywhere: pre-fills with your current selection if there is one, otherwise type/paste/speak. Source/target language pickers (DE/EN/ES/FR/JA) with a swap button, natural voice read-aloud. Voice input runs on-device; speech output is offline
- **Streaming preview & iterative refine** — the result streams in token by token, then refine it in place ("shorter", "more formal") before replacing
- **Custom prompts** with `{clipboard}`, `{app_name}`, `{language}`, `{selected_text}` variables that adapt to context at trigger time
- **Voice input** — push-to-talk dictation with Whisper or Parakeet running fully on-device (no audio leaves your Mac); optionally mutes your Mac's system audio for the duration of the recording
- **11 AI providers** — OpenAI · Anthropic Claude · Google Gemini · Mistral · Scaleway (EU) · Groq · Kimi (Moonshot) · Nebius (EU) · OpenRouter (300+ models, one key) · Ollama (local) · MLX (local, Apple-Silicon-native, ~1.5–2× faster than Ollama)
- **One-click MLX setup** from Settings — no Terminal needed
- **Auto-updates** via Sparkle 2
- **DE + EN UI**
- Native Swift / SwiftUI / AppKit, signed and notarized

---

## Privacy by design

- API keys live in the macOS Keychain only
- No request history persisted to disk
- Voice transcription runs locally (whisper.cpp, bundled binary)
- MLX and Ollama backends run 100% on your Mac — no cloud round-trip
- App container excluded from Spotlight indexing
- Audit the source: every line is on GitHub

---

## Try it in 60 seconds

1. Download the latest DMG from [GitHub Releases](https://github.com/miwixyz/Tippi/releases)
2. Drag **Tippi.app** to `/Applications`
3. Launch — the setup wizard takes 30 seconds (grant Accessibility, add one API key OR install MLX with one click)
4. Select any text, press **⌥⌘T**

---

## Requirements

- macOS 15 Sequoia or later
- Apple Silicon (M1 / M2 / M3 / M4 / M5)
- At least one AI provider — bring your own key for cloud, or run fully locally with MLX / Ollama

---

**Open source · MIT · [github.com/miwixyz/Tippi](https://github.com/miwixyz/Tippi)**

Made by [Michael Wlr](https://github.com/miwixyz). No analytics. No upsell. Just a tool.
