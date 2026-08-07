import Testing

@testable import GraphCore

/// Phase 1's exit criterion: ancestor queries cost the size of their answer, not the
/// size of the graph. A 10k-node chain is the worst case for that claim — precomputed
/// ancestor sets would be ~50M entries here.
@Suite("Scale")
struct ScaleTests {
    static let length = 10_000

    @Test(.timeLimit(.minutes(1)))
    func deepestAncestorQueryOnATenThousandNodeChain() {
        let clock = ContinuousClock()

        let nodes = Fixtures.chain(length: Self.length)
        var graph: KnowledgeGraph!
        let construction = clock.measure { graph = KnowledgeGraph(nodes: nodes) }

        let deepest = Fixtures.chainStep(Self.length - 1)
        var ancestors: [NodeID] = []
        let query = clock.measure { ancestors = graph.requiresAncestors(of: deepest) }

        var descendants: [NodeID] = []
        let reverse = clock.measure {
            descendants = graph.requiresDescendants(of: Fixtures.chainStep(0))
        }

        print("10k chain — construction \(construction), ancestors \(query), descendants \(reverse)")

        #expect(ancestors.count == Self.length - 1)
        #expect(ancestors.first == Fixtures.chainStep(0))
        #expect(ancestors.last == Fixtures.chainStep(Self.length - 2))
        #expect(descendants.count == Self.length - 1)

        #expect(construction < .seconds(5))
        #expect(query < .seconds(1))
        #expect(reverse < .seconds(1))
    }

    @Test func depthBoundedQueriesCostOnlyTheirWindow() {
        let graph = KnowledgeGraph(nodes: Fixtures.chain(length: Self.length))
        let deepest = Fixtures.chainStep(Self.length - 1)
        let clock = ContinuousClock()

        var window: [NodeID] = []
        let elapsed = clock.measure { window = graph.requiresAncestors(of: deepest, maxDepth: 3) }
        print("10k chain — D_max=3 window \(elapsed)")

        #expect(window == [
            Fixtures.chainStep(Self.length - 4),
            Fixtures.chainStep(Self.length - 3),
            Fixtures.chainStep(Self.length - 2),
        ])
        #expect(elapsed < .milliseconds(50))
    }

    @Test(.timeLimit(.minutes(1)))
    func validationHoldsUpAtTenThousandNodes() {
        let clock = ContinuousClock()
        let graph = KnowledgeGraph(nodes: Fixtures.chain(length: Self.length))
        var diagnostics: [Diagnostic] = []
        let elapsed = clock.measure { diagnostics = GraphValidator.validate(graph) }
        print("10k chain — validation \(elapsed)")

        #expect(diagnostics.isEmpty, "\(diagnostics.prefix(5).map(\.description))")
        #expect(elapsed < .seconds(10))
    }
}
