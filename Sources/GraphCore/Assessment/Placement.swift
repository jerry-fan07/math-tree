import Foundation

/// Constants for §5.3's adaptive placement. Separate from `ScoringConfig` because
/// none of these touch the memory model — they are the *probing policy*, and §11.3
/// applies to them at least as much as to γ: they are the current hypothesis, not
/// fitted values.
public struct PlacementConfig: Hashable, Sendable {
    /// Belief for a node the seed says nothing about.
    public var prior: Double
    /// Belief floor for the claimed set and everything it transitively requires.
    public var seedKnown: Double
    /// Belief ceiling for everything that transitively requires the claimed set —
    /// "started real analysis" implies not yet finished it.
    public var seedUnknown: Double
    /// §5.3: "A pass raises the inferred probability of *all* `requires`-ancestors."
    /// Flat rather than depth-damped, because that is what the sentence says: you
    /// cannot apply the MVT without limits, however many hops away limits sit.
    public var inferredFromPass: Double
    /// Belief ceiling for everything that transitively requires a failed node.
    public var inferredFromFail: Double
    /// Belief ceiling for the target of a miss that localized to a *prerequisite*.
    /// The problem was still missed, so the target is doubtful — but the user said
    /// the gap was elsewhere, so it is not measured as failed.
    public var displacedTarget: Double
    /// At or above this, the node counts as resolved-known and probing moves on.
    public var resolveKnown: Double
    /// At or below this, resolved-unknown.
    public var resolveUnknown: Double
    /// Hard cap on probes, so a session always terminates.
    public var maxProbes: Int
    /// The grade committed inferred evidence carries. Neutral by construction:
    /// inference says *whether* the user knows something, never how fluently.
    public var inferredGrade: Grade

    public init(
        prior: Double = 0.5,
        seedKnown: Double = 0.75,
        seedUnknown: Double = 0.30,
        inferredFromPass: Double = 0.90,
        inferredFromFail: Double = 0.10,
        displacedTarget: Double = 0.35,
        resolveKnown: Double = 0.85,
        resolveUnknown: Double = 0.15,
        maxProbes: Int = 24,
        inferredGrade: Grade = .good
    ) {
        self.prior = prior
        self.seedKnown = seedKnown
        self.seedUnknown = seedUnknown
        self.inferredFromPass = inferredFromPass
        self.inferredFromFail = inferredFromFail
        self.displacedTarget = displacedTarget
        self.resolveKnown = resolveKnown
        self.resolveUnknown = resolveUnknown
        self.maxProbes = maxProbes
        self.inferredGrade = inferredGrade
    }
}

/// What the user coarsely claims before any probing — §5.3 step 1, "finished
/// multivariable calc, started real analysis".
///
/// Claims may name structural nodes: "finished single-variable calculus" is
/// `analysis.svc`, and expanding it to its `contains` descendants is the whole
/// reason a subbranch is a legal claim. Empty is legal too — placement then starts
/// from the uniform prior, which is slower but not wrong.
public struct PlacementSeed: Codable, Hashable, Sendable {
    public var claimed: [NodeID]

    public init(claimed: [NodeID] = []) {
        self.claimed = claimed
    }

    /// The claimed set as content nodes: structural claims expand through
    /// `contains`, content claims stand for themselves.
    public func expanded(in graph: KnowledgeGraph) -> [NodeID] {
        var out: Set<NodeID> = []
        var stack = claimed.filter(graph.contains)
        var seen: Set<NodeID> = Set(stack)
        while let id = stack.popLast() {
            guard let node = graph[id] else { continue }
            if node.kind.isContent {
                out.insert(id)
                continue
            }
            for child in graph.containedChildren(of: id) where seen.insert(child).inserted {
                stack.append(child)
            }
        }
        return out.sorted()
    }
}

/// One answered probe. This is the session's only mutable content — belief is
/// *replayed* from the seed plus these, never stored, for exactly the reason
/// `ScoreStore` refolds instead of updating (D6.5): the derived thing must have
/// one derivation, or resuming and continuing can disagree.
public struct ProbeAnswer: Codable, Hashable, Sendable {
    public var problem: ProblemID
    /// The node the probe measured — the problem's target that placement chose it
    /// for. Recorded rather than re-derived because a problem may have several
    /// targets and the session's belief update is about this one.
    public var node: NodeID
    public var outcome: ProblemOutcome
    public var at: Date
    /// §5.4: where a miss was localized, when it was. `nil` on a miss means the
    /// user attributed the failure to the probed node itself.
    public var localizedTo: NodeID?

