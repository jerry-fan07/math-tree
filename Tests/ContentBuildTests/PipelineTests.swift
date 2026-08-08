import Foundation
import GraphCore
import Testing

@testable import ContentBuild

/// The repo root, located from this file rather than the working directory so
/// the tests run the same under `swift test` and under Xcode.
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // ContentBuildTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repo root

private func withTemporaryContent(
    _ files: [String: String], _ body: (URL) throws -> Void
) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("content-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for (name, text) in files {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    try body(root)
}

@Suite("Authored content")
struct SeedContentTests {
    /// Phase 9's exit criterion, first clause: the full corpus validates clean.
    ///
    /// The node count is *not* pinned. It was, at 27, when the corpus was design.md
    /// Appendix A and a change to it was necessarily a change to Appendix A; now
    /// the corpus grows every time a subbranch is authored, and a pinned total
    /// would be a number someone edits without reading. What is pinned instead is
    /// the shape that must not drift: every node validates, every node has a source
    /// location, and Appendix A's own subgraph is untouched (below).
    @Test func theCorpusLoadsAndValidatesClean() throws {
        let content = try ContentLoader.load(
            root: repoRoot.appendingPathComponent("content"), relativeTo: repoRoot)
        #expect(content.nodes.count > 27, "the corpus only ever grows")
        #expect(content.extraLocations.isEmpty)

        let diagnostics = GraphValidator.validate(KnowledgeGraph(nodes: content.nodes))
        #expect(diagnostics.isEmpty, "content must validate clean: \(diagnostics)")
    }

    /// The outline is a hand-authored artifact (§7.1 step 1) and every subbranch in
    /// it is a namespace other files may point into, so it does not drift casually.
    @Test func theCanonicalOutlineIsIntact() throws {
        let content = try ContentLoader.load(
            root: repoRoot.appendingPathComponent("content"), relativeTo: repoRoot)
        let graph = KnowledgeGraph(nodes: content.nodes)
        #expect(graph.nodes.filter { $0.kind == .branch }.count == 12)
        #expect(graph.nodes.filter { $0.kind == .subbranch }.count == 82)
        for branch in graph.branches {
            #expect(!graph.containedChildren(of: branch).isEmpty, "\(branch) has no subbranch")
        }
    }

    @Test func everySeedNodeHasASourceLocation() throws {
        let content = try ContentLoader.load(
            root: repoRoot.appendingPathComponent("content"), relativeTo: repoRoot)
        for node in content.nodes {
            let location = content.locations[node.id]
            #expect(location != nil, "no source location for \(node.id)")
            // Paths are repo-relative so diagnostics are clickable in CI output.
            #expect(location?.file.hasPrefix("content/") == true)
            #expect((location?.line ?? 0) > 0)
        }
    }

    /// Appendix A is the spec's own worked example and the reference every later
    /// file was written against, so its *internal* edges are pinned even though the
    /// corpus total is not. Counting only the edges whose both ends lie in
    /// `analysis.svc` is what makes this survive scale-up: later branches may point
    /// *into* Appendix A freely, and that is integration, not drift.
    @Test func appendixAEdgeCountsAreIntact() throws {
        let content = try ContentLoader.load(
            root: repoRoot.appendingPathComponent("content"), relativeTo: repoRoot)
        let graph = KnowledgeGraph(nodes: content.nodes)

        let svc = graph.nodes.filter { $0.id.rawValue.hasPrefix("analysis.svc.") }
        #expect(svc.count == 18)
        #expect(
            svc.reduce(0) { total, node in
                total + node.requires.filter { $0.rawValue.hasPrefix("analysis.svc.") }.count
            } == 21)
        #expect(
            graph.relatesEdges.contains {
                $0.key == "analysis.mvc.leibniz-rule ~ analysis.svc.ftc-part-2"
            })

        // Appendix A's landmark: FTC II requires FTC I and the zero-derivative
        // corollary, and *not* def-limit, which is an ancestor by every path.
        let ftc2: NodeID = "analysis.svc.ftc-part-2"
        #expect(graph.prerequisites(of: ftc2) == ["analysis.svc.ftc-part-1", "analysis.svc.zero-deriv-const"])
        #expect(graph.requiresAncestors(of: ftc2).contains("analysis.svc.def-limit"))
    }
}

@Suite("Loader")
struct LoaderTests {
    @Test func diagnosticsCarryFileAndLine() throws {
        let yaml = """
            nodes:
              - id: alpha
                kind: branch
                title: "Alpha"
              - id: alpha.one
                kind: subbranch
                title: "One"
                parent: alpha
              - id: alpha.one.a
                kind: definition
                prominence: 1
                title: "A"
                statement: "a"
                parent: alpha.one
                requires:
                  - alpha.one.nonexistent
            """
        try withTemporaryContent(["alpha/one.yaml": yaml]) { root in
            let content = try ContentLoader.load(root: root, relativeTo: root)
            let diagnostics = GraphValidator.validate(KnowledgeGraph(nodes: content.nodes))

            let dangling = try #require(diagnostics.first { $0.rule == .danglingRequires })
            let location = try #require(content.locations[dangling.subject!])
            #expect(location.file == "alpha/one.yaml")
            // `- id: alpha.one.a` is on line 9 (1-based).
            #expect(location.line == 9, "got \(location.display)")
        }
    }

