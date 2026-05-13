import SwiftUI

// MARK: - Tippi Brand Colors
//
// Signal Blue (#3B8CFF) is the app accent color — driven by AccentColor in Assets.xcassets.
// It is available via Color.accentColor / .tint everywhere in the app automatically.
//
// The extensions below expose the supporting brand palette.

extension Color {
    /// Tippi Navy (#10192B) — deep brand ink, used for the app icon / logo circle background.
    static let tippiNavy = Color("BrandNavy")

    /// Adaptive surface — Soft White (#F7F2EA) in light mode, dark navy in dark mode.
    static let tippiSurface = Color("BrandSurface")

    /// Adaptive mist — Mist Blue (#EAF3FF) in light mode, deep navy-blue in dark mode.
    /// Used as the suggestion column background tint in the preview window.
    static let tippiMist = Color("BrandMistBlue")
}
