import Foundation
import Testing

@testable import GraphCore

/// Phase 11's exit criterion, asserted: a subject's path is a valid topological
/// order over every content node the subject contains *plus* the unmet
/// prerequisites those nodes reach outside it, omitting exactly what is met.
///
/// The graph is built so the interesting cases are all present at once: a subject
/// (`topic`) whose every node sits behind another branch (`base`), a second
/// subbranch inside it that depends on the first, a cross-listed node whose *home*
/// is elsewhere, and an outlined-but-empty subbranch.
///
///     base.core.a ── base.core.b ── topic.one.x ── topic.one.y ── topic.two.z
///           ╰────── base.core.c   (cross-listed into topic.one via also_under)
///
///     topic.empty — outlined, nothing in it
@Suite("Subject path")
struct SubjectPathTests {
    private static let now = Date(timeIntervalSince1970: 1_775_000_000)

    private let graph = KnowledgeGraph(nodes: [
        Fixtures.branch("base", "Base"),
        Fixtures.subbranch("base.core", under: "base", "Core"),
        Fixtures.content("base.core.a", .definition, .standard, "A", under: "base.core"),
        Fixtures.content(
            "base.core.b", .definition, .standard, "B", under: "base.core",
            requires: ["base.core.a"]),
        Fixtures.content(
            "base.core.c", .lemma, .detail, "C", under: "base.core",
            alsoUnder: ["topic.one"], requires: ["base.core.a"]),

        Fixtures.branch("topic", "Topic"),
        Fixtures.subbranch("topic.one", under: "topic", "One"),
        Fixtures.content(
            "topic.one.x", .definition, .standard, "X", under: "topic.one",
            requires: ["base.core.b"]),
        Fixtures.content(
            "topic.one.y", .theorem, .landmark, "Y", under: "topic.one",
            requires: ["topic.one.x"]),
        Fixtures.subbranch("topic.two", under: "topic", "Two"),
        Fixtures.content(
            "topic.two.z", .corollary, .detail, "Z", under: "topic.two",
            requires: ["topic.one.y"]),
        Fixtures.subbranch("topic.empty", under: "topic", "Empty"),
    ])

    /// Retrievability ≈ 1 — comfortably above τ.
    private func met(_ ids: NodeID...) -> ScoreState {
        ScoreState(
            nodes: Dictionary(
                uniqueKeysWithValues: ids.map {
                    ($0, MemoryState(stability: 1000, difficulty: 5, lastReview: Self.now))
                }))
    }

    private func path(_ state: ScoreState, through subject: NodeID = "topic") -> FocusPlan? {
        FocusPlan.compute(subject: subject, graph: graph, state: state, at: Self.now)
    }

