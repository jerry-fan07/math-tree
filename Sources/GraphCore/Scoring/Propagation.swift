import Foundation

/// §4.3: reviewing a node exercises its prerequisites (long division exercises
/// subtraction). An explicit review on N emits damped implicit reviews to N's
/// `requires`-ancestors within `D_max`.
///
/// **Propagation happens at write time, not fold time.** The plan requires
/// implicit reviews to land in the log with `source: implicit` so they are
/// auditable and replayable — which means the fold must never generate them, or
/// replaying a log would apply each one twice. Appending an explicit review means
/// appending `expand(...)`'s output alongside it; the fold then just applies what
/// it is given, in order.
///
/// Refitting γ later is therefore a filter, not a rewrite: drop every
/// `source: implicit` event, re-expand the explicit ones under new constants.
public enum Propagation {
    /// The implicit events induced by one explicit review. Does **not** include
    /// the originating event — the caller appends both.
    ///
    /// - Parameter exercised: nodes a problem names as exercised (§5.2). These get
    ///   full-strength implicit reviews regardless of graph distance.
    public static func expand(
        _ event: EvidenceEvent,
        in graph: KnowledgeGraph,
        exercised: [NodeID] = [],
        config: ScoringConfig = ScoringConfig()
    ) -> [EvidenceEvent] {
        guard event.source != .implicit else { return [] }  // never cascade
        guard let origin = event.target.nodeID, let grade = event.grade else { return [] }
        guard grade.isPass || config.propagateOnFailure else { return [] }
        guard graph.contains(origin) else { return [] }

        // Depth 0 for explicitly-exercised nodes, shortest `requires`-hop distance
        // otherwise. `requiresAncestorsByDepth` is breadth-first, so a node
        // reachable by both a short and a long path is damped by the short one.
        var depthByNode: [NodeID: Int] = [:]
        for node in exercised where node != origin && graph.contains(node) {
            depthByNode[node] = 0
        }
        for reached in graph.requiresAncestorsByDepth(
            of: origin, maxDepth: config.maxPropagationDepth)
        where reached.id != origin {
            depthByNode[reached.id] = min(depthByNode[reached.id] ?? .max, reached.depth)
        }

        return depthByNode
            .map { node, depth in
                EvidenceEvent(
                    at: event.at,
                    target: .node(node),
                    grade: grade,
                    source: .implicit,
                    problem: event.problem,
                    origin: origin,
                    depth: depth,
                    weight: config.propagationWeight(depth: depth))
            }
            .sorted(by: EvidenceEvent.foldOrder)
    }

    /// Convenience: the explicit event followed by everything it induces, in fold
    /// order — exactly what should be appended to the log.
    public static func expanded(
        _ event: EvidenceEvent,
        in graph: KnowledgeGraph,
        exercised: [NodeID] = [],
        config: ScoringConfig = ScoringConfig()
    ) -> [EvidenceEvent] {
        ([event] + expand(event, in: graph, exercised: exercised, config: config))
            .sorted(by: EvidenceEvent.foldOrder)
    }
}
