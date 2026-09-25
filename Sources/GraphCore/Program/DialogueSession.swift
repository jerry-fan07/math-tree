import Foundation

/// §6.9's player state: one reader's pass through one lesson's cards, as a
/// Socratic dialogue — a transcript that shows everything up to the first
/// unanswered question and grows as questions are answered.
///
/// A value type in `GraphCore` rather than `@State` scattered through a view, so
/// the rules that make a dialogue a dialogue are testable without a window:
///
/// - **The gate is the first unanswered question.** Beats before it are shown;
///   nothing after it is (D16.1). A lesson with no questions has no gate, and
///   shows whole.
/// - **A wrong answer is kept, not replaced.** A wrong row stays on the page with
///   its authored feedback and the reader picks again; a wrong typed value is
///   listed with which way it missed. That is where a distractor teaches (D16.3).
/// - **Nothing locks.** `reveal` resolves any question as *shown*; a reflection
///   resolves on whatever the reader wrote, including nothing.
///
/// It records nothing anywhere (D13.2 holds): checks are formative, and a
/// session lives exactly as long as the player that owns it.
public struct DialogueSession: Hashable, Sendable {
    /// How a question was resolved.
    public enum Outcome: Hashable, Sendable {
        /// Answered correctly, on the given attempt (1 = first try).
        case answered(tries: Int)
        /// The reader asked to be shown.
        case shown
        /// A reflection, compared with the tutor's answer.
        case reflected
    }

    /// The reader's own verdict on a reflection, after reading the tutor's.
    /// View state only — it measures a feeling, and D13.2 keeps checks out of the
    /// log in any case.
    public enum Rating: String, CaseIterable, Hashable, Sendable {
        case had, partly, missed

        public var title: String {
            switch self {
            case .had: "had it"
            case .partly: "partly"
            case .missed: "missed it"
            }
        }
    }

    /// A wrong typed answer, with which way it missed — "too high" is a hint the
    /// reader has earned by committing to a number.
    public struct Miss: Hashable, Sendable {
        public enum Direction: Hashable, Sendable {
            case tooHigh
            case tooLow
            /// Off by roughly this factor (at least 10), in either direction.
            case factor(Int)
            /// Neither comparison means anything (a sign error, a zero answer).
            case wrong
        }

        public let text: String
        public let direction: Direction

        /// Plain prose — this is set with `Text`, never through `MathTextView`.
        public var message: String {
            switch direction {
            case .tooHigh: "Too high."
            case .tooLow: "Too low."
            case .factor(let factor): "Off by a factor of about \(factor)."
            case .wrong: "Not that."
            }
        }
    }

    public enum Attempt: Hashable, Sendable {
        case correct
        case wrong
        /// Not an attempt at all: an unreadable typed value, a row already
        /// ruled out, a question already resolved.
        case ignored
    }

    /// One titled section of the dialogue, for the outline.
    public struct Part: Hashable, Sendable {
        public let title: String?
        /// Card indices the part spans.
        public let cards: Range<Int>
    }

    public let cards: [LessonCard]
    public private(set) var outcomes: [Int: Outcome] = [:]
    /// Card → the wrong rows picked, in the order they were picked.
    public private(set) var wrongPicks: [Int: [Int]] = [:]
    /// Card → the wrong typed values, in order.
    public private(set) var misses: [Int: [Miss]] = [:]
    /// Card → what the reader wrote for a reflection (possibly empty).
    public private(set) var written: [Int: String] = [:]
    public private(set) var ratings: [Int: Rating] = [:]
    public private(set) var hinted: Set<Int> = []

    public init(cards: [LessonCard]) {
        self.cards = cards
    }

    // MARK: - Where the reader is

    /// The first question not yet resolved — the card the transcript waits on.
    /// `nil` once every question is resolved (or if there were none).
    public var gate: Int? {
        cards.indices.first { cards[$0].isQuestion && outcomes[$0] == nil }
    }

    /// How many cards the transcript shows: everything through the gate.
    public var visibleCount: Int { gate.map { $0 + 1 } ?? cards.count }

    /// Every question resolved: the lesson's ending is on the page.
    public var isFinished: Bool { gate == nil }

    public func isResolved(_ card: Int) -> Bool { outcomes[card] != nil }

    // MARK: - Counts

    public var questionCount: Int { cards.count(where: \.isQuestion) }
    public var resolvedCount: Int { outcomes.count }
    public var firstTryCount: Int {
        outcomes.values.count { $0 == .answered(tries: 1) }
    }
    public var shownCount: Int { outcomes.values.count { $0 == .shown } }

