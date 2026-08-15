import GraphCore
import SwiftUI

/// The chrome's palette, as a facade over the current `Theme`.
///
/// Until the redesign, these were literal dark values: the panel sat against
/// §6.1's dark canvas and had to read the same way whatever appearance the system
/// was in. Turn 1 gives the whole screen two directions instead — Observatory on
/// the dark canvas, Ledger on paper — so every one of these is now a lookup into
/// `ThemeStore.shared.theme`.
///
/// It stays a facade rather than being deleted because it is what makes the
/// switch total: every surface in the app already reads its colours from here, so
/// they all follow the appearance without each one growing an environment
/// dependency. The reads happen inside SwiftUI bodies, and `ThemeStore` is
/// `@Observable`, so an appearance change invalidates exactly the views that
/// painted with it.
@MainActor
enum PanelTheme {
    static var theme: Theme { ThemeStore.shared.theme }

    /// The detail column and the rail — the redesign's two chrome surfaces.
    static var background: Color { theme.panelFill.color }
    /// The rule between surfaces.
    static var separator: Color { theme.hairline.color }
    static var rowHighlight: Color { theme.rowHighlight.color }

    static var primaryText: Color { theme.ink.color }
    static var secondaryText: Color { theme.inkMuted.color }
    static var tertiaryText: Color { theme.inkFaint.color }
    static var accent: Color { theme.action.color }
    /// For the one destructive-ish affordance in the app: reporting a miss. Warm,
    /// and taken from outside §4.5's score arc so it can never be read as a
    /// retrievability value (D6.1's rule).
    static var warning: Color { theme.warning.color }

    /// Per-kind accent, used only where a kind is named as a word.
    ///
    /// The redesign drops the coloured chips these were invented for — a node's
    /// kind is now set in the panel's mono meta line ("THEOREM · LANDMARK · id"),
    /// which does not need a hue to be legible. What survives is the grouping:
    /// structural kinds neutral, statements warm, definitions cool, at low enough
    /// chroma that a list of them still looks like one object.
    static func color(for kind: NodeKind) -> Color {
        let dark = theme.isDark
        func tone(_ hue: Double, _ chroma: Double) -> Color {
            ThemeColor.oklch(dark ? 0.82 : 0.48, chroma, hue).color
        }
        switch kind {
        case .branch, .subbranch: return theme.inkMuted.color
        case .definition: return tone(238, 0.070)
        case .axiom: return tone(292, 0.070)
        case .theorem: return tone(78, 0.085)
        case .lemma: return tone(92, 0.075)
        case .proposition: return tone(108, 0.070)
        case .corollary: return tone(126, 0.070)
        case .technique: return tone(162, 0.080)
        case .example: return tone(28, 0.075)
        case .intuition: return tone(316, 0.065)
        }
    }

    /// Qualified: `SwiftUI` exports a `Prominence` of its own.
    static func label(for prominence: GraphCore.Prominence) -> String {
        switch prominence {
        case .detail: "detail"
        case .standard: "standard"
        case .landmark: "landmark"
        }
    }
}
