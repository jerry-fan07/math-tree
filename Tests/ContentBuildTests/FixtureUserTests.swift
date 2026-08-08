import Foundation
import GraphCore
import Testing

@testable import ContentBuild

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // ContentBuildTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repo root

/// Phase 6's exit criteria, asserted against the real seed content rather than a
/// hand-built mini-graph: the frontier on a fixture user matches hand-computed
/// truth, a deep self-report boosts its ancestors, and the colours a replay
/// produces are identical.
///
/// It lives in `ContentBuildTests` because this is the target that already loads
/// `content/` — the claim is about the shipped graph, not about a fixture of it.
@Suite("Fixture user")
struct FixtureUserTests {
    let graph: KnowledgeGraph
    let config = ScoringConfig()
    let fsrs: FSRS
    let events: [EvidenceEvent]
    let state: ScoreState
    let now = FixtureUser.now

    init() throws {
        let content = try ContentLoader.load(
            root: repoRoot.appendingPathComponent("content"), relativeTo: repoRoot)
        graph = KnowledgeGraph(nodes: content.nodes)
        fsrs = FSRS(parameters: config.fsrs)
        events = FixtureUser.log(in: graph, config: config)
        let folded = ScoreFold.fold(events, graph: graph, config: config)
        #expect(folded.defects.isEmpty, "the fixture log must fold clean: \(folded.defects)")
        state = folded.state
    }

    private func retrievability(_ id: NodeID) -> Double? {
        state.retrievability(of: id, at: now, fsrs: fsrs)
    }

    // MARK: - The state the fixture is in

    /// The facts the frontier assertion below rests on. Written out so that
    /// "hand-computed" means something a reader can check, rather than a list of
    /// ids that happens to match whatever the code did.
    @Test func theFixtureUserIsWhereTheStorySaysTheyAre() throws {
        // Ten nodes were reviewed directly. Before Phase 9 that was the whole of
        // the state, because every `requires`-ancestor of a reviewed node had been
        // reviewed too. Wiring foundations underneath analysis put nine more
        // ancestors inside §4.3's `D_max = 3` window, so they now carry damped
        // implicit state — which is propagation working, not the fixture drifting.
        #expect(state.nodes.count == 10 + 9)
        for id in FixtureUser.explicit.compactMap(\.target.nodeID) {
            #expect(state[id] != nil, "\(id) was reviewed and has no state")
        }

        // Differentiation is solid.
        #expect(try #require(retrievability("analysis.svc.def-derivative")) > 0.99)
        #expect(try #require(retrievability("analysis.svc.def-continuity")) > 0.95)
        #expect(try #require(retrievability("foundations.real.completeness")) > 0.94)

        // The Mean Value Theorem has slipped *just* below τ — 0.838 against 0.85.
        // This is the case that makes the threshold load-bearing rather than
        // decorative, and it is why `zero-deriv-const` is not on the frontier.
        let mvt = try #require(retrievability("analysis.svc.mvt"))
        #expect(mvt < config.masteryThreshold)
        #expect(mvt > 0.80, "still clearly learned — cool green, not grey")

        // Riemann sums went cold in March: badly decayed, at the blue end of §4.5.
        let riemannSum = try #require(retrievability("analysis.svc.def-riemann-sum"))
        #expect(riemannSum < 0.5)
        #expect(ScoreRamp.rampT(forRetrievability: riemannSum) < 0.35)

        // Integration was never started.
        #expect(retrievability("analysis.svc.def-riemann-integral") == nil)
        #expect(retrievability("analysis.svc.ftc-part-2") == nil)
    }

    // MARK: - Frontier

    /// **Exit criterion**: the frontier set matches hand-computed truth.
    ///
    /// By §4.5 a node is on the frontier when it has no state at all and every
    /// direct prerequisite is above τ = 0.85. Walking the twelve unlearned content
    /// nodes of the seed graph:
    ///
    /// | node | prerequisites | verdict |
    /// |---|---|---|
    /// | `mvc.def-partial-derivative` | `def-derivative` 0.99 | **in** |
    /// | `svc.def-antiderivative` | `def-derivative` 0.99 | **in** |
    /// | `svc.intuition-linearization` | `def-derivative` 0.99 | **in** |
    /// | `svc.ivt` | `def-continuity` 0.95, `completeness` 0.95 | **in** |
    /// | `svc.zero-deriv-const` | `mvt` 0.838 | out — below τ |
    /// | `svc.def-riemann-integral` | `def-riemann-sum` 0.484 | out — below τ |
    /// | `svc.cont-integrable` | `def-riemann-integral` unlearned | out |
    /// | `svc.ex-integral-x2` | `def-riemann-integral` unlearned | out |
    /// | `svc.ftc-part-1` | `cont-integrable`, `def-antiderivative` unlearned | out |
    /// | `svc.ftc-part-2` | `ftc-part-1`, `zero-deriv-const` unlearned | out |
    /// | `svc.u-sub` | `ftc-part-2` unlearned | out |
    /// | `mvc.leibniz-rule` | `def-partial-derivative`, `def-riemann-integral` unlearned | out |
    ///
    /// The table walks Appendix A's cone, which is what a reader can check, so that
    /// slice is pinned literally. The whole frontier is pinned differently: as
    /// §4.5's *definition*, recomputed here from the spec rather than taken from
    /// `Frontier`'s internals. A literal list of every id would have to be rewritten
    /// every time a subbranch lands, and would stop being read the second time.
    @Test func frontierMatchesHandComputedTruth() {
        let frontier = Set(Frontier.compute(graph: graph, state: state, at: now, config: config))

        #expect(
            frontier.filter { $0.rawValue.hasPrefix("analysis.") }.sorted() == [
                "analysis.mvc.def-partial-derivative",
                "analysis.svc.def-antiderivative",
                "analysis.svc.intuition-linearization",
                "analysis.svc.ivt",
            ])

