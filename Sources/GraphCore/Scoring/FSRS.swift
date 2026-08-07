import Foundation

/// FSRS-6 memory model (§4.2), ported from the reference implementation
/// `open-spaced-repetition/py-fsrs` @ 8add2d3f44eb9890c457bd4ce7d31319c8dede6e.
///
/// Only the *memory model* is ported — initial state, difficulty update, stability
/// update, retrievability, and the interval read-out. The reference's
/// Learning/Review/Relearning step machine is Anki scheduling UX, not memory: its
/// three branches perform byte-identical memory updates (verified against the
/// reference before porting), so dropping it changes nothing here. Interval
/// fuzzing is deliberately omitted — ground rule 5 requires determinism.
public enum FSRSVersion {
    public static let algorithm = "FSRS-6"
    public static let oracle = "open-spaced-repetition/py-fsrs@8add2d3"
}

/// A review outcome (§4.2). Raw values match the reference's `Rating`.
public enum Grade: Int, Codable, Hashable, Sendable, CaseIterable, Comparable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    /// `again` is a failure; everything else is a successful retrieval.
    public var isPass: Bool { self != .again }

    public static func < (lhs: Grade, rhs: Grade) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Per-node (or per-edge, §4.4) memory state. This is a *cache* — §3.2 makes the
/// evidence log the ground truth and this recomputable from it.
public struct MemoryState: Codable, Hashable, Sendable {
    public var stability: Double
    public var difficulty: Double
    public var lastReview: Date

    public init(stability: Double, difficulty: Double, lastReview: Date) {
        self.stability = stability
        self.difficulty = difficulty
        self.lastReview = lastReview
    }
}

public struct FSRSParameters: Hashable, Sendable {
    /// 21 weights; `w[20]` is the decay exponent.
    public var weights: [Double]
    public var desiredRetention: Double
    public var maximumInterval: Int

    public init(
        weights: [Double] = FSRSParameters.fsrs6DefaultWeights,
        desiredRetention: Double = 0.9,
        maximumInterval: Int = 36500
    ) {
        self.weights = weights
        self.desiredRetention = desiredRetention
        self.maximumInterval = maximumInterval
    }

    /// The reference's `DEFAULT_PARAMETERS`. Not hand-derived — §4.2 prescribes
    /// adopting the reference implementation rather than transcribing formulas.
    public static let fsrs6DefaultWeights: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
        1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
        1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ]
}

public struct FSRS: Sendable {
    public let parameters: FSRSParameters

    private let w: [Double]
    private let decay: Double
    private let factor: Double

    static let stabilityMin = 0.001
    static let difficultyMin = 1.0
    static let difficultyMax = 10.0

    public init(parameters: FSRSParameters = FSRSParameters()) {
        precondition(parameters.weights.count == 21, "FSRS-6 takes 21 weights")
        self.parameters = parameters
        w = parameters.weights
        decay = -parameters.weights[20]
        factor = pow(0.9, 1 / decay) - 1
    }

    // MARK: Elapsed time

