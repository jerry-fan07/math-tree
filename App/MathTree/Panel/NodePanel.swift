import GraphCore
import SwiftUI

/// Detail panel for the selected node (§6.1: "clicking opens the node panel").
///
/// Phase 4's exit criterion is that the panel "shows every field of every node kind", so
/// every authored field of §3.1 has a home here — `id`, `kind`, `prominence`, `title`,
/// `statement`, `summary`, `parent`, `also_under`, `requires`, `relates` (with its note,
/// which §2.3 makes content in its own right) and `tags` — plus the two derived indexes the
/// document carries, `dependents` and `contains`-children. Structural nodes have no
/// `statement`/`requires`/`relates` by invariant, so those sections are absent for them
/// rather than empty.
///
/// Score, history sparkline and next-due date arrive in Phase 6; this phase is explicitly
/// "minus scores".
struct NodePanel: View {
    let node: Node
    let document: GraphDocument
    /// Navigate to another node (prerequisite/dependent links, `relates`, taxonomy).
    var onSelect: (NodeID) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(PanelTheme.separator)
                .frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statementSection
                    summarySection
                    prerequisitesSection
                    dependentsSection
                    containsSection
                    relatesSection
                    detailsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        // Nearly opaque rather than fully: the panel owns its own contrast and must stay
        // legible whatever is behind it, but the last 14 % lets a material or the graph
        // canvas show through so the panel reads as sitting *over* the map, not beside it.
        .background(PanelTheme.background.opacity(0.86))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                MathTextView(source: node.title, size: 17, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                badges
            }
            Spacer(minLength: 0)
            PanelCloseButton(action: onClose)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var badges: some View {
        HStack(spacing: 6) {
            chip(node.kind.rawValue, color: PanelTheme.color(for: node.kind))
            chip(prominenceChipText, color: PanelTheme.secondaryText)
                .help(prominenceExplanation)
        }
    }

    /// Structural nodes are implicitly maximal prominence for display (§2.1); the authored
    /// value is still shown, in the tooltip and in the details grid, because it is a field.
    private var prominenceChipText: String {
        node.kind.isStructural
            ? "prominence implicit"
            : "prominence \(node.prominence.rawValue) · \(PanelTheme.label(for: node.prominence))"
    }

