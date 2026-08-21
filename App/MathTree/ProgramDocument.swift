import Foundation
import GraphCore

/// The compiled program (§6.6), decoded alongside `graph.json`.
///
/// Optional and non-fatal, exactly as the problem bank is (D8.8): a tree without
/// a program still runs, and the Program surface simply is not offered. The two
/// nothing-states stay distinct — *no artifact* (stale or unbuilt content) and
/// *an artifact with no program authored* (the math tree today) — and `build`
/// always writes the file so a stale artifact cannot answer the wrong one.
///
/// Not on the first-paint path, for D3.2's reason; it decodes after the scene
/// is standing.
struct ProgramDocument: Sendable {
    private struct ProgramFile: Decodable {
        let version: Int
        let parts: [ProgramSpine.Part]
        let units: [LessonUnit]
    }

    let program: Program
    /// Why there is no usable program, when there is none. `nil` when one loaded
    /// (even an empty one — that is a state, not a failure).
    let unavailable: String?
    /// Set only when an artifact *exists* and could not be used — the case the
    /// corpus self-check must fail loudly on rather than skip (a silently
    /// unchecked corpus is the outcome the check exists to prevent).
    let loadFailure: String?

    /// A program worth offering a surface for: authored, not merely present.
    var isAuthored: Bool { unavailable == nil && !program.isEmpty }

    static let missing = ProgramDocument(
        program: Program(spine: ProgramSpine(parts: [])),
        unavailable: "program.json not found — run: swift run ContentBuild build",
        loadFailure: nil)

    /// Never throws: every failure becomes a reason. Losing the program must not
    /// cost the user the map.
    static func load(from directories: [URL] = GraphDocument.searchDirectories()) -> ProgramDocument
    {
        let manager = FileManager.default
        guard
            let url = directories.map({ $0.appendingPathComponent("program.json") })
                .first(where: { manager.fileExists(atPath: $0.path) })
        else { return .missing }

        func failed(_ reason: String) -> ProgramDocument {
            ProgramDocument(
                program: Program(spine: ProgramSpine(parts: [])),
                unavailable: reason, loadFailure: reason)
        }

        do {
            let file = try JSONDecoder().decode(ProgramFile.self, from: Data(contentsOf: url))
            guard file.version == ContentFormat.version else {
                return failed(
                    "program.json is format v\(file.version), this build expects "
                        + "v\(ContentFormat.version) — rebuild content")
            }
            return ProgramDocument(
                program: Program(
                    spine: ProgramSpine(parts: file.parts), lessonUnits: file.units),
                unavailable: nil, loadFailure: nil)
        } catch {
            return failed("program.json: \(error)")
        }
    }
}