    /// Every claim the ordering makes, checked in one place.
    private func assertWellOrdered(_ plan: FocusPlan) {
        for (index, id) in plan.syllabus.enumerated() {
            for ancestor in graph.requiresAncestors(of: id)
            where plan.syllabus.contains(ancestor) {
                #expect(
                    plan.syllabus.firstIndex(of: ancestor)! < index,
                    "\(ancestor) is a prerequisite of \(id) and must precede it")
            }
        }
        for edge in plan.edges {
            #expect(
                plan.placed[edge.from]!.column < plan.placed[edge.to]!.column,
                "\(edge.from) → \(edge.to) must point rightward")
        }
        for (column, ids) in plan.columns.enumerated() {
            #expect(!ids.isEmpty, "no empty column survives compaction")
            for (row, id) in ids.enumerated() {
                #expect(plan.placed[id]?.column == column)
                #expect(plan.placed[id]?.row == row)
            }
        }
        // No node in a subject path is the "goal": a subject has no single
        // destination, so every displayed node is a step or a known boundary.
        #expect(plan.placed.values.allSatisfy { $0.role != .goal })
        for id in plan.syllabus { #expect(plan.placed[id]?.role == .unmet) }
        for id in plan.metBoundary { #expect(plan.placed[id]?.role == .metBoundary) }
    }

    // MARK: - Membership

    /// §2.3: a secondary `contains` parent is a claim that the node belongs to that
    /// subject too, so a cross-listed node is part of the subject that lists it —
    /// and part of its home subject as well.
    @Test func targetsAreEveryContentDescendantIncludingCrossListings() throws {
        let plan = try #require(path(ScoreState()))
        #expect(
            plan.targets == ["topic.one.x", "topic.one.y", "topic.two.z", "base.core.c"])
        #expect(Set(graph.contentDescendants(of: "base")) == ["base.core.a", "base.core.b", "base.core.c"])
        // Structural children are never targets — they carry no score (§2.1).
        #expect(!plan.targets.contains("topic.one"))
    }

    @Test func aSubbranchIsASubjectToo() throws {
        let plan = try #require(path(ScoreState(), through: "topic.one"))
        #expect(plan.targets == ["topic.one.x", "topic.one.y", "base.core.c"])
    }

    // MARK: - The path

    /// The headline of §6.5: asking for a subject you cannot start yet answers with
    /// the road in, not with a refusal.
    @Test func freshUserGetsTheSubjectPlusItsImportedPrerequisites() throws {
        let plan = try #require(path(ScoreState()))
        assertWellOrdered(plan)

        #expect(
            plan.syllabus == [
                "base.core.a",  // imported: nothing in `topic` is reachable without it
                "base.core.b",
                "base.core.c",  // cross-listed, so a target despite living in `base`
                "topic.one.x",
                "topic.one.y",
                "topic.two.z",
            ])
        // `base.core.c` is cross-listed *into* the subject, so it is a target and
        // not an import; a/b are neither.
        #expect(plan.importedSteps == ["base.core.a", "base.core.b"])
        #expect(plan.metTargets.isEmpty)
        #expect(plan.goalIsMet == false)
    }

    /// The first step of any path is always something the user can actually start:
    /// it has the least layer of anything unmet, so every prerequisite of it is met.
    /// This is what makes the ordered list a *guided* path rather than a checklist.
    @Test func theFirstStepIsAlwaysOnTheFrontier() throws {
        for state in [ScoreState(), met("base.core.a"), met("base.core.a", "base.core.b")] {
            let plan = try #require(path(state))
            let frontier = Set(Frontier.compute(graph: graph, state: state, at: Self.now))
            let first = try #require(plan.syllabus.first)
            #expect(frontier.contains(first), "\(first) must be ready to learn")
        }
    }

    @Test func metStepsDropOutAndTheProgressCountRises() throws {
        let plan = try #require(path(met("base.core.a", "base.core.b", "topic.one.x")))
        assertWellOrdered(plan)
        #expect(plan.syllabus == ["base.core.c", "topic.one.y", "topic.two.z"])
        // One of the four targets is met — the progress read-out a single-node
        // focus has no use for.
        #expect(plan.metTargets == ["topic.one.x"])
        #expect(plan.targets.count == 4)
        // §6.2's compression: the known edge stays visible, the rest is counted.
        #expect(plan.metBoundary == ["base.core.a", "topic.one.x"])
        #expect(plan.elidedMetCount == 1)  // base.core.b, behind the boundary
    }

    /// A decayed target re-enters the path, exactly as it re-enters a syllabus —
    /// §5.4's ongoing review and first-time learning are the same list.
    @Test func aDecayedTargetReentersThePath() throws {
        var state = met("base.core.a", "base.core.b", "base.core.c", "topic.one.x", "topic.one.y")
        state.nodes["topic.one.x"] = MemoryState(
            stability: 3, difficulty: 5, lastReview: Self.now.addingTimeInterval(-90 * 86_400))
        #expect(
            FSRS().retrievability(of: state.nodes["topic.one.x"]!, at: Self.now)
                < ScoringConfig().masteryThreshold, "fixture must actually be decayed")

        let plan = try #require(path(state))
        assertWellOrdered(plan)
        // Only x comes back. `y` is built on x and has decayed less, so it stays
        // met — retrievability is per-node (§4.1) and a weak prerequisite is not
        // retroactive evidence against what was learned from it. `z` was never
        // learned at all.
        #expect(plan.syllabus == ["topic.one.x", "topic.two.z"])
        #expect(plan.metTargets == ["base.core.c", "topic.one.y"])
    }

    @Test func masteringEverythingEmptiesThePath() throws {
        let plan = try #require(
            path(
                met(
                    "base.core.a", "base.core.b", "base.core.c", "topic.one.x", "topic.one.y",
                    "topic.two.z")))
        #expect(plan.syllabus.isEmpty)
        #expect(plan.goalIsMet, "every node of the subject is met")
        #expect(plan.metTargets == plan.targets)
        // Nothing unmet means nothing to compress *toward*, so the whole known
        // subgraph is elided and counted rather than drawn.
        #expect(plan.placed.isEmpty)
        #expect(plan.elidedMetCount == 6)
    }

    // MARK: - Boundaries

    /// §7.1 fixes the outline before the content, so an empty subject is the
    /// common case, not an edge case. It is an empty plan, not a refusal — the app
    /// has something true to say about it.
    @Test func anOutlinedButEmptySubjectIsAnEmptyPlan() throws {
        let plan = try #require(path(ScoreState(), through: "topic.empty"))
        #expect(plan.targets.isEmpty)
        #expect(plan.syllabus.isEmpty)
        #expect(plan.placed.isEmpty)
        #expect(plan.columns.isEmpty)
        // Not "complete": there is nothing here to have learned.
        #expect(plan.goalIsMet == false)
    }

    @Test func theTwoGoalKindsRefuseEachOthersIds() {
        #expect(FocusPlan.compute(subject: "topic.one.x", graph: graph, state: ScoreState(), at: Self.now) == nil)
        #expect(FocusPlan.compute(goal: "topic", graph: graph, state: ScoreState(), at: Self.now) == nil)
        #expect(FocusPlan.compute(subject: "no.such.thing", graph: graph, state: ScoreState(), at: Self.now) == nil)
    }

    /// A single-node focus is the same computation with a one-element target set,
    /// and must stay byte-identical to what Phase 7 shipped.
    @Test func aNodeFocusIsASingletonTargetSet() throws {
        let plan = try #require(
            FocusPlan.compute(goal: "topic.two.z", graph: graph, state: ScoreState(), at: Self.now))
        #expect(plan.targets == ["topic.two.z"])
        #expect(plan.isTarget("topic.two.z"))
        #expect(plan.importedSteps == plan.syllabus, "no step of a node focus is 'in' the goal")
        #expect(!plan.syllabus.contains("topic.two.z"), "the goal is the arrival, not a step")
        #expect(plan.placed["topic.two.z"]?.role == .goal)
    }

    @Test func pathIsDeterministic() throws {
        let state = met("base.core.a")
        #expect(try #require(path(state)) == (try #require(path(state))))
    }

    // MARK: - Subject list

    /// The list a subject is chosen *from* (§6.5) must agree with the path you get
    /// when you choose one: same notion of met, same notion of membership.
    @Test func subjectSummariesMatchThePlansTheyPromise() throws {
        let state = met("base.core.a", "topic.one.x")
        let summaries = Subjects.branches(graph: graph, state: state, at: Self.now)
        #expect(summaries.map(\.id) == ["base", "topic"])

        for summary in summaries {
            let plan = try #require(path(state, through: summary.id))
            #expect(summary.total == plan.targets.count)
            #expect(summary.met == plan.metTargets.count)
            #expect(summary.isAuthored == !plan.targets.isEmpty)
            #expect(summary.isComplete == plan.goalIsMet)
        }
        #expect(summaries[1].met == 1 && summaries[1].total == 4)
    }

    @Test func anEmptySubjectIsUnauthoredRatherThanUnstarted() {
        let summaries = Subjects.summarize(
            ["topic.empty"], graph: graph, state: ScoreState(), at: Self.now)
        #expect(summaries[0].isAuthored == false)
        #expect(summaries[0].isComplete == false)
        #expect(summaries[0].fraction == 0)
    }
}
