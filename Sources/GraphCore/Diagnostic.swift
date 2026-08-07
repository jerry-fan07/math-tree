/// The invariant a `Diagnostic` reports on. Raw values are stable, machine-readable
/// slugs — tooling and CI match on these, not on message text.
public enum DiagnosticRule: String, Codable, Hashable, Sendable, CaseIterable {
    case duplicateID = "duplicate-id"
    case malformedID = "malformed-id"
    case idParentPrefixMismatch = "id-parent-prefix-mismatch"
    case emptyTitle = "empty-title"

    case missingPrimaryParent = "missing-primary-parent"
    case unexpectedPrimaryParent = "unexpected-primary-parent"
    case primaryParentKindMismatch = "primary-parent-kind-mismatch"
    case selfContains = "self-contains"
    case containsCycle = "contains-cycle"
    case duplicateAlsoUnder = "duplicate-also-under"
    case alsoUnderRepeatsPrimaryParent = "also-under-repeats-primary-parent"
    case alsoUnderNotStructural = "also-under-not-structural"

    case danglingParent = "dangling-parent"
    case danglingAlsoUnder = "dangling-also-under"
    case danglingRequires = "dangling-requires"
    case danglingRelates = "dangling-relates"

    case duplicateRequires = "duplicate-requires"
    case requiresCycle = "requires-cycle"
    case redundantRequires = "redundant-requires"

    case structuralNodeHasStatement = "structural-node-has-statement"
    case structuralNodeHasRequires = "structural-node-has-requires"
    case structuralNodeHasRelates = "structural-node-has-relates"

    case selfRelates = "self-relates"
    case emptyRelatesNote = "empty-relates-note"
    case duplicateRelates = "duplicate-relates"

    // Problem bank (§5.2). Same diagnostic vocabulary as content because the bank
    // is content — authored, reviewed, and gated by the same CI step.
    case duplicateProblemID = "duplicate-problem-id"
    case malformedProblemID = "malformed-problem-id"
    case emptyProblemStatement = "empty-problem-statement"
    case emptyProblemAnswer = "empty-problem-answer"
    case emptyProblemRubric = "empty-problem-rubric"
    case problemMissingTargets = "problem-missing-targets"
    case danglingProblemTarget = "dangling-problem-target"
    case danglingProblemExercises = "dangling-problem-exercises"
    case danglingProblemConnects = "dangling-problem-connects"
    case problemTargetNotContent = "problem-target-not-content"
    case problemExercisesNotContent = "problem-exercises-not-content"
    case duplicateProblemTag = "duplicate-problem-tag"
    case problemTargetAlsoExercised = "problem-target-also-exercised"
    case problemExercisesNotPrerequisite = "problem-exercises-not-prerequisite"
    case problemConnectsUntaggedEndpoint = "problem-connects-untagged-endpoint"
}

/// One invariant violation. Typed rather than pass/fail so `ContentBuild` can group,
/// filter, and annotate with file/line in Phase 2.
public struct Diagnostic: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rule: DiagnosticRule
    public let message: String
    /// The offending node ids. `nodes[0]` is the subject — the node an author would
    /// open to fix this.
    public let nodes: [NodeID]
    /// Supporting chain, where a rule has one: the cycle in traversal order, or the
    /// alternate prerequisite route that makes an edge redundant. Empty otherwise.
    public let path: [NodeID]
    /// Set when the thing an author would open is a *problem* rather than a node
    /// (§5.2's bank). The node ids stay populated — a dangling target names both
    /// the problem to edit and the id that does not resolve.
    public let problem: ProblemID?

    public init(
        rule: DiagnosticRule,
        message: String,
        nodes: [NodeID],
        path: [NodeID] = [],
        problem: ProblemID? = nil
    ) {
        self.rule = rule
        self.message = message
        self.nodes = nodes
        self.path = path
        self.problem = problem
    }

    public var subject: NodeID? { nodes.first }

    public var description: String {
        let ids = (problem.map { [$0.rawValue] } ?? []) + nodes.map(\.rawValue)
        return "[\(rule.rawValue)] \(message) (\(ids.joined(separator: ", ")))"
    }

    /// Grouped by subject so an author sees everything wrong with one thing together,
    /// and fully total so two runs over the same content compare equal.
    ///
    /// Content diagnostics sort ahead of problem diagnostics (`problem == nil`
    /// first): the bank references the graph, so a dangling target is often a
    /// downstream symptom of a content problem, and fixing content first is the
    /// order that converges.
    public static func < (lhs: Diagnostic, rhs: Diagnostic) -> Bool {
        if lhs.problem != rhs.problem {
            guard let left = lhs.problem else { return true }
            guard let right = rhs.problem else { return false }
            return left < right
        }
        if lhs.nodes != rhs.nodes { return lhs.nodes.lexicographicallyPrecedes(rhs.nodes) }
        if lhs.rule != rhs.rule { return lhs.rule.rawValue < rhs.rule.rawValue }
        if lhs.path != rhs.path { return lhs.path.lexicographicallyPrecedes(rhs.path) }
        return lhs.message < rhs.message
    }
}
