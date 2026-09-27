import SwiftUI

// MARK: - Tippi Brand Colors
//
// Brand Blue (#3070F0) is the app accent color — driven by AccentColor in Assets.xcassets.
// It is available via Color.accentColor / .tint everywhere in the app automatically.
//
// The extensions below expose the supporting brand palette.

extension Color {

    /// Adaptive mist — Mist Blue (#EAF3FF) in light mode, deep navy-blue in dark mode.
    /// Used as the suggestion column background tint in the preview window.
    static let tippiMist = Color("BrandMistBlue")
}
