import Foundation

/// A problem's permanent identifier. Distinct from `NodeID` so the two can never
/// be crossed — §3.2's `history` records a `problem:` alongside node ids, and a
/// bare `String` on both sides would let them swap silently.
///
/// Format is `<subbranch-id-tail>-<nn>` in the authored bank (`svc-ftc-2-01`), but
/// nothing here depends on that; ids are opaque and permanent, like node ids.
public struct ProblemID: RawRepresentable, Hashable, Comparable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static func < (lhs: ProblemID, rhs: ProblemID) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension ProblemID {
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ProblemID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.rawValue = value }
}

extension ProblemID: CustomStringConvertible {
    public var description: String { rawValue }
}

/// §5.2: a problem is the evidence instrument. It is tagged with the node set it
/// exercises — one or more **targets** (what it primarily tests) and the
/// **exercised** prerequisites (what it necessarily drills in passing).
///
/// The two lists are not interchangeable and the difference is what §5.2 buys:
/// a target receives the graded review, an exercised node receives a
/// *full-strength* implicit review "regardless of graph distance" (§4.3). Damped
/// γᵈ propagation to the rest of the ancestry happens on top of both, unchanged
/// from Phase 5 — the tags only say which nodes skip the damping.
public struct Problem: Codable, Hashable, Sendable, Identifiable {
    /// How the solver is meant to answer, which is also how far the app can go in
    /// checking them. Math free-response cannot be machine-graded, so grading is
    /// ultimately the solver's own call against `answer` + `rubric` (§5.4 wants
    /// problems, not flashcards) — `kind` only says what the sheet should show.
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// Work it out, then check against the worked answer and rubric.
        case work
        /// True/false or "which hypothesis fails" — still self-graded, but the
        /// answer is short enough that self-deception is hard.
        case decide
        /// Produce a proof or a counterexample; the rubric carries the required beats.
        case justify
    }

    public let id: ProblemID
    public let kind: Kind
    /// The prompt, LaTeX allowed as `$...$` exactly like a node `statement` (§3.1).
    public let statement: String
    /// The worked answer, revealed after an attempt.
    public let answer: String
    /// What a correct solution must contain, one criterion per entry. This is what
    /// the solver grades against — a bare answer invites "close enough".
    public let rubric: [String]
    /// What this problem primarily tests (§5.2). Non-empty; every id must be a
    /// content node.
    public let targets: [NodeID]
    /// Prerequisites the problem necessarily drills in passing (§5.2).
    public let exercises: [NodeID]
    /// `relates` connections the problem exercises, as canonical `"a ~ b"` keys
    /// (§4.4: "an edge review happens when a problem explicitly exercises the
    /// connection"). This is the only writer of edge evidence in the system.
    public let connects: [String]
    /// Roughly how demanding the problem is, used only to order a probe ladder.
    public let difficulty: Difficulty
    public let tags: [String]

    /// Authoring-time difficulty, distinct from FSRS's fitted per-node difficulty —
    /// this one is a property of the *problem*, and never enters the memory model.
    public enum Difficulty: String, Codable, Hashable, Sendable, CaseIterable, Comparable {
        /// Recall or one-step application.
        case routine
        /// Combines two ideas, or needs the hypothesis checked.
        case standard
        /// Needs a construction, a counterexample, or a non-obvious route.
        case demanding

        var rank: Int {
            switch self {
            case .routine: 0
            case .standard: 1
            case .demanding: 2
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
    }

    public init(
        id: ProblemID,
        kind: Kind,
        statement: String,
        answer: String,
        rubric: [String] = [],
        targets: [NodeID],
        exercises: [NodeID] = [],
        connects: [String] = [],
        difficulty: Difficulty = .standard,
        tags: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.statement = statement
        self.answer = answer
        self.rubric = rubric
        self.targets = targets
        self.exercises = exercises
        self.connects = connects
        self.difficulty = difficulty
        self.tags = tags
    }

    /// Every node the problem touches, targets first. Deduplicated, order stable.
    public var taggedNodes: [NodeID] {
        var seen = Set<NodeID>()
        return (targets + exercises).filter { seen.insert($0).inserted }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, statement, answer, rubric, targets, exercises, connects, difficulty, tags
    }

    // Hand-written for the same reason `Node`'s is: absent collections decode as
    // empty and encode away again, so problems.json stays byte-stable (ground rule 5).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ProblemID.self, forKey: .id)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .work
        statement = try c.decode(String.self, forKey: .statement)
        answer = try c.decode(String.self, forKey: .answer)
        rubric = try c.decodeIfPresent([String].self, forKey: .rubric) ?? []
        targets = try c.decodeIfPresent([NodeID].self, forKey: .targets) ?? []
        exercises = try c.decodeIfPresent([NodeID].self, forKey: .exercises) ?? []
        connects = try c.decodeIfPresent([String].self, forKey: .connects) ?? []
        difficulty = try c.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .standard
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(statement, forKey: .statement)
        try c.encode(answer, forKey: .answer)
        if !rubric.isEmpty { try c.encode(rubric, forKey: .rubric) }
        try c.encode(targets, forKey: .targets)
        if !exercises.isEmpty { try c.encode(exercises, forKey: .exercises) }
        if !connects.isEmpty { try c.encode(connects, forKey: .connects) }
        try c.encode(difficulty, forKey: .difficulty)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
    }
}

