import Foundation

/// §5.4: "On a **failed** problem, the system disambiguates *which* knowledge
/// failed: offer the prerequisite chain of the target node and let the user (or a
/// follow-up micro-problem) localize the gap. The failure evidence lands on the
/// localized node, not automatically on the whole chain."
///
/// This is also the concrete form of §4.3's other half. That section says a failure
/// "propagates as a *flag for retesting*, not as a penalty" and never says what the
/// flag *is* — Phase 6 left it open (D6.3). It is this: the chain below is the set
/// of nodes a miss puts back in question, presented for retest. Nothing is written
/// until one of them is chosen, which is exactly "not as a penalty".
public enum Diagnosis {
    /// One candidate for where the knowledge actually failed.
    public struct Candidate: Hashable, Sendable {
        public let id: NodeID
        /// Longest-path layer within the failed target's ancestor subgraph: 0 for a
        /// node with no prerequisites inside it, rising toward the target.
        ///
        /// Longest path rather than hop distance, and it is load-bearing. Any
        /// directed `requires` path strictly increases the layer, so "A is a
        /// prerequisite of B" always implies `layer(A) < layer(B)` — which is
        /// exactly the ordering the ranking below needs. Shortest distance from the
        /// target does not have that property: in the seed graph `sup-inf` and
        /// `completeness` are both five hops below FTC Part II even though one
        /// requires the other, and a tie there would offer the symptom before the
        /// cause. Same construction, same reason, as `FocusPlan`'s layering (D7.1).
        public let layer: Int
        /// Current retrievability, or `nil` if the node was never learned — which
        /// is itself the strongest possible signal that this is the gap.
        public let retrievability: Double?
        /// Whether this node has ever been retrieved successfully.
        public let isLearned: Bool
        /// A problem that tests this node directly, if the bank has one. §5.4's
        /// "or a follow-up micro-problem" — the way to localize without asking the
        /// user to introspect.
        public let probe: ProblemID?

        public init(
            id: NodeID, layer: Int, retrievability: Double?, isLearned: Bool, probe: ProblemID?
        ) {
            self.id = id
            self.layer = layer
            self.retrievability = retrievability
            self.isLearned = isLearned
            self.probe = probe
        }

        /// Most-likely-culprit first, and the two clauses are the two things §5.4
        /// is trying to separate.
        ///
        /// **Weakest first**: never-learned outranks everything (there is no
        /// knowledge there to have failed *from*), then lowest retrievability.
        ///
        /// **Deepest first among equals**: a gap propagates *upward*. If a node and
        /// one of its own prerequisites are both suspect, the prerequisite is the
        /// cause and the node is the symptom — offering the symptom first is
        /// exactly the misattribution §5.4 exists to prevent, and it is what makes
        /// the failed target itself rank last rather than first.
        ///
        /// Id breaks the remaining ties, so the chain a user is shown is the same
        /// chain every time.
        static func rank(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
            if lhs.isLearned != rhs.isLearned { return !lhs.isLearned }
            let left = lhs.retrievability ?? -1
            let right = rhs.retrievability ?? -1
            if left != right { return left < right }
            if lhs.layer != rhs.layer { return lhs.layer < rhs.layer }
            return lhs.id < rhs.id
        }
    }

    /// The chain offered after a miss, weakest first.
    ///
    /// Scope is the failed problem's targets plus their **full** transitive
    /// `requires` ancestry — not `D_max`-capped. Damping caps how far *credit*
    /// spreads (§4.3); a gap can sit arbitrarily deep, and truncating the chain at
    /// three hops would hide the case this feature exists for. The chain is small
    /// in practice because it is one node's ancestry, not the graph.
    ///
    /// - Parameter bank: optional. When supplied, each candidate carries a probe
    ///   problem so the caller can offer a micro-problem instead of asking the user
    ///   to self-diagnose.
    public static func chain(
        after problem: Problem,
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        bank: ProblemBank? = nil,
        config: ScoringConfig = ScoringConfig()
    ) -> [Candidate] {
        chain(
            forTargets: problem.targets, graph: graph, state: state, at: now, bank: bank,
            config: config, excluding: problem.id)
    }

    /// The same chain for an arbitrary target set — used by placement, which probes
    /// a node rather than a problem.
    public static func chain(
        forTargets targets: [NodeID],
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        bank: ProblemBank? = nil,
        config: ScoringConfig = ScoringConfig(),
        excluding: ProblemID? = nil
    ) -> [Candidate] {
        let fsrs = FSRS(parameters: config.fsrs)

        let content = targets.filter { graph[$0]?.kind.isContent == true }
        let subgraph = Set(
            content + content.flatMap { graph.requiresAncestors(of: $0) }
                .filter { graph[$0]?.kind.isContent == true })

        // Longest-path layering over the subgraph — see `Candidate.layer`.
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

        return subgraph
            .map { id in
                Candidate(
                    id: id,
                    layer: layer[id] ?? 0,
                    retrievability: state.retrievability(of: id, at: now, fsrs: fsrs),
                    isLearned: state.isLearned(id),
                    // Never re-offer the problem that was just missed as its own
                    // micro-problem: the user has seen the answer.
                    probe: (bank?.problemsByTarget[id] ?? []).first { $0 != excluding })
            }
            .sorted(by: Candidate.rank)
    }

    /// The evidence a localized failure produces: one `again` on the chosen node
    /// and nothing else (§5.4). Propagation is deliberately absent — this is the
    /// same rule as `ScoringConfig.propagateOnFailure`, stated at the one call site
    /// that could plausibly want otherwise.
    public static func evidence(
        for problem: Problem,
        localizedTo id: NodeID,
        in graph: KnowledgeGraph,
        at now: Date
    ) -> [EvidenceEvent] {
        Grading.evidence(
            for: problem, outcome: .missed, in: graph, at: now, localizedTo: id)
    }
}
