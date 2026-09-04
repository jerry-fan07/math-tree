import Foundation
import Testing

@testable import GraphCore

/// §6.8's ladder and unit test, pinned where they are pinnable: every rung is a
/// function of the folded state and the log at one instant, Proficient is
/// exactly §4.5's met, Mastered needs the *last* problem to have passed, and a
/// unit test is a deterministic paper drawn unmastered-first at standard
/// difficulty.
@Suite("Mastery ladder")
struct MasteryTests {
    private static let now = Date(timeIntervalSince1970: 1_775_000_000)

    private let graph = KnowledgeGraph(nodes: [
        Fixtures.branch("g", "Ground"),
        Fixtures.subbranch("g.one", under: "g", "One"),
        Fixtures.content("g.one.r", .definition, .standard, "R", under: "g.one"),
        Fixtures.content("g.one.s", .theorem, .standard, "S", under: "g.one", requires: ["g.one.r"]),
        Fixtures.content("g.one.t", .lemma, .detail, "T", under: "g.one", requires: ["g.one.r"]),
        Fixtures.content("g.one.u", .example, .detail, "U", under: "g.one", requires: ["g.one.s"]),
    ])

    private func fresh(_ id: NodeID) -> (NodeID, MemoryState) {
        (id, MemoryState(stability: 1000, difficulty: 5, lastReview: Self.now))
    }

    /// Learned long ago with little stability — retrievability well under τ.
    private func stale(_ id: NodeID) -> (NodeID, MemoryState) {
        (id, MemoryState(stability: 1, difficulty: 5, lastReview: Self.now.addingTimeInterval(-86_400 * 60)))
    }

    private func level(_ id: NodeID, _ state: ScoreState, _ evidence: MasteryEvidence = .init())
        -> MasteryLevel
    {
        Mastery.level(of: id, state: state, evidence: evidence, at: Self.now)
    }

    @Test("Every rung is reachable, and the rungs are ordered")
    func rungs() {
        let state = ScoreState(
            nodes: Dictionary(uniqueKeysWithValues: [fresh("g.one.r"), stale("g.one.s"), fresh("g.one.t")]),
            learned: ["g.one.r", "g.one.s"])
        let evidence = MasteryEvidence(proven: ["g.one.r"], directlyReviewed: ["g.one.r", "g.one.s"])

        #expect(level("g.one.u", state, evidence) == .notStarted)
        // State but never learned: a localized miss (D8.3).
        #expect(level("g.one.t", state, evidence) == .attempted)
        #expect(level("g.one.s", state, evidence) == .familiar)
        #expect(level("g.one.r", state, evidence) == .mastered)
        #expect(level("g.one.r", state, MasteryEvidence()) == .proficient)

        #expect(MasteryLevel.notStarted < .attempted)
        #expect(MasteryLevel.attempted < .familiar)
        #expect(MasteryLevel.familiar < .proficient)
        #expect(MasteryLevel.proficient < .mastered)
        #expect(MasteryLevel.allCases.map(\.points) == [0, 0, 50, 80, 100])
    }

    /// Proficient-or-better is exactly §4.5's met — the number every "N / M"
    /// read-out already shows — so the ladder never disagrees with the map.
    @Test("Proficient is met, in the frontier's exact sense")
    func proficientIsMet() {
        let state = ScoreState(
            nodes: Dictionary(uniqueKeysWithValues: [fresh("g.one.r"), stale("g.one.s")]),
            learned: ["g.one.r", "g.one.s"])
        let fsrs = FSRS()
        for id: NodeID in ["g.one.r", "g.one.s", "g.one.t"] {
            let met =
                state.isLearned(id)
                && (state.nodes[id].map { fsrs.retrievability(of: $0, at: Self.now) } ?? 0)
                    > ScoringConfig().masteryThreshold
            #expect(level(id, state).isMet == met, "\(id)")
        }
    }

