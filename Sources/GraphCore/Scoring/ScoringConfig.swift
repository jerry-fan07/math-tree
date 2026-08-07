import Foundation

/// Every tunable constant in one place, as Phase 5 requires.
///
/// §11.3 is explicit that γ, `D_max` and implicit-review strength are guesses
/// until there is review data to fit against — which is much of why the evidence
/// log is replayable. Treat these as the current hypothesis, not settled values.
public struct ScoringConfig: Hashable, Sendable {
    /// Damping base: an implicit review `d` `requires`-hops away carries γᵈ (§4.3).
    public var gamma: Double
    /// `D_max` — propagation stops beyond this hop distance (§4.3).
    public var maxPropagationDepth: Int
    /// τ — retrievability above which a prerequisite counts as mastered (§4.5).
    public var masteryThreshold: Double
    /// Whether an implicit review resets the decay clock.
    ///
    /// `true` says exercising a prerequisite genuinely *is* a retrieval of it, so
    /// its retrievability should recover; damping then expresses that the
    /// *strengthening* is weaker than a direct review, not that the retrieval
    /// didn't happen. Set `false` to let implicit reviews raise stability only.
    public var implicitReviewsResetDecayClock: Bool
    /// §4.3: a failed review is evidence about the reviewed node; attribution to
    /// its prerequisites is ambiguous, so failure propagates as a flag for
    /// retesting (Phase 6 UI), never as a penalty. Off by default.
    public var propagateOnFailure: Bool
    public var fsrs: FSRSParameters

    public init(
        gamma: Double = 0.5,
        maxPropagationDepth: Int = 3,
        masteryThreshold: Double = 0.85,
        implicitReviewsResetDecayClock: Bool = true,
        propagateOnFailure: Bool = false,
        fsrs: FSRSParameters = FSRSParameters()
    ) {
        self.gamma = gamma
        self.maxPropagationDepth = maxPropagationDepth
        self.masteryThreshold = masteryThreshold
        self.implicitReviewsResetDecayClock = implicitReviewsResetDecayClock
        self.propagateOnFailure = propagateOnFailure
        self.fsrs = fsrs
    }

    /// Weight for an implicit review `depth` hops from the reviewed node.
    /// Depth 0 is a node the problem explicitly exercised (§5.2) — full strength,
    /// "regardless of graph distance".
    public func propagationWeight(depth: Int) -> Double {
        depth <= 0 ? 1.0 : pow(gamma, Double(depth))
    }
}
