import Foundation
import Testing

@testable import GraphCore

private let epoch = Date(timeIntervalSince1970: 1_669_725_000)  // 2022-11-29T12:30:00Z
private func day(_ n: Double) -> Date { epoch.addingTimeInterval(n * 86_400) }

private func event(
    _ id: NodeID, _ grade: Grade, day n: Double, source: EvidenceSource = .test
) -> EvidenceEvent {
    EvidenceEvent(at: day(n), target: .node(id), grade: grade, source: source)
}

@Suite("Evidence log")
struct EvidenceLogTests {
    private func temporaryURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("evidence-\(UUID().uuidString)")
            .appendingPathComponent("evidence.jsonl")
    }

    @Test func appendsAHeaderOnceThenEvents() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = EvidenceLog(url: url)

        try log.append([event("a.b.one", .good, day: 0)])
        try log.append([event("a.b.two", .hard, day: 1)])

        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 3)

        let contents = try log.read()
        #expect(contents.defects.isEmpty)
        #expect(contents.events.count == 2)
        // §4.2: the algorithm version is recorded so a log written under one model
        // can be identified and replayed under another.
        #expect(contents.header?.algorithm == FSRSVersion.algorithm)
        #expect(contents.header?.oracle == FSRSVersion.oracle)
        #expect(contents.header?.parameters == FSRSParameters.fsrs6DefaultWeights)
    }

    @Test func roundTripsEveryField() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = EvidenceLog(url: url)

        let original = EvidenceEvent(
            at: day(3), target: .node("a.b.one"), grade: .easy, confidence: 0.4,
            source: .implicit, problem: "prob-0142", origin: "a.b.two", depth: 2, weight: 0.25)
        let edgeEvent = EvidenceEvent(
            at: day(4), target: .edge("a.b.one ~ a.b.two"), grade: .good, source: .test)

        try log.append([original, edgeEvent])
        let read = try log.read()
        #expect(read.events == [original, edgeEvent])
    }

    /// A half-written line from a crash must cost one event, not the history.
    @Test func skipsAndReportsCorruptLines() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let good = EvidenceLog.encoder()
        let header = String(data: try good.encode(EvidenceLogHeader()), encoding: .utf8)!
        let first = String(data: try good.encode(event("a.b.one", .good, day: 0)), encoding: .utf8)!
        let last = String(data: try good.encode(event("a.b.two", .hard, day: 1)), encoding: .utf8)!
        let text = [
            header,
            first,
            #"{"at":"2022-11-29T12:30:00.000Z","target":{"node":"a.b.x"},"sour"#,  // truncated
            "",
            "not json at all",
            #"{"at":"nonsense","target":{"node":"a.b.y"},"grade":3,"source":"test"}"#,
            #"{"at":"2022-11-30T12:30:00.000Z","target":{},"grade":3,"source":"test"}"#,
            last,
        ].joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)

        let contents = try EvidenceLog(url: url).read()
        #expect(contents.events.count == 2)
        #expect(contents.defects.count == 4)
        #expect(contents.header != nil)
        // Line numbers are 1-based and point at the actual bad line.
        #expect(contents.defects.map(\.line) == [3, 5, 6, 7])
    }

    @Test func aMissingHeaderStillYieldsTheHistory() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = EvidenceLog.encoder()
        let line = String(data: try encoder.encode(event("a.b.one", .good, day: 0)), encoding: .utf8)!
        try line.write(to: url, atomically: true, encoding: .utf8)

        let contents = try EvidenceLog(url: url).read()
        #expect(contents.events.count == 1)
        #expect(contents.header == nil)
        #expect(contents.defects.contains { $0.reason == .missingHeader })
    }

    @Test func readingAMissingLogIsEmptyNotAnError() throws {
        let contents = try EvidenceLog(url: temporaryURL()).read()
        #expect(contents.events.isEmpty && contents.defects.isEmpty && contents.header == nil)
    }

    @Test func defaultURLLivesUnderApplicationSupport() throws {
        let base = URL(fileURLWithPath: "/tmp/appsupport")
        let url = try EvidenceLog.defaultURL(applicationSupport: base)
        #expect(url.path == "/tmp/appsupport/MathTree/evidence.jsonl")
    }
}

