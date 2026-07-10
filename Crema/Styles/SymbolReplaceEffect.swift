import SwiftUI

/// The native macOS symbol-replace on a dynamic glyph swap: the old symbol
/// scales out as the new one scales in, the system HUD/media feel. Shared by
/// every HUD icon (volume/brightness stepping across its glyph family) and the
/// transport play/pause glyph — one home for the three-modifier stack, per-style
/// size and color staying at each call site.
///
/// Scoped to the symbol name: the `.animation` keys on `symbolName` and rides
/// only the glyph it is attached to, so the swap animates without reaching the
/// level fill/bar beside or beneath it (that keeps its own value-keyed spring in
/// HUDLevelSlider — the only level animator). Under Reduce Motion the swap
/// carries no animation and lands dry, the accessibility fallback that matches
/// today's behavior.
struct SymbolReplaceEffect: ViewModifier {
    let symbolName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(.symbolEffect(.replace))
            // The replace only animates inside an animated transaction; this
            // supplies one keyed on the symbol name alone. A rapid burst across
            // glyph boundaries retargets the in-flight replace to the newest
            // symbol (SwiftUI does not stack content transitions), so the icon
            // chases the latest state the way the native HUD settles — no debounce
            // needed.
            .animation(reduceMotion ? nil : .default, value: symbolName)
    }
}

extension View {
    /// Applies `SymbolReplaceEffect` keyed on the current glyph name.
    func symbolReplace(on symbolName: String) -> some View {
        modifier(SymbolReplaceEffect(symbolName: symbolName))
    }
}
