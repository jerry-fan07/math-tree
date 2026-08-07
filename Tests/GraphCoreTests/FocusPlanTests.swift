import Foundation
import Testing

@testable import GraphCore

/// Phase 7's exit criterion, asserted: "the syllabus order is a valid topological
/// order and omits exactly the met prerequisites."
///
/// The graph under test is built to contain the case a naive ordering gets wrong:
/// an unmet node (`u2`) that precedes another unmet node (`u1`) only *through a
/// met intermediate* (`m`). A topological order computed over the unmet nodes
/// alone would be free to put `u1` first; layering over the full ancestor
/// subgraph is what keeps the precedence.
///
///     r ── u2 ── m ── u1 ──╮
///     ╰───────── b ────────┴── goal
@Suite("Focus plan")
struct FocusPlanTests {
    private static let now = Date(timeIntervalSince1970: 1_775_000_000)

    private let graph = KnowledgeGraph(nodes: [
        Fixtures.branch("t", "Test"),
        Fixtures.subbranch("t.s", under: "t", "Subbranch"),
        Fixtures.content("t.s.r", .definition, .standard, "Root", under: "t.s"),
        Fixtures.content("t.s.u2", .definition, .standard, "U2", under: "t.s", requires: ["t.s.r"]),
        Fixtures.content("t.s.m", .lemma, .standard, "M", under: "t.s", requires: ["t.s.u2"]),
        Fixtures.content("t.s.u1", .theorem, .standard, "U1", under: "t.s", requires: ["t.s.m"]),
        Fixtures.content("t.s.b", .definition, .standard, "B", under: "t.s", requires: ["t.s.r"]),
        Fixtures.content(
            "t.s.goal", .theorem, .landmark, "Goal", under: "t.s",
            requires: ["t.s.u1", "t.s.b"]),
    ])

    /// Retrievability ≈ 1 — comfortably above τ.
    private func met(_ ids: NodeID...) -> ScoreState {
        ScoreState(
            nodes: Dictionary(
                uniqueKeysWithValues: ids.map {
                    ($0, MemoryState(stability: 1000, difficulty: 5, lastReview: Self.now))
                }))
    }

    private func makePlan(_ state: ScoreState, goal: NodeID = "t.s.goal") -> FocusPlan? {
        FocusPlan.compute(goal: goal, graph: graph, state: state, at: Self.now)
    }

    /// Every structural claim the layout makes, checked in one place so every
    /// scenario asserts all of them.
    private func assertWellFormed(_ plan: FocusPlan) {
        // Columns hold exactly the placed nodes, rows dense in listed order.
        for (column, ids) in plan.columns.enumerated() {
            #expect(!ids.isEmpty, "no empty column survives compaction")
            for (row, id) in ids.enumerated() {
                #expect(plan.placed[id]?.column == column)
                #expect(plan.placed[id]?.row == row)
            }
        }
        #expect(plan.columns.reduce(0) { $0 + $1.count } == plan.placed.count)

        // Left-to-right: every displayed edge crosses at least one column.
        for edge in plan.edges {
            #expect(
                plan.placed[edge.from]!.column < plan.placed[edge.to]!.column,
                "\(edge.from) → \(edge.to) must point rightward")
        }

        // The goal is displayed, alone in the final column, and never a syllabus entry.
        #expect(plan.placed[plan.goal]?.role == .goal)
        #expect(plan.placed[plan.goal]?.column == plan.columns.count - 1)
        #expect(!plan.syllabus.contains(plan.goal))