    public init(
        problem: ProblemID,
        node: NodeID,
        outcome: ProblemOutcome,
        at: Date,
        localizedTo: NodeID? = nil
    ) {
        self.problem = problem
        self.node = node
        self.outcome = outcome
        self.at = at
        self.localizedTo = localizedTo
    }

    /// Where the failure actually landed — the localized node, or the probed node.
    var failedNode: NodeID { localizedTo ?? node }

    /// Every node this answer is a measurement of: all the problem's targets, since
    /// `Grading.evidence` writes a full graded review on each of them (§5.2).
    /// Falls back to the probed node when the bank is unavailable.
    func measuredNodes(in bank: ProblemBank?) -> [NodeID] {
        guard let targets = bank?[problem]?.targets, !targets.isEmpty else { return [node] }
        return targets.contains(node) ? targets : targets + [node]
    }
}

/// A resumable placement session (§5.3: "Placement is optional and resumable").
///
/// Value type, `Codable`, and complete: seed + answers is everything. The app
/// persists it next to the evidence log and can drop it on the floor at any point
/// without corrupting anything — the probes already wrote their own evidence.
public struct PlacementSession: Codable, Hashable, Sendable {
    public var seed: PlacementSeed
    public var answers: [ProbeAnswer]
    /// Set when the session was committed, so a resumed session does not commit
    /// its inferred evidence twice.
    public var committedAt: Date?

    public init(
        seed: PlacementSeed = PlacementSeed(),
        answers: [ProbeAnswer] = [],
        committedAt: Date? = nil
    ) {
        self.seed = seed
        self.answers = answers
        self.committedAt = committedAt
    }

    public var isCommitted: Bool { committedAt != nil }

    public mutating func record(_ answer: ProbeAnswer) {
        answers.append(answer)
    }
}

/// §5.3's adaptive probing over the DAG, as a pure function of session + graph +
/// bank. Nothing here is stateful and nothing here writes: `Placement.belief`
/// replays a session, `Placement.nextProbe` reads a belief, and
/// `Placement.inferredEvidence` turns a finished belief into log events.
public enum Placement {
    /// The inferred picture at some point in a session.
    public struct Belief: Sendable {
        /// Modelled probability the user knows each *content* node.
        public var probability: [NodeID: Double]
        /// Nodes a probe measured directly — certainty, not inference.
        public var tested: Set<NodeID>
        /// For each inferred-known node, the probe that raised it. Kept so the
        /// committed evidence can name an `origin` and stay auditable (D5.5's rule
        /// applies to anything that lands in the log).
        public var inferredFrom: [NodeID: (origin: NodeID, problem: ProblemID)]
        let config: PlacementConfig

        public func probability(of id: NodeID) -> Double { probability[id] ?? config.prior }

        public func isResolved(_ id: NodeID) -> Bool {
            tested.contains(id) || probability(of: id) >= config.resolveKnown
                || probability(of: id) <= config.resolveUnknown
        }

        public func isKnown(_ id: NodeID) -> Bool { probability(of: id) >= config.resolveKnown }

        /// Everything the session concluded is known, sorted.
        public var known: [NodeID] {
            probability.filter { $0.value >= config.resolveKnown }.keys.sorted()
        }

        /// Everything it concluded is not known, sorted.
        public var unknown: [NodeID] {
            probability.filter { $0.value <= config.resolveUnknown }.keys.sorted()
        }

        /// Everything it could not settle — reported rather than rounded, because
        /// an unprobeable node (no problem in the bank targets it) can end here
        /// through no fault of the policy.
        public var unresolved: [NodeID] {
            probability.keys.filter { !isResolved($0) }.sorted()
        }

        /// The knowledge boundary: known nodes with at least one dependent that is
        /// not known. This is what §5.3 converges *to*, and the thing an exit
        /// criterion can compare against a seeded persona.
        public func boundary(in graph: KnowledgeGraph) -> [NodeID] {
            known.filter { id in
                let dependents = graph.dependents(of: id)
                    .filter { graph[$0]?.kind.isContent == true }
                return dependents.contains { !isKnown($0) }
            }
        }
    }

    // MARK: Belief