    /// Mastered reads the *last* test event: a pass followed by a localized miss
    /// is not proven, and a miss followed by a pass is.
    @Test("Proven follows the most recent problem, in fold order")
    func provenFollowsTheLastTest() {
        let t0 = Self.now.addingTimeInterval(-3_600)
        let t1 = Self.now.addingTimeInterval(-1_800)
        func test(_ id: NodeID, _ grade: Grade, at: Date) -> EvidenceEvent {
            EvidenceEvent(at: at, target: .node(id), grade: grade, source: .test, problem: "p")
        }
        let passThenMiss = MasteryEvidence(events: [
            test("g.one.r", .good, at: t0), test("g.one.r", .again, at: t1),
        ])
        #expect(!passThenMiss.proven.contains("g.one.r"))
        // Arrival order does not matter — fold order does.
        let missThenPass = MasteryEvidence(events: [
            test("g.one.s", .good, at: t1), test("g.one.s", .again, at: t0),
        ])
        #expect(missThenPass.proven.contains("g.one.s"))

        // Self-report and implicit evidence never prove anything, and only
        // non-inferred evidence counts as a direct review.
        let indirect = MasteryEvidence(events: [
            EvidenceEvent(at: t0, target: .node("g.one.t"), grade: .good, source: .selfReport),
            EvidenceEvent(
                at: t0, target: .node("g.one.u"), grade: .good, source: .implicit,
                origin: "g.one.t", depth: 1, weight: 0.5),
        ])
        #expect(indirect.proven.isEmpty)
        #expect(indirect.directlyReviewed == ["g.one.t"])
    }

    @Test("A summary counts rungs, totals points and agrees with met")
    func summary() {
        let state = ScoreState(
            nodes: Dictionary(uniqueKeysWithValues: [fresh("g.one.r"), stale("g.one.s"), fresh("g.one.t")]),
            learned: ["g.one.r", "g.one.s"])
        let evidence = MasteryEvidence(proven: ["g.one.r"])
        let summary = Mastery.summary(
            of: ["g.one.r", "g.one.s", "g.one.t", "g.one.u"], state: state, evidence: evidence,
            at: Self.now)
        #expect(summary.total == 4)
        #expect(summary.count(.mastered) == 1)
        #expect(summary.count(.familiar) == 1)
        #expect(summary.count(.attempted) == 1)
        #expect(summary.count(.notStarted) == 1)
        #expect(summary.points == 150)
        #expect(summary.possiblePoints == 400)
        #expect(summary.metCount == 1)
        #expect(MasterySummary(total: 0, counts: [:]).fraction == 0)
    }
}

@Suite("Unit test")
struct UnitTestTests {
    private static func problem(
        _ id: ProblemID, _ node: NodeID, _ difficulty: Problem.Difficulty
    ) -> Problem {
        Problem(
            id: id, kind: .work, statement: "?", answer: "!", rubric: ["r"], targets: [node],
            difficulty: difficulty)
    }

    private let steps: [ProgramPlan.Step] = [
        .init(id: "g.one.r", unit: "g.one", isMet: true, isLearned: true),
        .init(id: "g.one.s", unit: "g.one", isMet: false, isLearned: false),
        .init(id: "g.one.t", unit: "g.one", isMet: false, isLearned: false),
        .init(id: "g.one.u", unit: "g.one", isMet: false, isLearned: false),
    ]

    private let bank = ProblemBank(problems: [
        problem("r-01", "g.one.r", .demanding),
        problem("r-02", "g.one.r", .standard),
        problem("s-01", "g.one.s", .demanding),
        problem("s-02", "g.one.s", .routine),
        problem("t-01", "g.one.t", .standard),
        problem("t-02", "g.one.t", .standard),
    ])

    @Test("Standard first, unattempted first, one per skill, in teaching order")
    func selection() {
        let paper = UnitTest.paper(
            for: steps, bank: bank, level: { $0 == "g.one.r" ? .mastered : .notStarted },
            attempted: ["t-01"])
        #expect(paper.questions.map(\.id) == ["r-02", "s-02", "t-02"])
        #expect(paper.questions.map(\.node) == ["g.one.r", "g.one.s", "g.one.t"])
        #expect(paper.unaskable == ["g.one.u"])
        #expect(paper.omitted.isEmpty)
    }

    /// A cap spends its questions on skills the ladder can still move — and the
    /// paper is still sat in teaching order once chosen.
    @Test("The cap drops mastered skills first")
    func capping() {
        let paper = UnitTest.paper(
            for: steps, bank: bank, level: { $0 == "g.one.r" ? .mastered : .notStarted },
            limit: 2)
        #expect(paper.questions.map(\.node) == ["g.one.s", "g.one.t"])
        #expect(paper.omitted == ["g.one.r"])
    }

    @Test("The same inputs give the same paper")
    func determinism() {
        let a = UnitTest.paper(for: steps, bank: bank, level: { _ in .notStarted })
        let b = UnitTest.paper(for: steps, bank: bank, level: { _ in .notStarted })
        #expect(a == b)
    }
}
