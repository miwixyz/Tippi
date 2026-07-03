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
| Locked to one provider | **10 providers** — pick what works for you |
| Cloud-only, your data leaves your Mac | **Two local engines** (MLX, Ollama) — fully offline option |
| Subscription | **Free, open-source (MIT)**, bring your own key |
| Telemetry, analytics, "anonymized" data | **Zero telemetry**, no analytics, no crash reports |

---

## What's in the box

- **24 curated built-in prompts** — Improve · Fix grammar · Shorten · Lengthen · Make formal · Make casual · Simplify · Explain like I'm 10 · Humanize · Summarize · TL;DR · Bullet points · Key points · Action items · Email reply · Adapt for App · LinkedIn / Instagram / Facebook post · Translate (DE/EN/ES)
- **Type or speak a free-form instruction** — select text, then type ("reply to this email", "translate to Spanish") or speak it; Tippi applies it via AI directly
- **Translate Quick Panel** — press ⌥⌘L anywhere (no text selected) for a Spotlight-style window: type or speak, get an instant German ⇄ Spanish translation, and hear it read aloud with a natural voice. Voice input runs on-device; speech output is offline
- **Streaming preview & iterative refine** — the result streams in token by token, then refine it in place ("shorter", "more formal") before replacing
- **Custom prompts** with `{clipboard}`, `{app_name}`, `{language}`, `{selected_text}` variables that adapt to context at trigger time
- **Voice input** — push-to-talk dictation with Whisper or Parakeet running fully on-device (no audio leaves your Mac)
- **10 AI providers** — OpenAI · Anthropic Claude · Google Gemini · Mistral · Scaleway (EU) · Groq · Kimi (Moonshot) · Nebius (EU) · Ollama (local) · MLX (local, Apple-Silicon-native, ~1.5–2× faster than Ollama)
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
