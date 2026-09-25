import Foundation
import Testing

@testable import GraphCore

/// Phase 16's exit criterion, asserted where it is assertable: a dialogue is
/// played ahead of `steps`, a reflection is its own kind of card, the artifact
/// stays byte-stable for lessons that have neither, and the dialogue contract's
/// rules each catch the failure they are named for — while binding only a lesson
/// that opted in.
@Suite("Socratic dialogues")
struct DialogueTests {

    private static let graph = KnowledgeGraph(nodes: [
        Fixtures.branch("g", "Ground"),
        Fixtures.subbranch("g.one", under: "g", "One"),
        Fixtures.content("g.one.r", .definition, .standard, "R", under: "g.one"),
    ])

    private static let spine = ProgramSpine(parts: [.init(title: "Part", units: ["g.one"])])

    private static func diagnose(
        steps: [LessonCard] = [], dialogue: [LessonCard] = []
    ) -> Set<DiagnosticRule> {
        let program = Program(
            spine: spine,
            lessonUnits: [
                LessonUnit(
                    unit: "g.one", opening: "An opening.",
                    lessons: [
                        Lesson(
                            node: "g.one.r", hook: "H", explanation: "E", recap: "R",
                            steps: steps, dialogue: dialogue)
                    ])
            ])
        return Set(ProgramValidator.validate(program, against: graph).map(\.rule))
    }

    private static func choice(_ correct: Bool = false, why: String? = "Because.") -> AnswerChoice {
        AnswerChoice(text: correct ? "Right" : "Wrong", correct: correct, feedback: why)
    }

    private static let question = LessonCard(
        ask: "Which?", choices: [choice(true), choice()], feedback: "The reason.")
    private static let reflection = LessonCard(
        reflect: "What does the first attempt do twice?", answer: "It re-adds the overlap.")

    /// The smallest dialogue the contract accepts: two parts, five questions, a
    /// reflection, never more than two beats between questions.
    private static let wellFormed: [LessonCard] = [
        LessonCard(teach: "A concrete puzzle, with numbers.", part: "A question"),
        question,
        LessonCard(ask: "How many?", expects: "4", feedback: "Two times two."),
        reflection,
        LessonCard(teach: "The idea, named now that you reached for it.", part: "The idea"),
        LessonCard(teach: "Why it holds."),
        question,
        question,
    ]

    // MARK: - The model

    @Test("A dialogue is played ahead of steps, and counts as authored")
    func dialogueWinsOverSteps() {
        let lesson = Lesson(
            node: "g.one.r", hook: "H", explanation: "E", recap: "R",
            dialogue: Self.wellFormed)
        #expect(lesson.isDialogue)
        #expect(lesson.isInteractive)
        #expect(lesson.cards == Self.wellFormed)
        #expect(lesson.checkCount == 4)
        #expect(lesson.reflectionCount == 1)
    }

    @Test("A reflection is a question the dialogue waits on, and not a check")
    func reflectionIsItsOwnKind() {
        let card = Self.reflection
        #expect(card.isReflection)
        #expect(card.isQuestion)
        #expect(!card.isCheck)
        #expect(card.check == nil)
        #expect(card.prompt == "What does the first attempt do twice?")
        #expect(!LessonCard(teach: "A beat.").isQuestion)
        #expect(LessonCard(teach: "A beat.", part: "  Opening  ").partTitle == "Opening")
        #expect(LessonCard(teach: "A beat.", part: "   ").partTitle == nil)
    }

