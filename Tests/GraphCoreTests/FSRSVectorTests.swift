import Foundation
import Testing

@testable import GraphCore

/// Vectors generated from `open-spaced-repetition/py-fsrs` @ 8add2d3 **before**
/// this port was written, so the port could not be tuned to its own bugs.
/// Regenerate with `Scripts/gen-fsrs-vectors.py` if the oracle is ever bumped.
private struct Vectors: Decodable {
    struct InitialStability: Decodable {
        let rating: Int
        let stability: Double
    }
    struct InitialDifficulty: Decodable {
        let rating: Int
        let difficulty: Double
    }
    struct Retrievability: Decodable {
        let stability: Double
        let elapsedDays: Double
        let retrievability: Double
    }
    struct NextDifficulty: Decodable {
        let difficulty: Double
        let rating: Int
        let next: Double
    }
    struct ShortTermStability: Decodable {
        let stability: Double
        let rating: Int
        let next: Double
    }
    struct NextStability: Decodable {
        let difficulty: Double
        let stability: Double
        let retrievability: Double
        let rating: Int
        let next: Double
    }
    struct NextInterval: Decodable {
        let stability: Double
        let desiredRetention: Double
        let days: Int
    }
    struct Step: Decodable {
        let rating: Int
        let elapsedDays: Int
    }
    struct TraceEntry: Decodable {
        let rating: Int
        let elapsedDays: Int
        let retrievabilityBefore: Double
        let stability: Double
        let difficulty: Double
    }
    struct Sequence: Decodable {
        let name: String
        let steps: [Step]
        let trace: [TraceEntry]
        let expectFinalStability: Double?
        let expectFinalDifficulty: Double?
    }

    let commit: String
    let algorithm: String
    let parameters: [Double]
    let initialStability: [InitialStability]
    let initialDifficulty: [InitialDifficulty]
    let retrievability: [Retrievability]
    let nextDifficulty: [NextDifficulty]
    let shortTermStability: [ShortTermStability]
    let nextStability: [NextStability]
    let nextInterval: [NextInterval]
    let sequences: [Sequence]

    static let shared: Vectors = {
        guard
            let url = Bundle.module.url(
                forResource: "fsrs-vectors", withExtension: "json", subdirectory: "Fixtures")
        else {
            fatalError("fsrs-vectors.json missing from the test bundle")
        }
        return try! JSONDecoder().decode(
            Vectors.self, from: try! Data(contentsOf: url))
    }()
}

/// Relative comparison: stability spans 0.001 to 10⁵, so a fixed epsilon would be
/// either meaningless at the top or unmeetable at the bottom.
private func close(_ actual: Double, _ expected: Double, tolerance: Double = 1e-9) -> Bool {
    let scale = max(1.0, abs(expected))
    return abs(actual - expected) <= tolerance * scale
}

private func grade(_ raw: Int) -> Grade { Grade(rawValue: raw)! }

@Suite("FSRS reference vectors")
struct FSRSVectorTests {
    let fsrs = FSRS()

    @Test func fixtureMatchesThePortedParameters() {
        let vectors = Vectors.shared
        #expect(vectors.algorithm == FSRSVersion.algorithm)
        #expect(FSRSVersion.oracle.hasSuffix(String(vectors.commit.prefix(7))))
        #expect(vectors.parameters == FSRSParameters.fsrs6DefaultWeights)
    }

    @Test func initialStability() {
        for vector in Vectors.shared.initialStability {
            let actual = fsrs.initialStability(grade(vector.rating))
            #expect(close(actual, vector.stability), "rating \(vector.rating): \(actual)")
        }
    }

    @Test func initialDifficulty() {
        for vector in Vectors.shared.initialDifficulty {
            let actual = fsrs.initialDifficulty(grade(vector.rating))
            #expect(close(actual, vector.difficulty), "rating \(vector.rating): \(actual)")
        }
    }