@Suite("Propagation")
struct PropagationTests {
    // sup-inf → def-limit → def-continuity → diff-implies-cont, i.e. the seed
    // graph's prerequisite chain, so depths are hand-checkable.
    let graph = KnowledgeGraph(nodes: Fixtures.clean)
    let config = ScoringConfig()

    private func expand(
        _ id: NodeID, _ grade: Grade, exercised: [NodeID] = [], config: ScoringConfig? = nil
    ) -> [EvidenceEvent] {
        Propagation.expand(
            event(id, grade, day: 0), in: graph, exercised: exercised, config: config ?? self.config)
    }

    @Test func dampingIsGammaToTheDepth() {
        let implicit = expand("analysis.svc.mvt", .good)
        let weights = Dictionary(
            uniqueKeysWithValues: implicit.map { ($0.target.key, ($0.depth!, $0.weight!)) })

        // mvt requires rolle (1 hop); rolle requires diff-implies-cont and evt (2);
        // those require def-derivative/def-continuity (3). D_max = 3 stops there.
        #expect(weights["analysis.svc.rolle"]?.0 == 1)
        #expect(weights["analysis.svc.rolle"]?.1 == 0.5)
        #expect(weights["analysis.svc.evt"]?.0 == 2)
        #expect(weights["analysis.svc.evt"]?.1 == 0.25)
        #expect(weights["analysis.svc.def-continuity"]?.0 == 3)
        #expect(weights["analysis.svc.def-continuity"]?.1 == 0.125)
    }

    @Test func depthCapIsHonoured() {
        let implicit = expand("analysis.svc.mvt", .good)
        #expect(implicit.allSatisfy { $0.depth! <= config.maxPropagationDepth })
        // def-limit is 4 hops from mvt — beyond D_max, so absent.
        #expect(!implicit.contains { $0.target.key == "analysis.svc.def-limit" })

        var deeper = config
        deeper.maxPropagationDepth = 5
        #expect(expand("analysis.svc.mvt", .good, config: deeper)
            .contains { $0.target.key == "analysis.svc.def-limit" })
    }

    /// §4.3: shortest-path damping. `requiresAncestorsByDepth` is breadth-first,
    /// so a node reachable by a short and a long route takes the short one.
    @Test func diamondsTakeTheShortestPath() {
        // d requires {b, c}, both of which require a — so a is 2 hops by two routes.
        let graph = KnowledgeGraph(nodes: Fixtures.diamond)
        let implicit = Propagation.expand(event("d.s.d", .good, day: 0), in: graph, config: config)
        let apex = implicit.first { $0.target.key == "d.s.a" }
        #expect(apex?.depth == 2)
        #expect(apex?.weight == 0.25)
        // Reached once, not once per route.
        #expect(implicit.filter { $0.target.key == "d.s.a" }.count == 1)
        #expect(implicit.count == 3)
    }

    @Test func explicitlyExercisedNodesGetFullStrengthAtAnyDistance() {
        // def-limit is 4 hops away — past D_max — but a problem naming it as
        // exercised (§5.2) overrides distance entirely.
        let implicit = expand(
            "analysis.svc.mvt", .good, exercised: ["analysis.svc.def-limit"])
        let limit = implicit.first { $0.target.key == "analysis.svc.def-limit" }
        #expect(limit?.depth == 0)
        #expect(limit?.weight == 1.0)
    }

    @Test func failureDoesNotPropagate() {
        // §4.3: a failed review is evidence about the reviewed node; attribution to
        // prerequisites is ambiguous, so failure is a retest flag, not a penalty.
        #expect(expand("analysis.svc.mvt", .again).isEmpty)

        var propagating = config
        propagating.propagateOnFailure = true
        #expect(!expand("analysis.svc.mvt", .again, config: propagating).isEmpty)
    }

    @Test func implicitEventsNeverCascade() {
        let implicit = event("analysis.svc.mvt", .good, day: 0, source: .implicit)
        #expect(Propagation.expand(implicit, in: graph, config: config).isEmpty)
    }

    @Test func theOriginIsNotItsOwnImplicitTarget() {
        #expect(!expand("analysis.svc.mvt", .good).contains { $0.target.key == "analysis.svc.mvt" })
        #expect(
            !expand("analysis.svc.mvt", .good, exercised: ["analysis.svc.mvt"])
                .contains { $0.target.key == "analysis.svc.mvt" })
    }

    @Test func expansionIsDeterministic() {
        #expect(expand("analysis.svc.ftc-part-2", .good) == expand("analysis.svc.ftc-part-2", .good))
        let bundle = Propagation.expanded(
            event("analysis.svc.mvt", .good, day: 0), in: graph, config: config)
        #expect(bundle.count == expand("analysis.svc.mvt", .good).count + 1)
        #expect(bundle.contains { $0.source == .test && $0.target.key == "analysis.svc.mvt" })
        // Fold order is (timestamp, target, source, …). Sorting by target first is
        // what matters — different targets never interact — but where a node is
        // both reviewed directly and boosted at the same instant, the direct
        // review must land first.
        let sameTarget = ([event("analysis.svc.rolle", .good, day: 0)] + bundle)
            .sorted(by: EvidenceEvent.foldOrder)
            .filter { $0.target.key == "analysis.svc.rolle" }
        #expect(sameTarget.map(\.source) == [.test, .implicit])
    }

    @Test func unknownOriginsAndTargetsAreIgnored() {
        #expect(expand("no.such.node", .good).isEmpty)
        #expect(!expand("analysis.svc.mvt", .good, exercised: ["no.such.node"])
            .contains { $0.target.key == "no.such.node" })
    }
}

