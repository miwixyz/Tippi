# Changelog

## [1.12.2] — 2026-06-24

### Added
- **Waveform indicator while recording.** The dictation pill now shows an animated 8-bar waveform driven by the live microphone level instead of a pulsing red dot — you can see how loud you're speaking in real time.
- **AI-polish badge in the indicator.** When the post-process setting is on, the pill shows a subtle "· AI" (or "· KI") suffix during transcription and an "AI cleanup…" label while the LLM is polishing, so it's always clear which step Tippi is on.

### Changed
- **Cleanup minimum raised 20 → 50 characters.** Weak local models (llama3.2:3B and similar) were misinterpreting short utterances as conversational prompts and replying instead of cleaning. Very short dictations are now inserted as-is — the latency saving outweighs any cleanup benefit anyway.
- **Hardened cleanup prompt.** The default post-process system prompt now locks the model into a "text cleanup tool only" role with an explicit "NEVER respond conversationally" instruction and five few-shot examples (DE + EN). Prevents instruction-light models from going off-script.

### Fixed
- **AI-cleanup fallback when model responds conversationally.** Tippi now detects when the cleanup LLM replied instead of cleaned (length blowup or known conversational openers in DE/EN) and falls back to the raw transcript with a visible toast. Previously, a misbehaving local model would silently replace your dictation with an AI reply.

## [1.12.1] — 2026-06-23

### Changed
- **Parakeet v3 is now the default speech engine.** It transcribes markedly faster than Whisper small with about half the word-error rate for German and other European languages, stays in memory after first load (no per-dictation cold start), and self-downloads its ~600 MB CoreML model on first use. You can switch back to Whisper any time in Settings → Voice → Speech engine; if you had already picked an engine, your choice is preserved.

## [1.12.0] — 2026-06-23

### Added
- **Give Tippi a free-form instruction — typed or spoken.** With text selected, the popup now has an input field at the bottom: type an instruction (e.g. "reply to this email politely", "translate to Spanish") and press Return, or tap the mic and speak it. Tippi follows it literally — transform instructions (translate, summarize, shorten) operate on the text as-is, reaction instructions (reply, respond) produce an answer. The field auto-focuses so you can type immediately; press ↓ to jump back to the prompt list. (The spoken path existed before; typing is new, and the underlying instruction prompt was rewritten to distinguish transform-vs-react so "translate a question" no longer answers the question.)
- **Streaming preview.** Results now stream in token by token in the preview window instead of appearing all at once after a wait — perceived latency drops sharply. Real streaming for OpenAI, Mistral, Scaleway and Groq; other providers show the result in one piece.
- **Iterative refine.** Once a result is ready, refine it in place: type a follow-up ("shorter", "more formal", "add a greeting") in the new Refine field and it rewrites the current result. Chain as many as you like.
- **Preview keyboard shortcuts.** Return = Replace, ⌘C = Copy, ⌘Return = Append, ⌘R = Regenerate, Esc = Cancel.
- **Optional provider fallback.** Providers tab → "Fall back to other providers on error": if the chosen provider fails (rate limit, server or network error), Tippi retries the next configured provider. Off by default (it sends your text to a second provider).

### Changed
- **Smarter default provider.** With no explicit default set, Tippi now uses the first provider you've actually added a key for, instead of always trying OpenAI first and falling through to a cold-starting local model.
- **Truncated results are no longer discarded silently.** When a model hits its output length limit mid-stream, the partial text is kept and flagged "Cut off" so you can decide, rather than failing outright.
- **Cloud request timeouts raised 30 s → 60 s** to accommodate reasoning models.
- **Faster text capture/insertion.** Replaced fixed 150 ms focus-switch sleeps with an early-exit poll on the source app becoming active (≈15–30 ms for snappy apps; capped for slow ones).
- **Faster repeat dictation.** The Whisper model cache is no longer re-read on every recording start once warmed; language detection only samples the first 500 characters.

