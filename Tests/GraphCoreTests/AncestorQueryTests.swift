import Testing

@testable import GraphCore

@Suite("Transitive requires queries")
struct AncestorQueryTests {
    @Test func diamondAncestorsAreDeduplicated() {
        let graph = KnowledgeGraph(nodes: Fixtures.diamond)
        #expect(graph.requiresAncestors(of: "d.s.d") == ["d.s.a", "d.s.b", "d.s.c"])
        #expect(graph.requiresAncestors(of: "d.s.a").isEmpty)
    }

    @Test func depthIsTheShortestHopCount() {
        let graph = KnowledgeGraph(nodes: Fixtures.diamond)
        let reached = graph.requiresAncestorsByDepth(of: "d.s.d")
        #expect(reached == [
            ReachedNode(id: "d.s.a", depth: 2),
            ReachedNode(id: "d.s.b", depth: 1),
            ReachedNode(id: "d.s.c", depth: 1),
        ])
        #expect(graph.requiresAncestors(of: "d.s.d", maxDepth: 1) == ["d.s.b", "d.s.c"])
        #expect(graph.requiresAncestors(of: "d.s.d", maxDepth: 0).isEmpty)
    }

    @Test func descendantsReverseTheQuery() {
        let graph = KnowledgeGraph(nodes: Fixtures.diamond)
        #expect(graph.requiresDescendants(of: "d.s.a") == ["d.s.b", "d.s.c", "d.s.d"])
        #expect(graph.requiresDescendants(of: "d.s.a", maxDepth: 1) == ["d.s.b", "d.s.c"])
        #expect(graph.requiresDescendants(of: "d.s.d").isEmpty)
    }

    @Test func ancestorsCrossSubbranchAndBranchBoundaries() {
        let graph = KnowledgeGraph(nodes: Fixtures.clean)
        // Hand-checked against Appendix A's edge list.
        #expect(graph.requiresAncestors(of: "analysis.svc.ftc-2") == [
            "analysis.svc.cont-integrable",
            "analysis.svc.def-antiderivative",
            "analysis.svc.def-continuity",
            "analysis.svc.def-derivative",
            "analysis.svc.def-limit",
            "analysis.svc.def-riemann-integral",
            "analysis.svc.def-riemann-sum",
            "analysis.svc.diff-implies-cont",
            "analysis.svc.evt",
            "analysis.svc.ftc-1",
            "analysis.svc.mvt",
            "analysis.svc.rolle",
            "analysis.svc.zero-deriv-const",
            "foundations.real.completeness",
            "foundations.real.sup-inf",
        ])
        // Structural nodes are never prerequisites (§2.3).
        #expect(!graph.requiresAncestors(of: "analysis.svc.ftc-2").contains("analysis.svc"))
        #expect(graph.requiresAncestors(of: "analysis.svc") .isEmpty)
    }

    @Test func unknownNodesQuietlyReturnNothing() {
        let graph = KnowledgeGraph(nodes: Fixtures.diamond)
        #expect(graph.requiresAncestors(of: "d.s.missing").isEmpty)
        #expect(graph.requiresDescendants(of: "d.s.missing").isEmpty)
    }

    @Test func aCyclicGraphStillTerminates() {
        // Invalid content, but a query must never hang on it.
        let graph = KnowledgeGraph(nodes: [
            Fixtures.branch("c", "C"),
            Fixtures.subbranch("c.s", under: "c", "S"),
            Fixtures.content("c.s.a", .theorem, .standard, "A", under: "c.s", requires: ["c.s.b"]),
            Fixtures.content("c.s.b", .theorem, .standard, "B", under: "c.s", requires: ["c.s.a"]),
        ])
        // The start node is pre-marked visited, so it never reports itself.
        #expect(graph.requiresAncestors(of: "c.s.a") == ["c.s.b"])
        #expect(graph.requiresDescendants(of: "c.s.a") == ["c.s.b"])
    }
}
