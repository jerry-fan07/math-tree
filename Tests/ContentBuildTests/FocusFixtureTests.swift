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
/// Phase 9 wired logic, set theory and functions underneath analysis, so the FTC's
/// ancestry no longer starts at `sup-inf`. These nine are the unmet foundations the
/// fixture user has never touched, in `FocusPlan`'s longest-path layer order, and
/// they open every syllabus below. Named once rather than repeated three times so
/// that a change to the foundations moves one list and is read once.
private let foundationsPrefix: [NodeID] = [
    "foundations.logic.def-proposition",
    "foundations.sets.def-set-membership",
    "foundations.logic.def-conditional",
    "foundations.logic.def-conjunction",
    "foundations.logic.def-predicate",
    "foundations.logic.quantifier-universal",
    "foundations.sets.set-builder",
    "foundations.logic.vacuous-truth",
    "foundations.sets.def-subset",
]

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
            plan.syllabus == foundationsPrefix + [
                "foundations.sets.empty-set",
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
            plan.syllabus == foundationsPrefix + [
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
        #expect(plan.elidedMetCount == 5)
        #expect(plan.goalIsMet == false)
    }

    /// After the deep FTC report, propagation (γᵈ to depth 3) lifts the whole
    /// integration chain and the MVT past τ; only Riemann sums — four hops down,
    /// beyond D_max — stay unmet. The syllabus shrinks to exactly that node.
    @Test func reviewedUserSyllabusShrinksToWhatPropagationMissed() throws {
        let state = state(FixtureUser.reviewedLog(in: graph, config: config))
        let plan = try plan(over: state)
        assertCriterion(plan, state: state)

        // Propagation lifts the integration chain and the MVT past τ, but γᵈ stops
        // at D_max = 3 — so Riemann sums (four hops down) and the whole foundations
        // prefix (five and more) stay unmet. Before Phase 9 this list was one node;
        // that it is now ten is the depth of the graph showing through, not a
        // regression in propagation.
        #expect(plan.syllabus == foundationsPrefix + ["analysis.svc.def-riemann-sum"])
        #expect(plan.goalIsMet, "the goal itself was the reported node")
        #expect(
            plan.metBoundary == [
                "analysis.svc.ftc-part-1",  // the goal's own direct prerequisites
                "analysis.svc.zero-deriv-const",
                "foundations.real.sup-inf",  // under the one unmet node
            ])
        #expect(plan.elidedMetCount == 12)
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

/// Phase 11's exit criterion against the real corpus: "for a branch with authored
/// content, the guided path is a valid topological order over the branch's content
/// nodes plus their unmet prerequisites, and names the ones that come from outside
/// the branch."
///
/// Linear Algebra is the case the criterion is written about, and it is not chosen
/// for convenience: `linear-algebra.systems` is the only authored subbranch of the
/// branch, and every one of its roots reaches into Foundations (`sets`,
/// `relations`, `number-systems`). So "learn linear algebra" from cold *must*
/// answer with foundations first, or the answer is wrong.
@Suite("Subject paths on the real corpus")
struct SubjectPathFixtureTests {
    let graph: KnowledgeGraph
    let config = ScoringConfig()
    let now = FixtureUser.now

    init() throws {
        let content = try ContentLoader.load(
            root: repoRoot.appendingPathComponent("content"), relativeTo: repoRoot)
        graph = KnowledgeGraph(nodes: content.nodes)
    }

    private func state(_ events: [EvidenceEvent]) -> ScoreState {
        ScoreFold.fold(events, graph: graph, config: config).state
    }

    private func path(_ subject: NodeID, over state: ScoreState) throws -> FocusPlan {
        try #require(
            FocusPlan.compute(
                subject: subject, graph: graph, state: state, at: now, config: config))
    }

    /// The exit criterion's two clauses, independently recomputed: the path is
    /// exactly the unmet nodes of (subject ∪ its prerequisite closure), in an order
    /// that respects the transitive `requires` relation.
    private func assertCriterion(_ plan: FocusPlan, state: ScoreState) {
        let fsrs = FSRS(parameters: config.fsrs)
        let targets = graph.contentDescendants(of: plan.goal)
        let reachable = Set(targets).union(
            graph.requiresAncestors(ofAll: targets).filter { graph[$0]?.kind.isContent == true })
        let expectedUnmet = reachable.filter { id in
            guard state.isLearned(id), let memory = state.nodes[id] else { return true }
            return fsrs.retrievability(of: memory, at: now) <= config.masteryThreshold
        }
        #expect(Set(plan.syllabus) == expectedUnmet, "omits exactly the met nodes")

        let position = Dictionary(
            uniqueKeysWithValues: plan.syllabus.enumerated().map { ($0.element, $0.offset) })
        for (index, id) in plan.syllabus.enumerated() {
            for ancestor in graph.requiresAncestors(of: id) {
                if let earlier = position[ancestor] {
                    #expect(earlier < index, "\(ancestor) must precede \(id)")
                }
            }
        }
    }

    /// The headline case, from cold.
    @Test func learningLinearAlgebraFromColdRoutesThroughFoundations() throws {
        let empty = ScoreState()
        let plan = try path("linear-algebra", over: empty)
        assertCriterion(plan, state: empty)

        // The whole branch, as authored today: `systems` and nothing else.
        #expect(plan.targets.count == 25)
        #expect(plan.metTargets.isEmpty)
        #expect(plan.syllabus.count == 50)

        // Half the path is not linear algebra at all — and every imported step is
        // from Foundations, which is the claim §2.4 makes about cross-branch
        // `requires` edges, arriving as something a user has to act on.
        #expect(plan.importedSteps.count == 25)
        #expect(plan.importedSteps.allSatisfy { $0.rawValue.hasPrefix("foundations.") })

        // Every target of the subject is in the path, none of them at the front.
        #expect(plan.targets.allSatisfy { plan.syllabus.contains($0) })
        let firstTarget = try #require(plan.syllabus.firstIndex { plan.isTarget($0) })
        #expect(firstTarget > 0, "nothing in the branch is reachable before the imports")
        #expect(plan.syllabus[firstTarget] == "linear-algebra.systems.def-linear-equation")

        // And the first step is one the user can actually take today.
        let frontier = Set(Frontier.compute(graph: graph, state: empty, at: now, config: config))
        #expect(frontier.contains(try #require(plan.syllabus.first)))
    }

    /// The same subject for the fixture user, who knows some analysis and none of
    /// this: exactly the foundations node their analysis work already exercised
    /// drops out, and nothing else moves.
    @Test func knownFoundationsDropOutOfTheLinearAlgebraPath() throws {
        let state = state(FixtureUser.log(in: graph, config: config))
        let plan = try path("linear-algebra", over: state)
        assertCriterion(plan, state: state)

        let cold = try path("linear-algebra", over: ScoreState())
        #expect(Set(cold.syllabus).subtracting(plan.syllabus) == ["foundations.sets.empty-set"])
        #expect(plan.metBoundary == ["foundations.sets.empty-set"])
        #expect(plan.metTargets.isEmpty, "no linear algebra has been touched")
    }

    /// A subject the user *has* worked in: the path shrinks to what is left, and
    /// the progress read-out is the reason to look at the list at all.
    @Test func analysisPathReportsProgressAndShrinks() throws {
        let state = state(FixtureUser.log(in: graph, config: config))
        let plan = try path("analysis", over: state)
        assertCriterion(plan, state: state)

        #expect(plan.targets.count == 47)
        #expect(plan.metTargets.count == 6)
        #expect(plan.goalIsMet == false)
        // A subject path is longer than the branch, because the prerequisites it
        // reaches are steps too — and shorter than the cold one, because six
        // targets and a dozen imports are already met.
        let cold = try path("analysis", over: ScoreState())
        #expect(cold.syllabus.count == 86 && plan.syllabus.count == 77)
    }

    /// §7.1's outline is most of the map, so this is the ordinary case, not a
    /// corner: a subject with no content is an empty plan the app can describe.
    @Test func anOutlinedBranchWithNoContentIsAnEmptyPath() throws {
        let plan = try path("topology", over: ScoreState())
        #expect(plan.targets.isEmpty)
        #expect(plan.syllabus.isEmpty)
        #expect(plan.columns.isEmpty)
    }

    /// The subject list the sidebar offers must agree with the paths it links to,
    /// over the real corpus and not only over a fixture.
    @Test func theSubjectListAgreesWithEveryPathItOffers() throws {
        let state = state(FixtureUser.log(in: graph, config: config))
        let summaries = Subjects.branches(graph: graph, state: state, at: now, config: config)
        #expect(summaries.count == 12, "every branch of the §9 outline is offered")
        for summary in summaries {
            let plan = try path(summary.id, over: state)
            #expect(summary.total == plan.targets.count)
            #expect(summary.met == plan.metTargets.count)
        }
        // Five branches are authored today; the rest are outline.
        #expect(summaries.filter(\.isAuthored).count == 5)
    }

    /// The mini-graph invariants, on paths an order of magnitude larger than any
    /// single-node focus: edges rightward, columns dense.
    @Test func subjectLayoutsAreLeftToRight() throws {
        let state = state(FixtureUser.log(in: graph, config: config))
        for subject: NodeID in ["linear-algebra", "analysis", "foundations", "algebra"] {
            for scoreState in [ScoreState(), state] {
                let plan = try path(subject, over: scoreState)
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
            }
        }
    }
}
