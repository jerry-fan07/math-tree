/// A node's permanent, namespaced identifier (§3.1). A distinct type rather than
/// a `String` typealias so ids can never be crossed with titles, tags, or slugs.
public struct NodeID: RawRepresentable, Hashable, Comparable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: NodeID, rhs: NodeID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Dot-separated pieces: `branch`, `branch.subbranch`, or `branch.subbranch.slug`.
    public var components: [Substring] {
        rawValue.split(separator: ".", omittingEmptySubsequences: false)
    }

    /// All but the last component — the id a well-formed node's primary parent must have.
    /// `nil` for a single-component (branch) id.
    public var parentPrefix: NodeID? {
        guard let cut = rawValue.lastIndex(of: ".") else { return nil }
        return NodeID(String(rawValue[rawValue.startIndex..<cut]))
    }
}

// Spelled out rather than left to `RawRepresentable`'s defaults: ids must land in
// graph.json as bare strings, and that is too load-bearing to leave to inference.
extension NodeID {
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension NodeID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

extension NodeID: CustomStringConvertible {
    public var description: String { rawValue }
}
