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

    public init(rule: DiagnosticRule, message: String, nodes: [NodeID], path: [NodeID] = []) {
        self.rule = rule
        self.message = message
        self.nodes = nodes
        self.path = path
    }

    public var subject: NodeID? { nodes.first }

    public var description: String {
        let ids = nodes.map(\.rawValue).joined(separator: ", ")
        return "[\(rule.rawValue)] \(message) (\(ids))"
    }

    /// Grouped by subject id so an author sees everything wrong with a node together,
    /// and fully total so two runs over the same content compare equal.
    public static func < (lhs: Diagnostic, rhs: Diagnostic) -> Bool {
        if lhs.nodes != rhs.nodes { return lhs.nodes.lexicographicallyPrecedes(rhs.nodes) }
        if lhs.rule != rhs.rule { return lhs.rule.rawValue < rhs.rule.rawValue }
        if lhs.path != rhs.path { return lhs.path.lexicographicallyPrecedes(rhs.path) }
        return lhs.message < rhs.message
    }
}
