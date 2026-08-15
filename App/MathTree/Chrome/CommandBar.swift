import GraphCore
import SwiftUI

/// The command line across the top — the first of the redesign's two surfaces.
///
/// It replaces what Phase 6 spread across three places: the app's identity (which
/// was only in the window title), where you are (which was nowhere), and how big
/// the map is (which was nowhere either). One rule-separated strip, no controls —
/// everything here is a read-out, because turn 1's argument is that the map does
/// not need a toolbar.
struct CommandBar: View {
    let document: GraphDocument
    var scores: ScoreStore?
    /// The selected node, whose taxonomy ancestors are the breadcrumb.
    var selection: NodeID?
    /// Selecting a crumb walks back up the taxonomy.
    var onSelect: (NodeID) -> Void

    var body: some View {
        let theme = ThemeStore.shared.theme
        HStack(spacing: 16) {
            wordmark(theme)
            Rectangle()
                .fill(theme.trailSeparator.color)
                .frame(width: 1, height: theme.isDark ? 14 : 15)
            breadcrumb(theme)
            Spacer(minLength: 24)
            stats(theme)
        }
        .padding(.horizontal, theme.isDark ? 20 : 24)
        .frame(height: theme.barHeight)
        .frame(maxWidth: .infinity)
        .background(theme.barFill.color)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.rule.color).frame(height: 1)
        }
    }

    /// Two directions, two voices: the dark canvas takes a mono, wide-tracked
    /// all-caps mark that reads as instrumentation; paper takes the serif set as a
    /// title. Same six syllables.
    @ViewBuilder
    private func wordmark(_ theme: Theme) -> some View {
        if theme.isDark {
            Text("KNOWLEDGE TREE")
                .font(Typeface.mono(11, .medium))
                .tracking(Typeface.tracking(0.22, at: 11))
                .foregroundStyle(theme.wordmark.color)
        } else {
            Text("Knowledge Tree")
                .font(Typeface.serif(18))
                .foregroundStyle(theme.wordmark.color)
        }
    }

    // MARK: - Breadcrumb

    /// Where the selection *is*, outermost first. Nothing selected is "All
    /// branches", which is the truthful description of the overview.
    ///
    /// A content node's own name is left off the trail: it is the headline of the
    /// panel directly beneath, and the bar's job is to say which neighbourhood the
    /// map is showing. A structural node keeps its name, because selecting a branch
    /// *is* navigating to it and there would otherwise be nothing to show for it.
    private var crumbs: [Node] {
        guard let selection, let index = document.index(of: selection) else { return [] }
        let selected = document[index]
        var chain: [Node] = []
        var cursor: Node? =
            selected.kind.isStructural
            ? selected
            : selected.parent.flatMap { document.index(of: $0) }.map { document[$0] }
        var guardCount = 0
        while let node = cursor, guardCount < 64 {
            chain.append(node)
            cursor = node.parent.flatMap { document.index(of: $0) }.map { document[$0] }
            guardCount += 1
        }
        return chain.reversed()
    }

    private func breadcrumb(_ theme: Theme) -> some View {
        HStack(spacing: 8) {
            crumb("All branches", isCurrent: crumbs.isEmpty, theme: theme) {}
            ForEach(Array(crumbs.enumerated()), id: \.element.id) { position, node in
                Text("/")
                    .font(Typeface.sans(12.5))
                    .foregroundStyle(theme.trailSeparator.color)
                crumb(
                    node.title, isCurrent: position == crumbs.count - 1, theme: theme,
                    action: { onSelect(node.id) })
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
    }

    @ViewBuilder
    private func crumb(
        _ title: String, isCurrent: Bool, theme: Theme, action: @escaping () -> Void
    ) -> some View {
        let tint = isCurrent ? theme.trailCurrent : theme.trail
        if isCurrent {
            MathTextView(source: title, size: 12.5, color: tint.color)
        } else {
            Button(action: action) {
                MathTextView(source: title, size: 12.5, color: tint.color)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stats

    /// Three numbers, all of them real: how big the graph is, and how much of it
    /// is above the mastery threshold.
    ///
    /// The design frame shows "112 nodes in view" at mid zoom. That is left out
    /// deliberately — the renderer culls by level-of-detail prefix rather than by
    /// frustum, so it has no count of what is on screen, and a number the app
    /// cannot actually compute is worse than one fewer number.
    private func stats(_ theme: Theme) -> some View {
        HStack(spacing: 20) {
            Text("\(grouped(document.nodes.count)) nodes")
            Text("\(grouped(edgeCount)) edges")
            if let coverage {
                Text(ScoreFormat.percent(coverage))
                    .foregroundStyle(theme.statEmphasis.color)
                    .help("Share of learnable nodes above the mastery threshold")
            }
        }
        .font(Typeface.mono(11))
        .foregroundStyle(theme.stat.color)
        .fixedSize()
    }

    private var edgeCount: Int {
        document.requiresEdges.count + document.relatesEdges.count
    }

    /// Content nodes above τ, over all content nodes. The same threshold the
    /// frontier is computed from, so "38%" and "ready to learn" are two read-outs
    /// of one model rather than two definitions of "known".
    private var coverage: Double? {
        guard let scores else { return nil }
        let content = document.nodes.filter { $0.kind.isContent }
        guard !content.isEmpty else { return nil }
        let mastered = content.filter { node in
            guard let retrievability = scores.retrievability(of: node.id),
                scores.isLearned(node.id)
            else { return false }
            return retrievability >= scores.config.masteryThreshold
        }
        return Double(mastered.count) / Double(content.count)
    }

    /// Thin spaces between thousands, as the design sets them ("1 248 nodes").
    private func grouped(_ value: Int) -> String {
        let digits = String(value)
        guard digits.count > 4 else { return digits }
        var out = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset.isMultiple(of: 3) { out.append("\u{2009}") }
            out.append(character)
        }
        return String(out.reversed())
    }
}
