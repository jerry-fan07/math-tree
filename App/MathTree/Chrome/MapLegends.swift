import SwiftUI

/// The two legends the design puts along the bottom of the map from mid zoom on.
///
/// They appear exactly when the things they explain do: the hover highlight's
/// prerequisite/dependent rings fade in over the same band (`highlightAlpha` in
/// the renderer), and the score ramp only becomes readable once nodes are big
/// enough to hold a colour. At overview both would be legends for things that are
/// not on screen.

/// What the rings mean: the hover highlight's two directions, and §4.5's frontier.
struct EdgeLegend: View {
    var body: some View {
        let theme = ThemeStore.shared.theme
        HStack(spacing: 20) {
            item(theme) {
                Rectangle().fill(theme.prerequisiteRing.color).frame(width: 16, height: 1.5)
            } label: {
                Text("requires")
            }
            item(theme) {
                Rectangle().fill(theme.dependentRing.color).frame(width: 16, height: 1.5)
            } label: {
                Text("required by")
            }
            item(theme) {
                Circle()
                    .fill(theme.unlearnedFill.color)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle()
                            .strokeBorder(theme.frontierRing.color, lineWidth: 1.3)
                            .frame(width: 11, height: 11)
                    }
                    .frame(width: 11, height: 11)
            } label: {
                Text("ready to learn")
            }
        }
        .font(Typeface.mono(10.5))
        .foregroundStyle(theme.stat.color)
        .allowsHitTesting(false)
    }

    private func item<Mark: View, Label: View>(
        _ theme: Theme, @ViewBuilder mark: () -> Mark, @ViewBuilder label: () -> Label
    ) -> some View {
        HStack(spacing: 7) {
            mark()
            label()
        }
    }
}

/// §4.5's ramp as a strip: unlearned grey at the left edge, then decayed through
/// solid. The one place in the app that shows the encoding rather than using it.
struct ScoreScale: View {
    var body: some View {
        let theme = ThemeStore.shared.theme
        HStack(spacing: 10) {
            Text("decayed")
            LinearGradient(
                stops: gradientStops(theme),
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 180, height: 3)
            Text("solid")
        }
        .font(Typeface.mono(10.5))
        .foregroundStyle(theme.stat.color)
        .allowsHitTesting(false)
        .accessibilityLabel("Colour scale: grey unlearned, then decayed through solid")
    }

    /// Grey holds to 12 % and the ramp starts at 18 %, so the two states read as
    /// two states — the gap is the point (§4.5: a decayed node is *not* an
    /// untouched one).
    private func gradientStops(_ theme: Theme) -> [Gradient.Stop] {
        let stops = theme.scaleStops
        guard stops.count == 4 else { return [] }
        return [
            .init(color: stops[0].color, location: 0),
            .init(color: stops[0].color, location: 0.12),
            .init(color: stops[1].color, location: 0.18),
            .init(color: stops[2].color, location: 0.60),
            .init(color: stops[3].color, location: 1.0),
        ]
    }
}
