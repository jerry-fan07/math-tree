import Foundation

/// §6.8's unit test: one problem per skill of a unit, drawn from the bank in
/// teaching order, that the reader takes as a set.
///
/// Khan Academy ends a unit with a test over every skill in it. This is that,
/// scoped to what the bank can ask: a skill with no problem is skipped and the
/// count says so, so a test over a half-covered unit is short rather than
/// padded with self-report. The selection is deterministic — a pure function
/// of the plan, the bank and the log — because the test writes real evidence
/// through §5.2's instrument and a reader retaking it should be able to see
/// what changed rather than get a different paper.
///
/// Two orderings are deliberate. Skills the reader has not yet *mastered* come
/// first (in teaching order), mastered ones after, so a capped test spends its
/// questions where the ladder can still move. And the difficulty preferred is
/// `standard`: a mastery set (D13.6) opens with the hardest problem because the
/// reader has just been taught the node; a test asks across a unit the reader
/// may have learned weeks ago, and a fair paper is the middle of the bank.
public enum UnitTest {
    public struct Question: Hashable, Sendable, Identifiable {
        /// The skill this question stands for — its primary target in the unit.
        public let node: NodeID
        public let problem: Problem

        public var id: ProblemID { problem.id }

        public init(node: NodeID, problem: Problem) {
            self.node = node
            self.problem = problem
        }
    }

    public struct Paper: Hashable, Sendable {
        public let questions: [Question]
        /// Skills of the unit the bank could not ask about.
        public let unaskable: [NodeID]
        /// Skills the cap left out.
        public let omitted: [NodeID]

        public init(questions: [Question], unaskable: [NodeID], omitted: [NodeID]) {
            self.questions = questions
            self.unaskable = unaskable
            self.omitted = omitted
        }

        public var isEmpty: Bool { questions.isEmpty }
    }

    public static let defaultLimit = 10

    /// - Parameters:
    ///   - steps: the unit's steps, in teaching order (`ProgramPlan.Unit.steps`).
    ///   - level: the reader's rung on each skill, for the unmastered-first order.
    ///   - attempted: problems the log already holds an attempt at — preferred
    ///     against, so a retake asks something new where the bank allows.
    public static func paper(
        for steps: [ProgramPlan.Step],
        bank: ProblemBank,
        level: (NodeID) -> MasteryLevel,
        attempted: Set<ProblemID> = [],
        limit: Int = defaultLimit
    ) -> Paper {
        // Stable partition: unmastered skills keep their teaching order and come
        // first; mastered ones follow, also in teaching order.
        let ordered =
            steps.filter { level($0.id) < .mastered } + steps.filter { level($0.id) >= .mastered }

        var questions: [Question] = []
        var unaskable: [NodeID] = []
        var omitted: [NodeID] = []
        var used = Set<ProblemID>()

        for step in ordered {
            let candidates = bank.problems(targeting: step.id).filter { !used.contains($0.id) }
            guard let pick = choose(from: candidates, attempted: attempted) else {
                if bank.problems(targeting: step.id).isEmpty { unaskable.append(step.id) }
                continue
            }
            if questions.count >= limit {
                omitted.append(step.id)
                continue
            }
            used.insert(pick.id)
            questions.append(Question(node: step.id, problem: pick))
        }

        // The paper itself is sat in teaching order — the unmastered-first
        // ordering decided *which* questions made the cut, not the sequence.
        let position = Dictionary(
            steps.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first })
        questions.sort { (position[$0.node] ?? 0, $0.id) < (position[$1.node] ?? 0, $1.id) }

        return Paper(questions: questions, unaskable: unaskable, omitted: omitted)
    }

    /// `standard` before `routine` before `demanding`; within a difficulty, an
    /// unattempted problem before a seen one; then by id, so ties are stable.
    private static func choose(from candidates: [Problem], attempted: Set<ProblemID>) -> Problem? {
        func rank(_ difficulty: Problem.Difficulty) -> Int {
            switch difficulty {
            case .standard: 0
            case .routine: 1
            case .demanding: 2
            }
        }
        return candidates.min { left, right in
            let l = (rank(left.difficulty), attempted.contains(left.id) ? 1 : 0, left.id)
            let r = (rank(right.difficulty), attempted.contains(right.id) ? 1 : 0, right.id)
            return l < r
        }
    }
}
