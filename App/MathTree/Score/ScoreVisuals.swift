import Foundation
import GraphCore

/// One score snapshot in the shape the renderer consumes: arrays parallel to
/// `GraphDocument.nodes` and `GraphDocument.relatesEdges`, so applying it is an
/// index walk with no lookups and no allocation per instance.
///
/// It is a value type on purpose. The renderer must never reach into the store —
/// a repaint has to be reproducible from what it was handed, which is what lets
/// the probe print the same colours it drew.
///
/// It carries ramp *positions* rather than colours, and that is what makes the
/// snapshot appearance-independent: the same visuals paint the dark map and the
/// light one, because §4.5's model ("how well is this known") and the redesign's
/// display ("how bright / how dense, in this branch's hue") are now two separate
/// decisions. Switching appearance re-applies the snapshot; it never recomputes a
/// score.
struct ScoreVisuals {
    /// Position on §4.5's ramp per node — 0 at the decayed anchor, 1 at the
    /// mastered one. `nil` is *not learned*: never retrieved, or attempted and
    /// missed (D8.3), both of which stay grey. Structural nodes are `nil` too and
    /// the renderer ignores them, because it knows their tier and paints them from
    /// the taxonomy instead (§2.1: not learnable).
    var rampT: [Double?]
    /// §4.5's accent-ring set — unlearned, but every prerequisite is above τ.
    var isFrontier: [Bool]
    /// §4.4: a `relates` edge carries its own FSRS state, so it shows its own
    /// score — as intensity, which is the form §4.4 actually asks for. `nil` means
    /// the connection has never been exercised.
    var relatesRampT: [Double?]
    var evaluatedAt: Date
}

extension ScoreStore {
    /// Project the current snapshot onto the document's index space.
    func visuals(for document: GraphDocument) -> ScoreVisuals {
        var rampT = [Double?](repeating: nil, count: document.nodes.count)
        var isFrontier = [Bool](repeating: false, count: document.nodes.count)
        for (index, node) in document.nodes.enumerated() where node.kind.isContent {
            // `isLearned` and "has FSRS state" are different facts since D8.3, and
            // only the first one earns a colour.
            if let retrievability = retrievability(of: node.id), isLearned(node.id) {
                rampT[index] = ScoreRamp.rampT(forRetrievability: retrievability)
            }
            isFrontier[index] = frontier.contains(node.id)
        }
        return ScoreVisuals(
            rampT: rampT,
            isFrontier: isFrontier,
            relatesRampT: document.relatesEdges.map { edge in
                retrievability(ofEdge: edge.key).map(ScoreRamp.rampT(forRetrievability:))
            },
            evaluatedAt: evaluatedAt)
    }
}
