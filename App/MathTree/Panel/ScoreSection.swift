import GraphCore
import SwiftUI

/// §6.1's "clicking opens the node panel (statement, summary, **score, review
/// history, 'learn this' action**)" — the half Phase 4 deferred.
///
/// Phase 8 makes problems the instrument (§5.2) and demotes self-report to the
/// fallback §5.4 allows ("via problems ... *whenever possible*"). Both are here,
/// and which one leads is decided by the bank: a node it can ask about gets the
/// problem action, everything else keeps the three confidence levels.
///
/// Self-report stays affirmative only, and the reason is unchanged (D6.3): the
/// frontier is defined by the *absence* of a successful retrieval (§4.5), so a
/// self-reported failure would be a claim about knowledge nobody measured. A
/// missed *problem* is different in kind — a measurement, with §5.4's diagnosis to
/// decide where it lands — which is why `missed` exists there and not here.
///
/// The redesign renames it: the panel's second block is **Retrievability**, a
/// number and a 3 pt bar rather than a swatch, a headline and a sparkline. The
/// sparkline is gone deliberately — it was the panel's only chart, it plotted six
/// points, and its whole message ("this has been reviewed a few times, and it is
/// holding") is carried by the bar plus the count beneath it.
struct ScoreSection: View {
    let node: Node
    let scores: ScoreStore
    /// §5.2's instrument. `nil` when no bank is loaded.
    var onReview: ((NodeID) -> Void)?
    /// Non-nil once a review has been refused, so the failure is visible rather
    /// than a button press that silently did nothing.
    @State private var failure: String?

    private var canProbe: Bool { onReview != nil && scores.canProbe(node.id) }

    private var state: ScoreFormat.State { ScoreFormat.state(of: node.id, in: scores) }
    private var history: [ScoreFold.ReviewPoint] { scores.history(of: node.id) }

    var body: some View {
        let theme = ThemeStore.shared.theme
        VStack(alignment: .leading, spacing: 9) {
            if node.kind.isStructural {
                // §2.1: structural nodes are navigation, not knowledge.
                Text("Structural node — a hub, not something to learn, so it carries no score.")
                    .font(Typeface.sans(12.5))
                    .foregroundStyle(theme.inkMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                readout(theme)
                selfReport(theme)
                if let failure {
                    Text(failure)
                        .font(Typeface.mono(10.5))
                        .foregroundStyle(theme.warning.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Read-out

    /// Label, value, bar, and the two facts underneath: when it is next owed, and
    /// what the number was built from.
    private func readout(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Retrievability")
                    .font(Typeface.sans(12.5))
                    .foregroundStyle(theme.inkMuted.color)
                Spacer(minLength: 12)
                Text(valueText)
                    .font(Typeface.mono(12.5, .medium))
                    .foregroundStyle(valueColor(theme).color)
                    .help(state.detail)
            }
            // Only a learned node gets a bar. An empty track beside "ready" would
            // read as a measured zero, and §4.5's whole point is that unlearned is
            // not a low score — it is the absence of one.
            if case let .learned(retrievability) = state {
                MeasureBar(value: retrievability, tint: valueColor(theme))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(ScoreFormat.due(scores.nextDue(of: node.id), relativeTo: scores.evaluatedAt))
                    .foregroundStyle(
                        scores.isDue(node.id) ? theme.attention.color : theme.inkFaint.color)
                Spacer(minLength: 12)
                Text(reviewCountText)
                    .foregroundStyle(theme.inkFaint.color)
            }
            .font(Typeface.mono(10.5))
        }
    }

    /// A learned node prints the modelled probability; the other three states of
    /// §4.5 print what they are, because a percentage would be a number nobody
    /// measured (D8.3).
    private var valueText: String {
        switch state {
        case let .learned(retrievability): String(format: "%.2f", retrievability)
        case .frontier: "ready"
        case .attempted: "missed"
        case .unlearned: "—"
        }
    }

    /// The bar and the number take the map's own colour for this node, so the
    /// panel is a read-out of the dot the user clicked rather than a second
    /// opinion about it. Off the ramp, they fall back to the theme's neutral.
    private func valueColor(_ theme: Theme) -> ThemeColor {
        switch state {
        case .learned: ScoreFormat.fill(of: node.id, in: scores)
        case .frontier: theme.attention
        case .attempted, .unlearned: theme.inkFaint
        }
    }

    /// Explicit and implicit reviews are counted separately: a node with nine
    /// boosts and no direct review is in a very different epistemic position from
    /// one with nine retrievals, and §4.3 is the reason.
    private var reviewCountText: String {
        let implicit = history.filter { $0.event.source == .implicit }.count
        let direct = history.count - implicit
        var parts: [String] = []
        if direct > 0 { parts.append("\(direct) review\(direct == 1 ? "" : "s")") }
        if implicit > 0 { parts.append("\(implicit) implicit") }
        if let last = history.last {
            parts.append("last \(ScoreFormat.elapsed(since: last.event.at, to: scores.evaluatedAt))")
        }
        return parts.isEmpty ? "no reviews yet" : parts.joined(separator: " · ")
    }

    // MARK: - Self-report

    /// Kept, though the design's frame does not draw it: §5.4 routes to a problem
    /// "whenever possible", and for a node the bank cannot ask about this is the
    /// *only* way to record what someone knows. Restyled to the redesign's one
    /// affordance shape — three underlined words rather than three bordered pills.
    private func selfReport(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(canProbe ? "Or just mark it" : (history.isEmpty ? "I know this" : "Review"))
                .font(Typeface.sans(11.5))
                .foregroundStyle(theme.inkFaint.color)
            HStack(spacing: 16) {
                ForEach(SelfReportConfidence.allCases, id: \.self) { confidence in
                    TextAction(
                        title: confidence.title, size: 11.5, isQuiet: true,
                        accessibilityHint: confidence.detail
                    ) { record(confidence) }
                }
            }
            Text("Marks this and, more weakly, its prerequisites (§4.3).")
                .font(Typeface.mono(10))
                .foregroundStyle(theme.inkFaint.fading(0.75).color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func record(_ confidence: SelfReportConfidence) {
        failure = scores.record(confidence, on: node.id)
            ? nil
            : (scores.diagnostics.last ?? "could not record this review")
    }
}