@Suite("Score fold")
struct ScoreFoldTests {
    let graph = KnowledgeGraph(nodes: Fixtures.clean)
    let config = ScoringConfig()
    let fsrs = FSRS()

    private func log() -> [EvidenceEvent] {
        var events: [EvidenceEvent] = []
        for (index, grade) in [Grade.good, .hard, .good, .easy].enumerated() {
            events += Propagation.expanded(
                event("analysis.svc.mvt", grade, day: Double(index) * 5),
                in: graph, config: config)
        }
        return events
    }

    /// Phase 5 exit criterion: replaying the same log twice yields identical scores.
    @Test func replayIsDeterministic() {
        let events = log()
        let first = ScoreFold.fold(events, graph: graph, config: config).state
        let second = ScoreFold.fold(events, graph: graph, config: config).state
        #expect(first.nodes == second.nodes)
        #expect(first.edges == second.edges)
        #expect(!first.nodes.isEmpty)
    }

    /// Phase 5 exit criterion: fold order-independence for same-timestamp events.
    /// FSRS updates do not commute, so this holds because the fold sorts — not
    /// because the maths is commutative.
    @Test func sameTimestampEventsFoldOrderIndependently() {
        var generator = SystemRandomNumberGenerator()
        let events = log()
        let reference = ScoreFold.fold(events, graph: graph, config: config).state
        for _ in 0..<50 {
            let shuffled = events.shuffled(using: &generator)
            let state = ScoreFold.fold(shuffled, graph: graph, config: config).state
            #expect(state.nodes == reference.nodes)
        }
    }

    @Test func explicitReviewsMatchRawFSRS() {
        let events = [
            event("analysis.svc.mvt", .good, day: 0),
            event("analysis.svc.mvt", .hard, day: 4),
        ]
        let state = ScoreFold.fold(events, graph: graph, config: config).state
        var expected = fsrs.review(nil, grade: .good, at: day(0))
        expected = fsrs.review(expected, grade: .hard, at: day(4))
        #expect(state[NodeID("analysis.svc.mvt")] == expected)
    }

    /// §4.3: implicit reviews never lower a score.
    @Test func implicitReviewsNeverLowerStability() {
        let base = MemoryState(stability: 100, difficulty: 5, lastReview: day(0))
        for grade in Grade.allCases {
            for weight in [0.0, 0.125, 0.5, 1.0] {
                let after = ScoreFold.applyImplicit(
                    grade: grade, weight: weight, at: day(30), to: base,
                    fsrs: fsrs, config: config)
                #expect(after.stability >= base.stability, "grade \(grade) weight \(weight)")
                // Difficulty is a property of the material, not of this retrieval.
                #expect(after.difficulty == base.difficulty)
            }
        }
    }

