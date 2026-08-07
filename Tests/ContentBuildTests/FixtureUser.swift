import Foundation
import GraphCore

/// A hand-authored user over the *real* seed content — Phase 6's fixture.
///
/// It is written here rather than as a literal JSONL file because propagation is a
/// write-time expansion (D5.5): a log has to *contain* the implicit events it
/// induced, and hand-typing those would encode a human's arithmetic instead of
/// `Propagation`'s. So the explicit reviews are authored and the log is derived,
/// exactly as the app derives it — and `fixtures/*.jsonl` is a golden copy of the
/// result, checked by `FixtureUserTests` and regenerated with
/// `MATHTREE_UPDATE_FIXTURES=1 swift test`.
///
/// The story: someone who has worked through limits, continuity and
/// differentiation up to the Mean Value Theorem, met Riemann sums once in the
/// spring and let them go cold, and has not started the Fundamental Theorem.
enum FixtureUser {
    /// The clock every fixture assertion is evaluated at. Pinned, because
    /// retrievability decays continuously (§4.1) — an unpinned fixture would have
    /// a different answer every time it ran.
    static let now = instant("2026-08-07T12:00:00Z")

    /// Only the reviews the user actually performed. Everything else in the log is
    /// derived from these.
    static let explicit: [EvidenceEvent] = [
        // Foundations, last spring.
        review("foundations.real.sup-inf", .good, "2026-03-02T09:00:00Z"),
        review("analysis.svc.def-riemann-sum", .hard, "2026-03-15T09:00:00Z"),
        review("analysis.svc.def-limit", .good, "2026-05-01T09:00:00Z"),
        review("foundations.real.completeness", .good, "2026-05-04T09:00:00Z"),
        review("analysis.svc.def-derivative", .good, "2026-05-20T09:00:00Z"),
        review("analysis.svc.def-continuity", .good, "2026-05-22T09:00:00Z"),
        // Building toward the Mean Value Theorem through June.
        review("analysis.svc.diff-implies-cont", .good, "2026-06-10T09:00:00Z"),
        review("analysis.svc.evt", .hard, "2026-06-12T09:00:00Z"),
        review("analysis.svc.rolle", .good, "2026-06-25T09:00:00Z"),
        review("analysis.svc.mvt", .easy, "2026-07-20T09:00:00Z"),
        // A recent pass over the derivative — two events on one node, so the
        // panel's sparkline has a segment to draw.
        review("analysis.svc.def-derivative", .easy, "2026-08-01T09:00:00Z"),
    ]

    /// The deep self-report used to demonstrate propagation in the UI: FTC Part II
    /// sits four `requires`-hops above the derivative, so reporting it lights up a
    /// chain the user never touched directly (§4.3).
    static let deepReview = SelfReportConfidence.fluent.event(
        on: "analysis.svc.ftc-part-2", at: now)

    /// The log as the app would have written it: every explicit review followed by
    /// the implicit reviews it induced.
    static func log(in graph: KnowledgeGraph, config: ScoringConfig = ScoringConfig())
        -> [EvidenceEvent]
    {
        explicit.flatMap { Propagation.expanded($0, in: graph, config: config) }
            .sorted(by: foldOrder)
    }

    /// The same log after one deep self-report — the "after" half of the
    /// propagation demonstration.
    static func reviewedLog(in graph: KnowledgeGraph, config: ScoringConfig = ScoringConfig())
        -> [EvidenceEvent]
    {
        (log(in: graph, config: config)
            + Propagation.expanded(deepReview, in: graph, config: config))
            .sorted(by: foldOrder)
    }

    // MARK: - Helpers

    static func instant(_ text: String) -> Date {
        guard
            let date = try? Date.ISO8601FormatStyle(
                includingFractionalSeconds: false, timeZone: .gmt
            ).parse(text)
        else { preconditionFailure("fixture timestamp is not ISO-8601: \(text)") }
        return date
    }

    private static func review(_ id: NodeID, _ grade: Grade, _ at: String) -> EvidenceEvent {
        EvidenceEvent(at: instant(at), target: .node(id), grade: grade, source: .selfReport)
    }

    /// `EvidenceEvent.foldOrder` is internal to GraphCore, so its precedence is
    /// mirrored here: instant, then target, then explicit-before-implicit.
    ///
    /// The fold sorts whatever it is given (D5.7), so *any* stable order would
    /// score identically — but matching the real precedence makes the golden file
    /// byte-for-byte what `ScoreStore.record` writes, which turns
    /// `diff after-report.jsonl fixture-user-reviewed.jsonl` into a check on the
    /// app's write path rather than a formatting curiosity.
    private static func foldOrder(_ lhs: EvidenceEvent, _ rhs: EvidenceEvent) -> Bool {
        if lhs.at != rhs.at { return lhs.at < rhs.at }
        if lhs.target.key != rhs.target.key { return lhs.target.key < rhs.target.key }
        return (lhs.source == .implicit ? 1 : 0) < (rhs.source == .implicit ? 1 : 0)
    }
}
