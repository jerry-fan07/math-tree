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
/// Phase 6 adds the score block — §4.5's state, the FSRS next-due date, the review
/// history and the self-report action — as `ScoreSection`, directly under the header so
/// "how well do I know this" is answered before the content is read. It is optional: the
/// panel still renders without user state (previews, and a run where the evidence log
/// could not be opened).
struct NodePanel: View {
    let node: Node
    let document: GraphDocument
    /// User state (§3.2). `nil` renders the Phase 4 panel exactly.
    var scores: ScoreStore?
    /// Navigate to another node (prerequisite/dependent links, `relates`, taxonomy).
    var onSelect: (NodeID) -> Void
    var onClose: () -> Void
    /// §6.1's "learn this" action — enter §6.2's focus mode with this node as the
    /// goal. `nil` (previews, no user state) renders the panel without it.
    var onFocus: ((NodeID) -> Void)? = nil
    /// §5.2's instrument: open a problem for this node. `nil` when no bank is
    /// loaded, which leaves Phase 6's self-report as the only reviewer (§5.4's
    /// "whenever possible" cuts both ways).
    var onReview: ((NodeID) -> Void)? = nil

    var body: some View {
        let theme = ThemeStore.shared.theme
        VStack(alignment: .leading, spacing: 0) {
            header(theme)
            Rule()
            if let scores {
                ScoreSection(node: node, scores: scores, onReview: onReview)
                    .padding(.horizontal, theme.isDark ? 28 : 30)
                    .padding(.vertical, 20)
                Rule()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statementSection(theme)
                    prerequisitesSection
                    dependentsSection
                    containsSection
                    relatesSection
                    detailsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.isDark ? 28 : 30)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            footer(theme)
        }
        // The one fully opaque surface in the redesign. Phase 6's panel was 86 %
        // so the map showed through; turn 1 wants a reading column that is a
        // reading column, and the rail is where the map is allowed to bleed.
        .background(theme.panelFill.color)
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    /// Title, and one mono line saying what this is. The redesign replaces the two
    /// bordered chips with `THEOREM · LANDMARK · analysis.svc.ftc-part-2` — the
    /// same three facts, set as metadata instead of as decoration, and now with
    /// the id visible without hovering.
    private func header(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                MathTextView(
                    source: node.title,
                    size: theme.isDark ? 21 : 24,
                    color: theme.inkStrong.color,
                    face: theme.isDark ? .sans : .serif
                )
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                PanelCloseButton(action: onClose)
            }
            Text(metaLine)
                .font(Typeface.mono(10.5))
                .tracking(Typeface.tracking(0.1, at: 10.5))
                .foregroundStyle(theme.eyebrow.color)
                .textSelection(.enabled)
                .help(prominenceExplanation)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, theme.isDark ? 28 : 30)
        .padding(.top, theme.isDark ? 26 : 28)
        .padding(.bottom, 20)
    }

    /// Structural nodes are implicitly maximal prominence for display (§2.1); the
    /// authored value is still shown, in the tooltip and in the details grid,
    /// because it is a field.
    private var metaLine: String {
        let prominence =
            node.kind.isStructural
            ? "PROMINENCE IMPLICIT"
            : PanelTheme.label(for: node.prominence).uppercased()
        return "\(node.kind.rawValue.uppercased()) · \(prominence) · \(node.id.rawValue)"
    }

    private var prominenceExplanation: String {
        node.kind.isStructural
            ? """
            Structural nodes are implicitly maximal prominence for display (§2.1). \
            Authored value: \(node.prominence.rawValue).
            """
            : "Prominence drives display size and label visibility, never semantics (§2.1)."
    }

    // MARK: - Footer

    /// The panel's two actions, on one rule-separated line: §6.1's "learn this"
    /// as the accented one, §5.2's problem beside it. Both were boxed controls
    /// before; the redesign has no boxed controls.
    @ViewBuilder
    private func footer(_ theme: Theme) -> some View {
        let canLearn = onFocus != nil && node.kind.isContent
        let canProbe = onReview != nil && (scores?.canProbe(node.id) ?? false)
        if canLearn || canProbe {
            VStack(spacing: 0) {
                Rule()
                HStack(alignment: .firstTextBaseline) {
                    if canLearn, let onFocus {
                        TextAction(
                            title: "Learn this →", size: 13,
                            accessibilityHint: "Opens focus mode with this node as the goal"
                        ) { onFocus(node.id) }
                    }
                    Spacer(minLength: 16)
                    if canProbe, let onReview {
                        TextAction(
                            title: "Review with a problem", size: 12.5, weight: .regular,
                            isQuiet: true,
                            accessibilityHint: "Opens a problem that targets this node"
                        ) { onReview(node.id) }
                    }
                }
                .padding(.horizontal, theme.isDark ? 28 : 30)
                .padding(.top, 18)
                .padding(.bottom, theme.isDark ? 22 : 24)
            }
        }
    }

    // MARK: - Sections

    /// Statement and summary as one block, which is how the design sets them: the
    /// statement in the reading face (serif on paper), the summary under it in the
    /// sans, no second heading between them.
    @ViewBuilder
    private func statementSection(_ theme: Theme) -> some View {
        let statement = node.statement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = node.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !statement.isEmpty || !summary.isEmpty {
            section(statement.isEmpty ? "Summary" : "Statement") {
                VStack(alignment: .leading, spacing: 9) {
                    if !statement.isEmpty {
                        MathTextView(
                            source: statement, size: theme.isDark ? 14 : 15,
                            color: theme.ink.color, face: theme.isDark ? .sans : .serif
                        )
                        .lineSpacing(theme.isDark ? 6 : 7)
                        .textSelection(.enabled)
                    }
                    if !summary.isEmpty {
                        MathTextView(source: summary, size: 13, color: theme.inkMuted.color)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                    }
                }
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
                                scores: scores,
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
                        .font(Typeface.mono(11.5))
                        .foregroundStyle(PanelTheme.secondaryText)
                        .textSelection(.enabled)
                }
                detailRow("kind") {
                    Text(node.kind.rawValue)
                        .font(Typeface.sans(12))
                        .foregroundStyle(PanelTheme.secondaryText)
                }
                detailRow("prominence") {
                    Text(verbatim: prominenceDetailText)
                        .font(Typeface.sans(12))
                        .foregroundStyle(PanelTheme.secondaryText)
                }
                detailRow("parent") {
                    if let parent = node.parent {
                        NodeReferenceLink(id: parent, document: document, onSelect: onSelect)
                    } else {
                        Text("— top-level branch")
                            .font(Typeface.sans(12))
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
                            .font(Typeface.sans(12))
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
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(title: title, count: count)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func references(_ ids: [NodeID]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ids, id: \.self) { id in
                NodeReferenceRow(
                    id: id, document: document, note: nil, scores: scores, onSelect: onSelect)
            }
        }
        // Rows carry their own hit-target padding; pull it back so titles line up with the
        // section headers above them.
        .padding(.horizontal, -4)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typeface.sans(12.5))
            .foregroundStyle(ThemeStore.shared.theme.inkMuted.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyValue: some View {
        Text("—")
            .font(Typeface.sans(12))
            .foregroundStyle(ThemeStore.shared.theme.inkFaint.color)
    }

    private func detailRow<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Typeface.mono(10))
                .foregroundStyle(ThemeStore.shared.theme.inkFaint.color)
                .frame(width: 76, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

/// Close affordance. Its own view so the hover state does not invalidate the whole
/// panel — and, in the redesign, the word `esc` rather than an `✕` in a circle:
/// the keystroke is the real affordance and the panel may as well name it.
private struct PanelCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        Button(action: action) {
            Text("esc")
                .font(Typeface.mono(theme.isDark ? 13 : 12.5))
                .foregroundStyle((isHovering ? theme.ink : theme.inkFaint).color)
                .padding(.top, theme.isDark ? 4 : 6)
                .contentShape(Rectangle())
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

    /// A store over a throwaway log with a short review history on the MVT, so the score
    /// section previews with a real sparkline rather than an empty state. Writing to a
    /// temporary path is deliberate — a preview must never touch the developer's own
    /// history in Application Support.
    @MainActor
    static func scores() -> ScoreStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mathtree-preview-\(UUID().uuidString)")
            .appendingPathComponent("evidence.jsonl")
        let graph = KnowledgeGraph(nodes: nodes)
        let now = Date()
        let events = [Grade.good, .hard, .easy].enumerated().flatMap { index, grade in
            Propagation.expanded(
                EvidenceEvent(
                    at: now.addingTimeInterval(-Double(24 - index * 8) * 86_400),
                    target: .node("analysis.svc.mvt"), grade: grade, source: .selfReport),
                in: graph)
        }
        _ = try? EvidenceLog(url: url).append(events)
        return ScoreStore(
            document: document,
            environment: ["MATHTREE_EVIDENCE_LOG": url.path],
            arguments: [])
    }
}

#Preview("Content node") {
    NodePanel(
        node: NodePanelPreviewData.mvt,
        document: NodePanelPreviewData.document,
        scores: NodePanelPreviewData.scores(),
        onSelect: { print("select \($0)") },
        onClose: { print("close") }
    )
    .frame(width: 360, height: 720)
}

#Preview("Structural node") {
    NodePanel(
        node: NodePanelPreviewData.nodes[1],
        document: NodePanelPreviewData.document,
        scores: NodePanelPreviewData.scores(),
        onSelect: { print("select \($0)") },
        onClose: { print("close") }
    )
    .frame(width: 360, height: 720)
}

/// The frontier state: unlearned, but its prerequisite (the MVT) has been reported —
/// grey fill, accent ring, no history, and the affirmative action.
#Preview("Frontier node") {
    NodePanel(
        node: NodePanelPreviewData.nodes[4],
        document: NodePanelPreviewData.document,
        scores: NodePanelPreviewData.scores(),
        onSelect: { print("select \($0)") },
        onClose: { print("close") }
    )
    .frame(width: 360, height: 720)
}

#Preview("Review sidebar") {
    ReviewSidebar(
        document: NodePanelPreviewData.document,
        scores: NodePanelPreviewData.scores(),
        onSelect: { print("select \($0)") },
        onClose: { print("close") }
    )
    .frame(width: 268, height: 720)
}

#Preview("Attributed-string path") {
    Text(NodePanelPreviewData.mvtStatementAttributed)
        .padding()
        .frame(width: 360)
        .background(PanelTheme.background)
}

#endif
