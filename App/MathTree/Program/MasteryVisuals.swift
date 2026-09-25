import GraphCore
import SwiftUI

/// §6.8's ladder, drawn. One tint per rung, resolved through the theme so the
/// same rung is the same colour on the course home, the unit page, the player's
/// finish card and the node panel — and so that none of them invents a fifth
/// colour the map does not have.
///
/// The tints are deliberately the theme's *existing* semantic colours rather
/// than a new scale: mastered takes the accent (it is the thing the course
/// points at), proficient takes retrievability's own colour, familiar takes the
/// attention colour (it is decayed, and due), attempted takes the warning
/// colour (a miss landed here), and not-started is the map's unlearned grey.
extension MasteryLevel {
    func tint(_ theme: Theme) -> ThemeColor {
        switch self {
        case .notStarted: theme.inkFaint
        case .attempted: theme.warning
        case .familiar: theme.attention
        case .proficient: theme.measure
        case .mastered: theme.action
        }
    }
}

/// A skill's rung as a dot: filled for a held skill, a ring for one that is
/// not, so a column of them reads as a checklist before any word is read.
struct MasteryDot: View {
    let level: MasteryLevel
    var diameter: CGFloat = 7

    var body: some View {
        let theme = ThemeStore.shared.theme
        let tint = level.tint(theme).color
        ZStack {
            if level >= .proficient {
                Circle().fill(tint)
            } else if level == .familiar {
                // Half-held: a ring with a filled centre.
                Circle().strokeBorder(tint, lineWidth: 1.2)
                Circle().fill(tint).frame(width: diameter * 0.45, height: diameter * 0.45)
            } else {
                Circle().strokeBorder(tint, lineWidth: 1.2)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// The ladder over a set of skills as one segmented bar — the read-out Khan
/// Academy puts beside every unit. Segments run mastered → proficient →
/// familiar → attempted, then the track for what is not started, so "how much
/// of this do I hold, and how firmly" is one glance.
struct MasteryBar: View {
    let summary: MasterySummary
    var height: CGFloat = 4

    var body: some View {
        let theme = ThemeStore.shared.theme
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach([MasteryLevel.mastered, .proficient, .familiar, .attempted], id: \.self) {
                    level in
                    let fraction =
                        summary.total == 0 ? 0 : Double(summary.count(level)) / Double(summary.total)
                    if fraction > 0 {
                        Rectangle()
                            .fill(level.tint(theme).color)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                Rectangle().fill(theme.measureTrack.color)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The words under a `MasteryBar`: only the rungs that are occupied, in the
/// bar's order, so a fresh unit says "18 not started" and nothing else.
struct MasteryLegend: View {
    let summary: MasterySummary
    var size: CGFloat = 10.5

    var body: some View {
        let theme = ThemeStore.shared.theme
        HStack(spacing: 12) {
            ForEach(MasteryLevel.allCases.reversed(), id: \.self) { level in
                let count = summary.count(level)
                if count > 0 {
                    HStack(spacing: 5) {
                        MasteryDot(level: level, diameter: 5)
                        Text("\(count) \(level.title.lowercased())")
                            .font(Typeface.mono(size))
                            .foregroundStyle(theme.stat.color)
                    }
                }
            }
        }
        .fixedSize()
        .accessibilityLabel(
            MasteryLevel.allCases.reversed().compactMap { level in
                summary.count(level) > 0 ? "\(summary.count(level)) \(level.title)" : nil
            }.joined(separator: ", "))
    }
}

/// "1,240 / 9,580 points" — Khan Academy's course measure, formatted once.
enum MasteryFormat {
    static func points(_ summary: MasterySummary) -> String {
        "\(grouped(summary.points)) / \(grouped(summary.possiblePoints)) points"
    }

    static func percent(_ summary: MasterySummary) -> String {
        "\(Int((summary.fraction * 100).rounded()))%"
    }

    private static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}
