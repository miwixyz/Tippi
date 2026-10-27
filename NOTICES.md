# Third-party notices

Tippi is released under the MIT License. This file lists external sources whose
code, prompts, or design ideas have been adapted into Tippi. Each entry stays
under its original license; downstream redistribution must preserve these
notices.

## FluidAudio — Parakeet speech-to-text engine (optional)

Tippi's optional "Parakeet v3" dictation engine is built on FluidAudio and the
NVIDIA Parakeet TDT model, both downloaded/loaded at runtime. Neither is bundled
in the app; the Swift package is linked as a dependency and the CoreML model is
fetched from Hugging Face on first use.

- **FluidAudio** — Swift SDK (CoreML/ANE inference)
  - Source: https://github.com/FluidInference/FluidAudio
  - License: **Apache License 2.0**
- **NVIDIA Parakeet TDT 0.6B v3** — multilingual ASR model
  - Source: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
  - CoreML conversion: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml
  - License: **CC-BY-4.0** — © NVIDIA. Use of the model is governed by the
    CC-BY-4.0 license; commercial use is permitted with attribution.
- **Parakeet Ultra** — Moondream's post-training of NVIDIA Parakeet TDT 0.6B v3
  (same architecture and languages), selectable as "Parakeet Ultra" under
  Settings → Voice → Parakeet model; downloaded only when chosen
  - Source: https://huggingface.co/moondream/parakeet-ultra
  - CoreML conversion: https://huggingface.co/FluidInference/parakeet-ultra-coreml
  - License: **CC-BY-4.0** — © Moondream, derived from NVIDIA Parakeet TDT
    0.6B v3 (© NVIDIA, CC-BY-4.0). Commercial use is permitted with attribution;
    this notice is that attribution.

The default dictation engine remains whisper.cpp (bundled). Parakeet is opt-in
under Settings → Voice → Speech engine.

## Unicode CLDR + emoji-test.txt — emoji names and search keywords

Tippi's emoji picker and `:name:` shortcodes ship a generated database
(`Tippi/Resources/emoji-data.json`, ~282 KB) built from two Unicode sources.
Unlike the entries above, this data **is bundled** in the app.

- **emoji-test.txt** — the canonical list of emoji and their ordering
  - Source: https://unicode.org/Public/emoji/16.0/emoji-test.txt
  - Version pinned: **Emoji 16.0**
- **CLDR annotations** — German and English names plus search keywords
  - Source: https://github.com/unicode-org/cldr-json (`cldr-annotations-full`,
    `cldr-annotations-derived-full`)
  - Version pinned: **CLDR 48.2.1**
- **License:** **Unicode License v3** — https://www.unicode.org/license.txt
  Permits redistribution with attribution; this notice is that attribution.

Regenerate with `python3 scripts/generate-emoji-data.py` (verify with
`--check`). Both versions are pinned in that script, so the shipped database
never changes silently underneath a release.

## Yams — YAML parsing (text snippets)

Tippi's text-snippet engine reads Espanso match files (`~/Library/Application
Support/espanso/match/*.yml`) directly, so existing Espanso configurations
work without any conversion step. Yams is linked as a Swift package
dependency for that YAML parsing.

- **Source:** https://github.com/jpsim/Yams
- **License:** MIT

## Blitztext App — "Defuse" and "Add emojis" mode prompts, Apple Intelligence access

- **Source repository:** https://github.com/cmagnussen/blitztext-app
- **Original maintainer:** Christian Magnussen / Blackboat Internet GmbH
- **License:** MIT
- **Adapted prompts:**
  1. The German system prompt for the "Dampf ablassen" workflow
     (`BlitztextMac/Features/Workflows/WorkflowProtocol.swift`,
     `DampfAblassenSettings.systemPrompt`).
  2. The German emoji-density prompt builder for the "Emoji-Text" workflow
     (`BlitztextMac/Services/LLMService.swift`, `buildEmojiSystemPrompt`,
     medium-density variant).
- **Where they live in Tippi:** the `defuse` and `addEmojis` built-in prompts
  in `Tippi/UI/PromptPopup/DemoPrompt.swift`. The wording was translated to
  English, parameterised with `{language}`, and aligned to Tippi's "Return
  ONLY" output convention; the underlying communicative intent and structure
  are preserved.
- **Adapted code (v1.15.1, commit `26022b9`, added 2026-10):**
  1. `BlitztextMac/Services/InsertionFitter.swift` — the rules that fit a
     dictation into the text around the cursor (spacing, sentence-start
     capital, lowercase function word mid-sentence, period before continuing
     text) including the German/English function-word list. In Tippi:
     `Tippi/Core/InsertionFitter.swift`, rules taken over closely; added a
     nil-field entry point (unreadable field → text unchanged) and the
     exclusion of terminals/code editors.
  2. `BlitztextMac/Services/FocusedFieldReader.swift` (`field(pid:bundleID:)`)
     — reading the text before/after the cursor via Accessibility, never from
     password fields. In Tippi: `Tippi/Core/FocusedFieldReader.swift`, with a
     per-element timeout instead of Blitztext's process-wide one and without
     the browser web-tree switch.
  3. `BlitztextMac/App/AppState.swift` (`noteTargetField`, the check before
     pasting) and `FocusedFieldReader.FocusSpot` — the field fingerprint (role
     + position at the end of the recording, compared before inserting, else
     clipboard). In Tippi: `Tippi/Core/FieldFingerprint.swift`,
     `FocusedFieldReader.focusSpot` and `DictationController+Insertion.swift`;
     position relative to the window and an 8 pt tolerance instead of exact
     screen coordinates.
  4. The Apple Intelligence access in
  `BlitztextShared/AI/TextRewriter.swift` — the `SystemLanguageModel`
  availability check with one user-facing sentence per unavailability reason,
  the `LanguageModelSession` call with greedy sampling, and the mapping of
  `GenerationError` cases (context window, guardrails, unsupported language) to
  plain-language messages. Lives in `Tippi/LLM/AppleIntelligenceModel.swift`;
  Tippi adds the macOS 27 `LanguageModelError` mapping, the
  `permissiveContentTransformations` guardrails and English/German strings.
- **Dictation modes (idea only, no code copied):** a hot key that starts
  dictation directly in a mode and runs that mode's prompt on the transcript
  follows Blitztext's workflows (`BlitztextMac/Features/Workflows/`). Tippi's
  implementation (`Tippi/Core/DictationModes.swift`,
  `Tippi/Core/DictationController+Modes.swift`) is its own: the tap-or-hold
  dictation key plus one held modifier picks one of four user-assignable slots.

### MIT License (Blitztext App)

```
MIT License

Copyright (c) 2026 Blitztext contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
