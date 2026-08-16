import Foundation

/// What a focus session is aimed at.
///
/// §6.2 wrote focus mode against a single goal node. §6.5 adds the other question
/// a knowledge graph obviously answers and the vision asks for outright — *"teach
/// me linear algebra"* — which is the same computation with a goal **set**: every
/// content node the subject contains. Both cases share one plan type, because
/// everything downstream of "which nodes am I aiming at" is identical.
public enum FocusGoal: Hashable, Sendable {
    /// §6.2: one content node. "What do I need to learn to get to X?"
    case node(NodeID)
    /// §6.5: a `branch` or `subbranch`, all of it. "Take me through X."
    case subject(NodeID)

    /// The focused id, whichever kind it is — the breadcrumb's identity.
    public var id: NodeID {
        switch self {
        case let .node(id), let .subject(id): id
        }
    }

    public var isSubject: Bool {
        if case .subject = self { return true }
        return false
    }
}

/// §6.2's focus mode, §6.5's guided path and §5.4's syllabus, as one pure
/// computation: given a goal — a node or a whole subject — and the user's
/// knowledge state, what stands between them and it, and in what order?
///
/// The display half (a left-to-right topologically ordered mini-graph) lives here
/// too, down to columns and row order, because the app target has no test target —
/// this module is the only place the Phase 7 exit criterion ("the syllabus order
/// is a valid topological order and omits exactly the met prerequisites") and
/// Phase 11's can be asserted. The app contributes nothing but point spacing.
///
/// "Met" is exactly the frontier's notion (§4.5): FSRS state exists *and*
/// retrievability is strictly above τ. A learned-but-decayed prerequisite is
/// unmet — it re-enters the syllabus, which is §5.4's "ongoing review" folded
/// into the same view as first-time learning.
public struct FocusPlan: Hashable, Sendable {
    /// How one displayed node participates in the plan.
    public enum Role: Hashable, Sendable {
        /// The destination itself, always the last column. Node goals only: a
        /// subject has no single destination, so its own nodes are steps like any
        /// other (§6.5).
        case goal
        /// An unmet prerequisite — a syllabus entry, rendered prominent.
        case unmet
        /// A met prerequisite on the boundary: directly required by an unmet
        /// node or the goal. Rendered compressed (§6.2); everything behind it
        /// is elided entirely.
        case metBoundary
    }

    /// One node placed in the mini-graph. `column` increases left-to-right and
    /// respects every `requires` edge; `row` is dense within a column.
    public struct PlacedNode: Hashable, Sendable {
        public let id: NodeID
        public let role: Role
        public let column: Int
        public let row: Int
    }

    /// A direct `requires` edge between two displayed nodes, prerequisite first.
    public struct Edge: Hashable, Sendable {
        public let from: NodeID
        public let to: NodeID
    }

    public let focus: FocusGoal
    /// The nodes the plan is aiming at: `[goal]` for a node focus, every content
    /// node the subject contains for a subject focus (§6.5). Empty is legitimate
    /// and common — most of §7.1's outline is subbranches with no content yet.
    public let targets: Set<NodeID>
    /// The targets already mastered — the progress read-out a subject needs and a
    /// single node does not.
    public let metTargets: Set<NodeID>
    /// §5.4: the ordered unmet set — the personalized syllabus. A valid topological
    /// order of the `requires` relation restricted to unmet nodes (including
    /// precedence through met intermediates). For a node focus this is the unmet
    /// *ancestors* and excludes the goal; for a subject the targets are steps too,
    /// so they are in it.
    public let syllabus: [NodeID]
    /// Met nodes directly required by an unmet node or the goal — the visible
    /// edge of what the user already knows.
    public let metBoundary: [NodeID]
    /// Met nodes *behind* the boundary, elided from display entirely. The count is
    /// shown so compression reads as compression, not as absence.
    public let elidedMetCount: Int
    /// Every displayed node with its column and row, keyed by id.
    public let placed: [NodeID: PlacedNode]
    /// Displayed nodes by column, row order within each — the drawing order.
    public let columns: [[NodeID]]
    /// Direct `requires` edges between displayed nodes.
    public let edges: [Edge]

