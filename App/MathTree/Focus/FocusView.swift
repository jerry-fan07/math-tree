import GraphCore
import SwiftUI

/// §6.2's focus mode and §6.5's guided path, which are one screen because they
/// are one computation: the `requires`-ancestor subgraph of the goal — where "the
/// goal" is either a node or every node of a subject — laid out left-to-right in
/// topological order (§5.4). The layout itself — columns, rows, met-boundary
/// compression — comes from `FocusPlan` in GraphCore, where it is testable; this
/// view contributes spacing, colour and interaction.
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
/// A subject changes what the same columns *say*, not how they are drawn (DT1.7):
/// the eyebrow reads LEARNING PATH, the steps that come from outside the subject
/// are set quiet with their origin branch named (§6.5, D11.5), there is no goal
/// row because a subject's own nodes are steps rather than an arrival, and the
/// progress bar counts targets instead of the whole plan.
///
/// The view recomputes its plan whenever the score snapshot changes (`revision`
/// is observable), so reviewing a node from the panel visibly compresses it out
/// of the chain — the loop the product is for, closed inside one screen.
struct FocusView: View {
    let focus: FocusGoal
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
            focus: focus, graph: scores.graph, state: scores.state, at: scores.evaluatedAt,
            config: scores.config)

        return VStack(spacing: 0) {
            if let plan {
                header(plan, theme)
                Rule()
                if plan.placed.isEmpty {
                    emptyPlan(plan, theme)
                } else {
                    stages(plan, theme)
                }
                progress(plan, theme)
            } else {
                // Unreachable through the UI (both actions are gated on kind) but
                // stale artifacts deserve words, not a blank.
                Text("This has no focus view — it is neither a learnable node nor a subject.")
                    .font(Typeface.sans(13))
                    .foregroundStyle(theme.inkMuted.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.canvasEdge.color)
        .background(.ultraThinMaterial)
    }

    private var title: String {
        document.index(of: focus.id).map { document[$0].title } ?? focus.id.rawValue
    }

    // MARK: - Header

    private func header(_ plan: FocusPlan, _ theme: Theme) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: theme.isDark ? 9 : 10) {
                Text(focus.isSubject ? "LEARNING PATH" : "PREREQUISITE PATH")
                    .font(Typeface.mono(10.5))
                    .tracking(Typeface.tracking(0.18, at: 10.5))
                    .foregroundStyle(theme.eyebrow.color)
                MathTextView(
                    source: title,
                    size: theme.isDark ? 26 : 28,
                    weight: theme.isDark ? .light : .regular,
                    color: theme.inkStrong.color,
                    face: theme.isDark ? .sans : .serif
                )
                .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            HStack(spacing: 22) {
                if focus.isSubject {
                    Text("\(plan.syllabus.count) steps")
                    // The honest headline of a subject path: how much of the work
                    // is not in the subject at all (D11.5). §2.4's cross-branch
                    // `requires` edges, as something the user has to act on.
                    if !plan.importedSteps.isEmpty {
                        Text("\(plan.importedSteps.count) imported")
                    }
                } else {
                    Text("\(plan.displayedCount + plan.elidedMetCount) nodes")
                    Text("\(metCount(plan)) met")
                }
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
    /// would make it unreadable exactly when it matters most. D11.4 measured what
    /// that is worth — `linear-algebra` is 23 stages against the FTC's 13.
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
                    Text(elidedNote(plan))
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

    /// In subject mode the elided set includes met *targets* — a mastered node of
    /// the subject that nothing unmet requires is compressed out like any other.
    /// Calling those "prerequisites" would be wrong twice over, so the noun
    /// changes with the mode.
    private func elidedNote(_ plan: FocusPlan) -> String {
        if focus.isSubject {
            return "\(plan.elidedMetCount) nodes you already know are not shown"
        }
        return plan.elidedMetCount == 1
            ? "1 earlier prerequisite you already know is not shown"
            : "\(plan.elidedMetCount) earlier prerequisites you already know are not shown"
    }

    /// What the stage *is*, in the design's vocabulary. `FocusPlan` knows met from
    /// unmet; "decayed" is the distinction the design adds on top — an unmet stage
    /// whose nodes have been learned once and have slipped below the threshold is a
    /// different problem from one that is new.
    private func stageLabel(_ plan: FocusPlan, ids: [NodeID]) -> String {
        if !focus.isSubject, ids.contains(plan.goal) { return "GOAL" }
        if ids.allSatisfy({ plan.placed[$0]?.role == .metBoundary }) { return "MET" }
        // A subject stage made entirely of steps borrowed from elsewhere is the
        // detour D11.5 insists on naming, and naming it on the stage as well as on
        // the row is what makes the shape of the path readable at a glance.
        if focus.isSubject, ids.allSatisfy({ !plan.isTarget($0) }) { return "IMPORTED" }
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
                // §6.5: a step inside the subject is the work; a step from another
                // branch is the toll on the way to it. Same row, quieter.
                origin: origin(plan, of: id),
                onSelect: onSelect)
        }
    }

    /// The branch a step was imported from, shown only when the step is not part of
    /// the subject being learned — inside Linear Algebra, "Linear Algebra" on every
    /// row is noise.
    private func origin(_ plan: FocusPlan, of id: NodeID) -> String? {
        guard focus.isSubject, !plan.isTarget(id) else { return nil }
        guard let index = document.index(of: id), let parent = document[index].parent else {
            return nil
        }
        return branchTitle(of: parent)
    }

    private func branchTitle(of id: NodeID) -> String? {
        guard let index = document.index(of: id) else { return nil }
        let node = document[index]
        if let parent = node.parent { return branchTitle(of: parent) }
        return node.title
    }

    /// The goal, behind the accent rule the design gives it — the only place in
    /// focus mode the accent appears, because it is the only thing the whole view
    /// is pointing at. Node goals only: a subject has no single destination, so
    /// `FocusPlan` never gives one of its nodes the `.goal` role.
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

    // MARK: - Empty

    /// Nothing to draw. For a node goal that means every prerequisite is met; for a
    /// subject it is usually the other thing entirely — §7.1 fixes the outline
    /// before the content, so most of the map is subjects with nothing authored in
    /// them yet. Two different facts, and a blank column states neither.
    private func emptyPlan(_ plan: FocusPlan, _ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(emptyHeadline(plan).uppercased())
                .font(Typeface.mono(10.5))
                .tracking(Typeface.tracking(0.18, at: 10.5))
                .foregroundStyle(theme.eyebrow.color)
            Text(emptyMessage(plan))
                .font(Typeface.sans(theme.isDark ? 15 : 16))
                .foregroundStyle(theme.inkMuted.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, theme.isDark ? 40 : 44)
        .padding(.top, theme.isDark ? 34 : 36)
    }

    private func emptyHeadline(_ plan: FocusPlan) -> String {
        plan.targets.isEmpty ? "Not authored yet" : "Nothing left"
    }

    private func emptyMessage(_ plan: FocusPlan) -> String {
        if plan.targets.isEmpty {
            return "\(title) is on the map but has no content authored yet, so there is no path "
                + "through it to draw."
        }
        if focus.isSubject {
            return "Mastered — all \(plan.targets.count) nodes in \(title) are above the threshold."
        }
        return plan.goalIsMet
            ? "Mastered — every prerequisite is met, and so is the goal."
            : "Every prerequisite is met. This is ready to learn — open it and report how it goes."
    }

    // MARK: - Progress

    /// A node focus counts progress over the plan's own nodes; a subject counts its
    /// targets, because "37 of 50 nodes of linear algebra" is §6.5's headline and
    /// the prerequisites imported from elsewhere are not part of what was asked
    /// for. Same bar, and in each mode the honest denominator (DT1.7). An
    /// unauthored subject has no denominator at all, and "0 / 0" under a paragraph
    /// that has just said so is the kind of read-out the redesign is subtracting.
    @ViewBuilder
    private func progress(_ plan: FocusPlan, _ theme: Theme) -> some View {
        let total = focus.isSubject ? plan.targets.count : plan.displayedCount + plan.elidedMetCount
        let met = focus.isSubject ? plan.metTargets.count : metCount(plan)
        if total > 0 {
            HStack(spacing: 16) {
                MeasureBar(value: Double(met) / Double(total), height: 2, tint: theme.measure)
                Text(focus.isSubject ? "\(met) / \(total) mastered" : "\(met) / \(total) met")
                    .font(Typeface.mono(10.5))
                    .foregroundStyle(theme.stat.color)
                    .fixedSize()
            }
            .padding(.horizontal, theme.isDark ? 40 : 44)
            .padding(.bottom, theme.isDark ? 26 : 28)
            .padding(.top, 8)
            .accessibilityLabel("\(met) of \(total) mastered")
        }
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
    /// §6.5: the branch this step was imported from, when it is not part of the
    /// subject being learned. Present is the signal — the row sets itself quiet.
    var origin: String?
    let onSelect: (NodeID) -> Void

    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        let isDue = scores.isDue(id)
        let isQuiet = isCompressed || origin != nil
        Button { onSelect(id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: isCompressed ? 9 : 10) {
                ScoreDot(id: id, scores: scores, diameter: isQuiet ? 5 : 6)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                VStack(alignment: .leading, spacing: 4) {
                    if let index = document.index(of: id) {
                        MathTextView(
                            source: document[index].title,
                            size: isCompressed ? 12 : (theme.isDark ? 14 : 14.5),
                            color: (isQuiet ? theme.inkMuted : theme.ink).color)
                    }
                    // The one thing focus mode is for saying: this is what is
                    // standing between you and the goal *right now*.
                    if isDue, !isCompressed {
                        Text("due — review to unblock")
                            .font(Typeface.mono(11))
                            .foregroundStyle(theme.attention.color)
                    } else if let origin, !origin.isEmpty {
                        Text(origin)
                            .font(Typeface.mono(10.5))
                            .foregroundStyle(theme.inkFaint.fading(0.75).color)
                            .lineLimit(1)
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
        .help(origin.map { "\(id.rawValue) — from \($0)" } ?? id.rawValue)
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
        focus: .node("analysis.svc.zero-deriv-const"),
        document: NodePanelPreviewData.document,
        scores: NodePanelPreviewData.scores(),
        onSelect: { print("select \($0)") },
        onExit: { print("exit") }
    )
    .frame(width: 1280, height: 800)
}

#Preview("Subject path") {
    FocusView(
        focus: .subject("analysis.svc"),
        document: NodePanelPreviewData.document,
        scores: NodePanelPreviewData.scores(),
        onSelect: { print("select \($0)") },
        onExit: { print("exit") }
    )
    .frame(width: 1280, height: 800)
}

#endif
