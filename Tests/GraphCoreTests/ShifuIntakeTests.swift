import Foundation
import Testing

@testable import GraphCore

/// Phase 10's exit criterion, model side:
///
/// > simulated Shifu events flow through to visible score changes; malformed and
/// > unknown-id events are rejected with diagnostics, never crash, never corrupt
/// > the log.
///
/// "Never corrupt the log" is the load-bearing half and the reason these tests are
/// mostly about rejection: an intake that accepts everything is trivial to write
/// and would be indistinguishable from a correct one until the day Shifu shipped a
/// typo.
@Suite("Shifu intake")
struct ShifuIntakeTests {
    let graph = KnowledgeGraph(nodes: Fixtures.clean)
    let now = Date(timeIntervalSince1970: 1_785_000_000)

    private func document(_ json: String) -> Data { Data(json.utf8) }

    private func parse(_ json: String) -> ShifuIntake.Report {
        ShifuIntake.parse(document(json), graph: graph)
    }

    // MARK: - The happy path

    @Test func anObservationBecomesConfidenceWeightedShifuEvidence() {
        let report = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z",
               "nodes": ["analysis.svc.def-derivative"],
               "confidence": 0.45,
               "activity": "differentiating composites"}
            ]}
            """)

        #expect(!report.isMalformed)
        #expect(report.accepted == 1)
        #expect(report.rejected == 0)
        #expect(report.diagnostics.isEmpty)
        #expect(report.events.count == 1)

        let event = report.events[0]
        #expect(event.target == .node("analysis.svc.def-derivative"))
        #expect(event.source == .shifu)
        #expect(event.confidence == 0.45)
        #expect(event.note == "differentiating composites")
        // Shifu observes; it does not assess. The grade is the neutral one, exactly
        // as placement's inferred evidence uses (D8.4).
        #expect(event.grade == .good)
        #expect(event.weight == nil)
        #expect(event.depth == nil)
        #expect(event.origin == nil)
    }

    @Test func oneObservationFansOutToEveryTargetItNames() {
        let report = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z",
               "nodes": ["analysis.svc.def-derivative", "analysis.svc.mvt"],
               "edges": ["analysis.mvc.leibniz-rule ~ analysis.svc.mvt"],
               "confidence": 0.5}
            ]}
            """)

        #expect(report.accepted == 1)
        #expect(report.events.count == 3)
        #expect(report.events.allSatisfy { $0.confidence == 0.5 })
        #expect(
            report.events.map(\.target) == [
                .node("analysis.svc.def-derivative"),
                .node("analysis.svc.mvt"),
                .edge("analysis.mvc.leibniz-rule ~ analysis.svc.mvt"),
            ])
    }

    /// The compounding D8.2 found in multi-target grading, at a different door.
    @Test func aRepeatedTargetInOneObservationIsCountedOnce() {
        let report = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z",
               "nodes": ["analysis.svc.mvt", "analysis.svc.mvt"],
               "confidence": 0.5}
            ]}
            """)
        #expect(report.events.count == 1)
    }

    // MARK: - The payload cannot claim a source, and cannot grade

    @Test func aPayloadCannotForgeItsOwnSourceOrGrade() {
        let report = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z",
               "nodes": ["analysis.svc.mvt"],
               "confidence": 0.5,
               "source": "test",
               "grade": 4}
            ]}
            """)

        #expect(report.accepted == 1)
        let event = try? #require(report.events.first)
        // The transport stamps the source; a document that says otherwise is
        // accepted, and its claim is ignored and said out loud.
        #expect(event?.source == .shifu)
        #expect(event?.grade == .good)

        let ignored = report.diagnostics.filter { $0.severity == .warning }
        #expect(ignored.count == 2)
        #expect(ignored.allSatisfy { $0.event == 0 })
        #expect(ignored.contains { "\($0.reason)" .contains("source") })
        #expect(ignored.contains { "\($0.reason)".contains("grade") })
    }

    // MARK: - Rejection, with diagnostics

    @Test func anUnknownIdRejectsTheWholeObservation() {
        let report = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z",
               "nodes": ["analysis.svc.mvt", "analysis.svc.no-such-node"],
               "confidence": 0.5}
            ]}
            """)

        // Not partially honoured: an observation naming two nodes is one claim
        // about a moment of usage, and keeping half of it changes what it says.
        #expect(report.events.isEmpty)
        #expect(report.rejected == 1)
        #expect(report.diagnostics.count == 1)
        #expect(report.diagnostics[0].reason == .unknownNode("analysis.svc.no-such-node"))
        #expect(report.diagnostics[0].description.contains("event 0"))
    }

    @Test func aStructuralTargetIsRejected() {
        let report = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc"], "confidence": 0.5}
            ]}
            """)
        #expect(report.events.isEmpty)
        #expect(report.diagnostics[0].reason == .structuralTarget("analysis.svc"))
    }

    @Test func anUnknownEdgeKeyIsRejected() {
        let report = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z", "edges": ["a ~ b"], "confidence": 0.5}
            ]}
            """)
        #expect(report.events.isEmpty)
        #expect(report.diagnostics[0].reason == .unknownEdge("a ~ b"))
    }

    @Test(arguments: [
        (
            #"{"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"], "confidence": 0}"#,
            IntakeDiagnostic.Reason.confidenceOutOfRange(0)
        ),
        (
            #"{"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"], "confidence": 4}"#,
            IntakeDiagnostic.Reason.confidenceOutOfRange(4)
        ),
        (
            #"{"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"], "confidence": "high"}"#,
            IntakeDiagnostic.Reason.wrongType(field: "confidence", expected: "a number in (0, 1]")
        ),
        (
            #"{"at": "yesterday", "nodes": ["analysis.svc.mvt"], "confidence": 0.5}"#,
            IntakeDiagnostic.Reason.badTimestamp("yesterday")
        ),
        (
            #"{"nodes": ["analysis.svc.mvt"], "confidence": 0.5}"#,
            IntakeDiagnostic.Reason.missingField("at")
        ),
        (
            #"{"at": "2026-08-06T14:20:00Z", "confidence": 0.5}"#,
            IntakeDiagnostic.Reason.noTargets
        ),
        (
            #"{"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"]}"#,
            IntakeDiagnostic.Reason.missingField("confidence")
        ),
        (
            #"{"at": "2026-08-06T14:20:00Z", "nodes": "analysis.svc.mvt", "confidence": 0.5}"#,
            IntakeDiagnostic.Reason.wrongType(field: "nodes", expected: "an array of node ids")
        ),
        (#"["not an object"]"#, IntakeDiagnostic.Reason.eventNotAnObject),
    ])
    func aMalformedObservationIsRejectedAndNamed(json: String, expected: IntakeDiagnostic.Reason) {
        let report = parse(#"{"schema": 1, "events": [\#(json)]}"#)
        #expect(report.events.isEmpty)
        #expect(report.rejected == 1)
        #expect(report.diagnostics.map(\.reason) == [expected])
        #expect(!report.isMalformed, "one bad observation does not condemn the document")
    }

    /// A boolean is an `NSNumber` in `JSONSerialization`'s world, and `true` would
    /// otherwise sail through as confidence 1.0 — the strongest possible claim,
    /// from a field that was not a number at all.
    @Test func aBooleanIsNotAConfidence() {
        let report = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"], "confidence": true}
            ]}
            """)
        #expect(report.events.isEmpty)
        #expect(
            report.diagnostics.map(\.reason)
                == [.wrongType(field: "confidence", expected: "a number in (0, 1]")])
    }

    @Test func oneBadObservationDoesNotCostTheGoodOnesInTheSameDocument() {
        let report = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"], "confidence": 0.5},
              {"at": "2026-08-06T14:25:00Z", "nodes": ["nope"], "confidence": 0.5},
              {"at": "2026-08-06T14:30:00Z", "nodes": ["analysis.svc.rolle"], "confidence": 0.5}
            ]}
            """)
        #expect(report.accepted == 2)
        #expect(report.rejected == 1)
        #expect(report.events.map(\.target.key) == ["analysis.svc.mvt", "analysis.svc.rolle"])
        #expect(report.diagnostics.map(\.event) == [1])
    }

    // MARK: - Document-level rejection

    @Test func anUnsupportedSchemaRejectsTheDocumentWhole() {
        let report = parse(
            """
            {"schema": 2, "events": [
              {"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"], "confidence": 0.5}
            ]}
            """)
        #expect(report.isMalformed)
        #expect(report.events.isEmpty)
        #expect(report.accepted == 0 && report.rejected == 0, "nothing was even looked at")
        #expect(report.diagnostics.map(\.reason) == [.unsupportedSchema(found: 2, supported: 1)])
    }

    @Test(arguments: [
        (#"{"events": []}"#, IntakeDiagnostic.Reason.missingField("schema")),
        (#"{"schema": 1}"#, IntakeDiagnostic.Reason.missingField("events")),
        (#"{"schema": "1", "events": []}"#, .wrongType(field: "schema", expected: "an integer")),
        (#"{"schema": 1, "events": {}}"#, .wrongType(field: "events", expected: "an array")),
        (#"[]"#, IntakeDiagnostic.Reason.envelopeNotAnObject),
    ])
    func aMalformedDocumentIsRejectedWhole(json: String, expected: IntakeDiagnostic.Reason) {
        let report = parse(json)
        #expect(report.isMalformed)
        #expect(report.diagnostics.map(\.reason) == [expected])
    }

    @Test func truncatedJSONIsRejectedRatherThanThrown() {
        let report = parse(#"{"schema": 1, "events": [{"at": "2026-08-06T14:20:00Z", "confid"#)
        #expect(report.isMalformed)
        #expect(report.events.isEmpty)
        if case .notJSON = report.diagnostics[0].reason {} else {
            Issue.record("expected a notJSON diagnostic, got \(report.diagnostics[0].reason)")
        }
    }

    @Test func anEmptyDocumentIsAcceptedAndDoesNothing() {
        let report = parse(#"{"schema": 1, "events": []}"#)
        #expect(!report.isMalformed)
        #expect(report.events.isEmpty)
        #expect(report.diagnostics.isEmpty)
    }

    // MARK: - What it does to a score

    /// The other half of the criterion: the events have to actually *move* a
    /// colour, and move it the way the inferred tier is supposed to.
    @Test func observedUsageLearnsANodeAtInferredStrength() {
        let observed = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"], "confidence": 0.4}
            ]}
            """
        ).events

        let (state, defects) = ScoreFold.fold(observed, graph: graph)
        #expect(defects.isEmpty, "\(defects)")
        // §4.5: a node with a successful retrieval is *learned* — coloured, not grey.
        #expect(state.isLearned("analysis.svc.mvt"))

        // …and weaker than a real review, which is the whole of §5.3's "decays
        // faster until confirmed by a direct test" (D8.4: confidence *is* the
        // weight; there is no second decay model). Both at the same instant, so
        // the only difference between them is the tier.
        let at = observed[0].at
        let real = ScoreFold.fold(
            [
                EvidenceEvent(
                    at: at, target: .node("analysis.svc.mvt"), grade: .good, source: .test)
            ], graph: graph
        ).state

        let observedStability = try? #require(state["analysis.svc.mvt"]?.stability)
        let realStability = try? #require(real["analysis.svc.mvt"]?.stability)
        #expect((observedStability ?? 0) < (realStability ?? 0))

        let fsrs = FSRS()
        let later = at.addingTimeInterval(10 * 86_400)
        let observedR = state.retrievability(of: "analysis.svc.mvt", at: later, fsrs: fsrs) ?? 0
        let realR = real.retrievability(of: "analysis.svc.mvt", at: later, fsrs: fsrs) ?? 0
        #expect(observedR < realR, "observed usage must decay faster than a passed problem")
    }

    /// §4.3's "implicit reviews never lower a score", from the Shifu door: a
    /// mediocre observation must not undo a real review.
    @Test func anObservationNeverLowersAScore() {
        let reviewed = EvidenceEvent(
            at: Date(timeIntervalSince1970: 1_780_000_000), target: .node("analysis.svc.mvt"),
            grade: .easy, source: .test)
        let observation = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"], "confidence": 0.1}
            ]}
            """
        ).events

        let before = ScoreFold.fold([reviewed], graph: graph).state
        let after = ScoreFold.fold([reviewed] + observation, graph: graph).state
        #expect(
            (after["analysis.svc.mvt"]?.stability ?? 0)
                >= (before["analysis.svc.mvt"]?.stability ?? 0))
    }

    /// Shifu evidence lands on the nodes Shifu named, and nowhere else. §4.3's
    /// propagation is defined for a *graded* review, and §8.2 gives Shifu ownership
    /// of inference-to-node mapping: an observation that exercises prerequisites is
    /// an observation Shifu should have named them in.
    @Test func observedUsageDoesNotPropagateToPrerequisites() {
        let events = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"], "confidence": 0.9}
            ]}
            """
        ).events

        #expect(events.count == 1)
        let (state, _) = ScoreFold.fold(events, graph: graph)
        #expect(state.nodes.keys.map(\.rawValue) == ["analysis.svc.mvt"])
        for ancestor in graph.requiresAncestors(of: "analysis.svc.mvt") {
            #expect(state[ancestor] == nil, "\(ancestor) was boosted by an observation")
        }
    }

    /// D5.5's refit filter is "drop implicit events that carry no confidence, and
    /// re-expand the explicit ones". Shifu events must survive it: nothing can
    /// regenerate them.
    @Test func shifuEvidenceSurvivesTheRefitFilter() {
        let shifu = parse(
            """
            {"schema": 1, "events": [
              {"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"], "confidence": 0.4}
            ]}
            """
        ).events
        let propagated = EvidenceEvent(
            at: Date(timeIntervalSince1970: 1_785_000_000), target: .node("analysis.svc.rolle"),
            grade: .good, source: .implicit, origin: "analysis.svc.mvt", depth: 1, weight: 0.5)

        let kept = (shifu + [propagated]).filter { !($0.source == .implicit && $0.confidence == nil) }
        #expect(kept.map(\.source) == [.shifu])
    }
}

