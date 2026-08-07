/// Importance, orthogonal to kind (§2.1). Drives display only — never semantics.
public enum Prominence: Int, Codable, Hashable, Sendable, Comparable, CaseIterable {
    /// Fine-grained detail: most lemmas, examples.
    case detail = 0
    /// Standard topic.
    case standard = 1
    /// Landmark result: FTC, SVD, Sylow, CLT.
    case landmark = 2

    public static func < (lhs: Prominence, rhs: Prominence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
