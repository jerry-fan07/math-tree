import Foundation

/// §6.8's mastery ladder: one word per skill, in the vocabulary a course uses.
///
/// §4.5 gives a node three states (unlearned, learned, decayed) and one
/// threshold (τ). A course needs a *ladder* — the reader has to see what the
/// next rung is and what climbs it — so this reads the same state and the same
/// evidence log and names five rungs, Khan Academy's, with Khan Academy's
/// points. The ladder adds no state of its own (§6.6's rule): every rung is a
/// function of the fold over the log at one instant.
///
/// The top two rungs split on *what measured the node*. Proficient is §4.5's
/// "met" — learned and above τ, by whatever evidence — so it agrees with the
/// map's colour and every "N / M" read-out in the app. Mastered is met *and*
/// the last problem that targeted the node was passed: a self-report is a claim
/// about a feeling and a problem is a measurement (§5.2), and the ladder is
/// where that difference is finally said in one word.
public enum MasteryLevel: Int, Comparable, CaseIterable, Sendable, Codable {
    /// No evidence at all.
    case notStarted = 0
    /// Attempted and missed, never yet retrieved (D8.3's reading of `again`).
    case attempted
    /// Learned once, but below τ now — decayed, and due.
    case familiar
    /// §4.5's met: learned and above τ, by any evidence.
    case proficient
    /// Met, and the most recent problem targeting this node was passed.
    case mastered

    public static func < (lhs: MasteryLevel, rhs: MasteryLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Khan Academy's scale, kept exactly: a skill is worth 100, and the rungs
    /// earn 0 / 0 / 50 / 80 / 100 of it. Course progress is points over the
    /// total, which is what makes a half-learned unit read as half rather than
    /// as zero.
    public var points: Int {
        switch self {
        case .notStarted, .attempted: 0
        case .familiar: 50
        case .proficient: 80
        case .mastered: 100
        }
    }

    public static let pointsPerSkill = 100

    public var title: String {
        switch self {
        case .notStarted: "Not started"
        case .attempted: "Attempted"
        case .familiar: "Familiar"
        case .proficient: "Proficient"
        case .mastered: "Mastered"
        }
    }

    /// What this rung means, and — for every rung but the top — what climbs it.
    public var detail: String {
        switch self {
        case .notStarted: "No evidence yet. Start the lesson."
        case .attempted: "A problem localized a miss here. Learn it, then try again."
        case .familiar: "Learned once, but it has decayed. Review to bring it back."
        case .proficient: "Held and fresh. Pass a problem to master it."
        case .mastered: "Held, fresh, and proven by a problem."
        }
    }

    /// §4.5's met, as the ladder reads it.
    public var isMet: Bool { self >= .proficient }
}

/// What the ladder needs from the evidence log beyond the folded state: which
/// nodes a problem has *proven*. Computed once per fold and read per node.
public struct MasteryEvidence: Hashable, Sendable {
    /// Nodes whose most recent `test`-sourced event was a pass.
    public let proven: Set<NodeID>
    /// Nodes with at least one direct (non-inferred) review of any grade.
    public let directlyReviewed: Set<NodeID>

    public init(proven: Set<NodeID> = [], directlyReviewed: Set<NodeID> = []) {
        self.proven = proven
        self.directlyReviewed = directlyReviewed
    }

    /// Reads the log in fold order, so "most recent" is the fold's own notion
    /// of recency (D5.7) and a replay reaches the same answer.
    public init(events: [EvidenceEvent]) {
        var lastTest: [NodeID: Bool] = [:]
        var direct = Set<NodeID>()
        for event in events.sorted(by: EvidenceEvent.foldOrder) {
            guard let id = event.target.nodeID, let grade = event.grade else { continue }
            if !event.source.isInferred { direct.insert(id) }
            if event.source == .test { lastTest[id] = grade.isPass }
        }
        proven = Set(lastTest.filter(\.value).keys)
        directlyReviewed = direct
    }
}

public enum Mastery {
    /// One node's rung, at one instant.
    public static func level(
        of id: NodeID,
        state: ScoreState,
        evidence: MasteryEvidence,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> MasteryLevel {
        guard let memory = state.nodes[id] else { return .notStarted }
        guard state.isLearned(id) else { return .attempted }
        let fsrs = FSRS(parameters: config.fsrs)
        guard fsrs.retrievability(of: memory, at: now) > config.masteryThreshold else {
            return .familiar
        }
        return evidence.proven.contains(id) ? .mastered : .proficient
    }

    /// Several nodes at once — a unit, a course — with the counts a progress
    /// bar segments by and the points a course totals.
    public static func summary(
        of ids: [NodeID],
        state: ScoreState,
        evidence: MasteryEvidence,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> MasterySummary {
        var counts: [MasteryLevel: Int] = [:]
        for id in ids {
            counts[level(of: id, state: state, evidence: evidence, at: now, config: config), default: 0]
                += 1
        }
        return MasterySummary(total: ids.count, counts: counts)
    }
}

/// The ladder over a set of skills: how many sit on each rung, and the points
/// that earns out of `total × 100`.
public struct MasterySummary: Hashable, Sendable {
    public let total: Int
    public let counts: [MasteryLevel: Int]

    public init(total: Int, counts: [MasteryLevel: Int]) {
        self.total = total
        self.counts = counts
    }

    public func count(_ level: MasteryLevel) -> Int { counts[level] ?? 0 }

    /// Skills at this rung *or higher*.
    public func count(atLeast level: MasteryLevel) -> Int {
        MasteryLevel.allCases.filter { $0 >= level }.reduce(0) { $0 + count($1) }
    }

    public var points: Int {
        MasteryLevel.allCases.reduce(0) { $0 + count($1) * $1.points }
    }

    public var possiblePoints: Int { total * MasteryLevel.pointsPerSkill }

    /// 0…1. Zero for an empty set, which is not the same as zero progress —
    /// callers distinguish by `total`.
    public var fraction: Double {
        possiblePoints == 0 ? 0 : Double(points) / Double(possiblePoints)
    }

    /// §4.5's met count — the number every existing "N / M" read-out shows.
    public var metCount: Int { count(atLeast: .proficient) }
}