### Fixed
- **Provider ordering used an invalid sort predicate** (undefined behaviour in Swift's `sort`) — replaced with a stable reorder.
- **Truncated cloud responses were inserted silently.** OpenAI, Mistral, Scaleway, Groq and Gemini now detect `finish_reason`/`MAX_TOKENS` and surface a truncation instead of pasting a cut-off rewrite (previously only Anthropic and MLX did). Gemini no longer crashes on a SAFETY-blocked response.
- **Mach port leak** in the Input-Monitoring permission probe (one leaked per check, run up to 10× at startup).
- **Two separate audio recorders** (dictation hotkey vs. popup mic) could collide on the same hardware/temp file — now a single shared recorder.
- **Cancelling a dictation left whisper-cli running** (CPU/Metal) until it finished; cancellation now reliably terminates it and a cancel-before-launch can't spawn an orphan.
- **Temp recording WAVs could be orphaned** on certain exit paths; the recorder now clears its URL after handoff and stale recordings are swept at launch.
- **MLX** no longer inserts a thinking model's raw reasoning text as the result, and warns when an already-running server on the port serves a different model than configured.
- **Whisper model deletion** during an active download no longer races the download writing the file back.
- Removed dead code and a deprecated `activate(ignoringOtherApps:)` call; replaced the brittle `objc_setAssociatedObject` download-progress retainer with a real property; hardened Accessibility type casts. The four OpenAI-compatible providers were de-duplicated into a shared request path (~200 LOC removed).
- Removed an emoji from a UI status string (pictogram/text policy).

## [1.11.1] — 2026-06-12

### Fixed
- **Built-in and custom prompts no longer answer your selected text instead of processing it.** Whenever the text you selected looked like a message addressed to the model — a greeting, a question, a request — small local models in particular would drop the prompt's actual instructions and just reply to it. "Hello, how are you?" + Translate → DE returned "Hallo! Ich bin okay, danke. Und du?" instead of the translation; "Hey team, kannst du das kurz lesen?" + Shorten returned "Klar, gerne!" instead of a shortened version. The fix is structural: every prompt sent through Tippi (built-in + custom prompts you create in Settings) is now prefixed with a universal role-boundary preamble that tells the model the user's message is INPUT to be operated on, never a conversation turn directed at it. The three translation prompts additionally carry worked examples per language (greeting / question / exclamation) so they handle these edge cases cleanly.
- **Insertion in non-AppKit apps now works without manual ⌘V.** Triggering a transformation while text was selected in VS Code, Cursor, Chrome, Slack, Discord, Figma or any other Electron / Chromium / web-based app would either silently drop the result or only stage it on the clipboard, forcing you to paste by hand. Both the picker popup AND the preview window explicitly activated Tippi when they appeared, which stole focus and collapsed the source app's selection; by the time you confirmed an action there was nothing left to replace, so every fallback path was broken.
  - Both the picker popup and the preview window are now true non-activating panels. Tippi never becomes the frontmost app during the prompt-selection or AI-result-preview flow — the source app stays active and its selection stays intact, so AX-based replacement and clipboard-paste fallback both have something to write into when you click **Einfügen** / Replace.
  - When Accessibility text writes are silently discarded by an app (Electron's typical behaviour), Tippi now activates the source app and synthesises ⌘V instead of just putting the result on the clipboard. The text lands where it should without any extra keystroke.
  - The no-op detection inside `replaceViaElement` and `setSelectedText` was extended to cover apps that don't expose `kAXValueAttribute` at all; previously those returned a false-positive "replaced" and the user saw nothing happen.

## [1.11.0] — 2026-06-10

### Added
- **Parakeet v3 speech engine (beta) for dictation.** Settings → Voice → **Speech engine** now offers a second, fully-local transcription engine alongside Whisper: NVIDIA's Parakeet TDT 0.6B v3, running on the Apple Neural Engine via [FluidAudio](https://github.com/FluidInference/FluidAudio) (CoreML). In our testing it transcribes German roughly **7× faster** than Whisper small with **about half the word-error rate** (FLEURS: 5.0 % vs 10.2 %), and — unlike Whisper — it does not hallucinate phrases during silence. It supports 25 European languages.
  - **Whisper remains the default.** Parakeet is opt-in. Its ~600 MB CoreML model downloads from Hugging Face on first use; the engine section shows a live status row (not downloaded / downloading with progress / ready) and a **Download now** button so the download never surprises you mid-dictation. Once loaded, the model stays in memory for the app's lifetime, so there is no per-dictation cold start.
  - Picking Parakeet no longer requires a Whisper model to be installed.
  - The toast after each dictation now names the engine that transcribed.
  - Licenses: FluidAudio is Apache 2.0; the Parakeet model is CC-BY-4.0 (© NVIDIA). FluidAudio links statically and the model is fetched at runtime — nothing model-related is bundled. See `NOTICES.md` and the About tab.

### Changed
- The Voice help section documents the engine switch, the model-download status, cancelling a dictation in progress, and the polish timeout.

This release also carries forward everything in 1.10.3 (16 review fixes + the faster Whisper pipeline) for anyone updating from 1.10.2 or earlier.

## [1.10.3] — 2026-06-10

Hardening release: 16 fixes from a full code review of the Core/App, LLM, UI, and Voice layers, plus a faster dictation pipeline. No new features.

### Fixed — privacy & data loss
- **Local-provider timeouts no longer fall through to the cloud.** When Ollama/MLX timed out (easy with large non-streaming models), the router treated the provider as "unavailable" and silently retried with the next configured provider — which could be OpenAI. Text the user deliberately routed to a local model never leaves the Mac on a timeout anymore; the error is surfaced instead. The Ollama request timeout was also raised 20 s → 120 s to accommodate cold model loads.
- **Voice recordings no longer linger in the temp directory.** The dictation WAV cleanup only ran after a successful transcription; any failure (missing binary/model, whisper-cli error, timeout) left the recording on disk. Cleanup now runs on every exit path.
- **Truncated AI answers are never inserted.** Anthropic (max_tokens 2048 → 8192) and MLX (cap 768 → 2048) responses now check `stop_reason`/`finish_reason`; a cut-off rewrite throws a clear error instead of silently destroying the tail of the selection.
- **Clipboard managers no longer archive Tippi's paste roundtrips.** The transient pasteboard writes used for inserting results now carry the `org.nspasteboard.ConcealedType` marker respected by Maccy, Paste, Alfred & co.
- **History CSV export neutralizes spreadsheet formula injection** (`=`, `+`, `-`, `@` field prefixes).

### Fixed — crashes & hangs
- **Settings hotkey recorder crash (SIGSEGV).** Stopping a recording and then clicking any recorder again called `NSEvent.removeMonitor` twice on the same token (over-release). The cleanup hook now holds the token itself with identity-checked, idempotent removal. This was the cause of the crash logs from 2026-06-03 and 2026-06-10.
- **Dictation can be cancelled.** Pressing the dictation hotkey while "Transcribing…" is shown cancels the in-flight pipeline (toast: "Dictation cancelled"). Previously the press was silently ignored.
- **The AI polish step is capped at 30 seconds.** A slow polish provider (e.g. a large local model cold-starting) could hold "Transcribing…" for minutes; past the cap the raw transcript is inserted.
- **whisper-cli gets SIGKILL if it ignores SIGTERM** — a hung Metal call can no longer leave dictation stuck in "Transcribing…" forever.
- **An unresponsive target app can no longer freeze Tippi.** Accessibility calls are capped process-wide at 2 s.
- **The ⌘, Settings scene no longer crashes** on the Hotkeys tab (missing GlobalKeyMonitor environment object).
- **The MLX server is stopped on app quit** — it used to outlive Tippi, holding the model in RAM and blocking its port.

### Fixed — reliability
- **Whisper model downloads no longer race the temp file.** The URLSession download is staged synchronously before the async hop; intermittent "file doesn't exist" failures are gone. Cancelling a download no longer reports a spurious error, and deleting the active model now falls back to auto-detecting other installed models.
- **Double-press at dictation start fixed** — a second hotkey press while the mic-permission prompt was open started a second recording on the same recorder.
- **Gemini no longer crashes on a malformed model name** (free-form settings field is now percent-encoded instead of force-unwrapped).
- **`make build` dev builds now bundle whisper-cli** — dictation in locally built (non-DMG) installs silently did nothing because the binary was only injected by the release pipeline.

### Changed
- **Dictation transcribes ~15 % faster:** whisper-cli now runs with `--flash-attn` (mathematically exact — output verified identical). The Whisper model file is additionally pre-warmed into the OS cache while you are still speaking, hiding the multi-second cold load on the first dictation after launch.

All notable changes to Tippi will be documented in this file.

## [1.10.2] — 2026-06-03

### Fixed
- **App froze for 2–5 s on every hotkey press.** Tippi registers three redundant trigger paths by design — a Carbon main hotkey (id 1), a Carbon safety hotkey (id 99, hardcoded ⌃⌥⌘T for "always works without Input Monitoring"), and an `NSEvent` global+local monitor. When the user-configured combo coincides with the safety, or when the same combo is reachable through several paths, a single keystroke dispatched several async `handleTriggered` calls in parallel. The existing `popupController.isOpen` guard didn't help, because all racing callers reached it before any of them had actually opened the popup. The competing calls then collided on the Accessibility selection-capture and the popup-open phase, and the UI stalled until the losers gave up. Tippi now sets a synchronous in-flight flag on `@MainActor` before any `await`, with a `defer` that releases it on every return path. A future repro can be diagnosed straight from Console.app — the ignore branch logs `in-flight=…`, `popup=…`, `preview=…`.

## [1.10.1] — 2026-06-03

### Fixed
- **Hotkey recorder swallowed keystrokes after switching settings tabs.** SwiftUI's `TabView` mounts every tab eagerly. If you had ever opened the recorder in one tab (e.g. **Hotkeys**) and then moved to another (e.g. **Voice** → Dictation), the first recorder's `NSEvent.addLocalMonitor` was still installed and — because monitors dispatch LIFO — silently consumed the keystroke you meant for the second recorder. The visible field stayed in "press now" forever. New behavior: starting a recording forces any previously-started recorder to release its monitor first, so only the recorder you actually clicked is listening.
- **Recording a dictation hotkey no longer overwrites your prompt hotkey.** The recorder used to hardcode `KeyComboStore.save(combo)` — the prompt-hotkey store — regardless of which combo binding it was attached to. Setting a new dictation combo in **Voice** therefore wiped out the prompt-hotkey in `tippi.hotkeyCombo.v1` as a side-effect (the dictation store got written via the parent's `.onChange`, so the dictation combo itself was correct, but the prompt combo silently followed it). The recorder no longer touches any store; persistence is fully delegated to the parent view's `.onChange` handler, where it already happened.

## [1.10.0] — 2026-06-02

### Added
- **Defuse mode** (23. built-in prompt) — turns an emotionally written or spoken message into a calm, respectful, and solution-oriented version. Removes insults, threats, sarcasm, and unnecessary escalation while preserving facts, urgency, and the actual goal. Symbol: `flame.fill`. Title: "Defuse" / "Dampf ablassen". Lives in the Communication group of the cursor popup. System prompt adapted from `cmagnussen/blitztext-app` (MIT) — see `NOTICES.md` for attribution.
- **Add emojis mode** (24. built-in prompt) — places fitting emojis throughout the text at medium density (roughly every 1–2 sentences), preserves style and meaning, fixes obvious typos. Symbol: `face.smiling`. Title: "Add emojis" / "Emojis einfügen". Lives in the Tone & style group. System prompt adapted from `cmagnussen/blitztext-app` (MIT, medium-density variant) — see `NOTICES.md` for attribution. Users wanting lighter/heavier emoji density can copy this as a Custom prompt and adjust the wording.

### Technical
- New top-level `NOTICES.md` documenting third-party prompt adoptions (MIT-licensed work from cmagnussen/blitztext-app).

## [1.9.0] — 2026-06-01

### Added
- **Encrypted local History (opt-in)** — every AI transformation can now be logged to a local SQLite database, with the `input` and `output` fields encrypted at rest using AES-GCM (CryptoKit). The 256-bit key is generated lazily on first use and lives in your macOS Keychain (`com.tippi.app` / `history.encryption.key`, `WhenUnlockedThisDeviceOnly`, **no iCloud sync**). Default OFF — Tippi writes nothing to disk until you toggle it on.
- **Settings → History tab** — turn recording on/off, browse the 200 most recent entries (newest first), open any entry in a side-by-side input/output detail sheet, delete individual rows from a context menu, or wipe the whole store with a confirmation dialog.
- **JSON + CSV export** — full decrypted dump from the History tab via standard `NSSavePanel`. Files are named `tippi-history-YYYY-MM-DD-HHMMSS.{json,csv}`. CSV escaping is RFC 4180-compliant (fields with commas, quotes, or newlines are double-quoted).
- **In-app Help section for History** (EN + DE) — explains the opt-in design, where the key lives, and how to wipe or export.

### Changed
- **Privacy claim updated**: "No request history saved" is no longer correct now that opt-in history exists. The README and About tab now say "No request history by default — opt-in encrypted local History (AES-GCM, Keychain key, no cloud)".
- **`CompletionResult` exposes `providerID` and `model` separately** in addition to `providerDisplay`, so callers (PreviewView, DictationController) can log structured metadata to History without parsing the human-readable display string.

### Technical
- **GRDB 7.x added as SPM dependency** (`groue/GRDB.swift`, `from: 7.0.0`) for the SQLite layer. System SQLite is used — **not SQLCipher**, because GRDB+SQLCipher SPM integration would require either CocoaPods, a GRDB fork, or manual `xcframework` linking. Field-level CryptoKit encryption gives the same effective security for Tippi's threat model (Keychain is the single point of failure either way), keeps the build pipeline clean, and adds zero non-Apple crypto code.

## [1.8.2] — 2026-05-24

### Added
- **In-app Help: new "Links & resources" section** listing every Tippi resource in one place — GitHub repository, landing page (miwixyz.github.io/Tippi/), one-pager (docs/ONE-PAGER.md), changelog, and latest release with DMG download. All entries render as clickable Markdown links.
- **About tab now exposes three links** — GitHub · Landing page · One-pager (was: GitHub only).

### Changed
- **Voice Help section expanded** to cover the v1.8.0 dictation polish (opt-in LLM smoothing, polish-provider override, skip-short heuristic, graceful fallback) and the v1.8.1 menubar dictation-language quick switcher. Previously these features only existed in the CHANGELOG and the Settings UI — now they're discoverable from the in-app Help where users actually look.
- **Help bodies are now rendered as inline Markdown** via `AttributedString`. URLs formatted as `[label](url)` are clickable; plain text remains selectable. Falls back to verbatim text on parse failure — no crashes if a localization slip introduces malformed Markdown.

## [1.8.1] — 2026-05-24

### Added
- **Menubar quick switcher for the dictation language**: a new "Dictation Language" submenu in Tippi's menubar lets you change Whisper's source language (Auto / Deutsch / English / Español / Français / 日本語) in one click — no more opening Settings just to switch between German calls during the day and Spanish calls in the evening. The active language is checkmarked; the picker in Settings → Voice → Language continues to work and stays in sync.

## [1.8.0] — 2026-05-24

### Added
- **Dictation polish** (opt-in): after Whisper transcribes your dictation, Tippi can send the raw text through an LLM provider to remove filler words ("um", "uh", "äh", "ähm", "halt", "also"), add punctuation, and fix obvious self-corrections — then insert the polished text at your cursor. Toggle in **Settings → Voice → Dictation Mode → "Polish transcript with AI"**. Default OFF. The polishing prompt is fully editable and language-agnostic (keeps your source language).
- **Polish-provider override**: pick a separate provider + model just for the polish step (e.g. Groq for dictation, OpenAI for everything else). Default "use active provider"; switching to Groq + Llama 3.1 8B Instant typically takes polish latency from 2–5 s down to well under 1 s — Pismo-class speed.
- **Groq provider** (new): OpenAI-compatible chat completions on Groq's LPU hardware. Llama 3.1 8B Instant (~800 tok/s) and Llama 3.3 70B Versatile (~270 tok/s) preset out of the box. Free tier available at console.groq.com.
- **Scaleway provider** (new, **EU-hosted Paris**): OpenAI-compatible chat completions on Scaleway's Generative APIs. Llama 3.1 8B Instruct (~300 tok/s), Llama 3.3 70B Instruct (~250 tok/s) and Mistral Nemo 12B preset out of the box. Combines Groq-class speed with GDPR/DSGVO compliance — the right default for German-language dictation polish that must not leave the EU. Free tier ~1M tokens/month at console.scaleway.com.
- **Curated model picker**: every hosted provider (OpenAI / Anthropic / Gemini / Mistral / Groq) now offers a dropdown of current, suitable models with a fastest/balanced/premium label, plus a "Custom…" option for IDs Tippi doesn't ship yet. Deprecated IDs (gpt-3.5, claude-3, gemini-1.5) removed.
- **Graceful fallback**: if the LLM call fails (no API key, network error, empty response) the raw Whisper transcript is inserted instead — dictation never breaks because of LLM trouble.
- **Skip-short heuristic**: utterances shorter than 20 characters ("ja", "ok", "danke") bypass the polish step entirely, so single-word dictations stay instant.

### Changed
- **OpenAI default model is now `gpt-4o-mini`** (was `gpt-5-mini`). The gpt-5 reasoning family adds thinking-token latency that's wrong for Tippi's "fix this short text, return the result" UX. Users who want reasoning can still pick gpt-5/gpt-5-nano/gpt-5-mini from the model dropdown.

### Fixed
- **OpenAI reasoning-family models (gpt-5*, o1*, o3*, o4*) no longer fail with `400 Unsupported value: 'temperature' does not support 0.3 with this model`.** Tippi previously hardcoded `temperature=0.3` for every OpenAI call; reasoning models only accept the default value. The `temperature` field is now omitted for those models and kept at 0.3 for gpt-4o*, gpt-4*, gpt-3.5*. Affected every Tippi feature using the OpenAI provider — not just the new dictation polish.

## [1.7.3] — 2026-05-22

### Changed
- **Transforming a selection in apps that ignore Accessibility writes** (Electron/Chromium: Obsidian, Claude, ChatGPT, Slack, VS Code) no longer appends the result next to the original. Tippi detects the ignored write, copies the result to the clipboard, and shows a "Copied — press ⌘V to insert" toast — so nothing unexpected is written into the document. Native apps still replace in place; dictation still inserts at the cursor everywhere.

## [1.7.2] — 2026-05-22

### Fixed
- **Double paste in Electron/Chromium apps** (Obsidian, Claude, ChatGPT, Slack, VS Code): the synthetic ⌘V was posted to two event taps, so those apps pasted the text twice. Dictation and the clipboard fallback now post a single ⌘V. **Dictation now works correctly in Electron apps.**
- **Stale clipboard mistaken for the selection**: when a synthetic ⌘C produced no copy (nothing selected, or the app ignored it), capture returned whatever happened to be on the clipboard. Capture now checks the clipboard change-count and discards a no-op copy instead of handing back unrelated content.
- **AX writes that report success but do nothing** (Electron/Chromium ignore them): insertion now verifies the element value actually changed and falls back to the clipboard path instead of silently failing.

### Known limitation
- Transforming and **replacing selected text in Electron/Chromium apps is not reliable** — those editors drop the live selection the moment the action picker appears and ignore Accessibility text writes, so the result is appended rather than replacing. Dictation (insert at cursor) and replacing in native apps (Mail, Notes, TextEdit, Pages, Word) work as expected.

## [1.7.1] — 2026-05-22

### Fixed
- **Voice Instruction answered the text instead of transforming it**: the spoken instruction is now wrapped in a hardened system prompt that treats the selected text strictly as content to transform and never answers or replies to a question contained in it.
- **"Replace" appended instead of replacing in the AI preview**: the preview's Replace/Append now reuse the selection range captured at trigger time and replace via the Accessibility API (the same fix already applied to local quick actions in 1.6), instead of falling back to a clipboard paste after the preview window stole focus and collapsed the selection.

## [1.7.0] — 2026-05-22

### Added
- **Dictation mode**: a dedicated hot key (default **⌃⌥⌘M**) starts recording, pressing it again stops recording, transcribes locally via Whisper, and inserts the text at the cursor — no popup, no text selection required.
- **Recording indicator**: a floating, non-activating indicator shows "Recording…" (pulsing) and "Transcribing…" status at the bottom of the active screen during dictation.
- **Dictation settings** (Settings → Voice): enable toggle plus a configurable hot key, gated on a downloaded Whisper model.

### Fixed
- **Carbon hot keys now check their `EventHotKeyID`**: handlers previously fired for every hot-key event, which would have caused the new dictation key and the main trigger to cross-fire. Each handler now reacts only to its own id (main = 1, dictation = 2, safety = 99).

## [1.6.0] — 2026-05-22

### Added
- **PopClip-style local quick actions** in the Tippi popup for selected text: Bold, Italic, Underline, Strikethrough, Uppercase, Lowercase, Capitalize Words, Underscore, Hyphenate, Brackets, Join Lines, Character Count, and Word Count.
- **Rich-text formatting path** for Bold/Italic/Underline/Strikethrough using RTF pasteboard data, with Markdown/plain-text fallback for apps that do not accept rich text.
- **Quick action counts** show character and word counts inline without changing the selected text.
- **Settings toggle** (Settings → General) to show or hide local quick actions.
- **Help tab section** (EN + DE) explaining local quick actions, permissions, and troubleshooting.

### Changed
- **Default modifier hotkey** for legacy `HotkeyManager` is now **⌥⌘T combo mode** instead of double-tap Option, so the documented shortcut works without Input Monitoring.
- **Text capture order**: clipboard `⌘C` runs before activating the source app, while the front app still owns the selection (immediately after hotkey).
- **Text insertion** targets the source app via Accessibility tree search, then falls back to dual-tap `⌘V` paste.

### Fixed
- **“No text captured”** when selection was visible: capture no longer waits on mic permission before reading text; pasteboard detection accepts identical clipboard content after copy; System Events + full window AX tree for TextEdit and similar apps.
- **Greyed-out / no-op quick actions**: popup closes before paste; selection is re-captured after closing the popup when the initial capture failed; paste runs synchronously in the action handler.
- **Popup showed quick actions without working text**: orange hint when capture failed; buttons stay clickable and retry capture on tap.
- **Local quick actions appended instead of replacing on macOS 26**: the popup steals focus and collapses the source app's selection, so the clipboard `⌘V` fallback pasted after the original text. The focused element and selection range are now captured at trigger time (selection still live) and the result is re-selected and replaced via the Accessibility API — works cross-app without bringing the source app to front.
- **Accessibility permission lost on every rebuild**: `make build` now signs with the Developer ID certificate instead of ad-hoc, giving a stable TCC identity (Team ID + bundle ID) so the granted Accessibility permission persists across local builds instead of resetting with each new code hash.

## [1.5.7] — 2026-05-22

### Changed
- **Local MLX speed optimized**: the default local MLX model is now Llama 3.2 3B Fast/Balanced instead of the slower 8B quality preset.
- **Local generation budget capped dynamically** so MLX transformations avoid slow runaway completions while still allowing longer rewrites when the selected text is longer.
- **Local provider timeouts tightened** for faster fallback when Ollama or a running local model does not respond.

### Added
- **Preview latency badge** now shows how long the AI generation took, making local model speed visible while testing presets.
- **MLX Help and README guidance** now explain the Fast/Balanced default and when to choose larger quality presets.

## [1.5.6] — 2026-05-22

### Fixed
- **Local build output path**: `make build` now stops a running local Tippi, writes to `build/Build/Products/Release`, and ad-hoc signs the app so Sparkle loads correctly during local testing.
- **Sparkle version ordering** fixed for local builds: `CURRENT_PROJECT_VERSION` is now higher than the public `1.5.6` appcast build, so update checks no longer offer an older public release over a newer local build.
- **Runtime safety hardening** for text capture, pasteback, voice recording, local provider fallback, MLX server detection, and release publishing.
- **Voice recording cleanup** now stops recordings when the popup closes and prevents `whisper-cli` subprocess hangs with cancellation, stderr draining, and timeout handling.
- **Local provider fallback** now skips unavailable Ollama/MLX providers instead of blocking the local demo fallback.
- **Release pipeline** now derives the default version from `project.yml`, parses notarization JSON robustly, fails closed on GitHub release upload errors, and avoids fragile `head` pipes in signing checks.
- **Release version drift protection** now fails the release if `release.env VERSION` does not match `project.yml` `MARKETING_VERSION`.
- **Localization drift** fixed for the English update-menu label and duplicate Voice model title.

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
