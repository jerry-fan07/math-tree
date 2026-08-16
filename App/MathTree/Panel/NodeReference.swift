import GraphCore
import SwiftUI

/// A navigable reference to another node — the panel's only navigation primitive.
///
/// Resolves the id against the document so the row can show a title and a colour. An
/// unresolvable id is rendered as the bare id and is *not* clickable: the validator forbids
/// dangling references (§3.3), but a panel that crashes or navigates into nothing when the
/// artifacts are stale is worse than one that says so.
///
/// The dot carries the node's **score** (§4.5) once user state exists, falling back to the
/// kind colour without it. That is what makes the Requires list answer §5.4's diagnosis
/// question — *which* prerequisite is weak — at a glance, and it keeps one colour language
/// between the panel and the map instead of two.
///
/// The redesign flattens the row: no card, no radius, and the kind moved out of a
/// per-row subtitle. What is left is the design's three columns — dot, title,
/// read-out — with the `relates` note (§2.3, which is content in its own right)
/// still set underneath when there is one.
struct NodeReferenceRow: View {
    let id: NodeID
    let document: GraphDocument
    /// The `relates` note.
    var note: String?
    /// Where this node comes from, when that is the interesting fact about it —
    /// §6.5's path shows the branch a step was imported from, because "you have to
    /// go through Foundations first" is the answer the user came for.
    var origin: String?
    var scores: ScoreStore?
    var titleSize: CGFloat = 13
    var onSelect: (NodeID) -> Void

    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        if let index = document.index(of: id) {
            let target = document[index]
            Button {
                onSelect(id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    dot(for: target, theme: theme)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    VStack(alignment: .leading, spacing: 4) {
                        MathTextView(source: target.title, size: titleSize, color: theme.rowTitle.color)
                        if let note, !note.isEmpty {
                            MathTextView(source: note, size: 12, color: theme.inkMuted.color)
                        }
                    }
                    Spacer(minLength: 8)
                    // §6.5's origin, when there is one. A bordered chip in the
                    // Phase 11 frame; the redesign has no chips, so it is set as
                    // quiet text before the read-out — same fact, one less box.
                    if let origin, !origin.isEmpty {
                        Text(origin)
                            .font(Typeface.mono(10))
                            .foregroundStyle(theme.inkFaint.fading(0.75).color)
                            .lineLimit(1)
                    }
                    Text(readout(for: target))
                        .font(Typeface.mono(10.5))
                        .foregroundStyle(theme.rowTrailing.color)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHovering ? theme.rowHighlight.color : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help("\(target.kind.rawValue) · \(target.id.rawValue)")
            .accessibilityLabel("\(target.title), \(target.kind.rawValue), \(readout(for: target))")
            .accessibilityHint("Opens this node")
        } else {
            Text(id.rawValue)
                .font(Typeface.mono(11))
                .foregroundStyle(theme.inkFaint.color)
                .padding(.vertical, 4)
                .help("Not present in the loaded graph — rebuild content artifacts")
        }
    }

    /// Score when there is one; kind colour otherwise. Structural nodes are never
    /// scored (§2.1), so they always show their kind.
    @ViewBuilder
    private func dot(for target: Node, theme: Theme) -> some View {
        if let scores, target.kind.isContent {
            ScoreDot(id: target.id, scores: scores)
        } else {
            Circle()
                .fill(PanelTheme.color(for: target.kind))
                .frame(width: 6, height: 6)
                .frame(width: 10.8, height: 10.8)
        }
    }

    /// A structural reference has no score, so it says what it is; a content one
    /// says where it sits on §4.5's three states.
    private func readout(for target: Node) -> String {
        guard let scores, target.kind.isContent else { return target.kind.rawValue }
        switch ScoreFormat.state(of: target.id, in: scores) {
        case .unlearned: return "new"
        case .frontier: return "ready"
        case .attempted: return "missed"
        case let .learned(retrievability): return ScoreFormat.percent(retrievability)
        }
    }
}

/// The same reference, sized for a metadata row rather than a list.
struct NodeReferenceLink: View {
    let id: NodeID
    let document: GraphDocument
    var onSelect: (NodeID) -> Void

    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        if let index = document.index(of: id) {
            let target = document[index]
            Button {
                onSelect(id)
            } label: {
                MathTextView(
                    source: target.title, size: 12, color: theme.action.color,
                    underline: isHovering)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
        } else {
            Text(id.rawValue)
                .font(Typeface.mono(11))
                .foregroundStyle(theme.inkFaint.color)
        }
    }
}
