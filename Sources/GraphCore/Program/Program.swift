import Foundation

/// §6.6's spine: the authored teaching order over a whole tree — every subbranch
/// as a *unit*, grouped into named *parts*, in the order someone who knows the
/// terrain chose. Authored data, not a derived view: `requires` yields a partial
/// order with astronomically many linear extensions, and which one teaches well
/// is pedagogy, not topology. `ProgramValidator` holds it to the one property the
/// plan's per-unit ordering depends on — the order must be a linear extension of
/// the cross-unit `requires` relation.
public struct ProgramSpine: Codable, Hashable, Sendable {
    public struct Part: Codable, Hashable, Sendable {
        public let title: String
        public let units: [NodeID]

        public init(title: String, units: [NodeID]) {
            self.title = title
            self.units = units
        }
    }

    /// A cross-unit `requires` edge the spine *accepts* pointing forward (D15.2).
    ///
    /// The linear-extension rule is the load-bearing one (D12.1), and it stays an
    /// error — but a corpus whose subbranches genuinely need each other (the
    /// math tree's relations ↔ functions, cardinality ↔ number systems) has no
    /// order that satisfies it. Rather than weaken the rule or re-home nodes
    /// whose ids are permanent, the author names each forward edge here with a
    /// note saying why the order is right anyway. The validator holds the list
    /// exactly: an undeclared forward edge is still `program-order-violation`,
    /// and a declared one that is no longer forward is `program-forward-stale`,
    /// so the list can neither hide a mistake nor rot.
    public struct ForwardReference: Codable, Hashable, Sendable {
        /// The node that requires something taught later.
        public let node: NodeID
        /// The prerequisite, which lives in a later unit.
        public let requires: NodeID
        /// The reviewer's sign-off — what the reader is expected to bring to the
        /// earlier step, or why the reference is benign there.
        public let note: String

        public init(node: NodeID, requires: NodeID, note: String) {
            self.node = node
            self.requires = requires
            self.note = note
        }
    }

    /// The course's name — "Undergraduate Mathematics", "Quant Interview
    /// Preparation". Authored, because a program is a course and a course has a
    /// name; `nil` on a spine authored before Phase 15, and the app falls back
    /// to the window's.
    public let title: String?
    public let parts: [Part]
    /// Accepted forward references, usually empty. See `ForwardReference`.
    public let forward: [ForwardReference]

    public init(title: String? = nil, parts: [Part], forward: [ForwardReference] = []) {
        self.title = title
        self.parts = parts
        self.forward = forward
    }

    /// Every unit in program order — the flattened spine.
    public var units: [NodeID] { parts.flatMap(\.units) }

    public var isEmpty: Bool { parts.allSatisfy(\.units.isEmpty) }

    enum CodingKeys: String, CodingKey {
        case title, parts, forward
    }

    // Hand-written so a spine with no title and no forward references encodes
    // without either key (ground rule 5's `encodeIfPresent` discipline).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        parts = try c.decode([Part].self, forKey: .parts)
        forward = try c.decodeIfPresent([ForwardReference].self, forKey: .forward) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(parts, forKey: .parts)
        if !forward.isEmpty { try c.encode(forward, forKey: .forward) }
    }
}

/// §6.6's lesson: authored *teaching* text for one content node. The node's
/// `statement` says what to know; the lesson says how to come to know it.
///
/// Sections are fixed so the reader has a rhythm. `hook`, `explanation` and
/// `recap` are required (the validator enforces it); `worked`, `interview` and
/// `pitfalls` are present wherever the node's kind can honestly fill them —
/// forcing all six on an `intuition` node would only manufacture filler.
/// Everything renders through the same LaTeX-lite subset as a `statement`, and
/// the corpus self-check covers every section.
public struct Lesson: Codable, Hashable, Sendable, Identifiable {
    /// The content node this lesson teaches.
    public let node: NodeID
    /// Where this sits and why it earns a step — one or two sentences.
    public let hook: String
    /// The actual teaching, several paragraphs. Paragraph breaks survive as
    /// newlines (folded YAML scalars keep blank lines), and the reader renders
    /// each paragraph separately.
    public let explanation: String
    /// An example computed to the end — the interview answer is the number.
    public let worked: String?
    /// How this is asked under pressure: canonical phrasings, what the
    /// interviewer is listening for.
    public let interview: String?
    /// The standard traps.
    public let pitfalls: String?
    /// One breath to retain.
    public let recap: String
    /// §6.7's authored cards: the lesson as a paged, checked sequence rather than
    /// a scroll of prose. Empty on a lesson nobody has made interactive yet, and
    /// `cards` then derives a paging from the prose above (D13.1) — so this being
    /// empty changes how good the lesson is, never whether it works.
    public let steps: [LessonCard]

