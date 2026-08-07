import Testing

@testable import GraphCore

/// `Dictionary` and `Set` iteration order is not stable, so anything that escapes into
/// an index or a diagnostic has to be sorted on the way out. These tests are the guard.
@Suite("Determinism")
struct DeterminismTests {
    static func shuffledClean(seed: Int) -> [Node] {
        // A tiny LCG rather than `shuffled()`: the failure has to be reproducible.
        var state = UInt64(truncatingIfNeeded: seed) &* 2_862_933_555_777_941_757 &+ 1
        var nodes = Fixtures.clean
        for index in stride(from: nodes.count - 1, to: 0, by: -1) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            nodes.swapAt(index, Int(state >> 33) % (index + 1))
        }
        return nodes
    }

    @Test func validatingTwiceGivesTheSameDiagnostics() {
        var broken = Fixtures.clean
        broken.append(Fixtures.content("analysis.svc.BAD", .theorem, .standard, "", under: "analysis.svc",
                                       requires: ["analysis.svc.nope", "analysis.svc.nope"]))
        broken.append(Fixtures.content("analysis.svc.also-bad", .theorem, .standard, "Bad",
                                       under: "analysis.svc",
                                       alsoUnder: ["analysis.svc.mvt"],
                                       relates: [RelatesRef(id: "analysis.svc.gone", note: "")]))
        #expect(GraphValidator.validate(nodes: broken) == GraphValidator.validate(nodes: broken))
        #expect(!GraphValidator.validate(nodes: broken).isEmpty)
    }

    @Test func authoringOrderDoesNotShowUpInTheOutput() {
        let reference = KnowledgeGraph(nodes: Fixtures.clean)
        for seed in 1...8 {
            let shuffled = KnowledgeGraph(nodes: Self.shuffledClean(seed: seed))
            #expect(shuffled.nodes == reference.nodes)
            #expect(shuffled.childrenByParent == reference.childrenByParent)
            #expect(shuffled.containedChildrenByParent == reference.containedChildrenByParent)
            #expect(shuffled.dependentsByPrerequisite == reference.dependentsByPrerequisite)
            #expect(shuffled.prerequisitesByNode == reference.prerequisitesByNode)
            #expect(shuffled.relatedByNode == reference.relatedByNode)
            #expect(shuffled.relatesEdges == reference.relatesEdges)
            #expect(shuffled.requiresAncestors(of: "analysis.svc.ftc-2")
                == reference.requiresAncestors(of: "analysis.svc.ftc-2"))
            #expect(GraphValidator.validate(shuffled) == GraphValidator.validate(reference))
        }
    }
}
