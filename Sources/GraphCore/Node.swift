/// One node of the knowledge graph, mirroring the authoring schema of §3.1.
///
/// `requires` and `relates` are authored on the *destination* node; reverse indexes
/// are derived, never authored (see `KnowledgeGraph`).
public struct Node: Codable, Hashable, Sendable, Identifiable {
    public let id: NodeID
    public let kind: NodeKind
    /// Authored value, kept faithful even on structural nodes; use
    /// `displayProminence` for anything display-facing.
    public let prominence: Prominence
    public let title: String
    /// Precise content of the node, LaTeX allowed. Absent on structural nodes (§3.1).
    public let statement: String?
    /// One-to-two sentence informal gloss for tooltips.
    public let summary: String?
    /// Primary `contains` parent. `nil` only for `branch` nodes.
    public let parent: NodeID?
    /// Secondary `contains` parents — cross-listings (§2.3). These make the taxonomy
    /// a DAG and are *not* expected to share the id prefix.
    public let alsoUnder: [NodeID]
    /// Direct prerequisites only; the transitive reduction (§2.3).
    public let requires: [NodeID]
    public let relates: [RelatesRef]
    public let tags: [String]

    public init(
        id: NodeID,
        kind: NodeKind,
        prominence: Prominence = .standard,
        title: String,
        statement: String? = nil,
        summary: String? = nil,
        parent: NodeID? = nil,
        alsoUnder: [NodeID] = [],
        requires: [NodeID] = [],
        relates: [RelatesRef] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.prominence = prominence
        self.title = title
        self.statement = statement
        self.summary = summary
        self.parent = parent
        self.alsoUnder = alsoUnder
        self.requires = requires
        self.relates = relates
        self.tags = tags
    }

    /// Structural nodes are implicitly maximal prominence for display purposes (§2.1).
    public var displayProminence: Prominence {
        kind.isStructural ? .landmark : prominence
    }

    /// This node's `relates` entries in canonical undirected form.
    public var relatesEdges: [RelatesEdge] {
        relates.map { RelatesEdge(id, $0.id, note: $0.note) }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, prominence, title, statement, summary, parent
        case alsoUnder = "also_under"
        case requires, relates, tags
    }

    // Hand-written so absent collections decode as empty and encode away again —
    // graph.json stays small and byte-stable (ground rule 5).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(NodeID.self, forKey: .id)
        kind = try c.decode(NodeKind.self, forKey: .kind)
        prominence = try c.decodeIfPresent(Prominence.self, forKey: .prominence) ?? .standard
        title = try c.decode(String.self, forKey: .title)
        statement = try c.decodeIfPresent(String.self, forKey: .statement)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        parent = try c.decodeIfPresent(NodeID.self, forKey: .parent)
        alsoUnder = try c.decodeIfPresent([NodeID].self, forKey: .alsoUnder) ?? []
        requires = try c.decodeIfPresent([NodeID].self, forKey: .requires) ?? []
        relates = try c.decodeIfPresent([RelatesRef].self, forKey: .relates) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(prominence, forKey: .prominence)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(statement, forKey: .statement)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(parent, forKey: .parent)
        if !alsoUnder.isEmpty { try c.encode(alsoUnder, forKey: .alsoUnder) }
        if !requires.isEmpty { try c.encode(requires, forKey: .requires) }
        if !relates.isEmpty { try c.encode(relates, forKey: .relates) }
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
    }
}
