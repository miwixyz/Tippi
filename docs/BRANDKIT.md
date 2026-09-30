# Tippi Brand Kit

Since v2.20 Tippi uses the design of the app family (Tippi, Kalli, TippAI, Qotti),
palette "Schiefer" (slate). **Source of truth for every value below:**
`Tippi/UI/FamilyTheme.swift` (`FamilyTheme.app = .tippi`, set in `AppDelegate.swift`).
The website mirrors the same tokens as CSS variables in `docs/style.css`. Change a value
in FamilyTheme first, then in `style.css` and here. Anything else is drift.

## Logo

The mascot (`docs/mascot.png`, 1254 px; `mascot-224.png` for the web, `apple-touch-icon.png`
180 px) and the wordmark "Tippi" in Plus Jakarta Sans SemiBold. Favicon: white I-beam on the
Tippi accent `#3E5998` (6.8:1).

## Colors

| Token (Swift / CSS) | Light | Dark | Role |
|---|---|---|---|
| `accent` / `--accent` | `#3E5998` | `#98AEE1` | Links, icons, focus ring, active state |
| `accentFill` / `--accent-fill` | `#3E5998` | `#5172BD` | Filled buttons and capsules with **white** text |
| (web only) `--accent-fill-hover` | `#354D83` | `#4662A3` | Hover of the above (accentFill 86 % + black) |
| `backgroundTop/Middle/Bottom` | `#F3F5F9` `#E7E9F1` `#D9DDE8` | `#0D1019` `#161A25` `#1F2433` | Page gradient, top to bottom, solid |
| `card` / `--card` | `#FFFFFF` | `#1B2130` | Content cards, never transparent |
| `cardStroke` / `--card-stroke` | `#E2E5EE` | `#2A3142` | Card border |
| `textPrimary` / `--text` | `#1E2433` | `#ECEFF6` | Text |
| `textSecondary` / `--text-2` | `#56607E` | `#A3ACC8` | Secondary text |
| `glassTint` / `--glass-tint` | `#F3F5F9` 78 % | `#161A25` 78 % | Tint under glass. On the web only the sticky nav is glass |

The app asset `AccentColor` carries the same pair (`#3E5998` / `#98AEE1`).

Contrast (WCAG 2.1, computed 2026-09-30): white on `accentFill` 6.8:1 light, 4.7:1 dark ·
accent on card 6.8:1 / 7.3:1 · secondary text on card 6.2:1 / 7.1:1, on the lightest
gradient end `#D9DDE8` 4.6:1. All AA.

Rules from the family design system: one accent per app, no second accent color, no
purple/blue "glow" gradients, glass only for floating elements, color never the only signal.

## Typography

**Plus Jakarta Sans** (SIL Open Font License 1.1). App: bundled TTF, registered via
`FamilyTheme.registerFonts()`. Website: self-hosted WOFF2 in `docs/fonts/` with `OFL.txt`,
no external font server. Weights: Regular and Medium for text, SemiBold (600) at most, only
for titles. Light for large figures.

## Shapes

Radius 28 for cards, 20 for tiles, 14 for fields. Buttons as circle or capsule. Soft shadow
only under cards.

## Iconography

App: SF Symbols. Website: inline SVG line icons, `stroke="currentColor"`, stroke width 2,
`aria-hidden="true"`. No emojis as icons or decoration. Emojis that show product behaviour
(`:daumen:` → 👍) are content, not decoration.

## Motion

Functional feedback only, no decorative animation. The website respects
`prefers-reduced-motion`.

## Voice of Brand

**Tone**: precise, calm, slightly playful. Never sales-y.
**Tagline**: *Mark text anywhere. Hit ⌥⌘T. Let AI do the rest.*
**Positioning**: one app instead of eight. AI writing at the cursor in every app, plus the
small helpers (emoji, snippets, selection bar, dictation, translation, notes, screen text,
text tools). BYOK, no telemetry, open source.
