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
struct NodeReferenceRow: View {
    let id: NodeID
    let document: GraphDocument
    /// The `relates` note (§2.3 — the connection is knowledge, so it is shown, not hidden
    /// behind a tooltip).
    var note: String?
    /// Where this node comes from, when that is the interesting fact about it —
    /// §6.5's path shows the branch a step was imported from, because "you have to
    /// go through Foundations first" is the answer the user came for.
    var origin: String?
    var scores: ScoreStore?
    var onSelect: (NodeID) -> Void

    @State private var isHovering = false

    var body: some View {
        if let index = document.index(of: id) {
            let target = document[index]
            Button {
                onSelect(id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    dot(for: target)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    VStack(alignment: .leading, spacing: 3) {
                        MathTextView(
                            source: target.title, size: 12.5,
                            color: isHovering ? .white : PanelTheme.primaryText)
                        Text(subtitle(for: target))
                            .font(.system(size: 10))
                            .foregroundStyle(PanelTheme.tertiaryText)
                        if let note, !note.isEmpty {
                            MathTextView(source: note, size: 11.5, color: PanelTheme.secondaryText)
                                .padding(.top, 1)
                        }
                    }
                    Spacer(minLength: 4)
                    if let origin, !origin.isEmpty {
                        Text(origin)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(PanelTheme.tertiaryText)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(PanelTheme.separator, lineWidth: 1))
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering ? PanelTheme.rowHighlight : Color.clear))
                .contentShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .accessibilityLabel("\(target.title), \(target.kind.rawValue)")
            .accessibilityHint("Opens this node")
        } else {
            Text(id.rawValue)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(PanelTheme.tertiaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .help("Not present in the loaded graph — rebuild content artifacts")
        }
    }

    /// Score when there is one; kind colour otherwise. Structural nodes are never
    /// scored (§2.1), so they always show their kind.
    @ViewBuilder
    private func dot(for target: Node) -> some View {
        if let scores, target.kind.isContent {
            ZStack {
                Circle()
                    .fill(ScoreFormat.color(of: target.id, in: scores))
                    .frame(width: 6, height: 6)
                if scores.isFrontier(target.id) {
                    Circle()
                        .strokeBorder(Color(ScoreRamp.frontierAccent), lineWidth: 1)
                        .frame(width: 11, height: 11)
                }
            }
            .frame(width: 12, height: 12)
        } else {
            Circle()
                .fill(PanelTheme.color(for: target.kind))
                .frame(width: 6, height: 6)
                .frame(width: 12, height: 12)
        }
    }

    /// The kind is still the primary fact about a reference; the score joins it
    /// rather than replacing it, so the row stays readable with no user state.
    private func subtitle(for target: Node) -> String {
        guard let scores, target.kind.isContent else { return target.kind.rawValue }
        switch ScoreFormat.state(of: target.id, in: scores) {
        case .unlearned: return "\(target.kind.rawValue) · unlearned"
        case .frontier: return "\(target.kind.rawValue) · ready to learn"
        case .attempted: return "\(target.kind.rawValue) · missed, not yet learned"
        case let .learned(retrievability):
            return "\(target.kind.rawValue) · \(ScoreFormat.percent(retrievability))"
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
        if let index = document.index(of: id) {
            let target = document[index]
            Button {
                onSelect(id)
            } label: {
                MathTextView(
                    source: target.title, size: 12, color: PanelTheme.accent,
                    underline: isHovering)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
        } else {
            Text(id.rawValue)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(PanelTheme.tertiaryText)
        }
    }
}
