import GraphCore
import SwiftUI

/// §6.2's focus mode and §6.5's guided path, which are one screen because they are
/// one computation: the goal's `requires`-ancestor subgraph — where "the goal" is
/// either a node or every node of a subject — laid out left-to-right in topological
/// order, beside the ordered unmet set as a syllabus (§5.4). The layout itself —
/// columns, rows, met-boundary compression — comes from `FocusPlan` in GraphCore,
/// where it is testable; this view contributes point spacing, colour and
/// interaction.
///
/// The view recomputes its plan whenever the score snapshot changes (`revision`
/// is observable), so reviewing a syllabus node from the panel visibly compresses
/// it out of the chain — the loop the product is for, closed inside one screen.
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
        let plan = FocusPlan.compute(
            focus: focus, graph: scores.graph, state: scores.state, at: scores.evaluatedAt,
            config: scores.config)

        return VStack(spacing: 0) {
            breadcrumb(plan: plan)
            Rectangle().fill(PanelTheme.separator).frame(height: 1)
            if let plan {
                HStack(spacing: 0) {
                    Group {
                        if plan.placed.isEmpty {
                            emptyGraph(plan: plan)
                        } else {
                            FocusMiniGraph(
                                plan: plan, document: document, scores: scores, onSelect: onSelect)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle().fill(PanelTheme.separator).frame(width: 1)
                    FocusSyllabus(
                        plan: plan, document: document, scores: scores, onSelect: onSelect)
                        .frame(width: 316)
                }
            } else {
                // Unreachable through the UI (the actions are gated on kind) but
                // stale artifacts deserve words, not a blank.
                Text("This node has no focus view — it is neither a learnable node nor a subject.")
                    .font(.system(size: 12))
                    .foregroundStyle(PanelTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Nearly opaque, like the node panel: the map is still faintly present
        // underneath, which is what makes the return transition read as
        // continuity of place rather than a scene change (§6.2).
        .background(PanelTheme.background.opacity(0.94))
    }

    private var title: String {
        document.index(of: focus.id).map { document[$0].title } ?? focus.id.rawValue
    }

    private func breadcrumb(plan: FocusPlan?) -> some View {
        HStack(spacing: 14) {
            Button(action: onExit) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Full map")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(PanelTheme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to the full map")

            Rectangle().fill(PanelTheme.separator).frame(width: 1, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(focus.isSubject ? "LEARNING PATH" : "FOCUS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(PanelTheme.tertiaryText)
                MathTextView(source: title, size: 14, weight: .semibold)
            }

            // A subject's headline number is how much of it you already hold —
            // the one fact a single-node focus has no use for.
            if focus.isSubject, let plan, !plan.targets.isEmpty {
                SubjectProgressBar(
                    met: plan.metTargets.count, total: plan.targets.count, width: 96)
                    .padding(.leading, 4)
            }

            Spacer(minLength: 0)

            Text("esc to go back")
                .font(.system(size: 10.5))
                .foregroundStyle(PanelTheme.tertiaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Nothing to draw: either the subject is outlined but unwritten (§7.1's
    /// skeleton, which is most of the map today), or every node of it is mastered
    /// and §6.2's compression has elided the lot.
    private func emptyGraph(plan: FocusPlan) -> some View {
        VStack(spacing: 8) {
            Image(systemName: plan.targets.isEmpty ? "square.dashed" : "checkmark.seal")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(PanelTheme.tertiaryText)
            Text(
                plan.targets.isEmpty
                    ? "\(title) is on the map but has no content authored yet."
                    : "Nothing left to draw — all \(plan.targets.count) nodes are mastered."
            )
            .font(.system(size: 12))
            .foregroundStyle(PanelTheme.secondaryText)
            .multilineTextAlignment(.center)
        }
        .padding(28)
    }
}

/// The met/total bar. Its own view so it can be reused by the sidebar's subject
/// list, where the same number is the reason to pick one subject over another.
struct SubjectProgressBar: View {
    let met: Int
    let total: Int
    var width: CGFloat = 96
    /// Drops the word and the spaces. A three-digit total is common (Foundations
    /// is 195 nodes) and "3 / 195 mastered" wraps inside a 268-point sidebar.
    var isCompact = false

    private var fraction: Double { total == 0 ? 0 : Double(met) / Double(total) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(isCompact ? "\(met)/\(total)" : "\(met) / \(total) mastered")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelTheme.tertiaryText)
                .lineLimit(1)
                .fixedSize()
            ZStack(alignment: .leading) {
                Capsule().fill(PanelTheme.separator).frame(width: width, height: 3)
                Capsule()
                    .fill(PanelTheme.accent.opacity(0.85))
                    .frame(width: width * fraction, height: 3)
            }
        }
        .accessibilityLabel("\(met) of \(total) nodes mastered")
    }
}

// MARK: - Mini-graph

/// The ancestor subgraph as a canvas: one draw pass over the plan's columns, so
/// a subgraph of any plausible depth stays a single view. Hit-testing is a
/// nearest-point walk over the same geometry the canvas drew — there are no
/// per-node subviews to fall out of sync with.
private struct FocusMiniGraph: View {
    let plan: FocusPlan
    let document: GraphDocument
    let scores: ScoreStore
    var onSelect: (NodeID) -> Void

    @State private var hovered: NodeID?

    private static let insetX: CGFloat = 84
    private static let insetY: CGFloat = 64

    var body: some View {
        GeometryReader { proxy in
            let spacing = spacing(in: proxy.size)
            let canvas = canvasSize(in: proxy.size, spacing: spacing)
            let points = layout(in: canvas, spacing: spacing)
            ZStack(alignment: .bottomLeading) {
                // Scrolls only when the plan outgrows the frame: a subject path is
                // twenty-odd columns deep where a single goal was a dozen (D11.4),
                // and the previous fixed frame simply drew the far end off-screen.
                // When it fits, the content is the frame and nothing scrolls.
                ScrollView([.horizontal, .vertical]) {
                    Canvas { context, _ in
                        draw(in: &context, points: points)
                    }
                    .frame(width: canvas.width, height: canvas.height)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location): hovered = node(at: location, points: points)
                        case .ended: hovered = nil
                        }
                    }
                    .onTapGesture { location in
                        if let id = node(at: location, points: points) { onSelect(id) }
                    }
                }
                legend
            }
        }
        .pointerStyle(hovered == nil ? .default : .link)
        .accessibilityLabel("Prerequisite graph for the focused goal")
    }

    // MARK: Geometry

    /// Spacing is chosen against the *frame*: it spreads to fill a roomy window and
    /// clamps to a legible minimum in a cramped one. What changed in Phase 11 is
    /// what happens past the clamp — the canvas grows and scrolls rather than the
    /// graph running off the edge.
    private func spacing(in frame: CGSize) -> (column: CGFloat, row: CGFloat) {
        let columnCount = plan.columns.count
        let maxRows = plan.columns.map(\.count).max() ?? 1
        let column =
            columnCount > 1
            ? min(200, max(96, (frame.width - Self.insetX * 2) / CGFloat(columnCount - 1))) : 0
        let row =
            maxRows > 1
            ? min(76, max(44, (frame.height - Self.insetY * 2) / CGFloat(maxRows - 1))) : 0
        return (column, row)
    }

    private func canvasSize(in frame: CGSize, spacing: (column: CGFloat, row: CGFloat)) -> CGSize {
        let columnCount = plan.columns.count
        let maxRows = plan.columns.map(\.count).max() ?? 1
        return CGSize(
            width: max(
                frame.width, Self.insetX * 2 + CGFloat(max(columnCount - 1, 0)) * spacing.column),
            height: max(
                frame.height, Self.insetY * 2 + CGFloat(max(maxRows - 1, 0)) * spacing.row))
    }

    /// Columns spread across the canvas, each column vertically centred.
    private func layout(in size: CGSize, spacing: (column: CGFloat, row: CGFloat)) -> [NodeID:
        CGPoint]
    {
        let spanX = CGFloat(max(plan.columns.count - 1, 0)) * spacing.column
        let originX = max(Self.insetX, (size.width - spanX) / 2)

        var points: [NodeID: CGPoint] = [:]
        for (column, ids) in plan.columns.enumerated() {
            let spanY = CGFloat(ids.count - 1) * spacing.row
            let originY = max(Self.insetY, (size.height - spanY) / 2)
            for (row, id) in ids.enumerated() {
                points[id] = CGPoint(
                    x: originX + CGFloat(column) * spacing.column,
                    y: originY + CGFloat(row) * spacing.row)
            }
        }
        return points
    }

    private func node(at location: CGPoint, points: [NodeID: CGPoint]) -> NodeID? {
        var best: (id: NodeID, distance: CGFloat)?
        for (id, point) in points {
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < (best?.distance ?? 18), distance < 18 { best = (id, distance) }
        }
        return best?.id
    }

    // MARK: Drawing

    private func radius(for id: NodeID, role: FocusPlan.Role) -> CGFloat {
        switch role {
        case .goal: 9
        // §6.5: a step inside the subject is the work; a step imported from
        // another branch is the toll on the way to it. Same colour language,
        // smaller mark.
        case .unmet: plan.focus.isSubject && !plan.isTarget(id) ? 5 : 6.5
        // §6.2: met prerequisites are *compressed* — present, small, quiet.
        case .metBoundary: 3.5
        }
    }

    private func fill(for id: NodeID) -> Color {
        Color(scores.color(of: id))
    }

    private func draw(in context: inout GraphicsContext, points: [NodeID: CGPoint]) {
        // Edges first, painter's order, exactly like the map.
        for edge in plan.edges {
            guard let from = points[edge.from], let to = points[edge.to] else { continue }
            var path = Path()
            path.move(to: from)
            // A horizontal-leaning cubic reads as flow without an arrowhead.
            let pull = (to.x - from.x) * 0.45
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + pull, y: from.y),
                control2: CGPoint(x: to.x - pull, y: to.y))
            let intoUnmet = plan.placed[edge.to]?.role != .metBoundary
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        fill(for: edge.from).opacity(intoUnmet ? 0.38 : 0.22),
                        fill(for: edge.to).opacity(intoUnmet ? 0.55 : 0.28),
                    ]),
                    startPoint: from, endPoint: to),
                lineWidth: intoUnmet ? 1.4 : 1.0)
        }

        for (id, point) in points {
            guard let placed = plan.placed[id] else { continue }
            let r = radius(for: id, role: placed.role)
            let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
            let compressed = placed.role == .metBoundary
            let imported = plan.focus.isSubject && !plan.isTarget(id)

            context.fill(
                Path(ellipseIn: rect),
                with: .color(fill(for: id).opacity(compressed ? 0.6 : (imported ? 0.75 : 1))))

            // The same accents the map wears: gold for frontier, a bright ring
            // for the hover, a steady ring for the goal.
            if scores.isFrontier(id) {
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -3.5, dy: -3.5)),
                    with: .color(Color(ScoreRamp.frontierAccent)), lineWidth: 1.4)
            }
            if placed.role == .goal {
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -4.5, dy: -4.5)),
                    with: .color(.white.opacity(0.85)), lineWidth: 1.2)
            }
            if id == hovered {
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -6, dy: -6)),
                    with: .color(.white.opacity(0.9)), lineWidth: 1.3)
            }

            if let index = document.index(of: id) {
                var text = Text(MathText.attributedString(document[index].title, baseSize: 10.5))
                    .font(.system(size: compressed ? 9.5 : 10.5))
                text = text.foregroundStyle(
                    compressed || imported
                        ? PanelTheme.tertiaryText
                        : (placed.role == .goal ? PanelTheme.primaryText : PanelTheme.secondaryText))
                // Labels wrap inside their own column's width and alternate
                // above/below by column parity — adjacent columns share rows
                // constantly (that is what a layered layout does), and two long
                // titles on the same side of the same row run into each other.
                // Found by rendering, not reasoned out: the first focus panel
                // shot had "…⇒ integrable" colliding with "FTC, Part I".
                let resolved = context.resolve(text)
                let maxWidth: CGFloat = compressed ? 120 : 150
                let size = resolved.measure(in: CGSize(width: maxWidth, height: 64))
                let above = placed.column.isMultiple(of: 2) == false
                let originY = above ? point.y - r - 8 - size.height : point.y + r + 8
                context.draw(
                    resolved,
                    in: CGRect(
                        x: point.x - size.width / 2, y: originY,
                        width: size.width, height: size.height))
            }
        }
    }

    @ViewBuilder
    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            if plan.elidedMetCount > 0 {
                // In subject mode the elided set includes met *targets* — a
                // mastered node of the subject that nothing unmet requires is
                // compressed out like any other. Calling those "prerequisites"
                // would be wrong twice over, so the noun changes with the mode.
                Text(
                    plan.focus.isSubject
                        ? "\(plan.elidedMetCount) nodes you already know are not shown"
                        : (plan.elidedMetCount == 1
                            ? "1 earlier prerequisite you already know is not shown"
                            : "\(plan.elidedMetCount) earlier prerequisites you already know are not shown")
                )
            }
            if !plan.metBoundary.isEmpty {
                Text("small dots — already known")
            }
            if plan.focus.isSubject, !plan.importedSteps.isEmpty {
                Text("dimmed dots — prerequisites from outside this subject")
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(PanelTheme.tertiaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .allowsHitTesting(false)
    }
}

