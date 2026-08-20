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

private func withTemporaryProgram(
    _ files: [String: String], _ body: (URL) throws -> Void
) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("program-\(UUID().uuidString)")
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

private let spineYAML = """
    parts:
      - title: "Groundwork"
        units:
          - g.one
      - title: "Applications"
        units:
          - g.two
    """

private let lessonsYAML = """
    unit: g.one
    opening: >
      Where everything starts.
    lessons:
      - node: g.one.r
        hook: >
          Why this matters.
        explanation: >
          The teaching, at length.

          A second paragraph survives the fold.
        worked: >
          An example worked to the number $2/3$.
        interview: >
          How it is asked.
        pitfalls: >
          The standard trap.
        recap: >
          One breath.
    """

@Suite("Program pipeline")
struct ProgramPipelineTests {
    @Test func aProgramRootLoadsWithLocations() throws {
        try withTemporaryProgram([
            "program.yaml": spineYAML,
            "lessons/g.one.yaml": lessonsYAML,
        ]) { root in
            let loaded = try ProgramLoader.load(root: root, relativeTo: root)
            #expect(loaded.exists)
            #expect(loaded.program.spine.units == ["g.one", "g.two"])
            #expect(loaded.program.spine.parts.map(\.title) == ["Groundwork", "Applications"])

            let lesson = try #require(loaded.program.lesson(for: "g.one.r"))
            #expect(lesson.hook.contains("Why this matters"))
            #expect(
                lesson.explanation.contains("\n"),
                "a folded scalar's blank line must survive as a paragraph break")
            #expect(lesson.worked?.contains("$2/3$") == true)
            #expect(loaded.program.opening(of: "g.one")?.contains("starts") == true)

            // Spine units point into program.yaml, lessons into their file.
            #expect(loaded.spineLocations[NodeID("g.one")]?.file == "program.yaml")
            #expect(loaded.lessonLocations[NodeID("g.one.r")]?.file == "lessons/g.one.yaml")
        }
    }

    @Test func aMissingProgramRootIsAStateNotAnError() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("no-such-program-\(UUID().uuidString)")
        let loaded = try ProgramLoader.load(root: missing, relativeTo: missing)
        #expect(!loaded.exists)
        #expect(loaded.program.isEmpty)
    }

    @Test func aMalformedSpineNamesTheFile() throws {
        try withTemporaryProgram(["program.yaml": "units:\n  - g.one\n"]) { root in
            #expect(throws: ContentLoadError.self) {
                _ = try ProgramLoader.load(root: root, relativeTo: root)
            }
        }
    }

    @Test func aMalformedLessonNamesTheFile() throws {
        try withTemporaryProgram([
            "program.yaml": spineYAML,
            "lessons/g.one.yaml": "unit: g.one\nlessons: []\n",  // no opening
        ]) { root in
            #expect(throws: ContentLoadError.self) {
                _ = try ProgramLoader.load(root: root, relativeTo: root)
            }
        }
    }

    /// Location routing: a lesson diagnostic sends the author into `lessons/`,
    /// a spine diagnostic into `program.yaml`.
    @Test func diagnosticsPointAtTheFileAnAuthorWouldOpen() throws {
        try withTemporaryProgram([
            "program.yaml": spineYAML,
            "lessons/g.one.yaml": lessonsYAML,
        ]) { root in
            let loaded = try ProgramLoader.load(root: root, relativeTo: root)
            let spineRule = Diagnostic(
                rule: .danglingProgramUnit, message: "", nodes: ["g.one"])
            #expect(loaded.location(of: spineRule)?.file == "program.yaml")
            let lessonRule = Diagnostic(
                rule: .lessonUnitIncomplete, message: "", nodes: ["g.one"])
            #expect(loaded.location(of: lessonRule)?.file == "lessons/g.one.yaml")
        }
    }

    @Test func theArtifactIsByteStable() throws {
        try withTemporaryProgram([
            "program.yaml": spineYAML,
            "lessons/g.one.yaml": lessonsYAML,
        ]) { root in
            let loaded = try ProgramLoader.load(root: root, relativeTo: root)
            let encoder = Artifacts.encoder()
            let first = try encoder.encode(ProgramArtifact(loaded.program))
            let second = try encoder.encode(ProgramArtifact(loaded.program))
            #expect(first == second)

            // The shape the app decodes: version, parts in authored order,
            // units sorted by id, absent sections absent.
            let json = try #require(
                try JSONSerialization.jsonObject(with: first) as? [String: Any])
            #expect(json["version"] as? Int == ContentFormat.version)
            let parts = try #require(json["parts"] as? [[String: Any]])
            #expect(parts.map { $0["title"] as? String } == ["Groundwork", "Applications"])
        }
    }
}

/// The live gate the generation batches run against: the real spine over the
/// real corpus. The moment a lessons file lands, `lessonUnitIncomplete` (and
/// friends) hold it to its whole unit — per file, which is what lets coverage
/// grow batch by batch while CI stays green.
@Suite("Quant program")
struct QuantProgramTests {
    @Test func theQuantSpineValidatesAgainstTheQuantCorpus() throws {
        let content = try ContentLoader.load(
            root: repoRoot.appendingPathComponent("content-quant"), relativeTo: repoRoot)
        let graph = KnowledgeGraph(nodes: content.nodes)
        let loaded = try ProgramLoader.load(
            root: repoRoot.appendingPathComponent("content-quant-program"), relativeTo: repoRoot)
        #expect(loaded.exists, "the quant tree ships with a program")

        let diagnostics = ProgramValidator.validate(loaded.program, against: graph)
        #expect(diagnostics.isEmpty, "the program must validate clean: \(diagnostics)")

        // 58 units in 9 parts — the outline's shape, pinned like the outline's.
        #expect(loaded.program.spine.units.count == 58)
        #expect(loaded.program.spine.parts.count == 9)
    }

    /// The spine order *is* the outline order, which is what made cross-file
    /// `requires` acyclic by construction — asserted directly so a reordering
    /// that happens to stay a linear extension still gets looked at.
    @Test func theSpineFollowsTheOutlineOrder() throws {
        let outline = try String(
            contentsOf: repoRoot.appendingPathComponent("content-quant/outline.md"),
            encoding: .utf8)
        var outlineOrder: [String] = []
        for line in outline.split(separator: "\n") {
            guard line.hasPrefix("## ") else { continue }
            // "## 4. quant-probability.foundations — Probability Foundations"
            let pieces = line.dropFirst(3).split(separator: " ")
            guard pieces.count >= 2 else { continue }
            outlineOrder.append(String(pieces[1]))
        }

        let loaded = try ProgramLoader.load(
            root: repoRoot.appendingPathComponent("content-quant-program"), relativeTo: repoRoot)
        #expect(loaded.program.spine.units.map(\.rawValue) == outlineOrder)
    }
}
