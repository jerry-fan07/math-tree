import GraphCore
import SwiftUI

/// §6.2's focus mode: the goal's `requires`-ancestor subgraph, laid out
/// left-to-right in topological order, beside the ordered unmet set as a
/// syllabus (§5.4). The layout itself — columns, rows, met-boundary compression
/// — comes from `FocusPlan` in GraphCore, where it is testable; this view
/// contributes point spacing, colour and interaction.
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
        let plan = FocusPlan.compute(
            goal: goal, graph: scores.graph, state: scores.state, at: scores.evaluatedAt,
            config: scores.config)

        return VStack(spacing: 0) {
            breadcrumb
            Rectangle().fill(PanelTheme.separator).frame(height: 1)
            if let plan {
                HStack(spacing: 0) {
                    FocusMiniGraph(plan: plan, document: document, scores: scores, onSelect: onSelect)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle().fill(PanelTheme.separator).frame(width: 1)
                    FocusSyllabus(plan: plan, document: document, scores: scores, onSelect: onSelect)
                        .frame(width: 316)
                }
            } else {
                // Unreachable through the UI (the action is only offered on
                // content nodes) but stale artifacts deserve words, not a blank.
                Text("This node has no focus view — it is not a learnable content node.")
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

    private var breadcrumb: some View {
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
                Text("FOCUS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(PanelTheme.tertiaryText)
                if let index = document.index(of: goal) {
                    MathTextView(source: document[index].title, size: 14, weight: .semibold)
                }
            }

            Spacer(minLength: 0)

            Text("esc to go back")
                .font(.system(size: 10.5))
                .foregroundStyle(PanelTheme.tertiaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    var body: some View {
        GeometryReader { proxy in
            let points = layout(in: proxy.size)
            ZStack(alignment: .bottomLeading) {
                Canvas { context, _ in
                    draw(in: &context, points: points)
                }
                legend
            }
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
        .pointerStyle(hovered == nil ? .default : .link)
        .accessibilityLabel("Prerequisite graph for the focused goal")
    }

    // MARK: Geometry

    /// Columns spread across the width, each column vertically centred. The
    /// spacing clamps rather than scrolls: the whole point of the view is seeing
    /// the entire chain at once, and the corpus this design admits (§7) keeps
    /// ancestor subgraphs at map scale, not document scale.
    private func layout(in size: CGSize) -> [NodeID: CGPoint] {
        let insetX: CGFloat = 84
        let insetY: CGFloat = 64
        let columnCount = plan.columns.count
        let maxRows = plan.columns.map(\.count).max() ?? 1

        let columnSpacing =
            columnCount > 1
            ? min(200, max(96, (size.width - insetX * 2) / CGFloat(columnCount - 1))) : 0
        let rowSpacing =
            maxRows > 1 ? min(76, max(44, (size.height - insetY * 2) / CGFloat(maxRows - 1))) : 0

        let spanX = CGFloat(max(columnCount - 1, 0)) * columnSpacing
        let originX = max(insetX, (size.width - spanX) / 2)

        var points: [NodeID: CGPoint] = [:]
        for (column, ids) in plan.columns.enumerated() {
            let spanY = CGFloat(ids.count - 1) * rowSpacing
            let originY = max(insetY, (size.height - spanY) / 2)
            for (row, id) in ids.enumerated() {
                points[id] = CGPoint(
                    x: originX + CGFloat(column) * columnSpacing,
                    y: originY + CGFloat(row) * rowSpacing)
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

    private func radius(for role: FocusPlan.Role) -> CGFloat {
        switch role {
        case .goal: 9
        case .unmet: 6.5
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
            let r = radius(for: placed.role)
            let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
            let compressed = placed.role == .metBoundary

            context.fill(
                Path(ellipseIn: rect),
                with: .color(fill(for: id).opacity(compressed ? 0.6 : 1)))

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
                    compressed
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
                Text(
                    plan.elidedMetCount == 1
                        ? "1 earlier prerequisite you already know is not shown"
                        : "\(plan.elidedMetCount) earlier prerequisites you already know are not shown"
                )
            }
            if !plan.metBoundary.isEmpty {
                Text("small dots — already known")
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
                        ForEach(Array(plan.syllabus.enumerated()), id: \.element) { index, id in
                            step(number: index + 1, id: id)
                        }
                    }
                    goalRow
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("SYLLABUS")
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

    private func step(number: Int, id: NodeID) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(number)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelTheme.tertiaryText)
                .frame(width: 20, alignment: .trailing)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            NodeReferenceRow(id: id, document: document, scores: scores, onSelect: onSelect)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Text(
            plan.goalIsMet
                ? "Mastered — every prerequisite is met, and so is the goal."
                : "Every prerequisite is met. This is ready to learn — open it and report how it goes."
        )
        .font(.system(size: 12))
        .foregroundStyle(PanelTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
                .frame(width: 20, alignment: .trailing)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            NodeReferenceRow(id: plan.goal, document: document, scores: scores, onSelect: onSelect)
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
    .frame(width: 1100, height: 700)
}

#endif