        // The syllabus is a valid topological order of the *transitive* requires
        // relation — precedence through met intermediates included.
        for (index, id) in plan.syllabus.enumerated() {
            for ancestor in graph.requiresAncestors(of: id)
            where plan.syllabus.contains(ancestor) {
                #expect(
                    plan.syllabus.firstIndex(of: ancestor)! < index,
                    "\(ancestor) is a prerequisite of \(id) and must precede it")
            }
        }

        // Roles partition the display: syllabus entries are unmet, boundary is met.
        for id in plan.syllabus { #expect(plan.placed[id]?.role == .unmet) }
        for id in plan.metBoundary { #expect(plan.placed[id]?.role == .metBoundary) }
    }

    @Test func freshUserGetsTheWholeAncestrySorted() throws {
        let plan = try #require(makePlan(ScoreState()))
        assertWellFormed(plan)
        // (layer, id): r alone, then {b, u2} by id, then the chain.
        #expect(plan.syllabus == ["t.s.r", "t.s.b", "t.s.u2", "t.s.m", "t.s.u1"])
        #expect(plan.metBoundary.isEmpty)
        #expect(plan.elidedMetCount == 0)
        #expect(plan.goalIsMet == false)
        #expect(plan.columns.count == 5)
    }

    @Test func unmetPrecedenceSurvivesAMetIntermediate() throws {
        // m and b are known; r, u2, u1 are not. u2 must still precede u1 even
        // though their only connection runs through the met node m.
        let plan = try #require(makePlan(met("t.s.m", "t.s.b")))
        assertWellFormed(plan)
        #expect(plan.syllabus == ["t.s.r", "t.s.u2", "t.s.u1"])
        let u2 = try #require(plan.syllabus.firstIndex(of: "t.s.u2"))
        let u1 = try #require(plan.syllabus.firstIndex(of: "t.s.u1"))
        #expect(u2 < u1)
        // The met nodes stay visible exactly where the unmet chain touches them.
        #expect(plan.metBoundary == ["t.s.b", "t.s.m"])
        #expect(plan.elidedMetCount == 0)
    }

    @Test func syllabusOmitsExactlyTheMetPrerequisites() throws {
        let state = met("t.s.m", "t.s.b")
        let plan = try #require(makePlan(state))
        let ancestors = Set(graph.requiresAncestors(of: "t.s.goal"))
        let expectedUnmet = ancestors.filter { state.nodes[$0] == nil }
        #expect(Set(plan.syllabus) == expectedUnmet)
    }

    @Test func allMetCompressesToTheBoundaryAndCountsTheRest() throws {
        let plan = try #require(makePlan(met("t.s.r", "t.s.u2", "t.s.m", "t.s.u1", "t.s.b")))
        assertWellFormed(plan)
        #expect(plan.syllabus.isEmpty)
        // Only the goal's direct prerequisites remain visible…
        #expect(plan.metBoundary == ["t.s.b", "t.s.u1"])
        // …and the three behind them are elided but accounted for.
        #expect(plan.elidedMetCount == 3)
        // Empty layers left behind by elision are compacted away.
        #expect(plan.columns.count == 3)
        #expect(plan.goalIsMet == false, "the goal itself was never reviewed")
    }

    @Test func learnedButDecayedCountsAsUnmet() throws {
        // b was learned months ago with modest stability — retrievability has
        // fallen well below τ, so it re-enters the syllabus (§5.4's ongoing
        // review folded into the same view).
        var state = met("t.s.r", "t.s.u2", "t.s.m", "t.s.u1")
        state.nodes["t.s.b"] = MemoryState(
            stability: 3, difficulty: 5, lastReview: Self.now.addingTimeInterval(-90 * 86_400))
        let fsrs = FSRS()
        let recall = fsrs.retrievability(of: state.nodes["t.s.b"]!, at: Self.now)
        #expect(recall < ScoringConfig().masteryThreshold, "fixture must actually be decayed")

        let plan = try #require(makePlan(state))
        assertWellFormed(plan)
        #expect(plan.syllabus == ["t.s.b"])
        #expect(plan.placed["t.s.b"]?.role == .unmet)
    }

    @Test func rootGoalHasAnEmptySyllabus() throws {
        let plan = try #require(makePlan(ScoreState(), goal: "t.s.r"))
        assertWellFormed(plan)
        #expect(plan.syllabus.isEmpty)
        #expect(plan.metBoundary.isEmpty)
        #expect(plan.columns == [["t.s.r"]])
    }

    @Test func goalCanItselfBeMet() throws {
        let plan = try #require(
            makePlan(met("t.s.r", "t.s.u2", "t.s.m", "t.s.u1", "t.s.b", "t.s.goal")))
        #expect(plan.goalIsMet)
        #expect(plan.syllabus.isEmpty)
    }

    @Test func structuralAndUnknownGoalsAreRefused() {
        #expect(makePlan(ScoreState(), goal: "t.s") == nil)
        #expect(makePlan(ScoreState(), goal: "t") == nil)
        #expect(makePlan(ScoreState(), goal: "t.s.no-such-node") == nil)
    }

    @Test func planIsDeterministic() throws {
        let state = met("t.s.m", "t.s.b")
        let first = try #require(makePlan(state))
        let second = try #require(makePlan(state))
        #expect(first == second)
    }

    /// Frontier and FocusPlan must agree on what "met" means, or the map's gold
    /// rings and the syllabus would contradict each other at the margin.
    @Test func metMirrorsTheFrontiersThreshold() throws {
        let state = met("t.s.r")
        let frontier = Set(Frontier.compute(graph: graph, state: state, at: Self.now))
        let plan = try #require(makePlan(state))
        // r met ⇒ u2 and b are frontier nodes; both must be syllabus entries and
        // r must be boundary, not syllabus.
        #expect(frontier.contains("t.s.u2") && frontier.contains("t.s.b"))
        #expect(plan.syllabus.contains("t.s.u2") && plan.syllabus.contains("t.s.b"))
        #expect(!plan.syllabus.contains("t.s.r"))
        #expect(plan.metBoundary == ["t.s.r"])
    }
}