    @Test func implicitStrengthIsMonotoneInWeightAndBoundedByExplicit() {
        let base = MemoryState(stability: 10, difficulty: 5, lastReview: day(0))
        let explicit = fsrs.review(base, grade: .good, at: day(10))
        var previous = base.stability
        for weight in [0.0, 0.125, 0.25, 0.5, 1.0] {
            let after = ScoreFold.applyImplicit(
                grade: .good, weight: weight, at: day(10), to: base, fsrs: fsrs, config: config)
            #expect(after.stability >= previous)
            #expect(after.stability <= explicit.stability + 1e-9)
            previous = after.stability
        }
        // Full strength is exactly an explicit review's stability.
        let full = ScoreFold.applyImplicit(
            grade: .good, weight: 1.0, at: day(10), to: base, fsrs: fsrs, config: config)
        #expect(abs(full.stability - explicit.stability) < 1e-9)
    }

    @Test func implicitReviewOnAnUnseenNodeCreatesDampedState() {
        let after = ScoreFold.applyImplicit(
            grade: .good, weight: 0.25, at: day(0), to: nil, fsrs: fsrs, config: config)
        #expect(abs(after.stability - 0.25 * fsrs.initialStability(.good)) < 1e-12)
        #expect(after.difficulty == fsrs.initialDifficulty(.good))
    }

    @Test func theDecayClockPolicyIsHonoured() {
        let base = MemoryState(stability: 10, difficulty: 5, lastReview: day(0))
        var frozen = config
        frozen.implicitReviewsResetDecayClock = false
        #expect(
            ScoreFold.applyImplicit(
                grade: .good, weight: 0.5, at: day(10), to: base, fsrs: fsrs, config: frozen)
                .lastReview == base.lastReview)
        #expect(
            ScoreFold.applyImplicit(
                grade: .good, weight: 0.5, at: day(10), to: base, fsrs: fsrs, config: config)
                .lastReview == day(10))
    }

    /// A deep review must be visible on its ancestors — Phase 6 renders this.
    @Test func aDeepReviewBoostsItsAncestors() {
        let events = Propagation.expanded(
            event("analysis.svc.mvt", .good, day: 0), in: graph, config: config)
        let state = ScoreFold.fold(events, graph: graph, config: config).state
        #expect(state[NodeID("analysis.svc.rolle")] != nil)
        #expect(state[NodeID("analysis.svc.evt")] != nil)
        // Damping is visible: nearer ancestors end up stronger.
        let near = state[NodeID("analysis.svc.rolle")]!.stability
        let far = state[NodeID("analysis.svc.def-continuity")]!.stability
        #expect(near > far)
    }

    @Test func unknownTargetsAreReportedNotApplied() {
        let events = [
            event("no.such.node", .good, day: 0),
            EvidenceEvent(at: day(0), target: .edge("x ~ y"), grade: .good, source: .test),
            event("analysis.svc.mvt", .good, day: 0),
        ]
        let (state, defects) = ScoreFold.fold(events, graph: graph, config: config)
        #expect(state.nodes.count == 1)
        #expect(defects.count == 2)
        #expect(defects.allSatisfy { $0.reason == .unknownTarget })
    }

    @Test func confidenceOnlyEventsAreDeferredNotGuessed() {
        // §5.1 permits grade *or* confidence; the fold consumes grades. Inferred
        // evidence gets its semantics in Phase 8 (§5.3), so it is reported here
        // rather than silently interpreted as some default grade.
        let events = [
            EvidenceEvent(
                at: day(0), target: .node("analysis.svc.mvt"), confidence: 0.6, source: .shifu)
        ]
        let (state, defects) = ScoreFold.fold(events, graph: graph, config: config)
        #expect(state.nodes.isEmpty)
        #expect(defects.first?.reason == .noGrade)
    }

    @Test func relatesEdgesCarryTheirOwnState() {
        // §4.4: a user can know both endpoints but not the connection.
        let key = graph.relatesEdges.first!.key
        let events = [EvidenceEvent(at: day(0), target: .edge(key), grade: .good, source: .test)]
        let (state, defects) = ScoreFold.fold(events, graph: graph, config: config)
        #expect(defects.isEmpty)
        #expect(state.edges[key] != nil)
        #expect(state.retrievability(ofEdge: key, at: day(0), fsrs: fsrs) != nil)
    }

    @Test func foldingThroughTheLogFileMatchesFoldingInMemory() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fold-\(UUID().uuidString)")
            .appendingPathComponent("evidence.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let events = log()
        try EvidenceLog(url: url).append(events)
        let reread = try EvidenceLog(url: url).read()
        #expect(reread.defects.isEmpty)

        let direct = ScoreFold.fold(events, graph: graph, config: config).state
        let viaDisk = ScoreFold.fold(reread.events, graph: graph, config: config).state
        #expect(direct.nodes == viaDisk.nodes)
    }
}

