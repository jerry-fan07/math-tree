/// A `relates` connection as *authored* on one endpoint (§3.1): the other endpoint
/// plus the note that explains the connection. The note is content in its own right,
/// which is why it is required rather than decorative (§2.3).
public struct RelatesRef: Codable, Hashable, Sendable, Comparable {
    public let id: NodeID
    public let note: String

    public init(id: NodeID, note: String) {
        self.id = id
        self.note = note
    }

    public static func < (lhs: RelatesRef, rhs: RelatesRef) -> Bool {
        (lhs.id, lhs.note) < (rhs.id, rhs.note)
    }
}

/// The same connection in canonical, undirected form: endpoints sorted so that a
/// relation authored from either side collapses to one edge. `key` is the exact
/// string §3.2 uses to index per-user edge state.
public struct RelatesEdge: Codable, Hashable, Sendable, Comparable {
    public let a: NodeID
    public let b: NodeID
    public let note: String

    public init(_ x: NodeID, _ y: NodeID, note: String) {
        if x <= y {
            self.a = x
            self.b = y
        } else {
            self.a = y
            self.b = x
        }
        self.note = note
    }

    /// `"a ~ b"` — the `edge_states` key of §3.2.
    public var key: String { "\(a.rawValue) ~ \(b.rawValue)" }

    public func endpoint(opposite id: NodeID) -> NodeID {
        id == a ? b : a
    }

    public static func < (lhs: RelatesEdge, rhs: RelatesEdge) -> Bool {
        (lhs.a, lhs.b, lhs.note) < (rhs.a, rhs.b, rhs.note)
    }
}
