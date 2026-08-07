import Foundation
import GraphCore

/// The compiled problem bank (§5.2), decoded at launch alongside `graph.json`.
///
/// Deliberately **optional and non-fatal**. `problems/` is an optional source tree
/// and a corpus with no bank still runs — self-report remains the fallback
/// instrument for any node the bank cannot ask about (§5.4's "whenever possible").
/// So a missing artifact is a state, not an error, and the two states are kept
/// distinct: *no artifact compiled* and *an artifact with no problems* mean
/// different things to the UI, and `ContentBuild build` always writes the file
/// precisely so a stale one cannot answer the wrong question.
///
/// Not on the first-paint path. D3.2 makes JSON decode the dominant term in
/// launch, and the map must be interactive before anything assessment-related is
/// needed — so this decodes after the scene is up.
struct ProblemDocument: Sendable {
    private struct ProblemFile: Decodable {
        let version: Int
        let problems: [Problem]
    }

    let bank: ProblemBank
    /// Why there is no bank, when there is none. `nil` when one loaded.
    let unavailable: String?

    var isAvailable: Bool { unavailable == nil }

    static let missing = ProblemDocument(
        bank: ProblemBank(problems: []),
        unavailable: "problems.json not found — run: swift run ContentBuild build")

    /// Never throws: every failure becomes an `unavailable` reason the panel can
    /// show. Losing the bank must not cost the user the map.
    static func load(from directories: [URL] = GraphDocument.searchDirectories()) -> ProblemDocument
    {
        let manager = FileManager.default
        guard
            let url = directories.map({ $0.appendingPathComponent("problems.json") })
                .first(where: { manager.fileExists(atPath: $0.path) })
        else { return .missing }

        do {
            let file = try JSONDecoder().decode(ProblemFile.self, from: Data(contentsOf: url))
            guard file.version == ContentFormat.version else {
                return ProblemDocument(
                    bank: ProblemBank(problems: []),
                    unavailable:
                        "problems.json is format v\(file.version), this build expects "
                        + "v\(ContentFormat.version) — rebuild content")
            }
            return ProblemDocument(bank: ProblemBank(problems: file.problems), unavailable: nil)
        } catch {
            return ProblemDocument(
                bank: ProblemBank(problems: []), unavailable: "problems.json: \(error)")
        }
    }
}
