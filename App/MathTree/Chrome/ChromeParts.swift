import GraphCore
import SwiftUI

/// The small vocabulary every surface in the redesign is built from.
///
/// Turn 1's whole argument is subtraction: two surfaces, rules instead of cards,
/// underlined text instead of filled buttons, one accent. That only reads as a
/// system if the parts are literally shared, so a section eyebrow in the rail and
/// one in the node panel are the same view rather than two `Text`s that happen to
/// agree today.

/// A section heading: mono, uppercase, wide-tracked, quiet, with the count of
/// what is under it set even quieter beside it.
struct Eyebrow: View {
    let title: String
    var count: Int?
    /// Rail sections put the count hard right; panel sections keep it tucked
    /// against the title.
    var spread = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(Typeface.mono(10, .medium))
                .tracking(Typeface.tracking(0.18, at: 10))
                .foregroundStyle(theme.eyebrow.color)
            if spread { Spacer(minLength: 0) }
            if let count {
                Text("\(count)")
                    .font(Typeface.mono(10))
                    .foregroundStyle(theme.eyebrowCount.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One hairline. The redesign separates everything with these and nothing with
/// borders, shadows or fills.
struct Rule: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(ThemeStore.shared.theme.hairline.color)
            .frame(height: 1)
            .padding(.horizontal, inset)
    }
}

/// A node's score, as the map draws it: a filled dot in the branch's hue at the
/// score's luminance, with §4.5's gold ring around it when it is on the frontier.
struct ScoreDot: View {
    let id: NodeID
    var scores: ScoreStore?
    var diameter: CGFloat = 6

    var body: some View {
        let theme = ThemeStore.shared.theme
        let isFrontier = scores?.isFrontier(id) ?? false
        Circle()
            .fill(scores.map { ScoreFormat.fill(of: id, in: $0).color } ?? theme.unlearnedFill.color)
            .frame(width: diameter, height: diameter)
            .overlay {
                if isFrontier {
                    Circle()
                        .strokeBorder(theme.frontierRing.color, lineWidth: 1.4)
                        // The map's ring sits outside the dot rather than on it,
                        // and a 6 pt dot has no room to do that inside its own
                        // bounds — so the ring is drawn on a larger circle and the
                        // row's spacing absorbs it.
                        .frame(width: diameter + 4.8, height: diameter + 4.8)
                }
            }
            .frame(width: diameter + 4.8, height: diameter + 4.8)
    }
}

/// The redesign's only affordance shape: a word in the accent colour with a rule
/// under it. No fill, no border, no radius — the same reason the chips went.
struct TextAction: View {
    let title: String
    var size: CGFloat = 12
    var weight: Font.Weight = .medium
    /// A quieter variant for the secondary action on a surface, which the design
    /// leaves as plain text beside the accented one.
    var isQuiet = false
    var accessibilityHint: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        let tint = isQuiet ? theme.inkMuted : theme.action
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Typeface.sans(size, weight))
                    .foregroundStyle(tint.color)
                Rectangle()
                    .fill(
                        isQuiet
                            ? theme.inkMuted.fading(isHovering ? 0.55 : 0).color
                            : theme.actionRule.fading(isHovering ? 1.6 : 1).color
                    )
                    .frame(height: 1)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityHint(accessibilityHint ?? "")
    }
}

/// Retrievability as a 3 pt bar. The design uses it in the node panel and, wider
/// and shorter, as focus mode's "9 / 14 met" progress.
struct MeasureBar: View {
    /// 0…1.
    let value: Double
    var height: CGFloat = 3
    /// Defaults to the theme's measure colour; focus mode's progress uses the same.
    var tint: ThemeColor?

    var body: some View {
        let theme = ThemeStore.shared.theme
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(theme.measureTrack.color)
                Rectangle()
                    .fill((tint ?? theme.measure).color)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A row in the rail or in one of the panel's reference lists: score dot, title,
/// and one right-aligned read-out. The design gives them no background, no radius
/// and no chevron — the hover state is a barely-there wash and nothing else.
struct NodeRow: View {
    let id: NodeID
    let document: GraphDocument
    var scores: ScoreStore?
    /// What to set on the right. `nil` shows the score read-out.
    var trailing: String?
    var titleSize: CGFloat = 12.5
    /// Revealed on hover, when the node has a problem to offer (§5.4).
    var onReview: ((NodeID) -> Void)?
    let onSelect: (NodeID) -> Void

    @State private var isHovering = false

    private var title: String {
        document.index(of: id).map { document[$0].title } ?? id.rawValue
    }

    /// A frontier row has no score to show, so it shows what it is waiting to
    /// become; a missed row says so rather than printing the meaningless
    /// retrievability a localized miss leaves behind (D8.3).
    private var readout: String {
        guard let scores else { return "—" }
        switch ScoreFormat.state(of: id, in: scores) {
        case .unlearned, .frontier: return "new"
        case .attempted: return "missed"
        case let .learned(retrievability): return ScoreFormat.percent(retrievability)
        }
    }

    var body: some View {
        let theme = ThemeStore.shared.theme
        Button { onSelect(id) } label: {
            HStack(spacing: 6) {
                ScoreDot(id: id, scores: scores)
                MathTextView(source: title, size: titleSize, color: theme.rowTitle.color)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if isHovering, let onReview {
                    Button { onReview(id) } label: {
                        Text("problem")
                            .font(Typeface.sans(10.5, .medium))
                            .foregroundStyle(theme.action.color)
                    }
                    .buttonStyle(.plain)
                    .help("Review this with a problem")
                } else {
                    Text(trailing ?? readout)
                        .font(Typeface.mono(10.5))
                        .foregroundStyle(theme.rowTrailing.color)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(isHovering ? theme.rowHighlight.color : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(id.rawValue)
    }
}
