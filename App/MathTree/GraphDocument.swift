import Foundation
import GraphCore

/// The compiled artifacts `ContentBuild` produces, decoded once at launch.
///
/// The app consumes JSON only — YAML parsing lives in tooling (ground rule 3).
/// Decode is the dominant term in first paint (D3.2), so this stays a plain
/// `Codable` pass with no post-processing beyond building the index maps the
/// renderer needs.
struct GraphDocument: Sendable {
    struct RequiresEdge: Decodable, Sendable {
        /// The prerequisite.
        let from: NodeID
        /// The node that needs it.
        let to: NodeID
    }

    private struct GraphFile: Decodable {
        let version: Int
        let nodes: [Node]
        let requiresEdges: [RequiresEdge]
        let relatesEdges: [RelatesEdge]
        let dependents: [String: [NodeID]]
        let children: [String: [NodeID]]
    }

    private struct LayoutFile: Decodable {
        struct Position: Decodable {
            let id: NodeID
            let x: Double
            let y: Double
        }
        let version: Int
        let seed: UInt64
        let positions: [Position]
    }

    let nodes: [Node]
    let requiresEdges: [RequiresEdge]
    let relatesEdges: [RelatesEdge]
    /// Reverse of `requires`, precomputed by `ContentBuild`.
    let dependents: [NodeID: [NodeID]]
    /// `contains` children, primary + secondary.
    let children: [NodeID: [NodeID]]
    /// Parallel to `nodes`.
    let positions: [SIMD2<Float>]
    /// Node id → index into `nodes`/`positions`.
    let indexByID: [NodeID: Int]

    var count: Int { nodes.count }

    subscript(index: Int) -> Node { nodes[index] }

    func index(of id: NodeID) -> Int? { indexByID[id] }

    func prerequisites(of id: NodeID) -> [NodeID] { indexByID[id].map { nodes[$0].requires } ?? [] }

    func dependents(of id: NodeID) -> [NodeID] { dependents[id] ?? [] }
}

enum GraphDocumentError: Error, CustomStringConvertible {
    case artifactsNotFound(searched: [String])
    case versionMismatch(file: String, found: Int, expected: Int)
    case layoutMismatch(missing: NodeID)
    case decodeFailed(file: String, underlying: any Error)

    var description: String {
        switch self {
        case let .artifactsNotFound(searched):
            return """
                graph.json / layout.json not found. Searched:
                \(searched.map { "  " + $0 }.joined(separator: "\n"))
                Run: swift run ContentBuild build && swift run ContentBuild layout
                """
        case let .versionMismatch(file, found, expected):
            return "\(file) is format v\(found), this build expects v\(expected) — rebuild content"
        case let .layoutMismatch(missing):
            return "layout.json has no position for \(missing) — rebuild layout"
        case let .decodeFailed(file, underlying):
            return "\(file): \(underlying)"
        }
    }
}

extension GraphDocument {
    /// Search order: the app bundle's resources, then the directory holding the
    /// executable, then `build/content` under the working directory — so a
    /// bundled `MathTree.app` and a bare `swift run` both find artifacts.
    static func searchDirectories() -> [URL] {
        var directories: [URL] = []
        if let resources = Bundle.main.resourceURL { directories.append(resources) }
        directories.append(Bundle.main.bundleURL.deletingLastPathComponent())
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        directories.append(workingDirectory.appendingPathComponent("build/content"))
        directories.append(workingDirectory)
        return directories
    }

    static func load(from directories: [URL] = searchDirectories()) throws -> GraphDocument {
        let manager = FileManager.default
        guard
            let directory = directories.first(where: {
                manager.fileExists(atPath: $0.appendingPathComponent("graph.json").path)
                    && manager.fileExists(atPath: $0.appendingPathComponent("layout.json").path)
            })
        else {
            throw GraphDocumentError.artifactsNotFound(searched: directories.map(\.path))
        }

        let decoder = JSONDecoder()
        let graphURL = directory.appendingPathComponent("graph.json")
        let layoutURL = directory.appendingPathComponent("layout.json")

        let graph: GraphFile
        let layout: LayoutFile
        do {
            graph = try decoder.decode(GraphFile.self, from: Data(contentsOf: graphURL))
        } catch {
            throw GraphDocumentError.decodeFailed(file: "graph.json", underlying: error)
        }
        do {
            layout = try decoder.decode(LayoutFile.self, from: Data(contentsOf: layoutURL))
        } catch {
            throw GraphDocumentError.decodeFailed(file: "layout.json", underlying: error)
        }

        guard graph.version == ContentFormat.version else {
            throw GraphDocumentError.versionMismatch(
                file: "graph.json", found: graph.version, expected: ContentFormat.version)
        }
        guard layout.version == ContentFormat.version else {
            throw GraphDocumentError.versionMismatch(
                file: "layout.json", found: layout.version, expected: ContentFormat.version)
        }

        let indexByID = Dictionary(
            uniqueKeysWithValues: graph.nodes.enumerated().map { ($0.element.id, $0.offset) })

        // Coordinates are stored as doubles but rendered as floats; the map spans
        // a few thousand units, so float precision is ample.
        var positions = [SIMD2<Float>](repeating: .zero, count: graph.nodes.count)
        var placed = [Bool](repeating: false, count: graph.nodes.count)
        for position in layout.positions {
            guard let index = indexByID[position.id] else { continue }
            positions[index] = SIMD2(Float(position.x), Float(position.y))
            placed[index] = true
        }
        if let missing = placed.firstIndex(of: false) {
            throw GraphDocumentError.layoutMismatch(missing: graph.nodes[missing].id)
        }

        return GraphDocument(
            nodes: graph.nodes,
            requiresEdges: graph.requiresEdges,
            relatesEdges: graph.relatesEdges,
            dependents: Dictionary(
                uniqueKeysWithValues: graph.dependents.map { (NodeID($0.key), $0.value) }),
            children: Dictionary(
                uniqueKeysWithValues: graph.children.map { (NodeID($0.key), $0.value) }),
            positions: positions,
            indexByID: indexByID)
    }
}