/// The transport half: a directory of documents in, evidence log out.
@Suite("Shifu intake directory")
struct IntakeDirectoryTests {
    let graph = KnowledgeGraph(nodes: Fixtures.clean)

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mathtree-intake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func drop(_ json: String, named name: String, into directory: IntakeDirectory) throws {
        try FileManager.default.createDirectory(
            at: directory.root, withIntermediateDirectories: true)
        try json.write(
            to: directory.root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private let good = """
        {"schema": 1, "events": [
          {"at": "2026-08-06T14:20:00Z", "nodes": ["analysis.svc.mvt"], "confidence": 0.4}
        ]}
        """
    private let bad = #"{"schema": 9, "events": []}"#

    @Test func aDrainFilesEachDocumentAndAppendsOnlyWhatItAccepted() throws {
        try withTemporaryDirectory { root in
            let directory = IntakeDirectory(root: root.appendingPathComponent("intake"))
            let log = EvidenceLog(url: root.appendingPathComponent("evidence.jsonl"))
            try drop(good, named: "001-good.json", into: directory)
            try drop(bad, named: "002-bad.json", into: directory)

            let result = try directory.drain(graph: graph, log: log)

            #expect(result.documents == 2)
            #expect(result.appended == 1)
            #expect(result.outcomes.map(\.file) == ["001-good.json", "002-bad.json"])
            #expect(result.outcomes.map(\.filedUnder) == ["accepted", "rejected"])
            #expect(try directory.pending().isEmpty, "the drop directory is emptied")

            let contents = try log.read()
            #expect(contents.events.count == 1)
            #expect(contents.events[0].source == .shifu)
            #expect(contents.defects.isEmpty)
            #expect(contents.header != nil, "a fresh log still gets its §4.2 header")
        }
    }

    @Test func everyFiledDocumentGetsAReceipt() throws {
        try withTemporaryDirectory { root in
            let directory = IntakeDirectory(root: root.appendingPathComponent("intake"))
            let log = EvidenceLog(url: root.appendingPathComponent("evidence.jsonl"))
            try drop(good, named: "001-good.json", into: directory)
            try drop(bad, named: "002-bad.json", into: directory)
            _ = try directory.drain(graph: graph, log: log)

            let accepted = directory.acceptedDirectory.appendingPathComponent("001-good.receipt.txt")
            let rejected = directory.rejectedDirectory.appendingPathComponent("002-bad.receipt.txt")
            #expect(FileManager.default.fileExists(atPath: accepted.path))
            #expect(FileManager.default.fileExists(atPath: rejected.path))
            #expect(try String(contentsOf: accepted, encoding: .utf8).contains("appended: 1"))
            #expect(try String(contentsOf: rejected, encoding: .utf8).contains("schema 9"))
        }
    }

    /// The failure the file/append/receipt ordering exists to make visible.
    @Test func anInterruptedIngestIsReportedRatherThanRepeated() throws {
        try withTemporaryDirectory { root in
            let directory = IntakeDirectory(root: root.appendingPathComponent("intake"))
            let log = EvidenceLog(url: root.appendingPathComponent("evidence.jsonl"))
            try FileManager.default.createDirectory(
                at: directory.acceptedDirectory, withIntermediateDirectories: true)
            // A document filed by a previous run that died before its receipt.
            try good.write(
                to: directory.acceptedDirectory.appendingPathComponent("001-good.json"),
                atomically: true, encoding: .utf8)
            try drop(good, named: "002-good.json", into: directory)

            let result = try directory.drain(graph: graph, log: log)
            #expect(result.interrupted == ["001-good.json"])
            #expect(result.appended == 1, "the interrupted document is not re-read")
        }
    }

    @Test func onlyJSONAtTheTopLevelIsConsumed() throws {
        try withTemporaryDirectory { root in
            let directory = IntakeDirectory(root: root.appendingPathComponent("intake"))
            let log = EvidenceLog(url: root.appendingPathComponent("evidence.jsonl"))
            // The rename-into-place convention: a `.part` file is mid-write and
            // must be invisible to a drain.
            try drop(good, named: "001-good.json.part", into: directory)
            try drop(good, named: "002-good.json", into: directory)

            let result = try directory.drain(graph: graph, log: log)
            #expect(result.outcomes.map(\.file) == ["002-good.json"])
            #expect(
                FileManager.default.fileExists(
                    atPath: directory.root.appendingPathComponent("001-good.json.part").path))
        }
    }

    @Test func anEmptyOrAbsentDirectoryIsNotAnError() throws {
        try withTemporaryDirectory { root in
            let directory = IntakeDirectory(root: root.appendingPathComponent("nothing-here"))
            let log = EvidenceLog(url: root.appendingPathComponent("evidence.jsonl"))
            let result = try directory.drain(graph: graph, log: log)
            #expect(result.documents == 0)
            #expect(result.appended == 0)
            #expect(!FileManager.default.fileExists(atPath: log.url.path), "no log was created")
        }
    }

    /// "Never corrupt the log": a run of documents that are all garbage must leave
    /// an existing log byte-identical.
    @Test func aDrainOfNothingUsableLeavesTheLogUntouched() throws {
        try withTemporaryDirectory { root in
            let directory = IntakeDirectory(root: root.appendingPathComponent("intake"))
            let url = root.appendingPathComponent("evidence.jsonl")
            let log = EvidenceLog(url: url)
            try log.append([
                EvidenceEvent(
                    at: Date(timeIntervalSince1970: 1_785_000_000),
                    target: .node("analysis.svc.mvt"), grade: .good, source: .test)
            ])
            let before = try Data(contentsOf: url)

            try drop(bad, named: "001.json", into: directory)
            try drop("not json at all", named: "002.json", into: directory)
            try drop(
                #"{"schema": 1, "events": [{"at": "2026-08-06T14:20:00Z", "nodes": ["nope"], "confidence": 0.5}]}"#,
                named: "003.json", into: directory)

            let result = try directory.drain(graph: graph, log: log)
            #expect(result.appended == 0)
            #expect(try Data(contentsOf: url) == before)
            #expect(result.outcomes.allSatisfy { $0.filedUnder == "rejected" })
        }
    }
}
