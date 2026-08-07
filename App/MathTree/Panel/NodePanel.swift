import GraphCore
import SwiftUI

/// Detail panel for the selected node (§6.1: "clicking opens the node panel").
///
/// Phase 4 scope is title, kind badge, statement with math rendering, summary,
/// and navigable prerequisite/dependent links. Score, history sparkline and
/// next-due date arrive in Phase 6 — this phase is explicitly "minus scores".
struct NodePanel: View {
    let node: Node
    let document: GraphDocument
    /// Navigate to another node (prerequisite/dependent links, `relates`).
    var onSelect: (NodeID) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(node.title).font(.title3)
            Text(node.kind.rawValue).font(.caption).foregroundStyle(.secondary)
            if let statement = node.statement {
                Text(statement).font(.body)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