    /// Replay a session into a belief. Deterministic and total: same session, same
    /// graph, same bank, same belief, every time.
    ///
    /// - Parameter bank: when supplied, a probe is credited with **every** target
    ///   of the problem asked, not only the node placement chose it for. This is
    ///   not a refinement — it is required for the belief to agree with the map.
    ///   `Grading.evidence` writes a full graded review on every target (§5.2), so
    ///   a session that recorded only `answer.node` would leave the belief calling
    ///   a node unknown that the evidence log had just recorded as learned. Passing
    ///   the bank is therefore the correct call, and the parameter is optional only
    ///   because the graph alone is enough when every problem has one target.
    public static func belief(
        for session: PlacementSession,
        graph: KnowledgeGraph,
        bank: ProblemBank? = nil,
        config: PlacementConfig = PlacementConfig()
    ) -> Belief {
        var probability: [NodeID: Double] = [:]
        for node in graph.nodes where node.kind.isContent {
            probability[node.id] = config.prior
        }

        // Step 1: the claimed frontier. Everything the claim transitively requires
        // is claimed too; everything that requires it is not yet claimed.
        let claimed = session.seed.expanded(in: graph)
        var seeded = Set(claimed)
        for id in claimed { seeded.formUnion(graph.requiresAncestors(of: id)) }
        for id in seeded where probability[id] != nil {
            probability[id] = max(probability[id]!, config.seedKnown)
        }
        for id in claimed {
            for descendant in graph.requiresDescendants(of: id) where !seeded.contains(descendant) {
                guard probability[descendant] != nil else { continue }
                probability[descendant] = min(probability[descendant]!, config.seedUnknown)
            }
        }

        // Step 2: the probes, in the order they were answered.
        var tested: Set<NodeID> = []
        var inferredFrom: [NodeID: (origin: NodeID, problem: ProblemID)] = [:]

        for answer in session.answers {
            guard probability[answer.node] != nil else { continue }
            // Everything the problem graded, not just the node placement picked it
            // for — see the `bank` parameter's note.
            let measured = answer.measuredNodes(in: bank).filter { probability[$0] != nil }

            if answer.outcome.isPass {
                for node in measured {
                    probability[node] = 1
                    tested.insert(node)
                }
                for node in measured {
                    for ancestor in graph.requiresAncestors(of: node) {
                        guard probability[ancestor] != nil, !tested.contains(ancestor) else {
                            continue
                        }
                        if config.inferredFromPass > probability[ancestor]! {
                            probability[ancestor] = config.inferredFromPass
                            inferredFrom[ancestor] = (origin: node, problem: answer.problem)
                        }
                    }
                }
            } else {
                let failed = answer.failedNode
                guard probability[failed] != nil else { continue }
                probability[failed] = 0
                tested.insert(failed)
                inferredFrom[failed] = nil
                // Anything that requires a node the user does not have cannot be
                // known either — this is what "a fail pushes probing down toward
                // prerequisites" looks like from the belief side.
                for descendant in graph.requiresDescendants(of: failed) {
                    guard probability[descendant] != nil, !tested.contains(descendant) else {
                        continue
                    }
                    probability[descendant] = min(probability[descendant]!, config.inferredFromFail)
                    inferredFrom[descendant] = nil
                }
                // A miss localized to a prerequisite leaves every target of the
                // problem doubtful but unmeasured: the problem was missed, but the
                // user said the reason was elsewhere.
                for node in measured where node != failed && !tested.contains(node) {
                    probability[node] = min(probability[node]!, config.displacedTarget)
                    inferredFrom[node] = nil
                }
            }
        }

        return Belief(
            probability: probability, tested: tested, inferredFrom: inferredFrom, config: config)
    }

    // MARK: Probe selection

    /// What to ask next, or `nil` when the session is done.
    ///
    /// §5.3's "binary-search style" made literal: over a DAG, the bisecting probe
    /// is the unresolved node that splits the *unresolved* poset most evenly, since
    /// a pass resolves everything below it and a fail resolves everything above.
    /// Score is `min(unresolved strict ancestors, unresolved strict descendants)`,
    /// which is maximised in the middle of the longest unresolved chain.
    ///
    /// Ties break toward maximum uncertainty (`|p − 0.5|` smallest) and then by id,
    /// so a session is reproducible — the exit criterion counts probes, and a
    /// selection that depended on dictionary order would make that number noise.
    public static func nextProbe(
        for session: PlacementSession,
        graph: KnowledgeGraph,
        bank: ProblemBank,
        config: PlacementConfig = PlacementConfig()
    ) -> (node: NodeID, problem: Problem)? {
        guard session.answers.count < config.maxProbes else { return nil }
        let belief = belief(for: session, graph: graph, bank: bank, config: config)
        return nextProbe(given: belief, session: session, graph: graph, bank: bank, config: config)
    }

