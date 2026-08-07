import GraphCore
import SwiftUI

/// §6.1's "clicking opens the node panel (statement, summary, **score, review
/// history, 'learn this' action**)" — the half Phase 4 deferred.
///
/// The review action is self-report, which §5.2 will replace with problems. It is
/// deliberately affirmative only: three confidence levels, no "I don't know this".
/// A self-reported failure would write FSRS state onto an unlearned node, and the
/// frontier is defined by the *absence* of state (§4.5) — so admitting ignorance
/// would quietly delete the node from "what you could learn next".
struct ScoreSection: View {
    let node: Node
    let scores: ScoreStore
    /// Non-nil once a review has been refused, so the failure is visible rather
    /// than a button press that silently did nothing.
    @State private var failure: String?

    private var state: ScoreFormat.State { ScoreFormat.state(of: node.id, in: scores) }
    private var history: [ScoreFold.ReviewPoint] { scores.history(of: node.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("KNOWLEDGE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(PanelTheme.tertiaryText)
            }
            if node.kind.isStructural {
                // §2.1: structural nodes are navigation, not knowledge.
                Text("Structural node — a hub, not something to learn, so it carries no score.")
                    .font(.system(size: 12))
                    .foregroundStyle(PanelTheme.tertiaryText)
            } else {
                readout
                if !history.isEmpty { historyBlock }
                selfReport
                if let failure {
                    Text(failure)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.94, green: 0.60, blue: 0.52))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Read-out

    private var readout: some View {
        HStack(alignment: .center, spacing: 11) {
            swatch
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PanelTheme.primaryText)
                    .help(state.detail)
                Text(ScoreFormat.due(scores.nextDue(of: node.id), relativeTo: scores.evaluatedAt))
                    .font(.system(size: 11.5))
                    .foregroundStyle(
                        scores.isDue(node.id) ? PanelTheme.accent : PanelTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    /// The dot the node wears on the map, at the size the panel can afford — grey
    /// with an accent ring on the frontier, exactly as §4.5 draws it.
    private var swatch: some View {
        ZStack {
            Circle()
                .fill(ScoreFormat.color(of: node.id, in: scores))
                .frame(width: 15, height: 15)
            if scores.isFrontier(node.id) {
                Circle()
                    .strokeBorder(Color(ScoreRamp.frontierAccent), lineWidth: 1.6)
                    .frame(width: 24, height: 24)
            }
        }
        .frame(width: 26, height: 26)
    }

    // MARK: - History

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            ScoreSparkline(
                history: history,
                fsrs: scores.fsrs,
                now: scores.evaluatedAt,
                threshold: scores.config.masteryThreshold)
            HStack(spacing: 8) {
                Text(reviewCountText)
                if let last = history.last {
                    Text("·")
                    Text("last \(ScoreFormat.elapsed(since: last.event.at, to: scores.evaluatedAt))")
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(PanelTheme.tertiaryText)
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
        if implicit > 0 { parts.append("\(implicit) exercised") }
        return parts.isEmpty ? "no reviews" : parts.joined(separator: " · ")
    }

    // MARK: - Self-report

    private var selfReport: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(history.isEmpty ? "I know this" : "Review")
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.secondaryText)
            HStack(spacing: 6) {
                ForEach(SelfReportConfidence.allCases, id: \.self) { confidence in
                    SelfReportButton(confidence: confidence) { record(confidence) }
                }
            }
            Text("Marks this and, more weakly, its prerequisites (§4.3).")
                .font(.system(size: 10.5))
                .foregroundStyle(PanelTheme.tertiaryText)
        }
    }

    private func record(_ confidence: SelfReportConfidence) {
        failure = scores.record(confidence, on: node.id)
            ? nil
            : (scores.diagnostics.last ?? "could not record this review")
    }
}

/// One confidence level. Its own view so hovering it does not invalidate the panel.
private struct SelfReportButton: View {
    let confidence: SelfReportConfidence
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(confidence.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isHovering ? PanelTheme.primaryText : PanelTheme.secondaryText)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering ? PanelTheme.rowHighlight : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(PanelTheme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(confidence.detail)
    }
}
