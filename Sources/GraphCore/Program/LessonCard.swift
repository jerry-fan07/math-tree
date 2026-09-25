import Foundation

/// §6.7's unit of a lesson, and §6.9's step of a dialogue.
///
/// A card is exactly one of three things — a **teaching beat** (`teach`), a
/// **check** (`ask`, machine-graded), or a **reflection** (`reflect`, §6.9: an
/// open question the reader answers in their own words and then compares with
/// the tutor's `answer`). One of the three, never two — enforced by the
/// validator rather than by the type, because YAML has no sum types and an
/// author who writes two should be told which line to delete rather than have
/// one silently win.
///
/// Any card may also open a **part** of a dialogue (`part:`, a short title) —
/// the dialogue's sections, which the player sets as headings and lists in its
/// outline.
///
/// The check's fields (`choices`, `expects`, `tolerance`, `feedback`) sit *inline*
/// rather than under a nested `check:` mapping (D13.3): the authored form stays
/// flat, and `AnswerCheck` is composed from them on read.
public struct LessonCard: Codable, Hashable, Sendable {
    /// A teaching beat — one idea, two or three sentences. Present exactly when
    /// this is neither a check nor a reflection.
    public let teach: String?
    /// The question. Present exactly when this is a check.
    public let ask: String?
    /// §6.9's open question: the reader writes an answer, then reads the tutor's.
    /// Present exactly when this is a reflection.
    public let reflect: String?
    /// The tutor's answer to a reflection — better than what a reader will write:
    /// it names the idea and says why. Present exactly on a reflection.
    public let answer: String?
    /// §6.9: the title of the dialogue part this card opens, or `nil` when the
    /// card continues the current one.
    public let part: String?
    /// Multiple-choice rows. Empty on a typed check and on a teaching card.
    public let choices: [AnswerChoice]
    /// The expected value of a typed check, as the author wrote it.
    public let expects: String?
    /// Absolute tolerance for a typed check; `nil` is effectively exact.
    public let tolerance: Double?
    /// Offered before the reader answers, on request — never shown unasked.
    public let hint: String?
    /// The canonical explanation, shown once the check resolves.
    public let feedback: String?
    /// True for a card the player *derived* from a lesson's prose rather than one
    /// an author wrote (D13.1). Never encoded: it is a property of how the card
    /// was obtained, not of the corpus.
    public let isDerived: Bool

    public init(
        teach: String? = nil,
        ask: String? = nil,
        reflect: String? = nil,
        answer: String? = nil,
        part: String? = nil,
        choices: [AnswerChoice] = [],
        expects: String? = nil,
        tolerance: Double? = nil,
        hint: String? = nil,
        feedback: String? = nil,
        isDerived: Bool = false
    ) {
        self.teach = teach
        self.ask = ask
        self.reflect = reflect
        self.answer = answer
        self.part = part
        self.choices = choices
        self.expects = expects
        self.tolerance = tolerance
        self.hint = hint
        self.feedback = feedback
        self.isDerived = isDerived
    }

    /// The check this card poses, or `nil` on a teaching card.
    public var check: AnswerCheck? {
        guard ask?.trimmed.isEmpty == false else { return nil }
        return AnswerCheck(
            choices: choices, expects: expects, tolerance: tolerance, feedback: feedback)
    }

    public var isCheck: Bool { ask?.trimmed.isEmpty == false }

    /// §6.9's reflection: an open question with a model answer, graded by the
    /// reader against the tutor rather than by the app.
    public var isReflection: Bool { !isCheck && reflect?.trimmed.isEmpty == false }

    /// Whether the dialogue waits on this card — a check or a reflection. A
    /// teaching beat never waits; it is read on the way to the next question.
    public var isQuestion: Bool { isCheck || isReflection }

    /// The part title this card opens, trimmed, or `nil`.
    public var partTitle: String? {
        guard let part = part?.trimmed, !part.isEmpty else { return nil }
        return part
    }

    /// What the card shows above the fold — the beat, or the question.
    public var prompt: String {
        (isCheck ? ask : (isReflection ? reflect : teach)) ?? ""
    }

    /// Every renderable field, for the corpus self-check.
    public var renderableFields: [(field: String, source: String)] {
        var out: [(String, String)] = []
        if let part { out.append(("card.part", part)) }
        if let teach { out.append(("card.teach", teach)) }
        if let ask { out.append(("card.ask", ask)) }
        if let reflect { out.append(("card.reflect", reflect)) }
        if let answer { out.append(("card.answer", answer)) }
        if let hint { out.append(("card.hint", hint)) }
        if let check { out.append(contentsOf: check.renderableFields.map { ("card.\($0.0)", $0.1) }) }
        return out
    }