/// The problem bank with the indexes assessment needs: by id, and by the node a
/// problem *targets*. Built once; every lookup downstream is a dictionary hit.
///
/// Indexed by target only, not by exercised node. A problem that merely drills
/// `def-limit` in passing is not a test *of* `def-limit` — probing it to measure
/// limits would attribute a failure to the wrong node, which is the exact
/// confusion §5.4's diagnosis exists to prevent.
public struct ProblemBank: Sendable {
    /// All problems, ordered by id, so anything derived by iteration is deterministic.
    public let problems: [Problem]
    public let problemsByID: [ProblemID: Problem]
    /// Problems whose `targets` include this node, ordered by (difficulty, id).
    public let problemsByTarget: [NodeID: [ProblemID]]
    /// Problems whose `exercises` include this node, ordered by (difficulty, id).
    public let problemsByExercised: [NodeID: [ProblemID]]

    public init(problems input: [Problem]) {
        // (id, authoring position) is a total order even when ids collide, so a
        // duplicate-id bank still loads the same way every time — same rule as
        // `KnowledgeGraph`.
        let ordered = input.enumerated()
            .sorted { ($0.element.id, $0.offset) < ($1.element.id, $1.offset) }
            .map(\.element)
        problems = ordered

        var byID: [ProblemID: Problem] = [:]
        byID.reserveCapacity(ordered.count)
        for problem in ordered where byID[problem.id] == nil { byID[problem.id] = problem }
        problemsByID = byID

        func index(_ nodes: (Problem) -> [NodeID]) -> [NodeID: [ProblemID]] {
            var out: [NodeID: [Problem]] = [:]
            for problem in ordered {
                for node in Set(nodes(problem)) { out[node, default: []].append(problem) }
            }
            // Easiest first: a probe ladder should not open with the hardest
            // problem in the bank.
            return out.mapValues { list in
                list.sorted { ($0.difficulty, $0.id) < ($1.difficulty, $1.id) }.map(\.id)
            }
        }

        problemsByTarget = index(\.targets)
        problemsByExercised = index(\.exercises)
    }

    public var isEmpty: Bool { problems.isEmpty }
    public var count: Int { problems.count }

    public subscript(id: ProblemID) -> Problem? { problemsByID[id] }

    /// Problems that test `node`, easiest first.
    public func problems(targeting node: NodeID) -> [Problem] {
        (problemsByTarget[node] ?? []).compactMap { problemsByID[$0] }
    }

    /// Nodes the bank can actually probe. Placement is only as good as its
    /// coverage, so this is reported rather than assumed (`Placement` skips
    /// unprobeable nodes and says so).
    public var probeableNodes: Set<NodeID> { Set(problemsByTarget.keys) }
}