    @Test("A lesson with neither steps nor dialogue encodes neither key")
    func absentDialogueEncodesAway() throws {
        let lesson = Lesson(node: "g.one.r", hook: "H", explanation: "E", recap: "R")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(lesson), as: UTF8.self)
        #expect(!json.contains("dialogue"))
        #expect(!json.contains("steps"))
    }

    @Test("A dialogue round-trips its parts and reflections")
    func dialogueRoundTrips() throws {
        let lesson = Lesson(
            node: "g.one.r", hook: "H", explanation: "E", recap: "R",
            dialogue: Self.wellFormed)
        let data = try JSONEncoder().encode(lesson)
        #expect(try JSONDecoder().decode(Lesson.self, from: data) == lesson)
        let beat = String(
            decoding: try JSONEncoder().encode(LessonCard(teach: "A beat.")), as: UTF8.self)
        for key in ["part", "reflect", "answer"] {
            #expect(!beat.contains(key), "\(key) leaked into a plain beat")
        }
    }

    // MARK: - Per-card rules

    @Test("The well-formed dialogue is clean")
    func wellFormedIsClean() {
        #expect(Self.diagnose(dialogue: Self.wellFormed).isEmpty)
    }

    @Test("A reflection needs its answer, and an answer needs its reflection")
    func reflectionRules() {
        #expect(
            Self.diagnose(steps: [LessonCard(reflect: "Why?")])
                .contains(.lessonReflectionMissingAnswer))
        #expect(
            Self.diagnose(steps: [LessonCard(teach: "A beat.", answer: "Stray.")])
                .contains(.lessonStrayAnswer))
        #expect(
            Self.diagnose(steps: [LessonCard(ask: "?", reflect: "Why?", answer: "A", expects: "1", feedback: "F")])
                .contains(.lessonCardAmbiguous))
        #expect(
            Self.diagnose(steps: [LessonCard(reflect: "Why?", answer: "A", expects: "1")])
                .contains(.lessonTeachCardAnswerable))
        // A reflection is legal in plain steps too — only the contract is opt-in.
        #expect(Self.diagnose(steps: [Self.reflection]).isEmpty)
    }

    // MARK: - The contract (opt-in)

    @Test("Steps and a dialogue on one lesson is an error")
    func stepsAndDialogue() {
        #expect(
            Self.diagnose(steps: [LessonCard(teach: "Old.")], dialogue: Self.wellFormed)
                .contains(.lessonStepsAndDialogue))
    }

    @Test("A dialogue opens a part")
    func opensWithPart() {
        var cards = Self.wellFormed
        cards[0] = LessonCard(teach: "A puzzle.")
        #expect(Self.diagnose(dialogue: cards).contains(.dialogueOpensWithoutPart))
    }

    @Test("Three beats in a row is a lecture")
    func lecture() {
        var cards = Self.wellFormed
        cards.insert(LessonCard(teach: "A third beat."), at: 6)
        #expect(Self.diagnose(dialogue: cards).contains(.dialogueLecture))
        // The same run in plain steps is not held to the contract.
        let lecture = [
            LessonCard(teach: "One."), LessonCard(teach: "Two."), LessonCard(teach: "Three."),
            Self.question,
        ]
        #expect(!Self.diagnose(steps: lecture).contains(.dialogueLecture))
    }

    @Test("Too few questions or a single part is thin")
    func thin() {
        #expect(
            Self.diagnose(dialogue: Array(Self.wellFormed.prefix(4))).contains(.dialogueThin))
        let onePart = Self.wellFormed.map {
            $0.partTitle == "The idea"
                ? LessonCard(teach: $0.teach) : $0
        }
        #expect(Self.diagnose(dialogue: onePart).contains(.dialogueThin))
    }

    @Test("A dialogue with no reflection is caught")
    func noReflection() {
        let cards = Self.wellFormed.map { $0.isReflection ? Self.question : $0 }
        #expect(Self.diagnose(dialogue: cards).contains(.dialogueNoReflection))
    }

    @Test("A choice with no why is caught in a dialogue, not in steps")
    func choiceWithoutWhy() {
        let silent = LessonCard(
            ask: "Which?", choices: [Self.choice(true), Self.choice(why: nil)],
            feedback: "The reason.")
        var cards = Self.wellFormed
        cards[1] = silent
        #expect(Self.diagnose(dialogue: cards).contains(.dialogueChoiceWithoutWhy))
        #expect(!Self.diagnose(steps: [silent]).contains(.dialogueChoiceWithoutWhy))
    }

    // MARK: - The session (D16.1, D16.3)

    @Test("The transcript shows everything through the first unanswered question")
    func gateIsFirstOpenQuestion() {
        var session = DialogueSession(cards: Self.wellFormed)
        #expect(session.gate == 1)
        #expect(session.visibleCount == 2)
        #expect(session.pick(0, at: 1) == .correct)
        #expect(session.gate == 2)
        #expect(session.submit("4", at: 2) == .correct)
        session.reflect("  It adds twice.  ", at: 3)
        #expect(session.written[3] == "It adds twice.")
        // Two beats, then the next question: the stretch unfolds together.
        #expect(session.gate == 6)
        #expect(session.visibleCount == 7)
        session.reveal(at: 6)
        session.reveal(at: 7)
        #expect(session.isFinished)
        #expect(session.visibleCount == Self.wellFormed.count)
        #expect(session.firstTryCount == 2)
        #expect(session.shownCount == 2)
    }

    @Test("A wrong row is kept and ruled out, and the right one counts the tries")
    func wrongPicksAreKept() {
        var session = DialogueSession(cards: Self.wellFormed)
        #expect(session.pick(1, at: 1) == .wrong)
        #expect(session.pick(1, at: 1) == .ignored)
        #expect(session.wrongPicks[1] == [1])
        #expect(!session.isResolved(1))
        #expect(session.pick(0, at: 1) == .correct)
        #expect(session.outcomes[1] == .answered(tries: 2))
        // A resolved question takes no more answers.
        #expect(session.pick(1, at: 1) == .ignored)
    }

    @Test("A wrong typed value says which way it missed; unreadable input is not an attempt")
    func typedMisses() {
        let card = LessonCard(ask: "How many?", expects: "250", feedback: "F.")
        var session = DialogueSession(cards: [card])
        #expect(session.submit("seven", at: 0) == .ignored)
        #expect(session.misses[0] == nil)
        #expect(session.submit("300", at: 0) == .wrong)
        #expect(session.submit("200", at: 0) == .wrong)
        #expect(session.submit("25", at: 0) == .wrong)
        #expect(session.misses[0]?.map(\.direction) == [.tooHigh, .tooLow, .factor(10)])
        #expect(session.submit("250", at: 0) == .correct)
        #expect(session.outcomes[0] == .answered(tries: 4))
    }

    @Test("A lesson with no questions has no gate and shows whole")
    func noQuestionsNoGate() {
        let session = DialogueSession(cards: [LessonCard(teach: "One."), LessonCard(teach: "Two.")])
        #expect(session.gate == nil)
        #expect(session.isFinished)
        #expect(session.visibleCount == 2)
    }

    @Test("Parts follow the part titles, with an untitled lead-in for plain steps")
    func partsFollowTitles() {
        let dialogue = DialogueSession(cards: Self.wellFormed)
        #expect(dialogue.parts.map(\.title) == ["A question", "The idea"])
        #expect(dialogue.parts.map(\.cards) == [0..<4, 4..<8])
        let plain = DialogueSession(cards: [LessonCard(teach: "One."), Self.question])
        #expect(plain.parts.map(\.title) == [nil])
        #expect(!plain.hasTitledParts)
    }

    @Test("The seam answers every question through a card, first time")
    func seamAnswersThrough() {
        var session = DialogueSession(cards: Self.wellFormed)
        session.answerCorrectly(through: 6)
        #expect(session.gate == 7)
        #expect(session.outcomes[1] == .answered(tries: 1))
        #expect(session.outcomes[2] == .answered(tries: 1))
        #expect(session.outcomes[3] == .reflected)
    }
}