    /// The dialogue's parts. A lesson whose first card opens no part (plain
    /// `steps`, or a derived paging) starts with an untitled one.
    public var parts: [Part] {
        var starts = cards.indices.filter { cards[$0].partTitle != nil }
        if starts.first != 0 { starts.insert(0, at: 0) }
        guard !cards.isEmpty else { return [] }
        return starts.enumerated().map { position, start in
            let end = position + 1 < starts.count ? starts[position + 1] : cards.count
            return Part(title: cards[start].partTitle, cards: start..<end)
        }
    }

    /// Whether any part carries a title — the outline is worth showing only then.
    public var hasTitledParts: Bool { cards.contains { $0.partTitle != nil } }

    // MARK: - Answering

    /// Pick a row of the choice check at `card`. A wrong row is kept and ruled
    /// out; the right one resolves the question on attempt `wrong rows + 1`.
    @discardableResult
    public mutating func pick(_ row: Int, at card: Int) -> Attempt {
        guard isOpen(card), let check = cards[card].check, check.form == .choice,
            check.choices.indices.contains(row), !(wrongPicks[card] ?? []).contains(row)
        else { return .ignored }
        if check.isCorrect(choiceAt: row) {
            outcomes[card] = .answered(tries: (wrongPicks[card]?.count ?? 0) + 1)
            return .correct
        }
        wrongPicks[card, default: []].append(row)
        return .wrong
    }

    /// Submit a typed answer at `card`. Unreadable input is `.ignored` — it is a
    /// spelling problem, not an attempt, and the player says so without counting it.
    @discardableResult
    public mutating func submit(_ text: String, at card: Int) -> Attempt {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isOpen(card), let check = cards[card].check, check.form == .typed,
            let got = NumericAnswer.value(of: trimmed)
        else { return .ignored }
        if check.isCorrect(typed: trimmed) {
            outcomes[card] = .answered(tries: (misses[card]?.count ?? 0) + 1)
            return .correct
        }
        let want = check.expects.flatMap(NumericAnswer.value(of:)) ?? 0
        misses[card, default: []].append(Miss(text: trimmed, direction: Self.direction(got, want)))
        return .wrong
    }

    /// Resolve the question at `card` as shown — the reader asked for the answer.
    public mutating func reveal(at card: Int) {
        guard isOpen(card), cards[card].isQuestion else { return }
        if cards[card].isReflection {
            written[card] = ""
            outcomes[card] = .reflected
        } else {
            outcomes[card] = .shown
        }
    }

    /// Commit the reader's own answer to a reflection; the tutor's is shown next.
    public mutating func reflect(_ text: String, at card: Int) {
        guard isOpen(card), cards[card].isReflection else { return }
        written[card] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        outcomes[card] = .reflected
    }

    public mutating func rate(_ rating: Rating, at card: Int) {
        guard outcomes[card] == .reflected else { return }
        ratings[card] = rating
    }

    public mutating func showHint(at card: Int) {
        guard cards.indices.contains(card), cards[card].hint != nil else { return }
        hinted.insert(card)
    }

    /// Resolve every question before `card` as a reader who got each right first
    /// time would have — the offscreen-render seam's way of opening a dialogue
    /// part-way through (input cannot be driven headlessly).
    public mutating func answerCorrectly(through card: Int) {
        for index in cards.indices where index <= card && cards[index].isQuestion {
            guard !isResolved(index) else { continue }
            if let check = cards[index].check {
                switch check.form {
                case .choice: if let row = check.correctIndex { pick(row, at: index) }
                case .typed: if let expects = check.expects { submit(expects, at: index) }
                }
                if !isResolved(index) { reveal(at: index) }
            } else {
                reveal(at: index)
            }
        }
    }

    private func isOpen(_ card: Int) -> Bool {
        cards.indices.contains(card) && outcomes[card] == nil
    }

    /// Which way a typed answer missed. A factor of ten or more is worth saying
    /// as a factor — it is a units or a place-value slip, not a near miss.
    static func direction(_ got: Double, _ want: Double) -> Miss.Direction {
        if want != 0, got != 0, (got > 0) == (want > 0) {
            let ratio = got / want
            if ratio >= 10 || ratio <= 0.1 {
                return .factor(Int((max(ratio, 1 / ratio)).rounded()))
            }
        }
        if (got > 0) != (want > 0), got != 0, want != 0 { return .wrong }
        return got > want ? .tooHigh : .tooLow
    }
}
