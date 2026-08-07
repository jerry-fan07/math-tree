/// The single kind every node carries (§2.1). Raw values are the lowercase names
/// as authored in YAML.
public enum NodeKind: String, Codable, Hashable, Sendable, CaseIterable {
    // Structural — navigation and clustering, not learnable, not scored.
    case branch
    case subbranch

    // Content — actual knowledge a user can master.
    case definition
    case axiom
    case theorem
    case lemma
    case proposition
    case corollary
    case technique
    case example
    case intuition

    public var isStructural: Bool {
        switch self {
        case .branch, .subbranch: true
        default: false
        }
    }

    public var isContent: Bool { !isStructural }

    /// How many dot-separated components a well-formed id of this kind has (§3.1):
    /// `branch`, `branch.subbranch`, `branch.subbranch.slug`.
    public var idComponentCount: Int {
        switch self {
        case .branch: 1
        case .subbranch: 2
        default: 3
        }
    }

    /// The kind a node's primary `contains` parent must have. `nil` for `branch`,
    /// which sits at the root of the taxonomy tree.
    public var primaryParentKind: NodeKind? {
        switch self {
        case .branch: nil
        case .subbranch: .branch
        default: .subbranch
        }
    }
}
