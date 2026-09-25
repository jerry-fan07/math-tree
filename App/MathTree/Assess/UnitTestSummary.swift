import GraphCore
import SwiftUI

/// The sheet a unit test ends on (§6.8): every question with how it went and
/// where the skill now stands. Nothing here is a second measurement — the
/// evidence was written question by question through §5.2's sheet — so this is
/// a read-out of the fold, exactly like the node panel.
struct UnitTestSummary: View {
    let unitTitle: String
    let results: [(node: NodeID, outcome: ProblemOutcome)]
    let document: GraphDocument
    let scores: ScoreStore
    var onOpenUnit: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        // Read on purpose: the levels below must reflect the grades just written.
        _ = scores.revision
        let theme = ThemeStore.shared.theme
        let passed = results.count(where: \.outcome.isPass)
        return ZStack {
            theme.scrim.color
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            SheetCard(width: 620, maxHeight: 640, header: AnyView(header(passed, theme))) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                            row(index + 1, result, theme)
                        }
                    }
                    Text(
                        "A pass recorded a review on the skill and, more weakly, on its "
                            + "prerequisites; a miss was localized where you said it broke. "
                            + "Mastered means proficient and proven by a problem."
                    )
                    .font(Typeface.sans(10.5))
                    .foregroundStyle(PanelTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 18) {
                        TextAction(
                            title: "Back to the unit →", size: 12.5,
                            accessibilityHint: "The unit page, with the ladder updated"
                        ) { onOpenUnit() }
                        TextAction(
                            title: "Close", size: 12, weight: .regular, isQuiet: true,
                            accessibilityHint: "Back to where you were"
                        ) { onDismiss() }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func header(_ passed: Int, _ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UNIT TEST · \(passed) OF \(results.count) PASSED")
                .font(Typeface.mono(10, .medium))
                .tracking(Typeface.tracking(0.18, at: 10))
                .foregroundStyle(PanelTheme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                MathTextView(source: unitTitle, size: 16, weight: .medium, color: PanelTheme.primaryText)
                Spacer(minLength: 0)
                SidebarCloseButton(symbol: "xmark", label: "Close", action: onDismiss)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func row(
        _ number: Int, _ result: (node: NodeID, outcome: ProblemOutcome), _ theme: Theme
    ) -> some View {
        let level = scores.level(of: result.node)
        let title = document.index(of: result.node).map { document[$0].title } ?? result.node.rawValue
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(format: "%02d", number))
                .font(Typeface.mono(10))
                .foregroundStyle(PanelTheme.tertiaryText)
                .frame(width: 20, alignment: .leading)
            Text(result.outcome.isPass ? "✓" : "✗")
                .font(Typeface.mono(11, .medium))
                .foregroundStyle((result.outcome.isPass ? theme.action : theme.warning).color)
                .frame(width: 14)
            MathTextView(source: title, size: 13, color: PanelTheme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(result.outcome.title.lowercased())
                .font(Typeface.mono(10))
                .foregroundStyle(PanelTheme.tertiaryText)
            HStack(spacing: 5) {
                MasteryDot(level: level, diameter: 5)
                Text(level.title.lowercased())
                    .font(Typeface.mono(10))
                    .foregroundStyle(level.tint(theme).color)
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }
}