    @Test func filesAreVisitedInSortedOrder() throws {
        let node = { (id: String, parent: String) in
            """
            nodes:
              - id: \(id)
                kind: subbranch
                title: "\(id)"
                parent: \(parent)
            """
        }
        try withTemporaryContent([
            "z/one.yaml": node("z.one", "z"),
            "a/one.yaml": node("a.one", "a"),
            "m/one.yaml": node("m.one", "m"),
        ]) { root in
            let files = try ContentLoader.yamlFiles(in: root)
            #expect(files.map(\.lastPathComponent).count == 3)
            #expect(files.map(\.path) == files.map(\.path).sorted())
        }
    }

    @Test func aFileWithoutANodesListIsRejected() throws {
        try withTemporaryContent(["stray.yaml": "title: not a node file\n"]) { root in
            #expect(throws: (any Error).self) {
                _ = try ContentLoader.load(root: root, relativeTo: root)
            }
        }
    }

    /// An out-of-range prominence fails at decode rather than as a diagnostic,
    /// so the loader must surface it as a readable error, not a crash.
    @Test func outOfRangeProminenceIsAReadableError() throws {
        let yaml = """
            nodes:
              - id: alpha
                kind: branch
                title: "Alpha"
              - id: alpha.one
                kind: subbranch
                title: "One"
                parent: alpha
              - id: alpha.one.a
                kind: definition
                prominence: 7
                title: "A"
                parent: alpha.one
            """
        try withTemporaryContent(["alpha/one.yaml": yaml]) { root in
            do {
                _ = try ContentLoader.load(root: root, relativeTo: root)
                Issue.record("expected a decode failure")
            } catch let error as ContentLoadError {
                #expect("\(error)".contains("alpha/one.yaml"))
            }
        }
    }
}

@Suite("Determinism")
struct DeterminismTests {
    private func seedGraph() throws -> KnowledgeGraph {
        let content = try ContentLoader.load(
            root: repoRoot.appendingPathComponent("content"), relativeTo: repoRoot)
        return KnowledgeGraph(nodes: content.nodes)
    }

    /// Phase 2 exit criterion: "running `layout` twice on identical input yields
    /// byte-identical coordinates."
    @Test func layoutIsByteIdenticalAcrossRuns() throws {
        let graph = try seedGraph()
        let order = graph.nodes.map(\.id).sorted()
        let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        let springs = Artifacts.springs(for: graph, index: index)
        let clusters = Artifacts.clusters(for: graph, order: order)

        let first = Layout.compute(count: order.count, springs: springs, clusters: clusters)
        let second = Layout.compute(count: order.count, springs: springs, clusters: clusters)
        #expect(first.x == second.x)
        #expect(first.y == second.y)
        #expect(first.x.allSatisfy(\.isFinite) && first.y.allSatisfy(\.isFinite))
    }

    @Test func differentSeedsProduceDifferentMaps() throws {
        let graph = try seedGraph()
        let order = graph.nodes.map(\.id).sorted()
        let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        let springs = Artifacts.springs(for: graph, index: index)
        let clusters = Artifacts.clusters(for: graph, order: order)

        var other = LayoutParameters()
        other.seed &+= 1
        let a = Layout.compute(count: order.count, springs: springs, clusters: clusters)
        let b = Layout.compute(
            count: order.count, springs: springs, clusters: clusters, parameters: other)
        #expect(a.x != b.x)
    }

    /// `dependents` and `children` are dictionaries, and Swift's dictionary
    /// iteration order varies run to run — `.sortedKeys` is what saves this.
    @Test func graphArtifactEncodesToIdenticalBytes() throws {
        let graph = try seedGraph()
        let first = try Artifacts.encoder().encode(GraphArtifact(graph))
        let second = try Artifacts.encoder().encode(GraphArtifact(graph))
        #expect(first == second)
    }

    @Test func splitMix64IsReproducibleAndSeedSensitive() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        var c = SplitMix64(seed: 43)
        let fromA = (0..<8).map { _ in a.next() }
        #expect(fromA == (0..<8).map { _ in b.next() })
        #expect(fromA != (0..<8).map { _ in c.next() })

        var d = SplitMix64(seed: 1)
        #expect((0..<1000).allSatisfy { _ in (0.0..<1.0).contains(d.unit()) })
    }

    /// Cluster gravity is what makes branches read as separate galaxies (§6.1).
    @Test func clusterGravityPullsBranchesApart() throws {
        let graph = try seedGraph()
        let order = graph.nodes.map(\.id).sorted()
        let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        let springs = Artifacts.springs(for: graph, index: index)
        let clusters = Artifacts.clusters(for: graph, order: order)
        #expect(clusters.allSatisfy { $0 != nil }, "every seed node belongs to a branch")

        func separationRatio(clusterGravity: Double) -> Double {
            var parameters = LayoutParameters()
            parameters.clusterGravity = clusterGravity
            let result = Layout.compute(
                count: order.count, springs: springs, clusters: clusters, parameters: parameters)
            var intra = (total: 0.0, count: 0.0)
            var inter = (total: 0.0, count: 0.0)
            for i in 0..<order.count {
                for j in (i + 1)..<order.count {
                    let distance = hypot(result.x[i] - result.x[j], result.y[i] - result.y[j])
                    if clusters[i] == clusters[j] {
                        intra.total += distance
                        intra.count += 1
                    } else {
                        inter.total += distance
                        inter.count += 1
                    }
                }
            }
            return (inter.total / inter.count) / (intra.total / intra.count)
        }

        #expect(separationRatio(clusterGravity: 0.05) > separationRatio(clusterGravity: 0))
    }
}
