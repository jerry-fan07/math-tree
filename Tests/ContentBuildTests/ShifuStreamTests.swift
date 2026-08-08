import Foundation
import GraphCore
import Testing

@testable import ContentBuild

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func loadGraph() throws -> KnowledgeGraph {
    let content = try ContentLoader.load(
        root: repoRoot.appendingPathComponent("content"), relativeTo: repoRoot)
    return KnowledgeGraph(nodes: content.nodes)
}

/// §8.2's canned stream is committed content, and content rots: a node id it names
/// can be renamed by a later authoring pass and nothing else would notice.
@Suite("The canned Shifu stream")
struct ShifuStreamFixtureTests {

    private func documents() throws -> [(name: String, data: Data)] {
        let directory = repoRoot.appendingPathComponent(ShifuSim.cannedStream)
        return try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: []
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { (name: $0.lastPathComponent, data: try Data(contentsOf: $0)) }
    }

    @Test func theValidDocumentStillNamesNodesThisCorpusHas() throws {
        let graph = try loadGraph()
        let document = try #require(
            try documents().first { $0.name == "001-derivative-session.json" })
        let report = ShifuIntake.parse(document.data, graph: graph)

        #expect(!report.isMalformed)
        #expect(report.rejected == 0, "\(report.diagnostics.map(\.description))")
        #expect(report.accepted == 3)
        #expect(report.events.count == 5, "three observations, four nodes and one edge between them")
        #expect(report.events.contains { if case .edge = $0.target { true } else { false } })
        #expect(report.events.allSatisfy { $0.source == .shifu && $0.confidence != nil })
    }

    /// A test double whose bad input quietly stopped being bad would pass forever.
    @Test func theRejectionCasesStillGetRejected() throws {
        let graph = try loadGraph()
        let all = try documents()

        let mixed = try #require(all.first { $0.name == "002-partly-unusable.json" })
        let report = ShifuIntake.parse(mixed.data, graph: graph)
        #expect(report.accepted == 1)
        #expect(report.rejected == 6)
        #expect(report.events.count == 1)
        // Ignored-field notes: `source` and `grade` on the first observation, and
        // `operator` on the envelope.
        #expect(report.diagnostics.filter { $0.severity == .warning }.count == 3)

        for name in ["003-unsupported-schema.json", "004-truncated.json"] {
            let document = try #require(all.first { $0.name == name })
            let report = ShifuIntake.parse(document.data, graph: graph)
            #expect(report.isMalformed, "\(name) must be rejected whole")
            #expect(report.events.isEmpty)
        }
    }
}
