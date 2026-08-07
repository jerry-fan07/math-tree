import Foundation

/// §6.2's focus mode and §5.4's syllabus, as one pure computation: given a goal
/// node and the user's knowledge state, what stands between them and it, and in
/// what order?
///
/// The display half (a left-to-right topologically ordered mini-graph) lives here
/// too, down to columns and row order, because the app target has no test target —
/// this module is the only place the Phase 7 exit criterion ("the syllabus order
/// is a valid topological order and omits exactly the met prerequisites") can be
/// asserted. The app contributes nothing but point spacing.
///
/// "Met" is exactly the frontier's notion (§4.5): FSRS state exists *and*
/// retrievability is strictly above τ. A learned-but-decayed prerequisite is
/// unmet — it re-enters the syllabus, which is §5.4's "ongoing review" folded
/// into the same view as first-time learning.
public struct FocusPlan: Hashable, Sendable {
    /// How one displayed node participates in the plan.
    public enum Role: Hashable, Sendable {
        /// The destination itself, always the last column.
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

    public let goal: NodeID
    /// Whether the goal itself is met (possible: focusing on something already
    /// mastered is a legitimate way to inspect what it rests on).
    public let goalIsMet: Bool
    /// §5.4: the ordered unmet prerequisite set — the personalized syllabus.
    /// Excludes the goal; a valid topological order of the `requires` relation
    /// restricted to unmet ancestors (including precedence through met
    /// intermediates).
    public let syllabus: [NodeID]
    /// Met ancestors directly required by an unmet node or the goal — the visible
    /// edge of what the user already knows.
    public let metBoundary: [NodeID]
    /// Met ancestors *behind* the boundary, elided from display entirely. The
    /// count is shown so compression reads as compression, not as absence.
    public let elidedMetCount: Int
    /// Every displayed node with its column and row, keyed by id.
    public let placed: [NodeID: PlacedNode]
    /// Displayed nodes by column, row order within each — the drawing order.
    public let columns: [[NodeID]]
    /// Direct `requires` edges between displayed nodes.
    public let edges: [Edge]

    public var displayedCount: Int { placed.count }

    // MARK: - Computation

    /// Build the plan for `goal`, or nil when `goal` is not a learnable content
    /// node (structural nodes have no prerequisites by invariant, and "learn
    /// this" is not a thing a branch supports).
    public static func compute(
        goal: NodeID,
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> FocusPlan? {
        guard let goalNode = graph[goal], goalNode.kind.isContent else { return nil }
        let fsrs = FSRS(parameters: config.fsrs)

        func isMet(_ id: NodeID) -> Bool {
            guard let memory = state.nodes[id] else { return false }
            return fsrs.retrievability(of: memory, at: now) > config.masteryThreshold
        }

        // The requires-ancestor subgraph (§6.2). Structural ids are excluded
        // defensively, mirroring Frontier: they carry no score, so one reached
        // through a bad edge would sit unmet in every syllabus forever.
        let ancestors = graph.requiresAncestors(of: goal)
            .filter { graph[$0]?.kind.isContent == true }
        let subgraph = Set(ancestors + [goal])

        // Longest-path layering over the FULL ancestor subgraph, met and unmet
        // alike. Any directed path strictly increases the layer, so (layer, id)
        // order is a valid topological order even when one unmet node precedes
        // another only through met intermediates — which (layer, id) over a
        // pruned subgraph would get wrong.
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

        let unmet = ancestors.filter { !isMet($0) }
        let unmetSet = Set(unmet)
        let syllabus = unmet.sorted { (layer[$0]!, $0) < (layer[$1]!, $1) }

        // §6.2's compression: a met ancestor is displayed only where the unmet
        // chain actually touches it — as a direct prerequisite of an unmet node
        // or of the goal. Met nodes behind that boundary are elided and counted.
        var boundary: Set<NodeID> = []
        for id in unmet + [goal] {
            for prerequisite in graph.prerequisites(of: id)
            where subgraph.contains(prerequisite) && !unmetSet.contains(prerequisite)
                && prerequisite != goal
            {
                boundary.insert(prerequisite)
            }
        }
        let metCount = ancestors.count - unmet.count
        let displayed = unmetSet.union(boundary).union([goal])

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
                role: id == goal ? .goal : (unmetSet.contains(id) ? .unmet : .metBoundary),
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
            goal: goal,
            goalIsMet: isMet(goal),
            syllabus: syllabus,
            metBoundary: boundary.sorted(),
            elidedMetCount: metCount - boundary.count,
            placed: placed,
            columns: columns,
            edges: edges)
    }
}
