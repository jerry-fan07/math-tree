import Foundation
import GraphCore
import Testing

@testable import ContentBuild

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // ContentBuildTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repo root

/// Phase 7's exit criterion against the real seed content: "for fixture users
/// with varying knowledge states, the syllabus order is a valid topological order
/// and omits exactly the met prerequisites."
///
/// Three knowledge states, one goal — `analysis.svc.ftc-part-2`, the node whose
/// ancestry spans the whole seed graph: a fresh user (empty log), the fixture
/// user, and the fixture user after the deep FTC self-report. Every expected
/// list below is hand-derived from the `requires` edges in `content/` and the
/// retrievabilities `FixtureUserTests` already pins (MVT 0.838, Riemann sums
/// 0.484, differentiation ≥ 0.95).
@Suite("Focus plan on fixture users")
struct FocusFixtureTests {
    let graph: KnowledgeGraph
    let config = ScoringConfig()
    let now = FixtureUser.now
    let goal: NodeID = "analysis.svc.ftc-part-2"

    init() throws {
        let content = try ContentLoader.load(
            root: repoRoot.appendingPathComponent("content"), relativeTo: repoRoot)
        graph = KnowledgeGraph(nodes: content.nodes)
    }

    private func state(_ events: [EvidenceEvent]) -> ScoreState {
        ScoreFold.fold(events, graph: graph, config: config).state
    }

    private func plan(over state: ScoreState) throws -> FocusPlan {
        try #require(
            FocusPlan.compute(goal: goal, graph: graph, state: state, at: now, config: config))
    }

    /// Independent check of the exit criterion's two clauses, shared by every
    /// scenario: the syllabus is exactly the unmet ancestors (met = state exists
    /// and retrievability strictly above τ, mirroring `Frontier`), in an order
    /// that respects the transitive `requires` relation.
    private func assertCriterion(_ plan: FocusPlan, state: ScoreState) {
        let fsrs = FSRS(parameters: config.fsrs)
        let expectedUnmet = Set(
            graph.requiresAncestors(of: goal).filter { id in
                guard let memory = state.nodes[id] else { return true }
                return fsrs.retrievability(of: memory, at: now) <= config.masteryThreshold
            })
        #expect(Set(plan.syllabus) == expectedUnmet, "omits exactly the met prerequisites")

        for (index, id) in plan.syllabus.enumerated() {
            for ancestor in graph.requiresAncestors(of: id)
            where plan.syllabus.contains(ancestor) {
                #expect(
                    plan.syllabus.firstIndex(of: ancestor)! < index,
                    "\(ancestor) must precede \(id)")
            }
        }
    }

    /// A fresh user must be told the whole ancestry, root first.
    @Test func freshUserSyllabusIsTheFullAncestry() throws {
        let empty = ScoreState()
        let plan = try plan(over: empty)
        assertCriterion(plan, state: empty)

        // (layer, id) over the requires DAG of content/: sup-inf is the root;
        // completeness/def-limit/def-riemann-sum hang directly off it; and so on
        // up the two chains (differentiation, integration) that meet at the FTC.
        #expect(
            plan.syllabus == [
                "foundations.real.sup-inf",
                "analysis.svc.def-limit",
                "analysis.svc.def-riemann-sum",
                "foundations.real.completeness",
                "analysis.svc.def-continuity",
                "analysis.svc.def-derivative",
                "analysis.svc.def-riemann-integral",
                "analysis.svc.cont-integrable",
                "analysis.svc.def-antiderivative",
                "analysis.svc.diff-implies-cont",
                "analysis.svc.evt",
                "analysis.svc.ftc-part-1",
                "analysis.svc.rolle",
                "analysis.svc.mvt",
                "analysis.svc.zero-deriv-const",
            ])
        #expect(plan.metBoundary.isEmpty)
        #expect(plan.elidedMetCount == 0)
        #expect(plan.goalIsMet == false)
    }

    /// The fixture user: integration untouched, the MVT *decayed just below τ*
    /// (0.838 vs 0.85, D6.8's deliberately borderline node). The MVT is therefore
    /// in the syllabus even though it was once learned — the single assertion
    /// that exercises the ≤ τ boundary, the "omits exactly" clause and
    /// met/unmet consistency with the frontier at once.
    @Test func fixtureUserSyllabusIsTheIntegrationChainPlusTheDecayed() throws {
        let state = state(FixtureUser.log(in: graph, config: config))
        let plan = try plan(over: state)
        assertCriterion(plan, state: state)

        #expect(
            plan.syllabus == [
                "analysis.svc.def-riemann-sum",  // decayed to 0.484 in March
                "analysis.svc.def-riemann-integral",  // never learned…
                "analysis.svc.cont-integrable",
                "analysis.svc.def-antiderivative",
                "analysis.svc.ftc-part-1",
                "analysis.svc.mvt",  // learned, decayed to 0.838 < τ
                "analysis.svc.zero-deriv-const",
            ])

        // §6.2's compression: the known edge the chain builds on stays visible…
        #expect(
            plan.metBoundary == [
                "analysis.svc.def-continuity",  // under cont-integrable
                "analysis.svc.def-derivative",  // under def-antiderivative
                "analysis.svc.rolle",  // under the decayed MVT
                "foundations.real.sup-inf",  // under def-riemann-sum
            ])
        // …and the four met nodes behind it (def-limit, diff-implies-cont, evt,
        // completeness) are elided but counted.
        #expect(plan.elidedMetCount == 4)
        #expect(plan.goalIsMet == false)
    }

    /// After the deep FTC report, propagation (γᵈ to depth 3) lifts the whole
    /// integration chain and the MVT past τ; only Riemann sums — four hops down,
    /// beyond D_max — stay unmet. The syllabus shrinks to exactly that node.
    @Test func reviewedUserSyllabusShrinksToWhatPropagationMissed() throws {
        let state = state(FixtureUser.reviewedLog(in: graph, config: config))
        let plan = try plan(over: state)
        assertCriterion(plan, state: state)

        #expect(plan.syllabus == ["analysis.svc.def-riemann-sum"])
        #expect(plan.goalIsMet, "the goal itself was the reported node")
        #expect(
            plan.metBoundary == [
                "analysis.svc.ftc-part-1",  // the goal's own direct prerequisites
                "analysis.svc.zero-deriv-const",
                "foundations.real.sup-inf",  // under the one unmet node
            ])
        #expect(plan.elidedMetCount == 11)
    }

    /// The mini-graph invariants hold on real content in every state: edges point
    /// rightward, columns are dense, the goal terminates the layout.
    @Test func layoutIsLeftToRightInEveryState() throws {
        for events in [
            [], FixtureUser.log(in: graph, config: config),
            FixtureUser.reviewedLog(in: graph, config: config),
        ] {
            let plan = try plan(over: state(events))
            for edge in plan.edges {
                #expect(plan.placed[edge.from]!.column < plan.placed[edge.to]!.column)
            }
            for (column, ids) in plan.columns.enumerated() {
                #expect(!ids.isEmpty)
                for (row, id) in ids.enumerated() {
                    #expect(plan.placed[id]?.column == column)
                    #expect(plan.placed[id]?.row == row)
                }
            }
            #expect(plan.placed[goal]?.column == plan.columns.count - 1)
        }
    }
}
