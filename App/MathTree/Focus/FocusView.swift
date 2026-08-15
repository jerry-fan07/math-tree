import GraphCore
import SwiftUI

/// §6.2's focus mode: the goal's `requires`-ancestor subgraph, laid out
/// left-to-right in topological order, beside the ordered unmet set as a
/// syllabus (§5.4). The layout itself — columns, rows, met-boundary compression
/// — comes from `FocusPlan` in GraphCore, where it is testable; this view
/// contributes point spacing, colour and interaction.
///
/// The redesign collapses Phase 7's two halves into one. It had a node-link
/// canvas on the left and a numbered syllabus on the right, which said the same
/// thing twice: the canvas's columns *were* the syllabus's order. Turn 1 draws
/// the columns as columns — one rule-separated stage each, met stages set small
/// and quiet, the unmet chain at reading size, the goal last behind an accent
/// rule — and puts the count on a progress bar at the foot.
///
/// What that gives up is the edges: the design's frame has no lines between
/// stages, so "which of stage 2 feeds which of stage 3" is no longer drawn. The
/// column order still carries the dependency (a node is in stage *n* because its
/// deepest prerequisite is in stage *n−1*), and the node panel still lists exact
/// prerequisites, so the fact is available rather than illustrated.
///
/// The view recomputes its plan whenever the score snapshot changes (`revision`
/// is observable), so reviewing a syllabus node from the panel visibly compresses
/// it out of the chain — the loop the product is for, closed inside one screen.
struct FocusView: View {
    let goal: NodeID
    let document: GraphDocument
    let scores: ScoreStore
    var onSelect: (NodeID) -> Void
    var onExit: () -> Void

