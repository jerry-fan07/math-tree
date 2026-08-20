import Foundation
import Testing

@testable import GraphCore

/// Phase 12's exit criterion, asserted where it is assertable: the spine is held
/// to a linear extension of cross-unit `requires`, the plan's step order is a
/// valid topological order per unit, the resume point is the first never-learned
/// step in program order — and provably *not* moved by decay — and the progress
/// counts match the state they were computed from.
///
/// The graph under test:
///
///     g.one.r ── g.one.s ── g.two.u ── g.two.v ── a.one.w ── a.one.x
///           ╰─── g.one.t                              a.one.y (rootless)
///
/// with `g.two.u` cross-listed into `a.one` (must *not* be taught there — a node
/// is taught once, where it lives), and `a.empty` outlined but unwritten.
@Suite("Program")
struct ProgramTests {
    private static let now = Date(timeIntervalSince1970: 1_775_000_000)

    private let graph = KnowledgeGraph(nodes: [
        Fixtures.branch("g", "Ground"),
        Fixtures.subbranch("g.one", under: "g", "One"),
        Fixtures.content("g.one.r", .definition, .standard, "R", under: "g.one"),
        Fixtures.content("g.one.s", .theorem, .standard, "S", under: "g.one", requires: ["g.one.r"]),
        Fixtures.content("g.one.t", .lemma, .detail, "T", under: "g.one", requires: ["g.one.r"]),
        Fixtures.subbranch("g.two", under: "g", "Two"),
        Fixtures.content(
            "g.two.u", .technique, .standard, "U", under: "g.two",
            alsoUnder: ["a.one"], requires: ["g.one.s"]),
        Fixtures.content("g.two.v", .example, .detail, "V", under: "g.two", requires: ["g.two.u"]),

        Fixtures.branch("a", "Applied"),
        Fixtures.subbranch("a.one", under: "a", "AppliedOne"),
        Fixtures.content(
            "a.one.w", .definition, .standard, "W", under: "a.one", requires: ["g.two.v"]),
        Fixtures.content("a.one.x", .theorem, .landmark, "X", under: "a.one", requires: ["a.one.w"]),
        Fixtures.content("a.one.y", .intuition, .detail, "Y", under: "a.one"),
        Fixtures.subbranch("a.empty", under: "a", "Empty"),
    ])

    private let spine = ProgramSpine(parts: [
        .init(title: "Groundwork", units: ["g.one", "g.two"]),
        .init(title: "Applications", units: ["a.one", "a.empty"]),
    ])

    /// Retrievability ≈ 1 — comfortably above τ.
    private func met(_ ids: NodeID...) -> ScoreState {
        ScoreState(
            nodes: Dictionary(
                uniqueKeysWithValues: ids.map {
                    ($0, MemoryState(stability: 1000, difficulty: 5, lastReview: Self.now))
                }))
    }

    private func plan(_ state: ScoreState) -> ProgramPlan {
        ProgramPlan.compute(spine: spine, graph: graph, state: state, at: Self.now)
    }

    // MARK: - Validation

    @Test func aCleanProgramValidates() {
        let program = Program(
            spine: spine,
            lessonUnits: [
                LessonUnit(
                    unit: "g.one", opening: "Where everything starts.",
                    lessons: [
                        lesson("g.one.r"), lesson("g.one.s"), lesson("g.one.t"),
                    ])
            ])
        #expect(ProgramValidator.validate(program, against: graph).isEmpty)
    }

    private func lesson(_ node: NodeID, hook: String = "Why this matters.") -> Lesson {
        Lesson(
            node: node, hook: hook, explanation: "The teaching, at length.",
            worked: "An example worked to the number.", recap: "One breath.")
    }

    private func rules(_ program: Program) -> [DiagnosticRule] {
        ProgramValidator.validate(program, against: graph).map(\.rule)
    }

