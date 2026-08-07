import Testing

@testable import GraphCore

@Suite("Derived indexes")
struct IndexTests {
    let graph = KnowledgeGraph(nodes: Fixtures.clean)

    @Test func nodesAreStoredInIDOrder() {
        #expect(graph.nodes.map(\.id) == graph.nodes.map(\.id).sorted())
        #expect(graph.nodes.count == Fixtures.clean.count)
        #expect(graph.branches == ["analysis", "foundations"])
    }

    @Test func childrenFollowThePrimaryParentTree() {
        #expect(graph.children(of: "analysis") == ["analysis.mvc", "analysis.svc"])
        #expect(graph.children(of: "analysis.mvc") == ["analysis.mvc.leibniz-rule"])
        #expect(graph.children(of: "analysis.svc").count == 18)
        // The cross-listed node is not a primary child of analysis.svc.
        #expect(!graph.children(of: "analysis.svc").contains("analysis.mvc.leibniz-rule"))
        #expect(graph.children(of: "analysis.svc.mvt").isEmpty)
    }

    @Test func containedChildrenAddTheCrossListings() {
        let contained = graph.containedChildren(of: "analysis.svc")
        #expect(contained.contains("analysis.mvc.leibniz-rule"))
        #expect(contained.count == graph.children(of: "analysis.svc").count + 1)
        #expect(contained == contained.sorted())
    }

    @Test func dependentsReverseTheRequiresEdges() {
        #expect(graph.dependents(of: "analysis.svc.def-limit")
            == ["analysis.svc.def-continuity", "analysis.svc.def-derivative"])
        #expect(graph.dependents(of: "foundations.real.sup-inf")
            == [
                "analysis.svc.def-limit",
                "analysis.svc.def-riemann-sum",
                "foundations.real.completeness",
            ])
        #expect(graph.dependents(of: "analysis.svc.u-sub").isEmpty)
        #expect(graph.prerequisites(of: "analysis.svc.ftc-2")
            == ["analysis.svc.ftc-1", "analysis.svc.zero-deriv-const"])
    }

    @Test func relatesAppearsOnBothEndpoints() {
        // Authored on ivt only.
        let authored = graph.related(to: "analysis.svc.ivt")
        #expect(authored.map(\.id) == ["analysis.svc.evt"])
        let mirrored = graph.related(to: "analysis.svc.evt")
        #expect(mirrored.map(\.id) == ["analysis.svc.ivt"])
        #expect(authored.first?.note == mirrored.first?.note)

        #expect(graph.related(to: "analysis.mvc.leibniz-rule").map(\.id) == ["analysis.svc.mvt"])
        #expect(graph.related(to: "analysis.svc.def-limit").isEmpty)
    }

    @Test func canonicalRelatesEdgesAreDedupedAndSorted() {
        #expect(graph.relatesEdges.count == 2)
        #expect(graph.relatesEdges.map(\.key) == [
            "analysis.mvc.leibniz-rule ~ analysis.svc.mvt",
            "analysis.svc.evt ~ analysis.svc.ivt",
        ])
    }

    @Test func danglingReferencesAreLeftOutOfTheIndexes() {
        let graph = KnowledgeGraph(nodes: [
            Fixtures.branch("a", "A"),
            Fixtures.subbranch("a.b", under: "a", "B"),
            Fixtures.content(
                "a.b.c", .theorem, .standard, "C", under: "a.b",
                requires: ["a.b.nope"],
                relates: [RelatesRef(id: "a.b.nope", note: "n")]
            ),
        ])
        #expect(graph.prerequisites(of: "a.b.c").isEmpty)
        #expect(graph.related(to: "a.b.c").isEmpty)
        #expect(graph.relatesEdges.isEmpty)
        #expect(graph.contains("a.b.nope") == false)
    }
}