    private var prominenceExplanation: String {
        node.kind.isStructural
            ? """
            Structural nodes are implicitly maximal prominence for display (§2.1). \
            Authored value: \(node.prominence.rawValue).
            """
            : "Prominence drives display size and label visibility, never semantics (§2.1)."
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .tracking(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color.opacity(0.32), lineWidth: 1))
    }

    // MARK: - Sections

    @ViewBuilder
    private var statementSection: some View {
        if let statement = node.statement?.trimmingCharacters(in: .whitespacesAndNewlines),
            !statement.isEmpty
        {
            section("Statement") {
                MathTextView(source: statement, size: 13.5)
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary = node.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
            !summary.isEmpty
        {
            section("Summary") {
                MathTextView(source: summary, size: 12.5, color: PanelTheme.secondaryText)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var prerequisitesSection: some View {
        // Structural nodes carry no `requires` by invariant (§3.1) — no empty section.
        if !node.kind.isStructural {
            section("Requires", count: node.requires.count) {
                if node.requires.isEmpty {
                    note("No prerequisites — a root of the requires DAG.")
                } else {
                    references(node.requires)
                }
            }
        }
    }

    @ViewBuilder
    private var dependentsSection: some View {
        let dependents = document.dependents(of: node.id)
        if !node.kind.isStructural {
            section("Required by", count: dependents.count) {
                if dependents.isEmpty {
                    note("Nothing in the graph depends on this yet.")
                } else {
                    references(dependents)
                }
            }
        }
    }

    @ViewBuilder
    private var containsSection: some View {
        // `contains` children (§2.3) — the substance of a branch or subbranch panel.
        let children = orderedChildren
        if node.kind.isStructural {
            section("Contains", count: children.count) {
                if children.isEmpty {
                    note("No child nodes authored yet.")
                } else {
                    references(children)
                }
            }
        }
    }

    @ViewBuilder
    private var relatesSection: some View {
        let edges = incidentRelates
        if !node.kind.isStructural {
            section("Related", count: edges.count) {
                if edges.isEmpty {
                    note("No conceptual relations recorded.")
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(edges, id: \.key) { edge in
                            NodeReferenceRow(
                                id: edge.endpoint(opposite: node.id),
                                document: document,
                                note: edge.note,
                                onSelect: onSelect)
                        }
                    }
                    .padding(.horizontal, -8)
                }
            }
        }
    }

    private var detailsSection: some View {
        section("Details") {
            VStack(alignment: .leading, spacing: 9) {
                detailRow("id") {
                    Text(node.id.rawValue)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(PanelTheme.secondaryText)
                        .textSelection(.enabled)
                }
                detailRow("kind") {
                    Text(node.kind.rawValue)
                        .font(.system(size: 12))
                        .foregroundStyle(PanelTheme.secondaryText)
                }
                detailRow("prominence") {
                    Text(verbatim: prominenceDetailText)
                        .font(.system(size: 12))
                        .foregroundStyle(PanelTheme.secondaryText)
                }
                detailRow("parent") {
                    if let parent = node.parent {
                        NodeReferenceLink(id: parent, document: document, onSelect: onSelect)
                    } else {
                        Text("— top-level branch")
                            .font(.system(size: 12))
                            .foregroundStyle(PanelTheme.tertiaryText)
                    }
                }
                detailRow("also under") {
                    if node.alsoUnder.isEmpty {
                        emptyValue
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(node.alsoUnder, id: \.self) { id in
                                NodeReferenceLink(id: id, document: document, onSelect: onSelect)
                            }
                        }
                    }
                }
                detailRow("tags") {
                    if node.tags.isEmpty {
                        emptyValue
                    } else {
                        Text(node.tags.joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundStyle(PanelTheme.secondaryText)
                    }
                }
            }
        }
    }

    /// The authored value, always, plus a note when display overrides it (§2.1).
    private var prominenceDetailText: String {
        let base = "\(node.prominence.rawValue) · \(PanelTheme.label(for: node.prominence))"
        return node.kind.isStructural ? base + "  (display: implicit maximum)" : base
    }

    // MARK: - Derived data

    /// Children ordered the way the taxonomy reads: subbranches first, then by prominence,
    /// then alphabetically — stable, since layout order is not meaningful here.
    private var orderedChildren: [NodeID] {
        (document.children[node.id] ?? []).sorted { left, right in
            guard let a = document.index(of: left).map({ document[$0] }),
                let b = document.index(of: right).map({ document[$0] })
            else { return left < right }
            if a.kind.isStructural != b.kind.isStructural { return a.kind.isStructural }
            if a.displayProminence != b.displayProminence {
                return a.displayProminence > b.displayProminence
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// `relates` is authored on one endpoint only (§3.1), so the panel reads the canonical
    /// undirected edge list rather than `node.relates` — otherwise the connection would be
    /// visible from one side of the graph and invisible from the other.
    private var incidentRelates: [RelatesEdge] {
        document.relatesEdges
            .filter { $0.a == node.id || $0.b == node.id }
            .sorted()
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, count: Int? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(PanelTheme.tertiaryText)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(PanelTheme.tertiaryText.opacity(0.7))
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func references(_ ids: [NodeID]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ids, id: \.self) { id in
                NodeReferenceRow(id: id, document: document, note: nil, onSelect: onSelect)
            }
        }
        // Rows carry their own hit-target padding; pull it back so titles line up with the
        // section headers above them.
        .padding(.horizontal, -8)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(PanelTheme.tertiaryText)
    }

    private var emptyValue: some View {
        Text("—")
            .font(.system(size: 12))
            .foregroundStyle(PanelTheme.tertiaryText)
    }

    private func detailRow<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(PanelTheme.tertiaryText)
                .frame(width: 76, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

/// Close affordance. Its own view so the hover state does not invalidate the whole panel.
private struct PanelCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isHovering ? PanelTheme.primaryText : PanelTheme.tertiaryText)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(isHovering ? PanelTheme.rowHighlight : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Close node panel")
    }
}

// MARK: - Preview

#if DEBUG

/// A hand-built stand-in for `GraphDocument.load()`, so the preview does not depend on
/// build artifacts being present.
enum NodePanelPreviewData {
    static let mvt = Node(
        id: "analysis.svc.mvt",
        kind: .theorem,
        prominence: .standard,
        title: "Mean Value Theorem",
        statement: """
            If $f$ is continuous on $[a,b]$ and differentiable on the open interval \
            $(a,b)$, then there exists $c \\in (a,b)$ with \
            $f'(c) = \\dfrac{f(b) - f(a)}{b - a}$. Proof: apply Rolle's Theorem to \
            $g(x) = f(x) - \\dfrac{f(b) - f(a)}{b - a}\\,(x - a)$, which satisfies the \
            same regularity hypotheses and has $g(a) = g(b) = f(a)$.
            """,
        summary: """
            Somewhere strictly inside the interval, the instantaneous rate of change \
            equals the average rate of change across it.
            """,
        parent: "analysis.svc",
        requires: ["analysis.svc.rolle"],
        relates: [
            RelatesRef(
                id: "analysis.svc.ftc-part-2", note: "Both express integral–derivative interchange.")
        ],
        tags: ["calculus"])

    static let nodes: [Node] = [
        Node(id: "analysis", kind: .branch, title: "Analysis"),
        Node(
            id: "analysis.svc", kind: .subbranch, title: "Single-Variable Calculus",
            summary: "Limits, continuity, differentiation and Riemann integration.",
            parent: "analysis"),
        Node(
            id: "analysis.svc.rolle", kind: .lemma, prominence: .detail, title: "Rolle's Theorem",
            statement: "If $f(a) = f(b)$ then there exists $c \\in (a,b)$ with $f'(c) = 0$.",
            parent: "analysis.svc"),
        mvt,
        Node(
            id: "analysis.svc.zero-deriv-const", kind: .corollary, prominence: .detail,
            title: "f′ ≡ 0 ⇒ f constant",
            statement: "If $f'(x) = 0$ on an interval $I$ then $f$ is constant on $I$.",
            parent: "analysis.svc", requires: ["analysis.svc.mvt"]),
        Node(
            id: "analysis.svc.ftc-part-2", kind: .theorem, prominence: .landmark,
            title: "FTC, Part II",
            statement: "$\\int_a^b f(x)\\,dx = F(b) - F(a)$.", parent: "analysis.svc"),
    ]

    static let document: GraphDocument = {
        let indexByID = Dictionary(
            uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
        return GraphDocument(
            nodes: nodes,
            requiresEdges: [],
            relatesEdges: mvt.relatesEdges,
            dependents: ["analysis.svc.mvt": ["analysis.svc.zero-deriv-const"]],
            children: [
                "analysis": ["analysis.svc"],
                "analysis.svc": [
                    "analysis.svc.rolle", "analysis.svc.mvt", "analysis.svc.zero-deriv-const",
                    "analysis.svc.ftc-part-2",
                ],
            ],
            positions: Array(repeating: .zero, count: nodes.count),
            indexByID: indexByID)
    }()

    /// The rendered statement, straight from the pure attributed-string API — present so the
    /// preview exercises `MathText.attributedString` and not only the `Text` path.
    static var mvtStatementAttributed: AttributedString {
        MathText.attributedString(mvt.statement ?? "", baseSize: 12)
    }
}

#Preview("Content node") {
    NodePanel(
        node: NodePanelPreviewData.mvt,
        document: NodePanelPreviewData.document,
        onSelect: { print("select \($0)") },
        onClose: { print("close") }
    )
    .frame(width: 360, height: 720)
}

#Preview("Structural node") {
    NodePanel(
        node: NodePanelPreviewData.nodes[1],
        document: NodePanelPreviewData.document,
        onSelect: { print("select \($0)") },
        onClose: { print("close") }
    )
    .frame(width: 360, height: 720)
}

#Preview("Attributed-string path") {
    Text(NodePanelPreviewData.mvtStatementAttributed)
        .padding()
        .frame(width: 360)
        .background(PanelTheme.background)
}

#endif
