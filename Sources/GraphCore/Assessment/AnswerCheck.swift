import Foundation

/// One option of a multiple-choice check (§6.7).
///
/// `feedback` is per-*choice* on purpose: "incorrect" teaches nothing, and the
/// whole reason a distractor is worth authoring is that it corresponds to a
/// specific mistake worth naming. It stays optional so a choice that is simply
/// wrong for the obvious reason can fall back to the check's own feedback.
public struct AnswerChoice: Codable, Hashable, Sendable {
    /// What the reader sees, LaTeX allowed as `$...$` exactly like a `statement`.
    public let text: String
    /// Exactly one choice of a check is correct (the validator enforces it).
    public let correct: Bool
    /// Why *this* answer is right or wrong.
    public let feedback: String?

    public init(text: String, correct: Bool = false, feedback: String? = nil) {
        self.text = text
        self.correct = correct
        self.feedback = feedback
    }

    enum CodingKeys: String, CodingKey {
        case text, correct, feedback
    }

    // Hand-written for the same reason `Node`'s is: `correct: false` and an absent
    // `feedback` encode away again, so both artifacts stay byte-stable (ground
    // rule 5).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        correct = try c.decodeIfPresent(Bool.self, forKey: .correct) ?? false
        feedback = try c.decodeIfPresent(String.self, forKey: .feedback)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        if correct { try c.encode(correct, forKey: .correct) }
        try c.encodeIfPresent(feedback, forKey: .feedback)
    }
}

/// §6.7's machine-checkable question, in the one shape that serves both hosts: a
/// lesson card's check and a bank problem's final answer.
///
/// Deliberately **not** `Codable` (D13.3). It is *composed* from fields the host
/// declares inline — `choices`, `expects`, `tolerance`, `feedback` — so a card and
/// a problem both stay flat in YAML and both artifacts keep ground rule 5's
/// `encodeIfPresent` byte stability. What lives here is the part that must not be
/// written twice: the grading, and the diagnostics.
///
/// Two forms, distinguished by which field is populated rather than by a tag the
/// author could contradict:
///
/// - **choice** — `choices` non-empty. The reader picks a row.
/// - **typed** — `expects` non-nil. The reader types a value, compared
///   *numerically* through `NumericAnswer` (D13.4: generous about spelling,
///   strict about value).
public struct AnswerCheck: Hashable, Sendable {
    public enum Form: String, Hashable, Sendable {
        case choice
        case typed
    }

    public let choices: [AnswerChoice]
    /// The expected value of a typed check, as the author wrote it (`7/15`,
    /// `0.4667`, `\frac{1}{6}`). Displayed verbatim on reveal; compared through
    /// `NumericAnswer`.
    public let expects: String?
    /// Absolute tolerance for the numeric comparison. `nil` means
    /// `defaultRelativeTolerance`, which is effectively exact — an answer that is
    /// irrational or long-decimal states its own.
    public let tolerance: Double?
    /// The canonical explanation, shown once the check resolves however it
    /// resolved. Required: a reader who guessed right still needs the reason.
    public let feedback: String

    /// `nil` when the host declared no answerable content at all — a teaching card,
    /// or a problem that self-grades against its rubric. The validator reports the
    /// cases where that is a mistake; this initializer just declines to invent a
    /// check that was never authored.
    public init?(
        choices: [AnswerChoice] = [], expects: String? = nil, tolerance: Double? = nil,
        feedback: String?
    ) {
        let trimmedExpects = expects?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasExpects = !(trimmedExpects ?? "").isEmpty
        guard !choices.isEmpty || hasExpects else { return nil }
        self.choices = choices
        self.expects = hasExpects ? trimmedExpects : nil
        self.tolerance = tolerance
        self.feedback = feedback ?? ""
    }

    public var form: Form { choices.isEmpty ? .typed : .choice }

    /// Relative tolerance applied when the author states none. Effectively exact:
    /// a check that wants `0.333` accepted for $1/3$ has to say so (D13.4).
    public static let defaultRelativeTolerance = 1e-6

    /// The correct row of a choice check, or `nil` if none is marked (which the
    /// validator reports as `check-no-correct-choice`).
    public var correctIndex: Int? { choices.firstIndex(where: \.correct) }

    public func isCorrect(choiceAt index: Int) -> Bool {
        choices.indices.contains(index) && choices[index].correct
    }

    /// Whether a typed answer matches, numerically. `false` for anything the
    /// parser cannot read on either side — an `expects` that does not parse is a
    /// build failure (`check-unparsable-answer`), so in a validated corpus the only
    /// unreadable side is what the reader typed.
    public func isCorrect(typed: String) -> Bool {
        guard let expects,
            let want = NumericAnswer.value(of: expects),
            let got = NumericAnswer.value(of: typed)
        else { return false }
        let allowed = tolerance ?? max(abs(want) * Self.defaultRelativeTolerance, 1e-12)
        return abs(got - want) <= allowed
    }

