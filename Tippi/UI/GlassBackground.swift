import SwiftUI

/// One place that decides how Tippi's floating surfaces are filled.
///
/// On macOS 26 and later this is Liquid Glass (`glassEffect`); below it, the
/// `.regularMaterial` these views used before. Tippi's deployment target is
/// macOS 15, so the old path is not dead code — it is what most installs still
/// render, and it must keep looking exactly as it did.
///
/// Scope follows Apple's HIG: Liquid Glass belongs in the functional layer —
/// controls, navigation, transient UI. Every call site here is a floating panel,
/// popup, toast or indicator. Nothing in the content layer uses it.
struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26+, `.regularMaterial` below — clipped to `shape`.
    ///
    /// Replaces `.background(.regularMaterial, in: shape)` one-for-one, so the
    /// pre-26 rendering is unchanged by construction.
    func tippiGlass<S: Shape>(in shape: S) -> some View {
        modifier(GlassBackground(shape: shape))
    }

    /// Variant for panels whose window already defines the outer shape.
    func tippiGlass() -> some View {
        modifier(GlassBackground(shape: Rectangle()))
    }
}