    @Test func retrievability() {
        for vector in Vectors.shared.retrievability {
            let actual = fsrs.retrievability(
                stability: vector.stability, elapsedDays: vector.elapsedDays)
            #expect(
                close(actual, vector.retrievability),
                "S=\(vector.stability) t=\(vector.elapsedDays): \(actual)")
        }
    }

    @Test func nextDifficulty() {
        for vector in Vectors.shared.nextDifficulty {
            let actual = fsrs.nextDifficulty(
                difficulty: vector.difficulty, grade: grade(vector.rating))
            #expect(
                close(actual, vector.next),
                "D=\(vector.difficulty) rating=\(vector.rating): \(actual)")
        }
    }

    @Test func shortTermStability() {
        for vector in Vectors.shared.shortTermStability {
            let actual = fsrs.shortTermStability(
                stability: vector.stability, grade: grade(vector.rating))
            #expect(
                close(actual, vector.next),
                "S=\(vector.stability) rating=\(vector.rating): \(actual)")
        }
    }

    @Test func nextStability() {
        for vector in Vectors.shared.nextStability {
            let actual = fsrs.nextStability(
                difficulty: vector.difficulty,
                stability: vector.stability,
                retrievability: vector.retrievability,
                grade: grade(vector.rating))
            #expect(
                close(actual, vector.next),
                "D=\(vector.difficulty) S=\(vector.stability) R=\(vector.retrievability) rating=\(vector.rating): \(actual)")
        }
    }

    @Test func nextInterval() {
        for vector in Vectors.shared.nextInterval {
            #expect(fsrs.parameters.desiredRetention == vector.desiredRetention)
            let actual = fsrs.nextInterval(stability: vector.stability)
            #expect(actual == vector.days, "S=\(vector.stability): \(actual) != \(vector.days)")
        }
    }

    /// End-to-end: every intermediate memory state across 42 review sequences
    /// (248 steps), not just the final one.
    @Test func reviewSequences() {
        let start = Date(timeIntervalSince1970: 1_669_725_000)  // 2022-11-29T12:30:00Z
        for sequence in Vectors.shared.sequences {
            var state: MemoryState?
            var now = start
            for (index, step) in sequence.steps.enumerated() {
                now = now.addingTimeInterval(Double(step.elapsedDays) * 86_400)
                let expected = sequence.trace[index]

                let observed = state.map { fsrs.retrievability(of: $0, at: now) } ?? 0
                #expect(
                    close(observed, expected.retrievabilityBefore),
                    "\(sequence.name) step \(index) retrievability: \(observed)")

                state = fsrs.review(state, grade: grade(step.rating), at: now)
                #expect(
                    close(state!.stability, expected.stability),
                    "\(sequence.name) step \(index) stability: \(state!.stability)")
                #expect(
                    close(state!.difficulty, expected.difficulty),
                    "\(sequence.name) step \(index) difficulty: \(state!.difficulty)")
            }

            if let expected = sequence.expectFinalStability {
                #expect(close(state!.stability, expected, tolerance: 1e-4), "\(sequence.name)")
            }
            if let expected = sequence.expectFinalDifficulty {
                #expect(close(state!.difficulty, expected, tolerance: 1e-4), "\(sequence.name)")
            }
        }
    }

    /// The two vectors py-fsrs publishes in its own test suite, asserted directly
    /// rather than only through the generated fixture.
    @Test func publishedMemoryStateVector() {
        let start = Date(timeIntervalSince1970: 1_669_725_000)
        var state: MemoryState?
        var now = start
        for (rawGrade, gap) in [(1, 0), (3, 0), (3, 1), (3, 3), (3, 8), (3, 21)] {
            now = now.addingTimeInterval(Double(gap) * 86_400)
            state = fsrs.review(state, grade: grade(rawGrade), at: now)
        }
        #expect(abs(state!.stability - 53.62691) < 1e-4)
        #expect(abs(state!.difficulty - 6.3574867) < 1e-4)
    }

    @Test func repeatedEasyReviewsDriveDifficultyToTheFloor() {
        var state: MemoryState?
        var now = Date(timeIntervalSince1970: 1_669_725_000)
        for _ in 0..<10 {
            state = fsrs.review(state, grade: .easy, at: now)
            now = now.addingTimeInterval(1)
        }
        #expect(state!.difficulty == FSRS.difficultyMin)
    }

    /// The update path must floor elapsed time to whole days, as the reference
    /// does — a fractional day there would silently diverge from the oracle.
    @Test func updatePathTruncatesElapsedDaysButDisplayDoesNot() {
        let start = Date(timeIntervalSince1970: 1_669_725_000)
        #expect(FSRS.wholeDaysElapsed(from: start, to: start.addingTimeInterval(86_399)) == 0)
        #expect(FSRS.wholeDaysElapsed(from: start, to: start.addingTimeInterval(86_400)) == 1)
        #expect(FSRS.wholeDaysElapsed(from: start, to: start.addingTimeInterval(172_799)) == 1)

        // Display retrievability is continuous: half a day of decay is visible.
        let state = MemoryState(stability: 10, difficulty: 5, lastReview: start)
        let atHalfDay = fsrs.retrievability(of: state, at: start.addingTimeInterval(43_200))
        let atDayStart = fsrs.retrievability(of: state, at: start)
        let atFullDay = fsrs.retrievability(of: state, at: start.addingTimeInterval(86_400))
        #expect(atDayStart > atHalfDay && atHalfDay > atFullDay)
    }
}
