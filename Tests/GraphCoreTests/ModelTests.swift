import Foundation
import Testing

@testable import GraphCore

@Suite("Model types")
struct ModelTests {
    @Test func contentFormatVersionIsSet() {
        #expect(ContentFormat.version == 1)
    }

    @Test func nodeIDEncodesAsABareString() throws {
        let encoded = try JSONEncoder().encode(["a": NodeID("analysis.svc")])
        #expect(String(decoding: encoded, as: UTF8.self) == #"{"a":"analysis.svc"}"#)

        let decoded = try JSONDecoder().decode([String: NodeID].self, from: encoded)
        #expect(decoded["a"] == "analysis.svc")
    }

    @Test func nodeIDExposesItsParentPrefix() {
        #expect(NodeID("analysis.svc.ftc-2").parentPrefix == "analysis.svc")
        #expect(NodeID("analysis.svc").parentPrefix == "analysis")
        #expect(NodeID("analysis").parentPrefix == nil)
    }

    @Test func kindsSplitIntoStructuralAndContent() {
        #expect(NodeKind.branch.isStructural)
        #expect(NodeKind.subbranch.isStructural)
        for kind in NodeKind.allCases where !kind.isStructural {
            #expect(kind.idComponentCount == 3)
            #expect(kind.primaryParentKind == .subbranch)
        }
        #expect(NodeKind.branch.primaryParentKind == nil)
        #expect(NodeKind.subbranch.primaryParentKind == .branch)
        #expect(NodeKind.theorem.rawValue == "theorem")
    }

    @Test func structuralNodesDisplayAsMaximalProminence() {
        let hub = Node(id: "analysis", kind: .branch, prominence: .detail, title: "Analysis")
        // Authored value stays untouched; only the display read-out is lifted.
        #expect(hub.prominence == .detail)
        #expect(hub.displayProminence == .landmark)

        let lemma = Node(id: "a.b.c", kind: .lemma, prominence: .detail, title: "L", parent: "a.b")
        #expect(lemma.displayProminence == .detail)
    }

    @Test func relatesEdgesAreCanonicalAndUndirected() {
        let forward = RelatesEdge("analysis.svc.ftc-2", "analysis.mvc.leibniz-rule", note: "x")
        let reverse = RelatesEdge("analysis.mvc.leibniz-rule", "analysis.svc.ftc-2", note: "x")
        #expect(forward == reverse)
        #expect(reverse.key == "analysis.mvc.leibniz-rule ~ analysis.svc.ftc-2")
        #expect(reverse.endpoint(opposite: "analysis.svc.ftc-2") == "analysis.mvc.leibniz-rule")
    }

    @Test func nodeRoundTripsThroughJSONWithAuthoringKeys() throws {
        let node = Node(
            id: "analysis.svc.ftc-2",
            kind: .theorem,
            prominence: .landmark,
            title: "FTC, Part II",
            statement: "…",
            parent: "analysis.svc",
            alsoUnder: ["analysis.mvc"],
            requires: ["analysis.svc.ftc-1"],
            relates: [RelatesRef(id: "analysis.mvc.leibniz-rule", note: "n")],
            tags: ["calculus"]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(node), as: UTF8.self)
        #expect(json.contains(#""also_under":["analysis.mvc"]"#))
        #expect(json.contains(#""prominence":2"#))
        #expect(try JSONDecoder().decode(Node.self, from: Data(json.utf8)) == node)
    }

    @Test func absentOptionalFieldsDecodeToEmptyDefaults() throws {
        let json = #"{"id":"analysis","kind":"branch","title":"Analysis"}"#
        let node = try JSONDecoder().decode(Node.self, from: Data(json.utf8))
        #expect(node.prominence == .standard)
        #expect(node.parent == nil)
        #expect(node.alsoUnder.isEmpty)
        #expect(node.requires.isEmpty)
        #expect(node.relates.isEmpty)
        #expect(node.tags.isEmpty)
        // Empties encode away again, so graph.json stays minimal.
        let round = String(decoding: try JSONEncoder().encode(node), as: UTF8.self)
        #expect(!round.contains("also_under"))
        #expect(!round.contains("requires"))
    }
}
