import Foundation
import Testing

@testable import GraphCore

/// Phase 13's exit criterion, asserted where it is assertable: a lesson with no
/// authored `steps` still pages; a check accepts every spelling of its answer the
/// parser promises and rejects a near miss outside tolerance; the card and check
/// rules catch the silent failure modes; and the mastery set is the probe ladder
/// read backwards.
@Suite("Interactive lessons")
struct InteractiveLessonTests {

    // MARK: - The answer parser (D13.4)

    @Test("Every spelling of the same number reads as the same number")
    func theParserIsGenerousAboutSpelling() {
        let seven15 = 7.0 / 15.0
        for spelling in ["7/15", "7 / 15", "$7/15$", "\\frac{7}{15}", "$\\dfrac{7}{15}$"] {
            #expect(NumericAnswer.value(of: spelling) == seven15, "\(spelling)")
        }
        #expect(NumericAnswer.value(of: "0.5") == 0.5)
        #expect(NumericAnswer.value(of: "50%") == 0.5)
        #expect(NumericAnswer.value(of: "\\frac{1}{2}") == 0.5)
        #expect(NumericAnswer.value(of: "1,024") == 1024)
        #expect(NumericAnswer.value(of: " -3 ") == -3)
        #expect(NumericAnswer.value(of: "2e-3") == 0.002)
        #expect(NumericAnswer.value(of: "0") == 0)
    }

    /// The parser stops at one fraction and plain decimals on purpose: anything it
    /// evaluates, it can silently disagree with the author about.
    @Test("Anything that is not one number is unreadable rather than guessed at")
    func theParserIsStrictAboutValue() {
        for junk in ["", "  ", "abc", "3/4/5", "1/0", "1 + 2", "x", "nan", "inf", "0x1p3", "7/"] {
            #expect(NumericAnswer.value(of: junk) == nil, "\(junk)")
        }
    }

    // MARK: - Grading (D13.5)

    @Test("A typed check accepts the spellings and rejects a near miss outside tolerance")
    func aTypedCheckComparesNumerically() throws {
        let exact = try #require(
            AnswerCheck(expects: "7/15", feedback: "Because the union has 7 of 15 outcomes."))
        #expect(exact.form == .typed)
        #expect(exact.isCorrect(typed: "7/15"))
        #expect(exact.isCorrect(typed: "$\\frac{7}{15}$"))
        // Rounded to four places is *not* 7/15, and with no authored tolerance the
        // check says so rather than guessing how much rounding was intended.
        #expect(!exact.isCorrect(typed: "0.4667"))
        #expect(!exact.isCorrect(typed: "8/15"))
        #expect(!exact.isCorrect(typed: "who knows"))

