import Foundation

/// How much of one subject the user holds — §6.5's read-out, for the list you pick
/// a subject *from*. `FocusPlan` answers "what is the path through this one"; this
/// answers "which one should I open", which is a different question and is asked
/// about every subject at once.
public struct SubjectSummary: Hashable, Sendable {
    public let id: NodeID
    /// Content nodes the subject contains, at any depth (§2.3's `contains` DAG).
    public let total: Int
    /// How many of them are met, in `Frontier`'s exact sense (§4.5).
    public let met: Int

    public init(id: NodeID, total: Int, met: Int) {
        self.id = id
        self.total = total
        self.met = met
    }

    /// Zero for a subject with no content authored yet — which is *not* the same
    /// as zero progress, and the two are distinguished by `isAuthored`.
    public var fraction: Double { total == 0 ? 0 : Double(met) / Double(total) }

    /// §7.1 fixes the outline before the content, so most of the map is subbranches
    /// with nothing in them. A subject with no nodes has no path.
    public var isAuthored: Bool { total > 0 }

    public var isComplete: Bool { total > 0 && met == total }
}

public enum Subjects {
    /// Every top-level branch, summarized. Sorted by id — deterministic; display
    /// order is the caller's business.
    public static func branches(
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> [SubjectSummary] {
        summarize(graph.branches, graph: graph, state: state, at: now, config: config)
    }

    public static func summarize(
        _ ids: [NodeID],
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> [SubjectSummary] {
        let fsrs = FSRS(parameters: config.fsrs)
        func isMet(_ id: NodeID) -> Bool {
            guard state.isLearned(id), let memory = state.nodes[id] else { return false }
            return fsrs.retrievability(of: memory, at: now) > config.masteryThreshold
        }
        return ids.sorted().map { id in
            let contents = graph.contentDescendants(of: id)
            return SubjectSummary(
                id: id, total: contents.count, met: contents.filter(isMet).count)
        }
    }
}
