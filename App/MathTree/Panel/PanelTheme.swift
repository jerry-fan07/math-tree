import GraphCore
import SwiftUI

/// The node panel's palette and metrics.
///
/// Deliberately literal colours rather than semantic ones (`.primary`, `.windowBackground`):
/// the panel sits against the graph view's dark canvas (§6.1) and must read the same way
/// whatever appearance the system is in. Restraint is the brief — one accent, one text ramp,
/// and kind colours desaturated enough that a list of them still looks like one object.
enum PanelTheme {
    static let background = Color(red: 0.055, green: 0.060, blue: 0.072)
    static let separator = Color(white: 1.0, opacity: 0.075)
    static let rowHighlight = Color(white: 1.0, opacity: 0.055)

    static let primaryText = Color(white: 0.92)
    static let secondaryText = Color(white: 0.66)
    static let tertiaryText = Color(white: 0.44)
    static let accent = Color(red: 0.47, green: 0.71, blue: 0.96)
    /// For the one destructive-ish affordance in the app: reporting a miss. Warm,
    /// and taken from outside §4.5's blue→green score arc so it can never be read
    /// as a retrievability value (D6.1's rule).
    static let warning = Color(red: 0.94, green: 0.66, blue: 0.52)

    /// Per-kind accent. Structural kinds are neutral slate so hubs read as scaffolding;
    /// content kinds are grouped by family — statements warm, definitions cool.
    static func color(for kind: NodeKind) -> Color {
        switch kind {
        case .branch: Color(red: 0.66, green: 0.70, blue: 0.78)
        case .subbranch: Color(red: 0.56, green: 0.60, blue: 0.68)
        case .definition: Color(red: 0.45, green: 0.72, blue: 0.88)
        case .axiom: Color(red: 0.66, green: 0.60, blue: 0.88)
        case .theorem: Color(red: 0.91, green: 0.73, blue: 0.44)
        case .lemma: Color(red: 0.84, green: 0.72, blue: 0.50)
        case .proposition: Color(red: 0.79, green: 0.75, blue: 0.53)
        case .corollary: Color(red: 0.72, green: 0.77, blue: 0.58)
        case .technique: Color(red: 0.48, green: 0.78, blue: 0.62)
        case .example: Color(red: 0.88, green: 0.61, blue: 0.60)
        case .intuition: Color(red: 0.73, green: 0.70, blue: 0.91)
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
