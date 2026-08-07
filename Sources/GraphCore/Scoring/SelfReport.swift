import Foundation

/// §5.1's `self-report` source: the user marking "I know this", graded by how well.
///
/// This is the **placeholder** evidence instrument. §5.2 makes problems the real
/// one, and Phase 8 replaces this — the value here is that everything downstream
/// (fold, propagation, colours, scheduling) can be exercised end to end before a
/// problem bank exists, and none of it has to change when one does.
///
/// **There is deliberately no "I don't know this".** The plan's flow is
/// affirmative — "I know this, with a confidence grade" — and a self-reported
/// `again` would be actively harmful here: it writes FSRS state onto a node that
/// has none, and the frontier is defined by the *absence* of state (§4.5), so
/// claiming ignorance would silently remove the node from "what you could learn
/// next" — the exact opposite of what the user meant. Negative evidence needs its
/// own semantics (a retest flag, §4.3), not a grade; that arrives with problems.
public enum SelfReportConfidence: String, Codable, Hashable, Sendable, CaseIterable {
    /// "I've met this, but I'd struggle."
    case shaky
    /// "I know this."
    case solid
    /// "This is automatic."
    case fluent

    /// FSRS reads a review as a grade; confidence is the user-facing vocabulary
    /// for the three passing grades. `again` has no self-report spelling.
    public var grade: Grade {
        switch self {
        case .shaky: .hard
        case .solid: .good
        case .fluent: .easy
        }
    }

    public var title: String {
        switch self {
        case .shaky: "Shaky"
        case .solid: "Solid"
        case .fluent: "Fluent"
        }
    }

    public var detail: String {
        switch self {
        case .shaky: "I've met this, but I'd have to work at it."
        case .solid: "I know this and could use it."
        case .fluent: "This is automatic."
        }
    }

    /// The evidence event this report is. Propagation to prerequisites is the
    /// caller's job (`Propagation.expanded`) — expansion is a write-time step, so
    /// it belongs with the append, not with the event's construction (D5.5).
    public func event(on id: NodeID, at now: Date) -> EvidenceEvent {
        EvidenceEvent(at: now, target: .node(id), grade: grade, source: .selfReport)
    }
}