    /// The focused id, node or subject.
    public var goal: NodeID { focus.id }

    /// Whether there is nothing left: the goal node is met, or every node of the
    /// subject is. A subject with no content authored yet is *not* complete —
    /// there is nothing to have learned.
    public var goalIsMet: Bool { !targets.isEmpty && metTargets.count == targets.count }

    public var displayedCount: Int { placed.count }

    /// Whether `id` belongs to the subject itself, as opposed to being a
    /// prerequisite pulled in from elsewhere in the graph. The distinction is the
    /// point of §6.5: "learn linear algebra" legitimately sends you to foundations
    /// first, and the path should say which steps are the detour.
    public func isTarget(_ id: NodeID) -> Bool { targets.contains(id) }

    /// Steps of the syllabus that lie outside the subject — met prerequisites
    /// elsewhere in the graph that have to be picked up on the way.
    public var importedSteps: [NodeID] { syllabus.filter { !targets.contains($0) } }

    // MARK: - Computation

    /// Build the plan for a single goal node, or nil when `goal` is not a learnable
    /// content node.
    public static func compute(
        goal: NodeID,
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> FocusPlan? {
        compute(focus: .node(goal), graph: graph, state: state, at: now, config: config)
    }

    /// Build the guided path through a whole subject (§6.5), or nil when `subject`
    /// is not a `branch`/`subbranch`. A subject with no content authored yet
    /// returns an *empty plan*, not nil: "Topology is outlined but unwritten" is a
    /// true answer, and the common one until §7's corpus is finished.
    public static func compute(
        subject: NodeID,
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> FocusPlan? {
        compute(focus: .subject(subject), graph: graph, state: state, at: now, config: config)
    }

    public static func compute(
        focus: FocusGoal,
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> FocusPlan? {
        guard let node = graph[focus.id] else { return nil }
        let fsrs = FSRS(parameters: config.fsrs)

        /// The goal node, when there is a single one. A subject leaves it nil, and
        /// every branch below reads as "the distinguished destination, if any" —
        /// which is exactly the one thing the two modes differ by.
        let destination: NodeID?
        let targets: [NodeID]
        switch focus {
        case let .node(id):
            guard node.kind.isContent else { return nil }
            destination = id
            targets = [id]
        case let .subject(id):
            guard node.kind.isStructural else { return nil }
            destination = nil
            targets = graph.contentDescendants(of: id)
        }

        // Frontier's exact notion, deliberately — D7.1: the gold rings and the
        // syllabus must not be able to disagree at the margin. `isLearned` rather
        // than "has state" for the same reason Frontier changed: a node that has
        // only ever been missed is unmet, however recent the attempt.
        func isMet(_ id: NodeID) -> Bool {
            guard state.isLearned(id), let memory = state.nodes[id] else { return false }
            return fsrs.retrievability(of: memory, at: now) > config.masteryThreshold
        }

        // The requires-ancestor subgraph of the whole target set (§6.2, §6.5).
        // Structural ids are excluded defensively, mirroring Frontier: they carry
        // no score, so one reached through a bad edge would sit unmet in every
        // syllabus forever.
        let ancestors = graph.requiresAncestors(ofAll: targets)
            .filter { graph[$0]?.kind.isContent == true }
        let subgraph = Set(ancestors).union(targets)

        // Longest-path layering over the FULL subgraph, met and unmet alike. Any
        // directed path strictly increases the layer, so (layer, id) order is a
        // valid topological order even when one unmet node precedes another only
        // through met intermediates — which (layer, id) over a pruned subgraph
        // would get wrong.
        var layer: [NodeID: Int] = [:]
        func layerOf(_ id: NodeID) -> Int {
            if let known = layer[id] { return known }
            // Marked before recursing so an (invalid, validator-rejected) cycle
            // terminates instead of recursing forever.
            layer[id] = 0
            let prerequisites = graph.prerequisites(of: id).filter { subgraph.contains($0) }
            let value = prerequisites.map { layerOf($0) + 1 }.max() ?? 0
            layer[id] = value
            return value
        }
        for id in subgraph.sorted() { _ = layerOf(id) }

        // Everything that can be a step or a known node: the subgraph, less the
        // single destination when there is one (it is the arrival, not a step).
        let pool = destination.map { subgraph.subtracting([$0]) } ?? subgraph
        let unmetSet = pool.filter { !isMet($0) }
        let syllabus = unmetSet.sorted { (layer[$0]!, $0) < (layer[$1]!, $1) }

        // §6.2's compression: a met node is displayed only where the unmet chain
        // actually touches it — as a direct prerequisite of an unmet node or of the
        // destination. Met nodes behind that boundary are elided and counted.
        var boundary: Set<NodeID> = []
        for id in unmetSet.union(destination.map { [$0] } ?? []) {
            for prerequisite in graph.prerequisites(of: id)
            where subgraph.contains(prerequisite) && !unmetSet.contains(prerequisite)
                && prerequisite != destination
            {
                boundary.insert(prerequisite)
            }
        }
        let metCount = pool.count - unmetSet.count
        let displayed = unmetSet.union(boundary).union(destination.map { [$0] } ?? [])

        // Columns: the distinct layers that survive into the displayed set,
        // compacted so elision never leaves an empty column.
        let displayedLayers = Set(displayed.map { layer[$0]! }).sorted()
        let columnOfLayer = Dictionary(
            uniqueKeysWithValues: displayedLayers.enumerated().map { ($0.element, $0.offset) })

        var columns: [[NodeID]] = Array(repeating: [], count: displayedLayers.count)
        for id in displayed { columns[columnOfLayer[layer[id]!]!].append(id) }

        // Row order: one left-to-right barycenter pass over displayed direct
        // prerequisites, ties by id — deterministic, and enough to keep edges
        // from crossing gratuitously at this scale. A node's prerequisites all
        // sit in earlier columns (an edge strictly increases the layer), so
        // their rows are always assigned by the time it asks.
        var row: [NodeID: Int] = [:]
        func barycenter(of id: NodeID) -> Double {
            let placedPrerequisites = graph.prerequisites(of: id)
                .filter { displayed.contains($0) }
                .compactMap { row[$0] }
            guard !placedPrerequisites.isEmpty else { return .infinity }
            return Double(placedPrerequisites.reduce(0, +)) / Double(placedPrerequisites.count)
        }
        for index in columns.indices {
            let ordered = columns[index].sorted { a, b in
                let (ba, bb) = (barycenter(of: a), barycenter(of: b))
                if ba != bb { return ba < bb }
                return a < b
            }
            columns[index] = ordered
            for (r, id) in ordered.enumerated() { row[id] = r }
        }

        var placed: [NodeID: PlacedNode] = [:]
        for id in displayed {
            placed[id] = PlacedNode(
                id: id,
                role: id == destination ? .goal : (unmetSet.contains(id) ? .unmet : .metBoundary),
                column: columnOfLayer[layer[id]!]!,
                row: row[id]!)
        }

        var edges: [Edge] = []
        for id in displayed.sorted() {
            for prerequisite in graph.prerequisites(of: id) where displayed.contains(prerequisite) {
                edges.append(Edge(from: prerequisite, to: id))
            }
        }

        return FocusPlan(
            focus: focus,
            targets: Set(targets),
            metTargets: Set(targets.filter(isMet)),
            syllabus: syllabus,
            metBoundary: boundary.sorted(),
            elidedMetCount: metCount - boundary.count,
            placed: placed,
            columns: columns,
            edges: edges)
    }
}