    /// The feedback to show for a resolved choice: the row's own words where the
    /// author wrote them, and the check's otherwise.
    public func feedback(forChoiceAt index: Int) -> String {
        guard choices.indices.contains(index),
            let specific = choices[index].feedback?.trimmingCharacters(
                in: .whitespacesAndNewlines),
            !specific.isEmpty
        else { return feedback }
        return specific
    }

    /// Every renderable field, for the corpus self-check (D12.5's rule: authored
    /// LaTeX that nothing renders is authored LaTeX nobody has checked).
    public var renderableFields: [(field: String, source: String)] {
        var out: [(String, String)] = [("check.feedback", feedback)]
        if let expects { out.append(("check.expects", expects)) }
        for (index, choice) in choices.enumerated() {
            out.append(("check.choices[\(index)].text", choice.text))
            if let feedback = choice.feedback {
                out.append(("check.choices[\(index)].feedback", feedback))
            }
        }
        return out
    }
}

// MARK: - Diagnostics

extension AnswerCheck {
    /// One rule violation, without the node ids — the caller knows whether it is
    /// annotating a lesson card or a bank problem, and only it can say which ids
    /// an author would open.
    public struct Fault: Hashable, Sendable {
        public let rule: DiagnosticRule
        public let detail: String

        public init(rule: DiagnosticRule, detail: String) {
            self.rule = rule
            self.detail = detail
        }
    }

