import Foundation
import GraphCore

/// One score snapshot in the shape the renderer consumes: arrays parallel to
/// `GraphDocument.nodes` and `GraphDocument.relatesEdges`, so applying it is an
/// index walk with no lookups and no allocation per instance.
///
/// It is a value type on purpose. The renderer must never reach into the store —
/// a repaint has to be reproducible from what it was handed, which is what lets
/// the probe print the same colours it drew.
struct ScoreVisuals {
    /// Colour per node. `nil` where §4.5 does not apply: structural nodes are not
    /// learnable (§2.1), so they keep Phase 4's taxonomy hue and the branch
    /// galaxies stay legible on a map that is otherwise mostly grey.
    var nodeColor: [ScoreColor?]
    /// §4.5's accent-ring set — unlearned, but every prerequisite is above τ.
    var isFrontier: [Bool]
    /// §4.4: a `relates` edge carries its own FSRS state, so it shows its own
    /// score. `nil` means the connection has never been exercised, and the edge
    /// falls back to blending its endpoints.
    var relatesColor: [ScoreColor?]
    var evaluatedAt: Date
}

extension ScoreStore {
    /// Project the current snapshot onto the document's index space.
    func visuals(for document: GraphDocument) -> ScoreVisuals {
        var nodeColor = [ScoreColor?](repeating: nil, count: document.nodes.count)
        var isFrontier = [Bool](repeating: false, count: document.nodes.count)
        for (index, node) in document.nodes.enumerated() where node.kind.isContent {
            nodeColor[index] = color(of: node.id)
            isFrontier[index] = frontier.contains(node.id)
        }
        return ScoreVisuals(
            nodeColor: nodeColor,
            isFrontier: isFrontier,
            relatesColor: document.relatesEdges.map { edge in
                retrievability(ofEdge: edge.key).map(ScoreRamp.color(forRetrievability:))
            },
            evaluatedAt: evaluatedAt)
    }
}