    public var id: NodeID { node }

    public init(
        node: NodeID,
        hook: String,
        explanation: String,
        worked: String? = nil,
        interview: String? = nil,
        pitfalls: String? = nil,
        recap: String,
        steps: [LessonCard] = []
    ) {
        self.node = node
        self.hook = hook
        self.explanation = explanation
        self.worked = worked
        self.interview = interview
        self.pitfalls = pitfalls
        self.recap = recap
        self.steps = steps
    }

    enum CodingKeys: String, CodingKey {
        case node, hook, explanation, worked, interview, pitfalls, recap, steps
    }

    // Hand-written for the same reason `Node`'s is: absent sections decode as nil
    // and encode away again, so program.json stays byte-stable (ground rule 5).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        node = try c.decode(NodeID.self, forKey: .node)
        hook = try c.decode(String.self, forKey: .hook)
        explanation = try c.decode(String.self, forKey: .explanation)
        worked = try c.decodeIfPresent(String.self, forKey: .worked)
        interview = try c.decodeIfPresent(String.self, forKey: .interview)
        pitfalls = try c.decodeIfPresent(String.self, forKey: .pitfalls)
        recap = try c.decode(String.self, forKey: .recap)
        steps = try c.decodeIfPresent([LessonCard].self, forKey: .steps) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(node, forKey: .node)
        try c.encode(hook, forKey: .hook)
        try c.encode(explanation, forKey: .explanation)
        try c.encodeIfPresent(worked, forKey: .worked)
        try c.encodeIfPresent(interview, forKey: .interview)
        try c.encodeIfPresent(pitfalls, forKey: .pitfalls)
        try c.encode(recap, forKey: .recap)
        if !steps.isEmpty { try c.encode(steps, forKey: .steps) }
    }
}

/// One authored lessons file: a unit's chapter opening plus a lesson per content
/// node the unit contains. Lessons are stored sorted by node id — the *teaching*
/// order within a unit is computed by `ProgramPlan`, never authored twice.
public struct LessonUnit: Codable, Hashable, Sendable, Identifiable {
    public let unit: NodeID
    /// The paragraph the chapter starts with.
    public let opening: String
    public let lessons: [Lesson]

    public var id: NodeID { unit }

    public init(unit: NodeID, opening: String, lessons: [Lesson]) {
        self.unit = unit
        self.opening = opening
        self.lessons = lessons.sorted { $0.node < $1.node }
    }
}

/// The assembled program corpus — spine plus every authored lessons file — with
/// the indexes both the tooling and the app want. Mirrors `ProblemBank`: built
/// once, deterministic, tolerant of invalid input (the validator reports, the
/// container still loads).
public struct Program: Sendable {
    public let spine: ProgramSpine
    /// Authored lesson units, keyed by unit id. Sparse while the corpus is being
    /// written — coverage is reported, not assumed.
    public let lessonUnits: [NodeID: LessonUnit]
    /// Every lesson, keyed by the node it teaches. First writer wins on
    /// (invalid, validator-reported) duplicates so loading stays deterministic.
    public let lessonsByNode: [NodeID: Lesson]

    public init(spine: ProgramSpine, lessonUnits: [LessonUnit] = []) {
        self.spine = spine

        var byUnit: [NodeID: LessonUnit] = [:]
        for unit in lessonUnits.sorted(by: { $0.unit < $1.unit })
        where byUnit[unit.unit] == nil {
            byUnit[unit.unit] = unit
        }
        self.lessonUnits = byUnit

        var byNode: [NodeID: Lesson] = [:]
        for unit in byUnit.values.sorted(by: { $0.unit < $1.unit }) {
            for lesson in unit.lessons where byNode[lesson.node] == nil {
                byNode[lesson.node] = lesson
            }
        }
        lessonsByNode = byNode
    }

    public var isEmpty: Bool { spine.isEmpty && lessonUnits.isEmpty }

    /// §6.7 coverage: lessons whose cards are *authored* rather than derived from
    /// their prose. Reported by `validate` on every run, never a gate — the same
    /// split D12.4 made for lesson coverage itself, for the same reason.
    public var interactiveLessonCount: Int {
        lessonsByNode.values.count(where: \.isInteractive)
    }

    public func lesson(for node: NodeID) -> Lesson? { lessonsByNode[node] }

    public func opening(of unit: NodeID) -> String? { lessonUnits[unit]?.opening }
}
