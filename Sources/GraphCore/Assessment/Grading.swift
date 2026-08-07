import Foundation

/// How well the solver did, in the vocabulary the problem sheet actually shows.
///
/// This is the problem-instrument counterpart of `SelfReportConfidence`, and the
/// one difference is the whole point of Phase 8: **`missed` exists.** A self-report
/// has no "I don't know this" (D6.3) because claiming ignorance would write FSRS
/// state onto an unlearned node and silently delete it from the frontier. A missed
/// *problem* is different in kind: it is a measurement, and §5.4 gives it
/// somewhere to go — diagnosis, which decides which node the failure lands on
/// before any state is written.
public enum ProblemOutcome: String, Codable, Hashable, Sendable, CaseIterable {
    /// Could not do it, or got it wrong. Opens diagnosis (§5.4) rather than
    /// writing evidence directly.
    case missed
    /// Got there, but slowly or with hints.
    case struggled
    /// Solved it.
    case solved
    /// Solved it immediately.
    case fluent

    public var grade: Grade {
        switch self {
        case .missed: .again
        case .struggled: .hard
        case .solved: .good
        case .fluent: .easy
        }
    }

    public var isPass: Bool { grade.isPass }

    public var title: String {
        switch self {
        case .missed: "Missed"
        case .struggled: "Struggled"
        case .solved: "Solved"
        case .fluent: "Fluent"
        }
    }

    public var detail: String {
        switch self {
        case .missed: "I couldn't do it, or my answer was wrong."
        case .struggled: "I got there, but slowly or with a hint."
        case .solved: "I solved it and met the rubric."
        case .fluent: "I saw it immediately."
        }
    }
}

/// §5.2: "Grading a problem emits evidence for all tagged nodes — full grade for
/// targets, implicit boosts for exercised nodes."
///
/// The subtlety that makes this its own type rather than a loop over
/// `Propagation.expanded`: a problem has *many* targets, and every target
/// propagates into an overlapping ancestry. Expanding per target and concatenating
/// would emit several implicit events for the same ancestor at the same instant,
/// and `ScoreFold` applies each one — the interpolation compounds and stability
/// overshoots what any single review could have produced. So the expansion is
/// **joint**: one implicit event per non-target node, carrying the *minimum* depth
/// over all targets (the shortest route wins, matching `Propagation`'s own
/// breadth-first damping rule).
public enum Grading {
    /// The evidence one graded problem produces, in fold order — exactly what
    /// should be appended to the log.
    ///
    /// - Parameter localizedTo: §5.4. On a **miss**, the failure lands on this node
    ///   alone and nothing else is emitted: "the failure evidence lands on the
    ///   localized node, not automatically on the whole chain". Pass `nil` for a
    ///   miss that has not been localized yet — the result is empty, and
    ///   `Diagnosis` is what the caller should run instead.
    public static func evidence(
        for problem: Problem,
        outcome: ProblemOutcome,
        in graph: KnowledgeGraph,
        at now: Date,
        localizedTo: NodeID? = nil,
        config: ScoringConfig = ScoringConfig()
    ) -> [EvidenceEvent] {
        guard outcome.isPass else {
            return failure(problem, at: now, localizedTo: localizedTo, in: graph)
        }

        let grade = outcome.grade
        let targets = problem.targets.filter { graph[$0]?.kind.isContent == true }
        guard !targets.isEmpty else { return [] }

        // Full grade for every target (§5.2).
        var events = targets.map {
            EvidenceEvent(
                at: now, target: .node($0), grade: grade, source: .test, problem: problem.id.rawValue)
        }

        // §4.4: the only writer of edge evidence in the system. An edge is scored
        // exactly when a problem says it worked the connection.
        let edgeKeys = Set(graph.relatesEdges.map(\.key))
        events += problem.connects.filter(edgeKeys.contains).sorted().map {
            EvidenceEvent(
                at: now, target: .edge($0), grade: grade, source: .test,
                problem: problem.id.rawValue)
        }

        events += implicitEvents(
            for: problem, targets: targets, grade: grade, in: graph, at: now, config: config)
        return events.sorted(by: EvidenceEvent.foldOrder)
    }

    /// One implicit event per non-target node, min-depth across every target.
    ///
    /// Depth 0 — full strength "regardless of graph distance" (§4.3) — for the
    /// nodes the problem names as exercised; shortest `requires`-hop distance from
    /// the nearest target otherwise, capped at `D_max`.
    static func implicitEvents(
        for problem: Problem,
        targets: [NodeID],
        grade: Grade,
        in graph: KnowledgeGraph,
        at now: Date,
        config: ScoringConfig
    ) -> [EvidenceEvent] {
        let targetSet = Set(targets)
        var depthByNode: [NodeID: Int] = [:]
        // The target a node was reached from, so the event stays auditable: `origin`
        // has to name one node, and the nearest target is the one that earned it.
        var originByNode: [NodeID: NodeID] = [:]

        func offer(_ id: NodeID, depth: Int, origin: NodeID) {
            guard !targetSet.contains(id), graph.contains(id) else { return }
            let existing = depthByNode[id]
            // Strictly-better depth wins; equal depth breaks toward the smaller
            // origin id so a multi-target problem expands identically every run.
            if existing == nil || depth < existing! || (depth == existing! && origin < originByNode[id]!) {
                depthByNode[id] = depth
                originByNode[id] = origin
            }
        }

        // Nearest target first, so an exercised node that is *also* within D_max of
        // some target still records the target it is closest to.
        for target in targets.sorted() {
            for reached in graph.requiresAncestorsByDepth(
                of: target, maxDepth: config.maxPropagationDepth)
            {
                offer(reached.id, depth: reached.depth, origin: target)
            }
        }
        // Depth 0 overrides anything the traversal found — that is what "regardless
        // of graph distance" means. The origin is kept if the traversal already
        // attributed the node to a target; otherwise it is the nearest target that
        // actually depends on it, so a reader of the log can see why the credit
        // was owed.
        let sortedTargets = targets.sorted()
        for node in problem.exercises {
            let origin =
                originByNode[node]
                ?? sortedTargets.first { graph.requiresAncestors(of: $0).contains(node) }
                ?? sortedTargets[0]
            offer(node, depth: 0, origin: origin)
        }

        return depthByNode.map { node, depth in
            EvidenceEvent(
                at: now,
                target: .node(node),
                grade: grade,
                source: .implicit,
                problem: problem.id.rawValue,
                origin: originByNode[node],
                depth: depth,
                weight: config.propagationWeight(depth: depth))
        }
    }

    /// §5.4 + §4.3: a miss is evidence about *one* node, and which one is a question
    /// diagnosis answers. Nothing propagates — "failure propagates as a flag for
    /// retesting, not as a penalty", and the retest flag is `Diagnosis.chain`.
    private static func failure(
        _ problem: Problem,
        at now: Date,
        localizedTo: NodeID?,
        in graph: KnowledgeGraph
    ) -> [EvidenceEvent] {
        guard let localizedTo, graph[localizedTo]?.kind.isContent == true else { return [] }
        return [
            EvidenceEvent(
                at: now, target: .node(localizedTo), grade: .again, source: .test,
                problem: problem.id.rawValue)
        ]
    }
}
