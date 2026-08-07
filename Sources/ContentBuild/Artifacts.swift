import Foundation
import GraphCore

/// The compiled content artifact the app consumes (§3.3). Layout ships beside
/// it in `layout.json` so the two can be regenerated independently.
///
/// Nothing here carries a timestamp or a build id: byte-stability is a Phase 2
/// exit criterion, and "when was this built" is git's job.
struct GraphArtifact: Encodable {
    struct RequiresEdge: Encodable, Comparable {
        /// The prerequisite.
        var from: NodeID
        /// The node that needs it.
        var to: NodeID

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.from == rhs.from ? lhs.to < rhs.to : lhs.from < rhs.from
        }
    }

    var version: Int
    var nodes: [Node]
    var requiresEdges: [RequiresEdge]
    var relatesEdges: [RelatesEdge]
    /// Reverse of `requires`, precomputed so the app doesn't rebuild it on load.
    var dependents: [String: [NodeID]]
    /// `contains` children, primary + secondary.
    var children: [String: [NodeID]]

    init(_ graph: KnowledgeGraph) {
        version = ContentFormat.version
        nodes = graph.nodes.sorted { $0.id < $1.id }
        requiresEdges = graph.nodes
            .flatMap { node in node.requires.map { RequiresEdge(from: $0, to: node.id) } }
            .sorted()
        relatesEdges = graph.relatesEdges.sorted()
        dependents = Dictionary(
            uniqueKeysWithValues: graph.dependentsByPrerequisite.map { ($0.key.rawValue, $0.value) })
        children = Dictionary(
            uniqueKeysWithValues: graph.containedChildrenByParent.map { ($0.key.rawValue, $0.value) })
    }
}

/// The compiled problem bank (§5.2), shipped beside `graph.json` so it can be
/// regenerated — and grow — without touching the content artifact. The app loads
/// it lazily: it is not on the first-paint path (D3.2 makes decode the dominant
/// term), and a corpus with no bank must still launch.
struct ProblemArtifact: Encodable {
    var version: Int
    var problems: [Problem]
    /// Reverse index: node id → the problems that target it, precomputed so the
    /// app doesn't rebuild it on load.
    var byTarget: [String: [ProblemID]]

    init(_ bank: ProblemBank) {
        version = ContentFormat.version
        problems = bank.problems
        byTarget = Dictionary(
            uniqueKeysWithValues: bank.problemsByTarget.map { ($0.key.rawValue, $0.value) })
    }
}

struct LayoutArtifact: Encodable {
    struct Position: Encodable {
        var id: NodeID
        var x: Double
        var y: Double
    }

    var version: Int
    var seed: UInt64
    var iterations: Int
    var positions: [Position]
}

enum Artifacts {
    /// `.sortedKeys` is load-bearing: Swift's `Dictionary` iteration order varies
    /// run to run, and `dependents`/`children` are dictionaries.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(value).write(to: url, options: .atomic)
    }

    /// Springs for the layout pass. `contains` pulls hardest — it is what makes
    /// branches cluster into the galaxies of §6.1 — then `requires`, then the
    /// soft `relates` edges.
    static func springs(for graph: KnowledgeGraph, index: [NodeID: Int]) -> [Spring] {
        var springs: [Spring] = []
        for node in graph.nodes {
            guard let to = index[node.id] else { continue }
            if let parent = node.parent, let from = index[parent] {
                springs.append(Spring(a: from, b: to, weight: 2.0))
            }
            for secondary in node.alsoUnder {
                if let from = index[secondary] {
                    springs.append(Spring(a: from, b: to, weight: 1.0))
                }
            }
            for prerequisite in node.requires {
                if let from = index[prerequisite] {
                    springs.append(Spring(a: from, b: to, weight: 1.0))
                }
            }
        }
        for edge in graph.relatesEdges {
            if let a = index[edge.a], let b = index[edge.b] {
                springs.append(Spring(a: a, b: b, weight: 0.4))
            }
        }
        return springs
    }

    /// Each node's root branch, used as its layout cluster.
    static func clusters(for graph: KnowledgeGraph, order: [NodeID]) -> [Int?] {
        let branchIndex = Dictionary(
            uniqueKeysWithValues: graph.branches.enumerated().map { ($0.element, $0.offset) })
        var cache: [NodeID: Int?] = [:]

        func branch(of id: NodeID) -> Int? {
            if let cached = cache[id] { return cached }
            var seen: Set<NodeID> = []
            var current = id
            var result: Int?
            while seen.insert(current).inserted {
                if let index = branchIndex[current] {
                    result = index
                    break
                }
                guard let parent = graph[current]?.parent else { break }
                current = parent
            }
            cache[id] = result
            return result
        }

        return order.map(branch)
    }
}