    @Test func spineViolationsAreEachReported() {
        // Dangling unit.
        #expect(
            rules(
                Program(
                    spine: ProgramSpine(parts: [
                        .init(title: "P", units: ["g.one", "g.two", "a.one", "a.empty", "g.gone"])
                    ]))
            ).contains(.danglingProgramUnit))
        // A unit that is not a subbranch.
        #expect(
            rules(
                Program(
                    spine: ProgramSpine(parts: [
                        .init(
                            title: "P",
                            units: ["g.one", "g.two", "a.one", "a.empty", "g.one.r"])
                    ]))
            ).contains(.programUnitNotSubbranch))
        // The same unit twice.
        #expect(
            rules(
                Program(
                    spine: ProgramSpine(parts: [
                        .init(title: "P", units: ["g.one", "g.two", "a.one", "a.empty", "g.one"])
                    ]))
            ).contains(.duplicateProgramUnit))
        // A subbranch the program forgot.
        #expect(
            rules(
                Program(
                    spine: ProgramSpine(parts: [
                        .init(title: "P", units: ["g.one", "g.two", "a.one"])
                    ]))
            ).contains(.programMissingSubbranch))
        // A part with no title.
        #expect(
            rules(
                Program(
                    spine: ProgramSpine(parts: [
                        .init(title: "  ", units: ["g.one", "g.two", "a.one", "a.empty"])
                    ]))
            ).contains(.emptyProgramPartTitle))
    }

    /// The load-bearing rule: `a.one.w` requires `g.two.v`, so a spine teaching
    /// `a.one` before `g.two` is not a linear extension of cross-unit requires.
    @Test func aForwardCrossUnitEdgeFailsTheSpine() {
        let reversed = ProgramSpine(parts: [
            .init(title: "P", units: ["g.one", "a.one", "g.two", "a.empty"])
        ])
        let found = ProgramValidator.validate(Program(spine: reversed), against: graph)
            .filter { $0.rule == .programOrderViolation }
        #expect(found.count == 1)
        #expect(found.first?.nodes == ["a.one.w", "g.two.v"])
        // The clean spine has no such finding — the rule can tell the two apart.
        #expect(!rules(Program(spine: spine)).contains(.programOrderViolation))
    }

    @Test func lessonViolationsAreEachReported() {
        func unit(_ lessons: [Lesson], opening: String = "Opening.", of id: NodeID = "g.one")
            -> Program
        {
            Program(
                spine: spine,
                lessonUnits: [LessonUnit(unit: id, opening: opening, lessons: lessons)])
        }
        let full = [lesson("g.one.r"), lesson("g.one.s"), lesson("g.one.t")]

        // A file that exists must teach its whole unit…
        #expect(
            rules(unit([lesson("g.one.r"), lesson("g.one.s")]))
                .contains(.lessonUnitIncomplete))
        // …only its own nodes…
        #expect(
            rules(unit(full + [lesson("g.two.u")])).contains(.lessonNodeOutsideUnit))
        // …that exist…
        #expect(rules(unit(full + [lesson("g.one.gone")])).contains(.danglingLessonNode))
        // …and are learnable.
        #expect(rules(unit(full + [lesson("g.two")])).contains(.lessonNodeNotContent))
        // Once each.
        #expect(rules(unit(full + [lesson("g.one.r")])).contains(.duplicateLesson))
        // Required sections are required.
        #expect(
            rules(unit([lesson("g.one.r", hook: " "), lesson("g.one.s"), lesson("g.one.t")]))
                .contains(.lessonMissingSection))
        // A chapter starts with a paragraph.
        #expect(rules(unit(full, opening: "")).contains(.lessonUnitMissingOpening))
        // Lessons for a unit the program does not know.
        #expect(
            ProgramValidator.validate(
                Program(
                    spine: spine,
                    lessonUnits: [
                        LessonUnit(unit: "g.one.r", opening: "Opening.", lessons: [])
                    ]),
                against: graph
            ).map(\.rule).contains(.lessonUnitNotInProgram))
    }

    // MARK: - Plan

    @Test func theStepOrderIsAValidTopologicalOrderPerUnit() {
        let plan = plan(ScoreState())
        #expect(plan.stepCount == 8)
        for unit in plan.units {
            let order = unit.steps.map(\.id)
            for (index, id) in order.enumerated() {
                for prerequisite in graph.prerequisites(of: id)
                where order.contains(prerequisite) {
                    #expect(
                        order.firstIndex(of: prerequisite)! < index,
                        "\(prerequisite) precedes \(id) in \(unit.id)")
                }
            }
        }
        // Deterministic: the same inputs give the same plan.
        #expect(plan == self.plan(ScoreState()))
        // The concrete order, pinned: longest-path layer, then id.
        #expect(plan.unit("g.one")?.steps.map(\.id) == ["g.one.r", "g.one.s", "g.one.t"])
        #expect(plan.unit("a.one")?.steps.map(\.id) == ["a.one.w", "a.one.y", "a.one.x"])
    }

    /// `g.two.u` is cross-listed into `a.one` (`also_under`), and §6.5's subject
    /// membership would count it there — the program must not: a node is taught
    /// once, in its home unit.
    @Test func aCrossListedNodeIsTaughtOnlyInItsHomeUnit() {
        let plan = plan(ScoreState())
        #expect(plan.unit("g.two")?.steps.map(\.id).contains("g.two.u") == true)
        #expect(plan.unit("a.one")?.steps.map(\.id).contains("g.two.u") == false)
    }

    @Test func anOutlinedButUnwrittenUnitIsUnauthoredNotComplete() {
        let empty = plan(ScoreState()).unit("a.empty")
        #expect(empty?.isAuthored == false)
        #expect(empty?.isComplete == false)
    }

    @Test func resumeIsTheFirstNeverLearnedStepInProgramOrder() {
        // Nothing learned: the program opens at its first step.
        #expect(plan(ScoreState()).resume?.id == "g.one.r")
        // The first unit mastered: the bookmark sits at the second.
        #expect(plan(met("g.one.r", "g.one.s", "g.one.t")).resume?.id == "g.two.u")
        // Everything learned: nothing to resume.
        let all = met(
            "g.one.r", "g.one.s", "g.one.t", "g.two.u", "g.two.v",
            "a.one.w", "a.one.x", "a.one.y")
        #expect(plan(all).resume == nil)
    }

    /// The D12 decision the type documents: a decayed early node re-enters the
    /// *work* (it is unmet, so adaptive mode un-compresses it) but does not move
    /// the *bookmark* — a program position means "where I got to".
    @Test func decayMakesAStepUnmetButDoesNotMoveTheBookmark() {
        var state = met("g.one.s", "g.one.t", "g.two.u", "g.two.v")
        // Learned long ago with low stability: retrievability well below τ.
        state.nodes["g.one.r"] = MemoryState(
            stability: 1, difficulty: 5,
            lastReview: Self.now.addingTimeInterval(-30 * 86_400))
        state.learned.insert("g.one.r")

        let config = ScoringConfig()
        let recall = FSRS(parameters: config.fsrs)
            .retrievability(of: state.nodes["g.one.r"]!, at: Self.now)
        #expect(recall < config.masteryThreshold, "the fixture must actually be decayed")

        let plan = plan(state)
        let decayed = plan.step(for: "g.one.r")
        #expect(decayed?.isMet == false)
        #expect(decayed?.isLearned == true)
        #expect(decayed?.isDecayed == true)
        // The bookmark is *past* the decayed step, at the first never-learned one.
        #expect(plan.resume?.id == "a.one.w")
    }

    @Test func progressCountsMatchTheState() {
        let plan = plan(met("g.one.r", "g.one.s", "g.two.u"))
        #expect(plan.metCount == 3)
        #expect(plan.unit("g.one")?.metCount == 2)
        #expect(plan.unit("g.one")?.isComplete == false)
        #expect(plan.unit("a.one")?.metCount == 0)
        let complete = plan.unit("g.one").map { unit in
            ProgramPlan.compute(
                spine: spine, graph: graph,
                state: met("g.one.r", "g.one.s", "g.one.t"), at: Self.now
            ).unit(unit.id)?.isComplete
        }
        #expect(complete == true)
    }

    @Test func stepLookupFindsContentAndRefusesStructure() {
        let plan = plan(ScoreState())
        #expect(plan.step(for: "g.two.u")?.unit == "g.two")
        #expect(plan.step(for: "g.two") == nil)
        #expect(plan.step(for: "not.a.node") == nil)
    }
}