    /// The rules both hosts share, checked against the *raw* authored fields
    /// rather than a constructed `AnswerCheck` — half of what can go wrong is a
    /// combination the initializer would have discarded.
    ///
    /// `isRequired` distinguishes the two hosts' expectations of a bare field set:
    /// a lesson card that asks a question with no answer is unanswerable, while a
    /// problem with no `expects` and no `choices` is simply a self-graded problem,
    /// which is the norm.
    public static func faults(
        choices: [AnswerChoice], expects: String?, tolerance: Double?, feedback: String?,
        isRequired: Bool
    ) -> [Fault] {
        func trimmed(_ text: String?) -> String {
            (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let expectation = trimmed(expects)
        var out: [Fault] = []

        if choices.isEmpty && expectation.isEmpty {
            if isRequired {
                out.append(
                    Fault(
                        rule: .checkUnanswerable,
                        detail: "needs either `choices` or an `expects` value to be answerable"))
            }
            // Nothing else is meaningful about a check that does not exist — but a
            // tolerance or a feedback string left behind says an author deleted
            // half of one.
            if tolerance != nil || !trimmed(feedback).isEmpty {
                out.append(
                    Fault(
                        rule: .checkUnanswerable,
                        detail:
                            "carries `tolerance`/`feedback` but no `choices` and no `expects` — "
                            + "half a check was left behind"))
            }
            return out
        }

        if !choices.isEmpty && !expectation.isEmpty {
            out.append(
                Fault(
                    rule: .checkAmbiguous,
                    detail:
                        "declares both `choices` and `expects` — a check is either picked or typed"))
        }

        if !choices.isEmpty {
            if choices.count < 2 {
                out.append(
                    Fault(
                        rule: .checkThinChoices,
                        detail: "has \(choices.count) choice — a choice needs at least two rows"))
            }
            let correct = choices.count(where: \.correct)
            if correct == 0 {
                out.append(
                    Fault(
                        rule: .checkNoCorrectChoice,
                        detail: "marks no choice `correct: true`"))
            } else if correct > 1 {
                out.append(
                    Fault(
                        rule: .checkManyCorrectChoices,
                        detail:
                            "marks \(correct) choices correct — the reader picks one row, so "
                            + "exactly one is right"))
            }
            for (index, choice) in choices.enumerated() where trimmed(choice.text).isEmpty {
                out.append(
                    Fault(rule: .emptyChoiceText, detail: "choice \(index + 1) has no text"))
            }
        }

        // A typed answer the parser cannot read would reach a reader as "your
        // correct answer is wrong", which is the worst failure this layer has.
        if !expectation.isEmpty, NumericAnswer.value(of: expectation) == nil {
            out.append(
                Fault(
                    rule: .checkUnparsableAnswer,
                    detail:
                        "`expects: \(expectation)` is not a number the answer parser reads — "
                        + "write a decimal, a fraction `a/b`, a percentage, or use `choices`"))
        }

        if let tolerance, tolerance <= 0 {
            out.append(
                Fault(
                    rule: .checkNonPositiveTolerance,
                    detail:
                        "`tolerance: \(tolerance)` is not positive — omit it for an exact match"))
        }

        if trimmed(feedback).isEmpty {
            out.append(
                Fault(
                    rule: .checkMissingFeedback,
                    detail: "has no `feedback` — a reader who guessed right still needs the reason"))
        }

        return out
    }
}

// MARK: - Numeric answers

/// Reads the value out of an answer a human typed or an author wrote (D13.4).
///
/// Generous about spelling, strict about value: `7/15`, `0.4667`, `46.67%`,
/// `$\frac{7}{15}$` and `1,024` all read, and everything is then compared as a
/// `Double`. It deliberately stops short of an expression evaluator — no sums, no
/// powers, no symbols — because the moment this parses arithmetic it becomes a
/// thing that can *silently* disagree with the author about what the answer is.
public enum NumericAnswer {
    public static func value(of source: String) -> Double? {
        var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Math delimiters and LaTeX spacing: an author pasting from a statement
        // brings them along, and they carry no value.
        text = text.replacingOccurrences(of: "$", with: "")
        for spacing in ["\\,", "\\;", "\\!", "\\ ", "\\quad", "\\qquad", "\\left", "\\right"] {
            text = text.replacingOccurrences(of: spacing, with: "")
        }
        text = rewritingFractions(in: text)
        text = text.replacingOccurrences(of: "\\times", with: "")
        text = text.replacingOccurrences(of: "\\%", with: "%")
        text = text.replacingOccurrences(of: "\u{2212}", with: "-")  // U+2212 MINUS SIGN
        text = text.replacingOccurrences(of: "\u{2044}", with: "/")  // U+2044 FRACTION SLASH
        text = text.replacingOccurrences(of: ",", with: "")
        text = text.replacingOccurrences(of: " ", with: "")
        text = text.replacingOccurrences(of: "(", with: "")
        text = text.replacingOccurrences(of: ")", with: "")

        var isPercent = false
        if text.hasSuffix("%") {
            isPercent = true
            text.removeLast()
        }
        guard !text.isEmpty else { return nil }

        guard let magnitude = rational(text) else { return nil }
        return isPercent ? magnitude / 100 : magnitude
    }

    /// A single fraction or a plain decimal. One `/` at most: `3/4/5` is not an
    /// answer, it is a typo, and reading it as $0.15$ would be a guess.
    private static func rational(_ text: String) -> Double? {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            return decimal(String(parts[0]))
        case 2:
            guard let numerator = decimal(String(parts[0])),
                let denominator = decimal(String(parts[1])),
                denominator != 0
            else { return nil }
            return numerator / denominator
        default:
            return nil
        }
    }

    /// `Double(_:)` with the surprises removed. It accepts "nan", "inf", "0x1p3"
    /// and a trailing "d"; none of those is an answer to a probability question.
    private static func decimal(_ text: String) -> Double? {
        guard !text.isEmpty else { return nil }
        var seenDigit = false
        var previous: Character?
        for character in text {
            switch character {
            case "0"..."9": seenDigit = true
            case ".": break
            // A sign is legal at the front and immediately after an exponent
            // marker, and nowhere else — `1-2` is a subtraction this parser
            // deliberately does not do.
            case "-", "+":
                guard previous == nil || previous == "e" || previous == "E" else { return nil }
            case "e", "E": guard seenDigit else { return nil }
            default: return nil
            }
            previous = character
        }
        guard seenDigit, let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// `\frac{a}{b}`, `\dfrac{a}{b}`, `\tfrac{a}{b}` → `a/b`. Written by hand
    /// rather than with a regex so `GraphCore` keeps its "no dependencies, no
    /// `NSRegularExpression` in the hot path" shape, and so a malformed macro
    /// returns the text unchanged (and then fails to parse) instead of throwing.
    private static func rewritingFractions(in source: String) -> String {
        var text = source
        for macro in ["\\dfrac", "\\tfrac", "\\frac"] {
            while let start = text.range(of: macro) {
                guard let numerator = braced(in: text, from: start.upperBound),
                    let denominator = braced(in: text, from: numerator.end)
                else { return text }
                text.replaceSubrange(
                    start.lowerBound..<denominator.end,
                    with: "\(numerator.body)/\(denominator.body)")
            }
        }
        return text
    }

    /// The `{...}` group starting at `index`, with its body and the index just past
    /// its closing brace. Nesting is counted, so `\frac{{1}}{2}` survives.
    private static func braced(
        in text: String, from index: String.Index
    ) -> (body: String, end: String.Index)? {
        guard index < text.endIndex, text[index] == "{" else { return nil }
        var depth = 0
        var cursor = index
        var body = ""
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "{" {
                depth += 1
                if depth > 1 { body.append(character) }
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return (body, text.index(after: cursor)) }
                body.append(character)
            } else {
                body.append(character)
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }
}
