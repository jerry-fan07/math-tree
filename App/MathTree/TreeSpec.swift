import Foundation

/// One knowledge tree the app can display: where its compiled artifacts live
/// and where its user state goes.
///
/// The math tree keeps its historical locations — artifacts at each search root
/// itself, `evidence.jsonl` in Application Support — so existing bundles, logs
/// and fixtures stay valid. Every other tree is namespaced: artifacts in a
/// subdirectory of the same roots, state in files of its own. Content ids may
/// collide across trees (both trees can own a `probability` branch), so the
/// evidence logs must never be shared — a review recorded on one tree folded
/// into the other would be silent corruption, which is exactly what per-tree
/// files preclude.
struct TreeSpec: Sendable {
    /// Artifact subdirectory under each search root; `nil` means the root.
    let subdirectory: String?
    /// Environment override for the evidence log (fixtures, determinism runs).
    let evidenceEnvironmentKey: String
    let evidenceFileName: String
    let placementEnvironmentKey: String
    let placementFileName: String
    /// §8.2's intake is a math-tree contract; no observer feeds other trees.
    let hasIntake: Bool

    static let math = TreeSpec(
        subdirectory: nil,
        evidenceEnvironmentKey: "MATHTREE_EVIDENCE_LOG",
        evidenceFileName: "evidence.jsonl",
        placementEnvironmentKey: "MATHTREE_PLACEMENT",
        placementFileName: "placement.json",
        hasIntake: true)

    static let quant = TreeSpec(
        subdirectory: "quant",
        evidenceEnvironmentKey: "MATHTREE_QUANT_EVIDENCE_LOG",
        evidenceFileName: "evidence-quant.jsonl",
        placementEnvironmentKey: "MATHTREE_QUANT_PLACEMENT",
        placementFileName: "placement-quant.json",
        hasIntake: false)
}