// MARK: - Syllabus

/// §5.4 rendered literally: "that ordered set *is* the personalized syllabus".
/// Rows are the panel's own reference rows, so score dots, frontier accents and
/// math titles stay one visual language across the app.
private struct FocusSyllabus: View {
    let plan: FocusPlan
    let document: GraphDocument
    let scores: ScoreStore
    var onSelect: (NodeID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if plan.syllabus.isEmpty {
                        emptyState
                    } else {
                        importNote
                        ForEach(Array(plan.syllabus.enumerated()), id: \.element) { index, id in
                            step(number: index + 1, id: id)
                        }
                    }
                    if !plan.focus.isSubject { goalRow }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(plan.focus.isSubject ? "PATH" : "SYLLABUS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(PanelTheme.tertiaryText)
            Text("\(plan.syllabus.count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelTheme.tertiaryText.opacity(0.7))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    /// The honest headline of a subject path: how much of the work is not in the
    /// subject at all. It is §2.4's cross-branch `requires` edges showing up as
    /// something a user has to act on.
    @ViewBuilder
    private var importNote: some View {
        let imported = plan.importedSteps.count
        if plan.focus.isSubject, imported > 0 {
            Text(
                "\(imported) of these \(plan.syllabus.count) steps sit outside this subject — "
                    + "prerequisites you need first."
            )
            .font(.system(size: 11))
            .foregroundStyle(PanelTheme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }

    private func step(number: Int, id: NodeID) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(number)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelTheme.tertiaryText)
                .frame(width: 24, alignment: .trailing)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            NodeReferenceRow(
                id: id, document: document, origin: origin(of: id), scores: scores,
                onSelect: onSelect)
        }
    }

    /// The branch a step was imported from, shown only when it is not the subject
    /// being learned — inside Linear Algebra, "Linear Algebra" on every row is noise.
    private func origin(of id: NodeID) -> String? {
        guard plan.focus.isSubject, !plan.isTarget(id) else { return nil }
        guard let index = document.index(of: id), let parent = document[index].parent,
            let branch = branchTitle(of: parent)
        else { return nil }
        return branch
    }

    private func branchTitle(of id: NodeID) -> String? {
        guard let index = document.index(of: id) else { return nil }
        let node = document[index]
        if let parent = node.parent { return branchTitle(of: parent) }
        return node.title
    }

    @ViewBuilder
    private var emptyState: some View {
        Text(emptyMessage)
            .font(.system(size: 12))
            .foregroundStyle(PanelTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private var emptyMessage: String {
        guard plan.focus.isSubject else {
            return plan.goalIsMet
                ? "Mastered — every prerequisite is met, and so is the goal."
                : "Every prerequisite is met. This is ready to learn — open it and report how it goes."
        }
        if plan.targets.isEmpty {
            return "Nothing to learn here yet: this subject is outlined but its nodes are not authored."
        }
        return "Mastered — all \(plan.targets.count) nodes in this subject are above the threshold."
    }

    @ViewBuilder
    private var goalRow: some View {
        Rectangle().fill(PanelTheme.separator).frame(height: 1)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Image(systemName: "scope")
                .font(.system(size: 9.5))
                .foregroundStyle(PanelTheme.tertiaryText)
                .frame(width: 24, alignment: .trailing)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            NodeReferenceRow(id: plan.goal, document: document, scores: scores, onSelect: onSelect)
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
    .frame(width: 1100, height: 700)
}

#Preview("Subject path") {
    FocusView(
        focus: .subject("analysis.svc"),
        document: NodePanelPreviewData.document,
        scores: NodePanelPreviewData.scores(),
        onSelect: { print("select \($0)") },
        onExit: { print("exit") }
    )
    .frame(width: 1100, height: 700)
}

#endif