    enum CodingKeys: String, CodingKey {
        case part, teach, ask, reflect, answer, choices, expects, tolerance, hint, feedback
    }

    // Hand-written for the same reason `Lesson`'s is: absent fields decode as nil
    // and encode away again, so `program.json` stays byte-stable (ground rule 5).
    // `isDerived` is deliberately absent from `CodingKeys` — a derived card never
    // round-trips through the artifact.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teach = try c.decodeIfPresent(String.self, forKey: .teach)
        ask = try c.decodeIfPresent(String.self, forKey: .ask)
        reflect = try c.decodeIfPresent(String.self, forKey: .reflect)
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
        part = try c.decodeIfPresent(String.self, forKey: .part)
        choices = try c.decodeIfPresent([AnswerChoice].self, forKey: .choices) ?? []
        expects = try c.decodeIfPresent(String.self, forKey: .expects)
        tolerance = try c.decodeIfPresent(Double.self, forKey: .tolerance)
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
        feedback = try c.decodeIfPresent(String.self, forKey: .feedback)
        isDerived = false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(part, forKey: .part)
        try c.encodeIfPresent(teach, forKey: .teach)
        try c.encodeIfPresent(ask, forKey: .ask)
        try c.encodeIfPresent(reflect, forKey: .reflect)
        try c.encodeIfPresent(answer, forKey: .answer)
        if !choices.isEmpty { try c.encode(choices, forKey: .choices) }
        try c.encodeIfPresent(expects, forKey: .expects)
        try c.encodeIfPresent(tolerance, forKey: .tolerance)
        try c.encodeIfPresent(hint, forKey: .hint)
        try c.encodeIfPresent(feedback, forKey: .feedback)
    }
}

// MARK: - Paging a lesson

extension Lesson {
    /// §6.7's cards: what the player plays.
    ///
    /// §6.9's `dialogue` when the lesson has one, then authored `steps`, and
    /// otherwise a **derivation from the prose already written** (D13.1) — the
    /// hook, each paragraph of the
    /// explanation, then worked, interview, pitfalls and recap, one card each, in
    /// the reader's own order. That fallback is why "click any node and be taught
    /// it in pieces" is true for the whole corpus on the day the player ships,
    /// rather than only for the units someone has since re-authored.
    public var cards: [LessonCard] {
        if !dialogue.isEmpty { return dialogue }
        if !steps.isEmpty { return steps }
        return derivedCards
    }

    /// The cards an author wrote — the dialogue, or the steps — and empty when
    /// the player would derive them.
    public var authoredCards: [LessonCard] { dialogue.isEmpty ? steps : dialogue }

    /// Whether this lesson's cards were authored — which is also, in practice,
    /// whether it can *check* anything: a derived card is prose, and prose asks
    /// nothing.
    public var isInteractive: Bool { !authoredCards.isEmpty }

    /// §6.9: whether this lesson is taught as a Socratic dialogue — questions
    /// first, the idea named only once the reader has reached for it.
    public var isDialogue: Bool { !dialogue.isEmpty }

    /// Whether an authored lesson actually poses a question. A `steps` list of
    /// nothing but `teach` cards pages nicely and still measures nothing, which is
    /// what `lesson-steps-no-check` exists to hint about.
    public var checkCount: Int { authoredCards.count(where: \.isCheck) }

    /// §6.9's reflections among the authored cards.
    public var reflectionCount: Int { authoredCards.count(where: \.isReflection) }

    private var derivedCards: [LessonCard] {
        var out: [LessonCard] = []
        func add(_ text: String?) {
            guard let text, !text.trimmed.isEmpty else { return }
            // A folded YAML scalar keeps blank lines as newlines, so an
            // explanation arrives with its paragraph breaks intact — which is the
            // only structure the prose offers, so it is the only place to cut.
            for paragraph in text.split(separator: "\n").map({ String($0).trimmed })
            where !paragraph.isEmpty {
                out.append(LessonCard(teach: paragraph, isDerived: true))
            }
        }
        add(hook)
        add(explanation)
        add(worked)
        add(interview)
        add(pitfalls)
        add(recap)
        return out
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