    /// Whole elapsed days, floored — matching the reference's `(t2 - t1).days`.
    /// The update path **must** use this or ported state diverges from the oracle.
    /// Display uses `retrievability(of:at:)` below, which is continuous.
    public static func wholeDaysElapsed(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) / 86_400).rounded(.down))
    }

    // MARK: Core model

    public func initialStability(_ grade: Grade) -> Double {
        clampStability(w[grade.rawValue - 1])
    }

    public func initialDifficulty(_ grade: Grade, clamp: Bool = true) -> Double {
        let difficulty = w[4] - exp(w[5] * Double(grade.rawValue - 1)) + 1
        return clamp ? clampDifficulty(difficulty) : difficulty
    }

    /// Modelled probability of successful retrieval after `elapsedDays`.
    public func retrievability(stability: Double, elapsedDays: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + factor * max(0, elapsedDays) / stability, decay)
    }

    /// §4.1: the score, decaying continuously and computed on read — no timer
    /// mutates state. Continuous (fractional days) rather than the whole-day
    /// truncation the update path uses, because a score that only moved at
    /// midnight would visibly step.
    public func retrievability(of state: MemoryState, at now: Date) -> Double {
        retrievability(
            stability: state.stability,
            elapsedDays: max(0, now.timeIntervalSince(state.lastReview) / 86_400))
    }

    public func shortTermStability(stability: Double, grade: Grade) -> Double {
        var increase = exp(w[17] * (Double(grade.rawValue) - 3 + w[18])) * pow(stability, -w[19])
        if grade.isPass { increase = max(increase, 1.0) }
        return clampStability(stability * increase)
    }

    public func nextDifficulty(difficulty: Double, grade: Grade) -> Double {
        let deltaDifficulty = -(w[6] * Double(grade.rawValue - 3))
        let damped = (10.0 - difficulty) * deltaDifficulty / 9.0
        let reverted = w[7] * initialDifficulty(.easy, clamp: false) + (1 - w[7]) * (difficulty + damped)
        return clampDifficulty(reverted)
    }

    public func nextStability(
        difficulty: Double, stability: Double, retrievability: Double, grade: Grade
    ) -> Double {
        let next =
            grade == .again
            ? nextForgetStability(
                difficulty: difficulty, stability: stability, retrievability: retrievability)
            : nextRecallStability(
                difficulty: difficulty, stability: stability, retrievability: retrievability,
                grade: grade)
        return clampStability(next)
    }

    private func nextForgetStability(
        difficulty: Double, stability: Double, retrievability: Double
    ) -> Double {
        let longTerm =
            w[11] * pow(difficulty, -w[12]) * (pow(stability + 1, w[13]) - 1)
            * exp((1 - retrievability) * w[14])
        let shortTerm = stability / exp(w[17] * w[18])
        return min(longTerm, shortTerm)
    }

    private func nextRecallStability(
        difficulty: Double, stability: Double, retrievability: Double, grade: Grade
    ) -> Double {
        let hardPenalty = grade == .hard ? w[15] : 1
        let easyBonus = grade == .easy ? w[16] : 1
        return stability
            * (1 + exp(w[8]) * (11 - difficulty) * pow(stability, -w[9])
                * (exp((1 - retrievability) * w[10]) - 1) * hardPenalty * easyBonus)
    }

    /// Days until the card next falls to `desiredRetention` — the §6 "next due"
    /// read-out. `.toNearestOrEven` matches Python's banker's `round`.
    public func nextInterval(stability: Double) -> Int {
        let interval = (stability / factor) * (pow(parameters.desiredRetention, 1 / decay) - 1)
        return min(max(Int(interval.rounded(.toNearestOrEven)), 1), parameters.maximumInterval)
    }

    public func nextDue(after state: MemoryState) -> Date {
        state.lastReview.addingTimeInterval(Double(nextInterval(stability: state.stability)) * 86_400)
    }

    // MARK: The update

    /// Apply one explicit review. Mirrors the reference's `review_card` memory
    /// update, which is identical in every card state.
    public func review(_ state: MemoryState?, grade: Grade, at now: Date) -> MemoryState {
        guard let state else {
            return MemoryState(
                stability: initialStability(grade),
                difficulty: initialDifficulty(grade),
                lastReview: now)
        }
        let elapsed = Self.wholeDaysElapsed(from: state.lastReview, to: now)
        let stability: Double
        if elapsed < 1 {
            stability = shortTermStability(stability: state.stability, grade: grade)
        } else {
            stability = nextStability(
                difficulty: state.difficulty,
                stability: state.stability,
                retrievability: retrievability(
                    stability: state.stability, elapsedDays: Double(elapsed)),
                grade: grade)
        }
        return MemoryState(
            stability: stability,
            difficulty: nextDifficulty(difficulty: state.difficulty, grade: grade),
            lastReview: now)
    }

    private func clampStability(_ stability: Double) -> Double {
        max(stability, Self.stabilityMin)
    }

    private func clampDifficulty(_ difficulty: Double) -> Double {
        min(max(difficulty, Self.difficultyMin), Self.difficultyMax)
    }
}
