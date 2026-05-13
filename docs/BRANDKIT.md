# Tippi Brand Kit

## Logo

The Tippi wordmark uses the system font (SF Pro Display, bold) — no custom typeface. The icon is a robot mascot rendered in CoreGraphics: dark navy circle, white bot face, Signal Blue speech bubble.

## Color Palette

| Name | Hex | Role |
|------|-----|------|
| **Signal Blue** | `#3B8CFF` | Primary accent — buttons, links, selection highlights, icon tints |
| **Tippi Navy** | `#10192B` | Brand ink — logo background, dark header surfaces, deep contrast |
| **Bubble Cream** | `#FFF8EE` | Warm light surface — welcome screens, onboarding cards (light mode) |
| **Soft White** | `#F7F2EA` | Secondary light surface — settings panels, general backgrounds (light mode) |
| **Mist Blue** | `#EAF3FF` | Suggestion column tint, preview accent surfaces (light mode) |

### Adaptive Color Mapping

| Asset Name | Light Mode | Dark Mode |
|------------|------------|-----------|
| `AccentColor` | Signal Blue `#3B8CFF` | Signal Blue `#3B8CFF` |
| `BrandNavy` | `#10192B` | `#10192B` |
| `BrandSurface` | Soft White `#F7F2EA` | Dark Navy `#1C2333` |
| `BrandMistBlue` | Mist Blue `#EAF3FF` | Deep Navy-Blue `#1E2D4A` |

### Usage in Code

```swift
// AccentColor drives all .tint / .accentColor / .borderedProminent throughout the app
// Supporting palette via TippiColors.swift:

Color.tippiNavy   // #10192B — dark ink, logo bg
Color.tippiSurface // adaptive surface
Color.tippiMist    // adaptive suggestion column tint
```

## Typography

- **UI font**: SF Pro (system default via SwiftUI `.font(...)`)
- **Headlines**: `.headline` / `.title` weight `.bold`
- **Body**: `.body` / `.callout`
- **Captions**: `.caption` / `.caption2` for metadata, badges, hints

## Iconography

SF Symbols throughout — consistent with macOS HIG. Primary app icon: `pencil.and.outline`.

Key icon mappings:

| Action | Symbol |
|--------|--------|
| App icon / header | `pencil.and.outline` |
| Improve | `sparkles` |
| Fix Grammar | `checkmark.circle` |
| Translate | `globe` |
| Shorten | `arrow.down.right.and.arrow.up.left` |
| Lengthen | `arrow.up.left.and.arrow.down.right` |
| Voice | `mic.fill` / `mic` |
| Settings | `gear` |
| Providers | `key` |
| Privacy | `lock.shield` |

## Motion

- Transitions: SwiftUI defaults (`.easeInOut`, `0.2s`)
- Voice waveform: `.easeInOut(duration: 0.1)` per bar
- No decorative animations — functional feedback only

## Voice of Brand

**Tone**: Precise, calm, slightly playful. Never sales-y.
**Tagline**: *Mark text anywhere. Hit ⌥⌘T. Let AI do the rest.*
**Positioning**: Privacy-first system-wide AI writing assistant. BYOK, no telemetry, open source.
