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

The default dictation engine remains whisper.cpp (bundled). Parakeet is opt-in
under Settings → Voice → Speech engine.

## Blitztext App — "Defuse" and "Add emojis" mode prompts

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
