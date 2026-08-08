import Foundation
import GraphCore

/// Diff-aware validation output, for review (Phase 9's tooling task).
///
/// At 27 nodes a reviewer reads the whole diff; at ten times that they read a
/// branch at a time, and the question that actually matters stops being "what
/// changed in this file" — git answers that — and becomes "what did this change do
/// to the *graph*". A subbranch landing in one file can silently re-parent a node
/// across the corpus, and a prerequisite added over here can make an existing edge
/// over there transitively redundant. Those are graph facts, and this is what
/// reports them.
///
/// The baseline is a previously built `graph.json`, not a git ref: the comparison
/// is between two *compiled* graphs, which keeps it dependency-free (ground rule
/// 3, no shelling out to git) and makes it work identically in CI, in a worktree,
/// and against an artifact from a tag.
struct BaselineGraph: Decodable {
    struct RequiresEdge: Decodable, Hashable, Comparable {
        var from: NodeID
        var to: NodeID

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.from == rhs.from ? lhs.to < rhs.to : lhs.from < rhs.from
        }
    }

    var version: Int
    var nodes: [Node]
    var requiresEdges: [RequiresEdge]
    var relatesEdges: [RelatesEdge]
}

enum GraphDiff {
    struct Result {
        var baselineVersion = 0
        var addedNodes: [NodeID] = []
        var removedNodes: [NodeID] = []
        /// Same id, different content — the ones a reviewer has to re-read.
        var changedNodes: [NodeID] = []
        var addedRequires: [BaselineGraph.RequiresEdge] = []
        var removedRequires: [BaselineGraph.RequiresEdge] = []
        var addedRelates: [String] = []
        var removedRelates: [String] = []

        /// Added ∪ changed: the nodes this change is actually about.
        var touched: Set<NodeID> { Set(addedNodes).union(changedNodes) }

        var isEmpty: Bool {
            addedNodes.isEmpty && removedNodes.isEmpty && changedNodes.isEmpty
                && addedRequires.isEmpty && removedRequires.isEmpty && addedRelates.isEmpty
                && removedRelates.isEmpty
        }
    }

    static func load(_ url: URL) throws -> BaselineGraph {
        let decoder = JSONDecoder()
        return try decoder.decode(BaselineGraph.self, from: try Data(contentsOf: url))
    }

    static func compare(baseline: BaselineGraph, with graph: KnowledgeGraph) -> Result {
        var result = Result()
        result.baselineVersion = baseline.version

        let before = Dictionary(uniqueKeysWithValues: baseline.nodes.map { ($0.id, $0) })
        let after = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })

        result.addedNodes = after.keys.filter { before[$0] == nil }.sorted()
        result.removedNodes = before.keys.filter { after[$0] == nil }.sorted()
        result.changedNodes = after.keys
            .filter { id in before[id].map { $0 != after[id]! } ?? false }
            .sorted()

        let beforeRequires = Set(baseline.requiresEdges)
        let afterRequires = Set(
            graph.nodes.flatMap { node in
                node.requires.map { BaselineGraph.RequiresEdge(from: $0, to: node.id) }
            })
        result.addedRequires = afterRequires.subtracting(beforeRequires).sorted()
        result.removedRequires = beforeRequires.subtracting(afterRequires).sorted()

        let beforeRelates = Set(baseline.relatesEdges.map(\.key))
        let afterRelates = Set(graph.relatesEdges.map(\.key))
        result.addedRelates = afterRelates.subtracting(beforeRelates).sorted()
        result.removedRelates = beforeRelates.subtracting(afterRelates).sorted()

        return result
    }

    /// The review read-out. Counts first, then the ids, then — the part git cannot
    /// produce — which branch boundaries the new `requires` edges cross, because
    /// that is the integration step §7.1 step 4 and Phase 9 both hang on.
    static func report(_ result: Result, graph: KnowledgeGraph, limit: Int = 40) -> String {
        guard !result.isEmpty else { return "no change against the baseline graph" }

        var lines: [String] = []
        func section(_ title: String, _ ids: [String]) {
            guard !ids.isEmpty else { return }
            lines.append("\(title) (\(ids.count))")
            for id in ids.prefix(limit) { lines.append("    \(id)") }
            if ids.count > limit {
                lines.append("    … and \(ids.count - limit) more (raise --diff-limit to see them)")
            }
        }

        section("nodes added", result.addedNodes.map(\.rawValue))
        section("nodes removed", result.removedNodes.map(\.rawValue))
        section("nodes changed", result.changedNodes.map(\.rawValue))
        section(
            "requires added", result.addedRequires.map { "\($0.from) → \($0.to)" })
        section(
            "requires removed", result.removedRequires.map { "\($0.from) → \($0.to)" })
        section("relates added", result.addedRelates)
        section("relates removed", result.removedRelates)

        func branch(_ id: NodeID) -> String {
            id.components.first.map(String.init) ?? id.rawValue
        }
        let crossing = result.addedRequires.filter { branch($0.from) != branch($0.to) }
        if !crossing.isEmpty {
            var pairs: [String: Int] = [:]
            for edge in crossing {
                pairs["\(branch(edge.from)) → \(branch(edge.to))", default: 0] += 1
            }
            lines.append("cross-branch requires added (\(crossing.count))")
            for (pair, count) in pairs.sorted(by: { $0.key < $1.key }) {
                lines.append("    \(pair): \(count)")
            }
        } else if !result.addedRequires.isEmpty {
            lines.append(
                "cross-branch requires added (0) — every new edge stayed inside one branch")
        }

        return lines.joined(separator: "\n")
    }
}