@Suite("Frontier")
struct FrontierTests {
    let graph = KnowledgeGraph(nodes: Fixtures.clean)
    let fsrs = FSRS()
    var config = ScoringConfig()

    /// A node with no state is unlearned; a root is on the frontier vacuously.
    @Test func rootsAreOnTheFrontierOfAnEmptyState() {
        let frontier = Frontier.compute(graph: graph, state: ScoreState(), at: day(0))
        #expect(frontier.contains("foundations.real.sup-inf"))
        // Everything with an unmet prerequisite is not.
        #expect(!frontier.contains("analysis.svc.def-limit"))
        // Structural nodes are not learnable (§2.1).
        #expect(!frontier.contains("analysis"))
        #expect(!frontier.contains("analysis.svc"))
    }

    @Test func learningAPrerequisiteAdvancesTheFrontier() {
        let events = [event("foundations.real.sup-inf", .easy, day: 0)]
        let state = ScoreFold.fold(events, graph: graph, config: config).state

        let frontier = Frontier.compute(graph: graph, state: state, at: day(0), config: config)
        #expect(!frontier.contains("foundations.real.sup-inf"), "learned nodes leave the frontier")
        #expect(frontier.contains("analysis.svc.def-limit"))
        #expect(frontier.contains("foundations.real.completeness"))
        // Two hops out is still blocked — def-limit itself is unlearned.
        #expect(!frontier.contains("analysis.svc.def-continuity"))
    }

    @Test func aDecayedPrerequisiteWithdrawsTheFrontier() {
        let events = [event("foundations.real.sup-inf", .good, day: 0)]
        let state = ScoreFold.fold(events, graph: graph, config: config).state

        #expect(
            Frontier.compute(graph: graph, state: state, at: day(0), config: config)
                .contains("analysis.svc.def-limit"))
        // Far enough out, retrievability falls below τ and it is no longer
        // something you could learn next — it is something to review first.
        let later = day(400)
        let retrievability = state.retrievability(
            of: "foundations.real.sup-inf", at: later, fsrs: fsrs)!
        #expect(retrievability < config.masteryThreshold)
        #expect(
            !Frontier.compute(graph: graph, state: state, at: later, config: config)
                .contains("analysis.svc.def-limit"))
        #expect(
            Frontier.due(graph: graph, state: state, at: later, config: config)
                .contains("foundations.real.sup-inf"))
    }

    @Test func thresholdIsRespected() {
        let events = [event("foundations.real.sup-inf", .good, day: 0)]
        let state = ScoreFold.fold(events, graph: graph, config: config).state
        let at = day(2)
        let retrievability = state.retrievability(
            of: "foundations.real.sup-inf", at: at, fsrs: fsrs)!

        var strict = config
        strict.masteryThreshold = min(retrievability + 0.01, 0.999)
        var lax = config
        lax.masteryThreshold = max(retrievability - 0.01, 0.001)

        #expect(
            !Frontier.compute(graph: graph, state: state, at: at, config: strict)
                .contains("analysis.svc.def-limit"))
        #expect(
            Frontier.compute(graph: graph, state: state, at: at, config: lax)
                .contains("analysis.svc.def-limit"))
    }

    @Test func frontierIsSortedAndDeterministic() {
        let state = ScoreFold.fold(
            [event("foundations.real.sup-inf", .easy, day: 0)], graph: graph, config: config).state
        let first = Frontier.compute(graph: graph, state: state, at: day(0), config: config)
        #expect(first == first.sorted())
        #expect(first == Frontier.compute(graph: graph, state: state, at: day(0), config: config))
    }
}