    var body: some View {
        // Read on purpose: registers observation of the snapshot, so a recorded
        // review or a decay tick recomputes the plan.
        _ = scores.revision
        let theme = ThemeStore.shared.theme
        let plan = FocusPlan.compute(
            goal: goal, graph: scores.graph, state: scores.state, at: scores.evaluatedAt,
            config: scores.config)

        return VStack(spacing: 0) {
            if let plan {
                header(plan, theme)
                Rule()
                stages(plan, theme)
                progress(plan, theme)
            } else {
                // Unreachable through the UI (the action is only offered on
                // content nodes) but stale artifacts deserve words, not a blank.
                Text("This node has no focus view — it is not a learnable content node.")
                    .font(Typeface.sans(13))
                    .foregroundStyle(theme.inkMuted.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.canvasEdge.color)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private func header(_ plan: FocusPlan, _ theme: Theme) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: theme.isDark ? 9 : 10) {
                Text("PREREQUISITE PATH")
                    .font(Typeface.mono(10.5))
                    .tracking(Typeface.tracking(0.18, at: 10.5))
                    .foregroundStyle(theme.eyebrow.color)
                if let index = document.index(of: goal) {
                    MathTextView(
                        source: document[index].title,
                        size: theme.isDark ? 26 : 28,
                        weight: theme.isDark ? .light : .regular,
                        color: theme.inkStrong.color,
                        face: theme.isDark ? .sans : .serif
                    )
                    .accessibilityAddTraits(.isHeader)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 22) {
                Text("\(plan.displayedCount + plan.elidedMetCount) nodes")
                Text("\(metCount(plan)) met")
                if readyCount(plan) > 0 {
                    Text("\(readyCount(plan)) ready now")
                        .foregroundStyle(theme.attention.color)
                }
                Button(action: onExit) {
                    Text("esc — full map")
                        .foregroundStyle(theme.statEmphasis.color)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Return to the full map")
            }
            .font(Typeface.mono(11))
            .foregroundStyle(theme.stat.color)
            .fixedSize()
        }
        .padding(.horizontal, theme.isDark ? 40 : 44)
        .padding(.top, theme.isDark ? 30 : 32)
        .padding(.bottom, theme.isDark ? 22 : 24)
    }

    // MARK: - Stages

    /// One column per topological stage, separated by rules. Horizontally
    /// scrollable rather than compressed: a long chain is a real answer to "what
    /// do I need for this", and squeezing eight stages into five columns' width
    /// would make it unreadable exactly when it matters most.
    private func stages(_ plan: FocusPlan, _ theme: Theme) -> some View {
        let inset: CGFloat = theme.isDark ? 40 : 44
        return GeometryReader { proxy in
            // A short chain fills the frame — the design's five columns are five
            // fifths of the width, not five fixed slabs with a gap at the end. A
            // long one falls back to a readable minimum and scrolls.
            let available = proxy.size.width - inset * 2
            let count = CGFloat(max(plan.columns.count, 1))
            let width = max((available - (count - 1)) / count, 232)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(plan.columns.enumerated()), id: \.offset) { index, ids in
                        stage(plan, index: index, ids: ids, width: width, theme: theme)
                        if index < plan.columns.count - 1 {
                            Rectangle().fill(theme.hairline.color).frame(width: 1)
                        }
                    }
                }
                .padding(.horizontal, inset)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stage(
        _ plan: FocusPlan, index: Int, ids: [NodeID], width: CGFloat, theme: Theme
    ) -> some View {
        let compressed = ids.allSatisfy { plan.placed[$0]?.role == .metBoundary }
        return VStack(alignment: .leading, spacing: 14) {
            Text("STAGE \(index + 1) · \(stageLabel(plan, ids: ids))")
                .font(Typeface.mono(10))
                .tracking(Typeface.tracking(0.16, at: 10))
                .foregroundStyle(theme.eyebrow.fading(0.7).color)
            VStack(alignment: .leading, spacing: compressed ? 11 : 16) {
                ForEach(ids, id: \.self) { id in
                    row(plan, id: id, theme: theme)
                }
                if index == 0, plan.elidedMetCount > 0 {
                    Text(
                        plan.elidedMetCount == 1
                            ? "1 earlier prerequisite you already know is not shown"
                            : "\(plan.elidedMetCount) earlier prerequisites you already know are not shown"
                    )
                    .font(Typeface.mono(10))
                    .foregroundStyle(theme.inkFaint.fading(0.7).color)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, theme.isDark ? 26 : 28)
        .frame(width: width, alignment: .leading)
    }

    /// What the stage *is*, in the design's vocabulary. `FocusPlan` knows met from
    /// unmet; "decayed" is the distinction the design adds on top — an unmet stage
    /// whose nodes have been learned once and have slipped below the threshold is a
    /// different problem from one that is new.
    private func stageLabel(_ plan: FocusPlan, ids: [NodeID]) -> String {
        if ids.contains(plan.goal) { return "GOAL" }
        if ids.allSatisfy({ plan.placed[$0]?.role == .metBoundary }) { return "MET" }
        let decayed = ids.contains { id in
            guard plan.placed[id]?.role != .metBoundary else { return false }
            if case .learned = ScoreFormat.state(of: id, in: scores) { return true }
            return false
        }
        return decayed ? "DECAYED" : "UNMET"
    }

    @ViewBuilder
    private func row(_ plan: FocusPlan, id: NodeID, theme: Theme) -> some View {
        let role = plan.placed[id]?.role ?? .unmet
        if role == .goal {
            goalRow(plan, id: id, theme: theme)
        } else {
            FocusRow(
                id: id, document: document, scores: scores,
                // §6.2: met prerequisites are *compressed* — present, small, quiet.
                isCompressed: role == .metBoundary,
                onSelect: onSelect)
        }
    }

    /// The goal, behind the accent rule the design gives it — the only place in
    /// focus mode the accent appears, because it is the only thing the whole view
    /// is pointing at.
    private func goalRow(_ plan: FocusPlan, id: NodeID, theme: Theme) -> some View {
        Button { onSelect(id) } label: {
            VStack(alignment: .leading, spacing: 7) {
                if let index = document.index(of: id) {
                    MathTextView(
                        source: document[index].title,
                        size: theme.isDark ? 17 : 19,
                        color: theme.inkStrong.color,
                        face: theme.isDark ? .sans : .serif)
                }
                Text(goalSubtitle(plan))
                    .font(Typeface.mono(11))
                    .foregroundStyle(theme.inkFaint.color)
            }
            .padding(.leading, 16)
            .overlay(alignment: .leading) {
                Rectangle().fill(theme.actionRule.color).frame(width: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func goalSubtitle(_ plan: FocusPlan) -> String {
        if plan.goalIsMet { return "goal · mastered" }
        let steps = plan.syllabus.count
        if steps == 0 { return "goal · ready to learn" }
        return "goal · \(steps) node\(steps == 1 ? "" : "s") away"
    }

    // MARK: - Progress

    private func progress(_ plan: FocusPlan, _ theme: Theme) -> some View {
        let total = plan.displayedCount + plan.elidedMetCount
        let met = metCount(plan)
        return HStack(spacing: 16) {
            MeasureBar(
                value: total == 0 ? 0 : Double(met) / Double(total), height: 2,
                tint: theme.measure)
            Text("\(met) / \(total) met")
                .font(Typeface.mono(10.5))
                .foregroundStyle(theme.stat.color)
                .fixedSize()
        }
        .padding(.horizontal, theme.isDark ? 40 : 44)
        .padding(.bottom, theme.isDark ? 26 : 28)
        .padding(.top, 8)
    }

    /// Everything the plan compressed out, plus the boundary it kept — the elided
    /// nodes are met by definition, which is why they were elided.
    private func metCount(_ plan: FocusPlan) -> Int {
        plan.metBoundary.count + plan.elidedMetCount + (plan.goalIsMet ? 1 : 0)
    }

    private func readyCount(_ plan: FocusPlan) -> Int {
        plan.placed.keys.filter { scores.isFrontier($0) }.count
    }
}

/// One prerequisite. Its own view so hovering does not invalidate the whole plan.
private struct FocusRow: View {
    let id: NodeID
    let document: GraphDocument
    let scores: ScoreStore
    let isCompressed: Bool
    let onSelect: (NodeID) -> Void

    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        let isDue = scores.isDue(id)
        Button { onSelect(id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: isCompressed ? 9 : 10) {
                ScoreDot(id: id, scores: scores, diameter: isCompressed ? 5 : 6)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                VStack(alignment: .leading, spacing: 4) {
                    if let index = document.index(of: id) {
                        MathTextView(
                            source: document[index].title,
                            size: isCompressed ? 12 : (theme.isDark ? 14 : 14.5),
                            color: (isCompressed ? theme.inkMuted : theme.ink).color)
                    }
                    // The one thing focus mode is for saying: this is what is
                    // standing between you and the goal *right now*.
                    if isDue, !isCompressed {
                        Text("due — review to unblock")
                            .font(Typeface.mono(11))
                            .foregroundStyle(theme.attention.color)
                    }
                }
                Spacer(minLength: 8)
                Text(readout)
                    .font(Typeface.mono(isCompressed ? 10 : 10.5))
                    .foregroundStyle((isCompressed ? theme.eyebrowCount : theme.rowTrailing).color)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(isHovering ? theme.rowHighlight.color : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(id.rawValue)
    }

    /// Met rows print the bare percentage the design sets ("94"); unmet rows have
    /// nothing to print and stay blank rather than showing a zero.
    private var readout: String {
        switch ScoreFormat.state(of: id, in: scores) {
        case let .learned(retrievability):
            return "\(Int((min(max(retrievability, 0), 1) * 100).rounded()))"
        case .frontier: return "ready"
        case .attempted: return "missed"
        case .unlearned: return ""
        }
    }
}

// MARK: - Preview

#if DEBUG

#Preview("Focus mode") {
    FocusView(
        goal: "analysis.svc.zero-deriv-const",
        document: NodePanelPreviewData.document,
        scores: NodePanelPreviewData.scores(),
        onSelect: { print("select \($0)") },
        onExit: { print("exit") }
    )
    .frame(width: 1280, height: 800)
}

#endif
