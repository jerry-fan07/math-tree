import GraphCore
import SwiftUI

/// A navigable reference to another node — the panel's only navigation primitive.
///
/// Resolves the id against the document so the row can show a title and a kind colour. An
/// unresolvable id is rendered as the bare id and is *not* clickable: the validator forbids
/// dangling references (§3.3), but a panel that crashes or navigates into nothing when the
/// artifacts are stale is worse than one that says so.
struct NodeReferenceRow: View {
    let id: NodeID
    let document: GraphDocument
    /// The `relates` note (§2.3 — the connection is knowledge, so it is shown, not hidden
    /// behind a tooltip).
    var note: String?
    var onSelect: (NodeID) -> Void

    @State private var isHovering = false

    var body: some View {
        if let index = document.index(of: id) {
            let target = document[index]
            Button {
                onSelect(id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(PanelTheme.color(for: target.kind))
                        .frame(width: 6, height: 6)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    VStack(alignment: .leading, spacing: 3) {
                        MathTextView(
                            source: target.title, size: 12.5,
                            color: isHovering ? .white : PanelTheme.primaryText)
                        Text(target.kind.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(PanelTheme.tertiaryText)
                        if let note, !note.isEmpty {
                            MathTextView(source: note, size: 11.5, color: PanelTheme.secondaryText)
                                .padding(.top, 1)
                        }
                    }
                    Spacer(minLength: 0)
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
