import Foundation

/// §4.5: the frontier is the unlearned nodes whose prerequisites all exceed τ —
/// "what you could learn next", and the actionable set the whole product points
/// at. Pure function of graph + state + clock; nothing is cached.
public enum Frontier {
    public static func compute(
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> [NodeID] {
        let fsrs = FSRS(parameters: config.fsrs)
        return graph.nodes
            .filter { node in
                // Structural nodes are not learnable and carry no score (§2.1).
                guard !node.kind.isStructural else { return false }
                // Unlearned means *no state entry at all* — a decayed node was
                // learned and is a review candidate, not a frontier candidate.
                guard state.nodes[node.id] == nil else { return false }
                // Direct prerequisites only: the transitive ones are implied,
                // because a prerequisite above τ was itself learned, which
                // required *its* prerequisites. Roots qualify vacuously.
                return node.requires.allSatisfy { prerequisite in
                    guard let memory = state.nodes[prerequisite] else { return false }
                    return fsrs.retrievability(of: memory, at: now) > config.masteryThreshold
                }
            }
            .map(\.id)
            .sorted()
    }

    /// Learned nodes whose retrievability has fallen to or below τ — the review
    /// queue by score. Phase 6 pairs this with the FSRS due-date read-out.
    public static func due(
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> [NodeID] {
        let fsrs = FSRS(parameters: config.fsrs)
        return state.nodes
            .filter { id, memory in
                guard let node = graph[id], !node.kind.isStructural else { return false }
                return fsrs.retrievability(of: memory, at: now) <= config.masteryThreshold
            }
            .keys
            .sorted()
    }
}
