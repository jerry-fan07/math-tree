import Foundation

/// The result of folding an evidence log: FSRS state per node and per `relates`
/// edge (§3.2). A pure cache — nothing here that the log cannot regenerate.
public struct ScoreState: Sendable {
    public var nodes: [NodeID: MemoryState]
    public var edges: [String: MemoryState]

    public init(nodes: [NodeID: MemoryState] = [:], edges: [String: MemoryState] = [:]) {
        self.nodes = nodes
        self.edges = edges
    }

    public subscript(id: NodeID) -> MemoryState? { nodes[id] }

    /// §4.1: retrievability is computed on read — no timer mutates state. A node
    /// with no entry is **unlearned**, which `nil` distinguishes from
    /// learned-but-decayed (§3.2, §4.5).
    public func retrievability(of id: NodeID, at now: Date, fsrs: FSRS) -> Double? {
        nodes[id].map { fsrs.retrievability(of: $0, at: now) }
    }

    public func retrievability(ofEdge key: String, at now: Date, fsrs: FSRS) -> Double? {
        edges[key].map { fsrs.retrievability(of: $0, at: now) }
    }
}

/// An event the fold could not apply.
public struct FoldDefect: Hashable, Sendable, CustomStringConvertible {
    public enum Reason: Hashable, Sendable {
        case unknownTarget
        case noGrade
    }

    public var index: Int
    public var target: String
    public var reason: Reason

    public var description: String {
        switch reason {
        case .unknownTarget: return "event \(index): no such node or edge — \(target)"
        case .noGrade: return "event \(index): no grade to fold — \(target)"
        }
    }
}

public enum ScoreFold {
    /// Fold an evidence log into memory state.
    ///
    /// Events are **sorted before application**: FSRS updates do not commute, so
    /// two events at the same instant must be applied in a content-determined
    /// order or the result depends on log arrival order and replay stops being
    /// reproducible.
    ///
    /// - Parameter graph: when supplied, events naming unknown ids are skipped and
    ///   reported rather than silently creating phantom state — content ids can
    ///   disappear between releases, and §10 (Shifu) sends ids we do not control.
    public static func fold(
        _ events: [EvidenceEvent],
        graph: KnowledgeGraph? = nil,
        config: ScoringConfig = ScoringConfig(),
        state initial: ScoreState = ScoreState()
    ) -> (state: ScoreState, defects: [FoldDefect]) {
        let fsrs = FSRS(parameters: config.fsrs)
        var state = initial
        var defects: [FoldDefect] = []

        for (index, event) in events.sorted(by: EvidenceEvent.foldOrder).enumerated() {
            guard let grade = event.grade else {
                // Confidence-only evidence is valid per §5.1 but has no fold
                // semantics until §5.3's inferred-tier handling lands in Phase 8.
                defects.append(.init(index: index, target: event.target.key, reason: .noGrade))
                continue
            }

            switch event.target {
            case let .node(id):
                if let graph, !graph.contains(id) {
                    defects.append(.init(index: index, target: id.rawValue, reason: .unknownTarget))
                    continue
                }
                state.nodes[id] = apply(
                    event, grade: grade, to: state.nodes[id], fsrs: fsrs, config: config)

            case let .edge(key):
                if let graph, !graph.relatesEdges.contains(where: { $0.key == key }) {
                    defects.append(.init(index: index, target: key, reason: .unknownTarget))
                    continue
                }
                state.edges[key] = apply(
                    event, grade: grade, to: state.edges[key], fsrs: fsrs, config: config)
            }
        }

        return (state, defects)
    }

    private static func apply(
        _ event: EvidenceEvent,
        grade: Grade,
        to current: MemoryState?,
        fsrs: FSRS,
        config: ScoringConfig
    ) -> MemoryState {
        guard event.source == .implicit else {
            return fsrs.review(current, grade: grade, at: event.at)
        }
        // Weight is authored into the event so the log stays auditable and a
        // replay reproduces the original damping even if γ has since changed.
        let weight = event.weight ?? config.propagationWeight(depth: event.depth ?? 1)
        return applyImplicit(
            grade: grade, weight: weight, at: event.at, to: current, fsrs: fsrs, config: config)
    }

    /// §4.3: "an implicit review boosts stability by a fraction of what an
    /// explicit review would", and "implicit reviews never *lower* a score".
    static func applyImplicit(
        grade: Grade,
        weight: Double,
        at now: Date,
        to current: MemoryState?,
        fsrs: FSRS,
        config: ScoringConfig
    ) -> MemoryState {
        let weight = min(max(weight, 0), 1)

        guard let current else {
            // Never directly reviewed: a fraction of the stability a first
            // explicit review would have granted. §5.3's "passing raises the
            // inferred probability of all ancestors" is this case.
            return MemoryState(
                stability: max(FSRS.stabilityMin, weight * fsrs.initialStability(grade)),
                difficulty: fsrs.initialDifficulty(grade),
                lastReview: now)
        }

        let explicit = fsrs.review(current, grade: grade, at: now)
        let interpolated = current.stability + weight * (explicit.stability - current.stability)
        return MemoryState(
            // The `max` is what enforces never-lower. It is belt-and-braces for
            // passing grades (FSRS raises stability on a pass) but load-bearing if
            // `propagateOnFailure` is ever switched on.
            stability: max(current.stability, interpolated),
            // Difficulty is left alone: §4.3 speaks only of stability, and
            // difficulty is a property of the material, not of this retrieval.
            difficulty: current.difficulty,
            lastReview: config.implicitReviewsResetDecayClock ? now : current.lastReview)
    }
}