        let rounded = try #require(
            AnswerCheck(expects: "7/15", tolerance: 0.001, feedback: "As above."))
        #expect(rounded.isCorrect(typed: "0.4667"))
        #expect(rounded.isCorrect(typed: "46.67%"))
        #expect(!rounded.isCorrect(typed: "0.46"))
    }

    @Test("A choice check is right on exactly the row marked correct")
    func aChoiceCheckGradesTheMarkedRow() throws {
        let check = try #require(
            AnswerCheck(
                choices: [
                    AnswerChoice(text: "$1/6$", feedback: "That is one face, not the pair."),
                    AnswerChoice(text: "$1/36$", correct: true),
                ],
                feedback: "Two independent faces multiply."))
        #expect(check.form == .choice)
        #expect(check.correctIndex == 1)
        #expect(check.isCorrect(choiceAt: 1))
        #expect(!check.isCorrect(choiceAt: 0))
        // Out of range is wrong, not a crash: the shot seams and a stale @State
        // index can both reach here.
        #expect(!check.isCorrect(choiceAt: 7))
        #expect(!check.isCorrect(choiceAt: -1))
        // Per-choice words where authored, the check's own otherwise.
        #expect(check.feedback(forChoiceAt: 0) == "That is one face, not the pair.")
        #expect(check.feedback(forChoiceAt: 1) == "Two independent faces multiply.")
    }

    @Test("A host that declared no answer has no check")
    func anUnansweredHostHasNoCheck() {
        #expect(AnswerCheck(feedback: "unused") == nil)
        #expect(AnswerCheck(choices: [], expects: "   ", feedback: "unused") == nil)
        #expect(LessonCard(teach: "A beat.").check == nil)
        #expect(!LessonCard(teach: "A beat.").isCheck)
    }

    // MARK: - Derived cards (D13.1)

    /// The claim Phase 13's deliverable rests on: *every* node with a lesson
    /// pages, whether or not anyone has authored cards for it.
    @Test("A lesson with no steps pages off its prose, one card per section")
    func aLessonWithNoStepsStillPages() {
        let lesson = Lesson(
            node: "g.one.r",
            hook: "The hook.",
            explanation: "First paragraph.\n\nSecond paragraph.",
            worked: "The worked example.",
            interview: "The interview note.",
            pitfalls: "The traps.",
            recap: "The recap.")
        #expect(!lesson.isInteractive)
        let cards = lesson.cards
        // hook + two explanation paragraphs + worked + interview + pitfalls + recap
        #expect(cards.count == 7)
        #expect(cards.allSatisfy { $0.isDerived })
        #expect(cards.allSatisfy { !$0.isCheck })
        #expect(cards.first?.teach == "The hook.")
        #expect(cards[1].teach == "First paragraph.")
        #expect(cards[2].teach == "Second paragraph.")
        #expect(cards.last?.teach == "The recap.")
    }

    @Test("Absent optional sections simply do not become cards")
    func derivationSkipsWhatWasNotAuthored() {
        let lesson = Lesson(
            node: "g.one.r", hook: "Hook.", explanation: "Body.", recap: "Recap.")
        #expect(lesson.cards.count == 3)
    }

    @Test("Authored steps replace the derivation entirely")
    func authoredStepsWin() {
        let lesson = Lesson(
            node: "g.one.r",
            hook: "The hook.",
            explanation: "A paragraph.\n\nAnother.",
            recap: "The recap.",
            steps: [
                LessonCard(teach: "One beat."),
                LessonCard(ask: "How many?", expects: "2", feedback: "Two."),
            ])
        #expect(lesson.isInteractive)
        #expect(lesson.cards.count == 2)
        #expect(lesson.cards.allSatisfy { !$0.isDerived })
        #expect(lesson.checkCount == 1)
    }

    // MARK: - Byte stability (ground rule 5)

    @Test("A lesson with no steps round-trips without growing a steps key")
    func absentStepsEncodeAway() throws {
        let lesson = Lesson(node: "g.one.r", hook: "H", explanation: "E", recap: "R")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(lesson)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("steps"))
        #expect(try JSONDecoder().decode(Lesson.self, from: data) == lesson)
    }

    @Test("A card round-trips its authored fields and nothing else")
    func cardsRoundTrip() throws {
        let card = LessonCard(
            ask: "Which?",
            choices: [
                AnswerChoice(text: "A"),
                AnswerChoice(text: "B", correct: true, feedback: "Yes."),
            ],
            hint: "Think.",
            feedback: "Because B.")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(card)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("teach"))
        #expect(!json.contains("expects"))
        #expect(!json.contains("tolerance"))
        // `correct: false` is the default and encodes away; the true one stays.
        #expect(json.components(separatedBy: "\"correct\"").count - 1 == 1)
        #expect(try JSONDecoder().decode(LessonCard.self, from: data) == card)
    }

    @Test("A problem with no check round-trips unchanged")
    func uncheckedProblemsRoundTrip() throws {
        let problem = Problem(
            id: "p-01", kind: .justify, statement: "Prove it.", answer: "A proof.",
            rubric: ["States the hypotheses."], targets: ["g.one.r"])
        #expect(problem.check == nil)
        #expect(!problem.isChecked)
        let data = try JSONEncoder().encode(problem)
        let json = String(decoding: data, as: UTF8.self)
        for key in ["expects", "tolerance", "choices", "feedback"] {
            #expect(!json.contains(key), "\(key) leaked into an unchecked problem")
        }
        #expect(try JSONDecoder().decode(Problem.self, from: data) == problem)
    }

    /// D13.3: a checked problem keeps its rubric — the check scopes §5.2's "math
    /// free response cannot be machine-graded", it does not repeal it.
    @Test("A checked problem carries both a machine answer and a rubric")
    func aCheckedProblemKeepsItsRubric() throws {
        let problem = Problem(
            id: "p-02", kind: .work, statement: "Compute it.", answer: "It is $7/15$.",
            rubric: ["Counts the complement."], targets: ["g.one.r"], expects: "7/15")
        let check = try #require(problem.check)
        #expect(check.isCorrect(typed: "7/15"))
        // With no authored `feedback`, the worked answer is the explanation.
        #expect(check.feedback == "It is $7/15$.")
        #expect(!problem.rubric.isEmpty)
    }

    // MARK: - The mastery set (D13.6)

    @Test("The mastery set is the probe ladder read backwards")
    func masterySetsAreHardestFirst() {
        let bank = ProblemBank(problems: [
            Self.problem("m-easy", .routine),
            Self.problem("m-hard", .demanding),
            Self.problem("m-mid", .standard),
            Self.problem("m-hard-2", .demanding),
        ])
        // The probe ladder opens with the easiest problem in the bank…
        #expect(bank.problems(targeting: "g.one.r").first?.id == "m-easy")
        // …and the mastery set opens with the hardest, ties broken by id so the
        // order is stable across runs.
        let mastery = bank.masterySet(for: "g.one.r")
        #expect(mastery.map(\.id) == ["m-hard", "m-hard-2", "m-mid"])
        #expect(bank.masterySet(for: "g.one.r", limit: 1).map(\.id) == ["m-hard"])
        #expect(bank.masterySet(for: "g.one.r", limit: 0).isEmpty)
        #expect(bank.masterySet(for: "g.one.nothing").isEmpty)
    }

    private static func problem(_ id: ProblemID, _ difficulty: Problem.Difficulty) -> Problem {
        Problem(
            id: id, kind: .work, statement: "S", answer: "A", rubric: ["R"],
            targets: ["g.one.r"], difficulty: difficulty)
    }

    // MARK: - Validation

    private static let graph = KnowledgeGraph(nodes: [
        Fixtures.branch("g", "Ground"),
        Fixtures.subbranch("g.one", under: "g", "One"),
        Fixtures.content("g.one.r", .definition, .standard, "R", under: "g.one"),
    ])

    private static let spine = ProgramSpine(parts: [.init(title: "Part", units: ["g.one"])])

    private static func diagnose(_ steps: [LessonCard]) -> Set<DiagnosticRule> {
        let program = Program(
            spine: spine,
            lessonUnits: [
                LessonUnit(
                    unit: "g.one", opening: "An opening.",
                    lessons: [
                        Lesson(
                            node: "g.one.r", hook: "H", explanation: "E", recap: "R", steps: steps)
                    ])
            ])
        return Set(ProgramValidator.validate(program, against: graph).map(\.rule))
    }

    @Test("A well-formed steps list is clean")
    func goodCardsValidate() {
        #expect(
            Self.diagnose([
                LessonCard(teach: "A beat."),
                LessonCard(ask: "How many?", expects: "2", feedback: "Two."),
                LessonCard(
                    ask: "Which?",
                    choices: [AnswerChoice(text: "A", correct: true), AnswerChoice(text: "B")],
                    feedback: "A."),
            ]).isEmpty)
    }

    /// A lesson with no steps is not a finding: paging falls back to the prose,
    /// and interactivity coverage is a lint hint plus a `validate` report (D12.4's
    /// split, reused).
    @Test("No steps at all is not a violation")
    func absentStepsAreNotAViolation() {
        #expect(Self.diagnose([]).isEmpty)
    }

    @Test("Each way a card can be silently broken is a named rule")
    func badCardsAreCaught() {
        #expect(Self.diagnose([LessonCard()]).contains(.lessonCardEmpty))
        #expect(
            Self.diagnose([LessonCard(teach: "A beat.", ask: "A question?", expects: "1", feedback: "F")])
                .contains(.lessonCardAmbiguous))
        #expect(
            Self.diagnose([LessonCard(teach: "A beat.", expects: "1")])
                .contains(.lessonTeachCardAnswerable))
        #expect(Self.diagnose([LessonCard(ask: "?", feedback: "F")]).contains(.checkUnanswerable))
        #expect(
            Self.diagnose([
                LessonCard(ask: "?", choices: [AnswerChoice(text: "A", correct: true)], feedback: "F")
            ]).contains(.checkThinChoices))
        #expect(
            Self.diagnose([
                LessonCard(
                    ask: "?", choices: [AnswerChoice(text: "A"), AnswerChoice(text: "B")],
                    feedback: "F")
            ]).contains(.checkNoCorrectChoice))
        #expect(
            Self.diagnose([
                LessonCard(
                    ask: "?",
                    choices: [
                        AnswerChoice(text: "A", correct: true), AnswerChoice(text: "B", correct: true),
                    ], feedback: "F")
            ]).contains(.checkManyCorrectChoices))
        #expect(
            Self.diagnose([
                LessonCard(
                    ask: "?", choices: [AnswerChoice(text: ""), AnswerChoice(text: "B", correct: true)],
                    feedback: "F")
            ]).contains(.emptyChoiceText))
        #expect(
            Self.diagnose([
                LessonCard(
                    ask: "?", choices: [AnswerChoice(text: "A", correct: true), AnswerChoice(text: "B")],
                    expects: "1", feedback: "F")
            ]).contains(.checkAmbiguous))
        #expect(Self.diagnose([LessonCard(ask: "?", expects: "1")]).contains(.checkMissingFeedback))
        #expect(
            Self.diagnose([LessonCard(ask: "?", expects: "1", tolerance: 0, feedback: "F")])
                .contains(.checkNonPositiveTolerance))
    }

    /// The worst failure this layer has: an `expects` the parser cannot read
    /// reaches a reader as "your correct answer is wrong". It fails the build.
    @Test("An unparsable expected answer fails the build")
    func unparsableAnswersFailTheBuild() {
        #expect(
            Self.diagnose([LessonCard(ask: "How many?", expects: "about seven", feedback: "F")])
                .contains(.checkUnparsableAnswer))
        #expect(
            Self.diagnose([LessonCard(ask: "How many?", expects: "7/15", feedback: "F")])
                .isEmpty)
    }

    @Test("The same rules hold a bank problem's check, and only when it has one")
    func problemChecksAreValidatedByTheSameRules() {
        func diagnose(_ problem: Problem) -> Set<DiagnosticRule> {
            Set(ProblemValidator.validate(problems: [problem], against: Self.graph).map(\.rule))
        }
        // Self-graded is the norm, not a finding.
        #expect(
            !diagnose(
                Problem(
                    id: "p-01", kind: .justify, statement: "S", answer: "A", rubric: ["R"],
                    targets: ["g.one.r"])
            ).contains(.checkUnanswerable))
        #expect(
            diagnose(
                Problem(
                    id: "p-02", kind: .work, statement: "S", answer: "A", rubric: ["R"],
                    targets: ["g.one.r"], expects: "roughly a half")
            ).contains(.checkUnparsableAnswer))
        #expect(
            diagnose(
                Problem(
                    id: "p-03", kind: .decide, statement: "S", answer: "A", rubric: ["R"],
                    targets: ["g.one.r"],
                    choices: [AnswerChoice(text: "yes"), AnswerChoice(text: "no")])
            ).contains(.checkNoCorrectChoice))
    }

    @Test("Lint hints name a paged slideshow and a lesson split in two")
    func lintHintsCoverAuthoredCards() {
        func hints(_ steps: [LessonCard]) -> Set<LintHint.Rule> {
            let program = Program(
                spine: Self.spine,
                lessonUnits: [
                    LessonUnit(
                        unit: "g.one", opening: "An opening.",
                        lessons: [
                            Lesson(
                                node: "g.one.r",
                                hook: "H",
                                explanation: String(repeating: "Teaching. ", count: 60),
                                recap: "R", steps: steps)
                        ])
                ])
            return Set(ContentLint.hints(for: program, graph: Self.graph).map(\.rule))
        }
        let paged = Array(repeating: LessonCard(teach: "A beat."), count: 5)
        #expect(hints(paged).contains(.lessonStepsNoCheck))
        #expect(!hints(paged).contains(.thinLessonSteps))
        #expect(
            hints([LessonCard(ask: "?", expects: "1", feedback: "F")]).contains(.thinLessonSteps))
        // A lesson with no authored cards is not hinted about at all — hinting on
        // all 958 would bury every hint that names a fixable defect.
        #expect(hints([]).isEmpty)
    }
}
