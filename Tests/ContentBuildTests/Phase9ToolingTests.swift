import Foundation
import GraphCore
import Testing

@testable import ContentBuild

private let toolingRepoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func loadToolingGraph() throws -> KnowledgeGraph {
    let content = try ContentLoader.load(
        root: toolingRepoRoot.appendingPathComponent("content"), relativeTo: toolingRepoRoot)
    return KnowledgeGraph(nodes: content.nodes)
}

/// A two-branch graph, small enough that every assertion below can be read off it.
private enum DiffFixture {
    static func node(
        _ id: NodeID, under parent: NodeID, statement: String = "x", requires: [NodeID] = [],
        relates: [RelatesRef] = []
    ) -> Node {
        Node(
            id: id, kind: .theorem, prominence: .standard, title: id.rawValue,
            statement: statement, parent: parent, requires: requires, relates: relates)
    }

    static let base: [Node] = [
        Node(id: "alpha", kind: .branch, title: "Alpha"),
        Node(id: "alpha.one", kind: .subbranch, title: "One", parent: "alpha"),
        node("alpha.one.a", under: "alpha.one"),
        node("alpha.one.b", under: "alpha.one", requires: ["alpha.one.a"]),
        Node(id: "beta", kind: .branch, title: "Beta"),
        Node(id: "beta.one", kind: .subbranch, title: "One", parent: "beta"),
        node("beta.one.a", under: "beta.one"),
    ]
}

/// The diff read-out. What it has to get right is the distinction git cannot draw:
/// *added* versus *changed*, and which of the new edges crossed a branch boundary —
/// the integration step §7.1 step 4 and Phase 9 both hang on.
@Suite("Baseline graph diff")
struct GraphDiffTests {

    private func baseline(_ nodes: [Node]) throws -> BaselineGraph {
        let data = try Artifacts.encoder().encode(GraphArtifact(KnowledgeGraph(nodes: nodes)))
        return try JSONDecoder().decode(BaselineGraph.self, from: data)
    }

    @Test func aGraphComparedWithItselfIsEmpty() throws {
        let graph = KnowledgeGraph(nodes: DiffFixture.base)
        let diff = GraphDiff.compare(baseline: try baseline(DiffFixture.base), with: graph)
        #expect(diff.isEmpty)
        #expect(GraphDiff.report(diff, graph: graph).contains("no change"))
    }

    @Test func theRealArtifactDecodesAsABaseline() throws {
        // The baseline type is a hand-written mirror of `GraphArtifact`, which is
        // encode-only. If the artifact grows a field the mirror does not have, this
        // is what says so.
        let graph = try loadToolingGraph()
        let data = try Artifacts.encoder().encode(GraphArtifact(graph))
        let decoded = try JSONDecoder().decode(BaselineGraph.self, from: data)
        #expect(decoded.nodes.count == graph.nodes.count)
        #expect(decoded.relatesEdges.count == graph.relatesEdges.count)
        #expect(GraphDiff.compare(baseline: decoded, with: graph).isEmpty)
    }

    @Test func addedNodesAndEdgesAreReported() throws {
        let before = try baseline(DiffFixture.base)
        var nodes = DiffFixture.base
        nodes.append(DiffFixture.node("alpha.one.c", under: "alpha.one", requires: ["alpha.one.b"]))

        let diff = GraphDiff.compare(baseline: before, with: KnowledgeGraph(nodes: nodes))
        #expect(diff.addedNodes == ["alpha.one.c"])
        #expect(diff.removedNodes.isEmpty)
        #expect(diff.changedNodes.isEmpty)
        #expect(diff.addedRequires.map(\.to) == ["alpha.one.c"])
        #expect(diff.touched == ["alpha.one.c"])
    }

    /// A node whose file did not change can still change — an edited statement has
    /// to reach the reviewer as something other than noise.
    @Test func anEditedNodeIsChangedNotAdded() throws {
        let before = try baseline(DiffFixture.base)
        let nodes = DiffFixture.base.map { node in
            node.id == "alpha.one.b"
                ? DiffFixture.node(
                    "alpha.one.b", under: "alpha.one", statement: "rewritten",
                    requires: ["alpha.one.a"])
                : node
        }
        let diff = GraphDiff.compare(baseline: before, with: KnowledgeGraph(nodes: nodes))
        #expect(diff.changedNodes == ["alpha.one.b"])
        #expect(diff.addedNodes.isEmpty)
        #expect(diff.addedRequires.isEmpty)
    }

    @Test func removalsAreReported() throws {
        let before = try baseline(DiffFixture.base)
        let nodes = DiffFixture.base.filter { $0.id != "alpha.one.b" }
        let diff = GraphDiff.compare(baseline: before, with: KnowledgeGraph(nodes: nodes))
        #expect(diff.removedNodes == ["alpha.one.b"])
        #expect(diff.removedRequires.map { "\($0.from) → \($0.to)" } == ["alpha.one.a → alpha.one.b"])
    }

    @Test func crossBranchEdgesAreCountedSeparately() throws {
        let before = try baseline(DiffFixture.base)
        let nodes = DiffFixture.base.map { node in
            node.id == "beta.one.a"
                ? DiffFixture.node("beta.one.a", under: "beta.one", requires: ["alpha.one.b"])
                : node
        }
        let graph = KnowledgeGraph(nodes: nodes)
        let report = GraphDiff.report(
            GraphDiff.compare(baseline: before, with: graph), graph: graph)
        #expect(report.contains("alpha → beta: 1"))
    }

    @Test func anEdgeThatStayedInsideOneBranchSaysSo() throws {
        let before = try baseline(DiffFixture.base)
        var nodes = DiffFixture.base
        nodes.append(DiffFixture.node("alpha.one.c", under: "alpha.one", requires: ["alpha.one.a"]))
        let graph = KnowledgeGraph(nodes: nodes)
        let report = GraphDiff.report(
            GraphDiff.compare(baseline: before, with: graph), graph: graph)
        #expect(report.contains("cross-branch requires added (0)"))
    }

    @Test func relatesEdgesAreDiffedByKey() throws {
        let before = try baseline(DiffFixture.base)
        let nodes = DiffFixture.base.map { node in
            node.id == "beta.one.a"
                ? DiffFixture.node(
                    "beta.one.a", under: "beta.one",
                    relates: [
                        RelatesRef(id: "alpha.one.a", note: "the same construction, twice over")
                    ])
                : node
        }
        let diff = GraphDiff.compare(baseline: before, with: KnowledgeGraph(nodes: nodes))
        #expect(diff.addedRelates == ["alpha.one.a ~ beta.one.a"])
    }
}