    static func nextProbe(
        given belief: Belief,
        session: PlacementSession,
        graph: KnowledgeGraph,
        bank: ProblemBank,
        config: PlacementConfig
    ) -> (node: NodeID, problem: Problem)? {
        let asked = Set(session.answers.map(\.problem))
        let unresolved = Set(belief.unresolved)
        guard !unresolved.isEmpty else { return nil }

        var best: (node: NodeID, problem: Problem, score: Int, uncertainty: Double)?
        // Ascending id, and replace only on a strict improvement — that is the id
        // tie-break, without needing it in the comparison.
        for id in unresolved.sorted() {
            // A node the bank cannot ask about is not a probe candidate; inference
            // is its only route to being resolved.
            guard let problem = bank.problems(targeting: id).first(where: { !asked.contains($0.id) })
            else { continue }
            let above = graph.requiresAncestors(of: id).filter(unresolved.contains).count
            let below = graph.requiresDescendants(of: id).filter(unresolved.contains).count
            let score = min(above, below)
            let uncertainty = abs(belief.probability(of: id) - 0.5)
            guard let current = best else {
                best = (id, problem, score, uncertainty)
                continue
            }
            if score > current.score || (score == current.score && uncertainty < current.uncertainty) {
                best = (id, problem, score, uncertainty)
            }
        }
        guard let best else { return nil }
        return (best.node, best.problem)
    }

    // MARK: Commit

    /// §5.3's third clause: "Inferred (untested) knowledge is stored as
    /// low-confidence evidence — ... it decays faster until confirmed by a direct
    /// test."
    ///
    /// One event per inferred-known node that no probe measured directly. They ride
    /// the implicit path in `ScoreFold`, with `confidence` as the weight — which is
    /// the whole of "decays faster": a weight below 1 yields a fraction of the
    /// stability a real review would, so retrievability falls off sooner, and a
    /// later `source: test` event takes the full FSRS branch and replaces it.
    ///
    /// Two things distinguish these from §4.3's propagation events even though both
    /// carry `source: implicit`. They are **not** `D_max`-capped: §5.3 says a pass
    /// raises *all* ancestors, and truncating at three hops would leave the deep
    /// foundations of a claimed curriculum grey forever. And they carry a
    /// `confidence`, which is the discriminator a γ refit must filter on — D5.5's
    /// "drop every implicit event and re-expand" would otherwise destroy them,
    /// since `Propagation.expand` cannot regenerate them.
    public static func inferredEvidence(
        for session: PlacementSession,
        graph: KnowledgeGraph,
        bank: ProblemBank? = nil,
        at now: Date,
        config: PlacementConfig = PlacementConfig()
    ) -> [EvidenceEvent] {
        let belief = belief(for: session, graph: graph, bank: bank, config: config)
        return belief.known
            .filter { !belief.tested.contains($0) }
            .map { id in
                let source = belief.inferredFrom[id]
                return EvidenceEvent(
                    at: now,
                    target: .node(id),
                    grade: config.inferredGrade,
                    confidence: belief.probability(of: id),
                    source: .implicit,
                    problem: source?.problem.rawValue,
                    origin: source?.origin,
                    // No hop distance: this is inference over the whole ancestry,
                    // not a damped review at a measured depth. Leaving `depth` nil
                    // is what says so in the log.
                    depth: nil,
                    weight: nil)
            }
            .sorted(by: EvidenceEvent.foldOrder)
    }

    /// How far along a session is, for the UI's progress read-out and for tests
    /// that want a bound rather than a fixed count.
    public struct Progress: Hashable, Sendable {
        public let probesAnswered: Int
        public let resolved: Int
        public let unresolved: Int
        public let probeable: Int

        public var isComplete: Bool { unresolved == 0 }
        public var fraction: Double {
            let total = resolved + unresolved
            return total == 0 ? 1 : Double(resolved) / Double(total)
        }
    }

    public static func progress(
        for session: PlacementSession,
        graph: KnowledgeGraph,
        bank: ProblemBank,
        config: PlacementConfig = PlacementConfig()
    ) -> Progress {
        let belief = belief(for: session, graph: graph, bank: bank, config: config)
        let unresolved = belief.unresolved
        return Progress(
            probesAnswered: session.answers.count,
            resolved: belief.probability.count - unresolved.count,
            unresolved: unresolved.count,
            probeable: unresolved.filter { !bank.problems(targeting: $0).isEmpty }.count)
    }
}
