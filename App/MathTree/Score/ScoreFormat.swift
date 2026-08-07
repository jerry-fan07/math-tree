import Foundation
import GraphCore
import SwiftUI

/// Shared vocabulary for talking about a score in the UI.
///
/// One place, because the panel and the sidebar must never describe the same node
/// differently — "84 %" beside "due now" beside a green dot has to be three
/// read-outs of one state, not three opinions.
enum ScoreFormat {
    /// §4.5's three states, named.
    enum State: Equatable {
        case unlearned
        /// Unlearned, but every prerequisite is above τ — "what you could learn next".
        case frontier
        /// Attempted and missed, never yet retrieved successfully. Phase 8 is the
        /// first thing that can produce this: §5.4's diagnosis writes an `again`
        /// onto a node with no history, which creates FSRS state without creating
        /// knowledge (D8.3). It is *not* `learned(0.02)`, and saying so is the
        /// whole point — the map keeps it grey and keeps it on the frontier.
        case attempted
        case learned(Double)

        var title: String {
            switch self {
            case .unlearned: "Unlearned"
            case .frontier: "Ready to learn"
            case .attempted: "Not yet"
            case let .learned(retrievability): ScoreFormat.percent(retrievability)
            }
        }

        var detail: String {
            switch self {
            // Not "a prerequisite is missing": it may well be learned but sitting
            // below τ, which is a different situation and a different next step.
            case .unlearned: "No evidence yet, and a prerequisite is not yet solid enough."
            case .frontier: "Every prerequisite is above the mastery threshold."
            case .attempted: "A problem localized here and it was missed. Still to learn."
            case .learned: "Modelled chance you could retrieve this right now."
            }
        }
    }

    @MainActor
    static func state(of id: NodeID, in scores: ScoreStore) -> State {
        if let retrievability = scores.retrievability(of: id), scores.isLearned(id) {
            return .learned(retrievability)
        }
        if scores.retrievability(of: id) != nil { return .attempted }
        return scores.isFrontier(id) ? .frontier : .unlearned
    }

    static func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    /// The swatch colour: a frontier node is grey *plus* an accent, exactly as it
    /// is drawn on the map, so the panel and the graph agree at a glance.
    @MainActor
    static func color(of id: NodeID, in scores: ScoreStore) -> Color {
        Color(scores.color(of: id))
    }

    /// Relative to the snapshot's clock, not to `Date()` — under `MATHTREE_NOW`
    /// those differ, and the one the colours used is the truthful one.
    static func due(_ date: Date?, relativeTo now: Date) -> String {
        guard let date else { return "Not scheduled" }
        let days = date.timeIntervalSince(now) / 86_400
        if days <= 0 { return "Due now" }
        if days < 1 { return "Due in \(Int((days * 24).rounded(.up))) h" }
        if days < 2 { return "Due tomorrow" }
        if days < 45 { return "Due in \(Int(days.rounded())) days" }
        return "Due \(date.formatted(.dateTime.year().month(.abbreviated).day()))"
    }

    static func elapsed(since date: Date, to now: Date) -> String {
        let days = now.timeIntervalSince(date) / 86_400
        if days < 1 { return "today" }
        if days < 2 { return "yesterday" }
        if days < 45 { return "\(Int(days.rounded())) days ago" }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }
}

extension Color {
    /// `ScoreColor` is GraphCore's own value type — the score model owns §4.5's
    /// mapping, and this is the only place it becomes a UI colour.
    init(_ score: ScoreColor) {
        self.init(
            .sRGB, red: score.red, green: score.green, blue: score.blue, opacity: score.alpha)
    }
}
