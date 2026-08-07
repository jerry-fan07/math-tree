import Foundation

/// One node the scheduler has something to say about.
public struct ScheduledReview: Hashable, Sendable, Comparable {
    public let id: NodeID
    /// When FSRS expects retrievability to reach the desired retention.
    public let due: Date
    /// Retrievability right now (§4.1) — the colour the node is wearing.
    public let retrievability: Double
    public let memory: MemoryState

    public init(id: NodeID, due: Date, retrievability: Double, memory: MemoryState) {
        self.id = id
        self.due = due
        self.retrievability = retrievability
        self.memory = memory
    }

    /// Most overdue first, ties broken by id so the queue is a stable list rather
    /// than whatever order the state dictionary happened to hash into.
    public static func < (lhs: ScheduledReview, rhs: ScheduledReview) -> Bool {
        if lhs.due != rhs.due { return lhs.due < rhs.due }
        return lhs.id < rhs.id
    }

    public func isDue(at now: Date) -> Bool { due <= now }
}

/// §5.4: "the FSRS scheduler surfaces due reviews" — the sidebar's data source.
///
/// This is the **scheduler** read-out (`nextDue`), which is not the same question
/// as `Frontier.due`'s: that one asks "has retrievability fallen past τ", a
/// property of the colour ramp. FSRS schedules against its own desired retention
/// (0.9 by default) rather than against τ (0.85), so the two lists differ at the
/// margin — deliberately. The scheduler decides *when to review*; τ decides *what
/// counts as mastered* for the frontier.
///
/// Only nodes are queued. `relates` edges carry FSRS state too (§4.4), but an
/// edge review happens when a problem exercises the connection, and problems are
/// Phase 8 — a self-report on an edge would be evidence about nothing the user
/// was actually asked.
public enum ReviewQueue {
    /// Every node with FSRS state, scheduled, most overdue first.
    public static func all(
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> [ScheduledReview] {
        let fsrs = FSRS(parameters: config.fsrs)
        return state.nodes
            .compactMap { id, memory -> ScheduledReview? in
                // Structural nodes are not learnable (§2.1); ids the content no
                // longer defines are stale log entries, not review candidates.
                guard let node = graph[id], node.kind.isContent else { return nil }
                return ScheduledReview(
                    id: id,
                    due: fsrs.nextDue(after: memory),
                    retrievability: fsrs.retrievability(of: memory, at: now),
                    memory: memory)
            }
            .sorted()
    }

    /// Reviews the scheduler says are owed now.
    public static func due(
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> [ScheduledReview] {
        all(graph: graph, state: state, at: now, config: config).filter { $0.isDue(at: now) }
    }

    /// Reviews not yet owed, soonest first — the "nothing due" case still has
    /// something honest to show.
    public static func upcoming(
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        limit: Int? = nil,
        config: ScoringConfig = ScoringConfig()
    ) -> [ScheduledReview] {
        let pending = all(graph: graph, state: state, at: now, config: config)
            .filter { !$0.isDue(at: now) }
        guard let limit else { return pending }
        return Array(pending.prefix(limit))
    }
}
