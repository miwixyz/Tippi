import SwiftUI

// MARK: - Tippi Brand Colors
//
// Ab 2.20.0: Design der App-Familie (Vault „App-Familie Design-System“, Farbwelt
// „Schiefer“). Akzent „Schieferblau“ hell #3E5998, dunkel #98AEE1 — steht in
// AccentColor (Assets.xcassets) und kommt per Color.accentColor / .tint überall an.
// Vorher widersprachen sich drei Angaben: dieser Kommentar (#3070F0), HANDOVER.md
// (#3B8CFF) und das Asset selbst (#083077, gemessen 2026-09-29).
//
// The extensions below expose the supporting brand palette.

extension Color {

    /// Adaptive mist — Schiefer (#E7E9F1) in light mode, #161A25 in dark mode (ab 2.20.0).
    /// Used as the suggestion column background tint in the preview window.
    static let tippiMist = Color("BrandMistBlue")
}