        // §4.5: unlearned, with every direct prerequisite at or above τ. Vacuously
        // true for a root, which is why the foundations roots the fixture user has
        // never touched belong here — they are exactly "what you could learn next".
        let expected = Set(
            graph.nodes
                .filter { $0.kind.isContent && !state.isLearned($0.id) }
                .filter { node in
                    graph.prerequisites(of: node.id).allSatisfy { prerequisite in
                        state.isLearned(prerequisite)
                            && (retrievability(prerequisite) ?? 0) >= config.masteryThreshold
                    }
                }
                .map(\.id))
        #expect(frontier == expected, "extra: \(frontier.subtracting(expected).sorted())")
    }

    /// The two exclusions that are *not* "a prerequisite is unlearned" — the ones
    /// τ decides. Asserted separately so a change to τ fails here, loudly, rather
    /// than quietly shifting the list above.
    @Test func theThresholdIsWhatKeepsTwoNodesOff() throws {
        let frontier = Set(Frontier.compute(graph: graph, state: state, at: now, config: config))
        #expect(!frontier.contains("analysis.svc.zero-deriv-const"))
        #expect(!frontier.contains("analysis.svc.def-riemann-integral"))

        // Lower τ under the MVT's 0.838 and its dependent appears; nothing else
        // moves, because every other exclusion is an unlearned prerequisite.
        var relaxed = config
        relaxed.masteryThreshold = 0.80
        let widened = Set(Frontier.compute(graph: graph, state: state, at: now, config: relaxed))
        #expect(widened.contains("analysis.svc.zero-deriv-const"))
        #expect(widened.subtracting(frontier) == ["analysis.svc.zero-deriv-const"])
    }

    /// Structural nodes are never actionable (§2.1), whatever their subtree does.
    @Test func structuralNodesAreNeverOnTheFrontier() {
        let frontier = Set(Frontier.compute(graph: graph, state: state, at: now, config: config))
        for node in graph.nodes where node.kind.isStructural {
            #expect(!frontier.contains(node.id), "\(node.id)")
        }
    }

    // MARK: - Scheduler

    /// The sidebar's list is FSRS's own schedule, not the τ threshold.
    @Test func theDueListIsTheSchedulerReadOut() {
        let due = ReviewQueue.due(graph: graph, state: state, at: now, config: config)
        // Appendix A's two: the Riemann sum that went cold in March and the MVT.
        #expect(
            due.map(\.id).filter { $0.rawValue.hasPrefix("analysis.") }
                == ["analysis.svc.def-riemann-sum", "analysis.svc.mvt"])
        // Everything else owed is a foundations node that acquired state only by
        // propagation. A damped implicit review on a node with no history grants a
        // *fraction* of a first review's stability, so it comes due almost at once
        // — §4.3 working as written, and the reason a deep prerequisite chain fills
        // the queue the moment anything above it is reviewed.
        for review in due where !review.id.rawValue.hasPrefix("analysis.") {
            #expect(review.id.rawValue.hasPrefix("foundations."))
            #expect(!FixtureUser.explicit.compactMap(\.target.nodeID).contains(review.id))
        }
        #expect(due.allSatisfy { $0.due <= now })

        let upcoming = ReviewQueue.upcoming(graph: graph, state: state, at: now, config: config)
        #expect(upcoming.count == state.nodes.count - due.count)
        #expect(upcoming.allSatisfy { $0.due > now })
        // Most overdue first: March beats July.
        #expect(due.first?.due ?? now < (due.last?.due ?? now))
    }

    // MARK: - Propagation

    /// **Exit criterion**: a self-report on a deep node visibly boosts its
    /// ancestors. FTC Part II sits three `requires`-hops above the derivative, so
    /// one report reaches nine nodes the user never touched.
    @Test func aDeepSelfReportBoostsItsAncestors() throws {
        let after = ScoreFold.fold(
            FixtureUser.reviewedLog(in: graph, config: config), graph: graph, config: config
        ).state

        func recall(_ id: NodeID) -> Double? {
            after.retrievability(of: id, at: now, fsrs: fsrs)
        }

        // Six ancestors had no state at all and now have one — grey to coloured,
        // which is the change that is actually visible on the map.
        for id: NodeID in [
            "analysis.svc.ftc-part-2", "analysis.svc.ftc-part-1",
            "analysis.svc.zero-deriv-const", "analysis.svc.cont-integrable",
            "analysis.svc.def-antiderivative", "analysis.svc.def-riemann-integral",
        ] {
            #expect(state[id] == nil, "\(id) starts unlearned")
            #expect(recall(id) != nil, "\(id) is learned after the report")
        }

        // Already-learned ancestors are lifted, never lowered (§4.3).
        for id: NodeID in ["analysis.svc.mvt", "analysis.svc.rolle", "analysis.svc.def-derivative"] {
            let before = try #require(retrievability(id))
            #expect(try #require(recall(id)) > before, "\(id)")
        }
        // The MVT crosses τ, so `zero-deriv-const`'s exclusion is lifted too — the
        // frontier advances, which is propagation made visible in the UI.
        #expect(try #require(recall("analysis.svc.mvt")) > config.masteryThreshold)

        // D_max = 3: everything four or more hops up is untouched. Without the cap
        // one report would repaint the entire graph.
        for id: NodeID in [
            "analysis.svc.def-limit", "analysis.svc.diff-implies-cont", "analysis.svc.evt",
            "analysis.svc.def-riemann-sum", "foundations.real.completeness",
            "foundations.real.sup-inf",
        ] {
            #expect(after[id] == state[id], "\(id) is beyond D_max and must not move")
        }
    }

    @Test func theReportedFrontierAdvances() {
        let after = ScoreFold.fold(
            FixtureUser.reviewedLog(in: graph, config: config), graph: graph, config: config
        ).state
        let before = Set(Frontier.compute(graph: graph, state: state, at: now, config: config))
        let widened = Set(Frontier.compute(graph: graph, state: after, at: now, config: config))
        // Learning something removes it from the frontier and opens what it unlocks.
        #expect(!widened.contains("analysis.svc.def-antiderivative"))
        #expect(widened.contains("analysis.svc.u-sub"))
        #expect(widened.contains("analysis.svc.ex-integral-x2"))
        #expect(widened != before)
    }

    // MARK: - Determinism

    /// **Exit criterion**: relaunching reproduces identical colours. A relaunch is
    /// a re-read of the log and a refold, so this asserts the whole chain the app
    /// walks — log → fold → retrievability → §4.5 — down to the hex the renderer packs.
    @Test func replayReproducesIdenticalColours() {
        func colours(_ events: [EvidenceEvent]) -> [NodeID: String] {
            let state = ScoreFold.fold(events, graph: graph, config: config).state
            return Dictionary(
                uniqueKeysWithValues: graph.nodes.filter { $0.kind.isContent }.map { node in
                    (node.id, ScoreRamp.color(for: state[node.id], at: now, fsrs: fsrs).hex)
                })
        }

        let first = colours(events)
        #expect(first == colours(events))
        // Arrival order must not matter either — the fold sorts by content (D5.7).
        #expect(first == colours(events.reversed()))
        #expect(first == colours(events.shuffled()))

        // And the fixture really does span §4.5's ramp, so this is not vacuous.
        #expect(Set(first.values).count > 3)
        #expect(first["analysis.svc.ftc-part-2"] == ScoreRamp.unlearned.hex)
        #expect(first["analysis.svc.def-riemann-sum"] != ScoreRamp.unlearned.hex)
    }

    // MARK: - Golden logs

    /// `fixtures/*.jsonl` are what the app reads under `MATHTREE_EVIDENCE_LOG`, so
    /// they must stay in step with `FixtureUser`. Regenerate with
    /// `MATHTREE_UPDATE_FIXTURES=1 swift test`.
    @Test func goldenLogsMatchTheFixtureDefinition() throws {
        try check(FixtureUser.log(in: graph, config: config), "fixture-user.jsonl")
        try check(FixtureUser.reviewedLog(in: graph, config: config), "fixture-user-reviewed.jsonl")
    }

    private func check(_ events: [EvidenceEvent], _ name: String) throws {
        let expected = try encode(events)
        let url = repoRoot.appendingPathComponent("fixtures").appendingPathComponent(name)

        if ProcessInfo.processInfo.environment["MATHTREE_UPDATE_FIXTURES"] != nil {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try expected.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        let actual = try String(contentsOf: url, encoding: .utf8)
        #expect(
            actual == expected,
            "fixtures/\(name) is stale — regenerate with MATHTREE_UPDATE_FIXTURES=1 swift test")
    }

    /// Round-trips through `EvidenceLog` rather than a local encoder, so the golden
    /// file is byte-for-byte what the app would have written.
    private func encode(_ events: [EvidenceEvent]) throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fixture-\(UUID().uuidString)")
            .appendingPathComponent("evidence.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try EvidenceLog(url: url).append(events)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
