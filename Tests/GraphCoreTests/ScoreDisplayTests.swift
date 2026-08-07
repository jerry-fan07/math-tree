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

/// Perceived lightness, used only to assert the *direction* of §4.5's ramp —
/// "decayed nodes stay coloured but cool and dim" is a claim about brightness, so
/// the test has to measure brightness rather than eyeball a hex string.
private func luma(_ color: ScoreColor) -> Double {
    0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
}

@Suite("Colour ramp")
struct ScoreRampTests {
    /// §4.5's three states must be *distinguishable*, which is the whole reason
    /// the mapping exists: grey is not on the ramp at all.
    @Test func unlearnedIsNeutralGreyAndRecedes() {
        let grey = ScoreRamp.unlearned
        #expect(grey.red == grey.green || abs(grey.red - grey.blue) < 0.1, "grey is near-neutral")
        #expect(grey.alpha < 0.5, "§4.5: low opacity, visually recedes")

        // A badly decayed node is *more* present than an untouched one, because it
        // carries information the grey node does not.
        #expect(ScoreRamp.color(forRetrievability: 0.0).alpha > grey.alpha)
    }

    @Test func theRampRunsColdToWarmAcrossTheAnchors() {
        let decayed = ScoreRamp.color(forRetrievability: ScoreRamp.decayedAnchor)
        let mid = ScoreRamp.color(forRetrievability: 0.625)
        let solid = ScoreRamp.color(forRetrievability: ScoreRamp.masteredAnchor)

        // Deep blue: blue dominates. Teal: green and blue together, green ahead.
        // Green: green dominates and blue has fallen away.
        #expect(decayed.blue > decayed.green && decayed.blue > decayed.red)
        #expect(mid.green > mid.red && mid.blue > mid.red)
        #expect(solid.green > solid.blue && solid.green > solid.red)
        #expect(solid.blue < mid.blue, "blue drains as retrievability rises")

        // "cool and dim" → "solid": brightness is monotone along the ramp.
        #expect(luma(decayed) < luma(mid))
        #expect(luma(mid) < luma(solid))
    }

    @Test func theRampSaturatesOutsideTheAnchors() {
        #expect(
            ScoreRamp.color(forRetrievability: 0.05) == ScoreRamp.color(forRetrievability: 0.30))
        #expect(
            ScoreRamp.color(forRetrievability: 0.99) == ScoreRamp.color(forRetrievability: 0.95))
        #expect(ScoreRamp.rampT(forRetrievability: -5) == 0)
        #expect(ScoreRamp.rampT(forRetrievability: 5) == 1)
    }

    @Test func theRampIsMonotoneAndContinuous() {
        var previous = ScoreRamp.color(forRetrievability: 0)
        var steps = 0
        for i in 1...200 {
            let color = ScoreRamp.color(forRetrievability: Double(i) / 200)
            #expect(luma(color) >= luma(previous) - 1e-12, "never darkens as recall improves")
            // No visible banding: one step of 0.005 can never jump a whole 8-bit
            // level in more than one component by more than a hair.
            #expect(abs(color.green - previous.green) < 0.02)
            previous = color
            steps += 1
        }
        #expect(steps == 200)
    }

    /// The frontier accent must be unmistakable *as an accent* — it is the one
    /// thing on the map that is not a score, so it may not land on the ramp.
    @Test func theFrontierAccentIsNotAnyRampColour() {
        let accent = ScoreRamp.frontierAccent
        #expect(accent.red > accent.blue, "warm, where the whole ramp is cool")
        for i in 0...100 {
            let ramp = ScoreRamp.color(forRetrievability: Double(i) / 100)
            #expect(ramp.red < accent.red - 0.2)
        }
    }

    /// The read-out the display path actually calls: `nil` state is unlearned, and
    /// a colour follows the clock because retrievability is computed on read (§4.1).
    @Test func stateAndClockDetermineTheColour() {
        let fsrs = FSRS()
        #expect(ScoreRamp.color(for: nil, at: day(0), fsrs: fsrs) == ScoreRamp.unlearned)

        let memory = fsrs.review(nil, grade: .good, at: day(0))
        let fresh = ScoreRamp.color(for: memory, at: day(0), fsrs: fsrs)
        let stale = ScoreRamp.color(for: memory, at: day(60), fsrs: fsrs)
        #expect(fresh != stale, "§4.1: the colour decays continuously")
        #expect(luma(stale) < luma(fresh))
        #expect(stale != ScoreRamp.unlearned, "decayed is never mistaken for untouched")
    }

    @Test func hexIsStableAndFullyDetermined() {
        #expect(ScoreRamp.unlearned.hex == ScoreRamp.unlearned.hex)
        #expect(ScoreRamp.color(forRetrievability: 0.5).hex.count == 9)
        #expect(ScoreColor(red: 1, green: 0, blue: 0, alpha: 1).hex == "#FF0000FF")
        #expect(ScoreColor(red: 0, green: 0, blue: 0, alpha: 0).hex == "#00000000")
    }

    @Test func mixBlendsEndpointsForEdges() {
        let a = ScoreColor(red: 0, green: 0, blue: 0, alpha: 0)
        let b = ScoreColor(red: 1, green: 1, blue: 1, alpha: 1)
        #expect(ScoreColor.mix(a, b, 0) == a)
        #expect(ScoreColor.mix(a, b, 1) == b)
        #expect(ScoreColor.mix(a, b, 0.5).red == 0.5)
        #expect(ScoreColor.mix(a, b, 4) == b, "t is clamped")
    }
}

@Suite("Review queue")
struct ReviewQueueTests {
    let graph = KnowledgeGraph(nodes: Fixtures.clean)
    let fsrs = FSRS()
    let config = ScoringConfig()

    private func state(_ events: [EvidenceEvent]) -> ScoreState {
        ScoreFold.fold(events, graph: graph, config: config).state
    }

    @Test func nothingIsScheduledWithoutEvidence() {
        #expect(ReviewQueue.all(graph: graph, state: ScoreState(), at: day(0)).isEmpty)
        #expect(ReviewQueue.due(graph: graph, state: ScoreState(), at: day(0)).isEmpty)
    }

    /// The scheduler read-out is `nextDue`, not the τ threshold: a node becomes due
    /// when FSRS says so, and stays out of the queue until then.
    @Test func aNodeBecomesDueAtItsScheduledDate() {
        let state = state([event("foundations.real.sup-inf", .good, day: 0)])
        let scheduled = try! #require(
            ReviewQueue.all(graph: graph, state: state, at: day(0)).first)
        #expect(scheduled.id == "foundations.real.sup-inf")
        #expect(scheduled.due == fsrs.nextDue(after: scheduled.memory))

        #expect(ReviewQueue.due(graph: graph, state: state, at: day(0)).isEmpty)
        #expect(ReviewQueue.upcoming(graph: graph, state: state, at: day(0)).count == 1)

        let after = scheduled.due.addingTimeInterval(1)
        #expect(ReviewQueue.due(graph: graph, state: state, at: after).count == 1)
        #expect(ReviewQueue.upcoming(graph: graph, state: state, at: after).isEmpty)
    }

    @Test func theQueueIsMostOverdueFirstAndDeterministic() {
        let state = state([
            event("foundations.real.sup-inf", .easy, day: 0),
            event("foundations.real.completeness", .hard, day: 0),
            event("analysis.svc.def-limit", .good, day: 1),
        ])
        let queue = ReviewQueue.all(graph: graph, state: state, at: day(400))
        #expect(queue.count == 3)
        #expect(queue == queue.sorted())
        #expect(zip(queue, queue.dropFirst()).allSatisfy { $0.due <= $1.due })
        // Same inputs, same list — the sidebar may not reshuffle between launches.
        #expect(ReviewQueue.all(graph: graph, state: state, at: day(400)) == queue)
    }

    @Test func retrievabilityTravelsWithTheQueueEntry() {
        let state = state([event("analysis.svc.def-limit", .good, day: 0)])
        let entry = try! #require(ReviewQueue.all(graph: graph, state: state, at: day(30)).first)
        #expect(
            entry.retrievability == fsrs.retrievability(of: entry.memory, at: day(30)))
    }

    /// Structural nodes are not learnable (§2.1) and stale ids are log residue —
    /// neither belongs in a list the user is asked to act on.
    @Test func structuralAndUnknownIdsAreNotQueued() {
        var state = state([event("analysis.svc.def-limit", .good, day: 0)])
        let memory = MemoryState(stability: 5, difficulty: 5, lastReview: day(0))
        state.nodes["analysis.svc"] = memory
        state.nodes["gone.away.entirely"] = memory

        let queue = ReviewQueue.all(graph: graph, state: state, at: day(90))
        #expect(queue.map(\.id) == ["analysis.svc.def-limit"])
    }

    @Test func upcomingRespectsItsLimit() {
        let state = state([
            event("foundations.real.sup-inf", .easy, day: 0),
            event("foundations.real.completeness", .easy, day: 0),
            event("analysis.svc.def-limit", .easy, day: 0),
        ])
        #expect(ReviewQueue.upcoming(graph: graph, state: state, at: day(0), limit: 2).count == 2)
    }
}

@Suite("History trajectory")
struct TrajectoryTests {
    let graph = KnowledgeGraph(nodes: Fixtures.clean)
    let config = ScoringConfig()

    private func log() -> [EvidenceEvent] {
        [Grade.good, .hard, .good, .easy].enumerated().flatMap { index, grade in
            Propagation.expanded(
                event("analysis.svc.mvt", grade, day: Double(index) * 9), in: graph, config: config)
        }
    }

    /// The panel's sparkline and the map's colour must not be able to disagree.
    @Test func historyEndsWhereTheFoldDoes() {
        let events = log()
        let folded = ScoreFold.fold(events, graph: graph, config: config).state
        for id: NodeID in ["analysis.svc.mvt", "analysis.svc.rolle", "foundations.real.sup-inf"] {
            let points = ScoreFold.trajectory(of: .node(id), in: events, config: config)
            #expect(points.last?.state == folded[id], "\(id)")
        }
    }

    @Test func historyIsInChronologicalOrderAndOnlyThisTarget() {
        let points = ScoreFold.trajectory(of: .node("analysis.svc.mvt"), in: log(), config: config)
        #expect(points.count == 4, "four explicit reviews, no implicit ones — mvt is the origin")
        #expect(points.allSatisfy { $0.event.target == .node("analysis.svc.mvt") })
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.event.at <= $1.event.at })
    }

    @Test func anUntouchedTargetHasNoHistory() {
        #expect(ScoreFold.trajectory(of: .node("analysis.mvc"), in: log()).isEmpty)
        #expect(ScoreFold.trajectory(of: .node("nope.not.here"), in: log()).isEmpty)
    }

    /// Confidence-only events are deferred by the fold (D5.8); the history must
    /// defer them too, or the sparkline would show a step the colour never took.
    @Test func gradelessEventsAreSkipped() {
        let events = [
            event("analysis.svc.mvt", .good, day: 0),
            EvidenceEvent(
                at: day(1), target: .node("analysis.svc.mvt"), confidence: 0.6, source: .shifu),
        ]
        #expect(ScoreFold.trajectory(of: .node("analysis.svc.mvt"), in: events).count == 1)
    }
}

@Suite("Self-report")
struct SelfReportTests {
    let graph = KnowledgeGraph(nodes: Fixtures.clean)

    /// The rule that keeps the frontier honest: no self-report writes `again`,
    /// because state on an unlearned node silently ejects it from the frontier.
    @Test func noConfidenceLevelMapsToAgain() {
        #expect(SelfReportConfidence.allCases.allSatisfy { $0.grade.isPass })
        #expect(!SelfReportConfidence.allCases.map(\.grade).contains(.again))
    }

    @Test func confidenceOrdersTheThreePassingGrades() {
        #expect(SelfReportConfidence.shaky.grade == .hard)
        #expect(SelfReportConfidence.solid.grade == .good)
        #expect(SelfReportConfidence.fluent.grade == .easy)
        #expect(Set(SelfReportConfidence.allCases.map(\.grade)).count == 3)
    }

    @Test func theEventCarriesTheSelfReportSource() {
        let now = day(3)
        let report = SelfReportConfidence.solid.event(on: "analysis.svc.mvt", at: now)
        #expect(report.source == .selfReport)
        #expect(report.target == .node("analysis.svc.mvt"))
        #expect(report.grade == .good)
        #expect(report.at == now)
        #expect(report.confidence == nil, "a confidence *grade*, not §5.3's inferred confidence")
    }

    /// A self-report is ordinary evidence: it propagates exactly like a test does,
    /// which is what makes it a usable stand-in until problems exist (§5.2).
    @Test func aSelfReportPropagatesLikeAnyOtherExplicitReview() {
        let report = SelfReportConfidence.fluent.event(on: "analysis.svc.mvt", at: day(0))
        let expanded = Propagation.expanded(report, in: graph)
        #expect(expanded.count > 1)
        #expect(expanded.filter { $0.source == .implicit }.allSatisfy { $0.origin == "analysis.svc.mvt" })

        let state = ScoreFold.fold(expanded, graph: graph).state
        #expect(state["analysis.svc.mvt"] != nil)
        #expect(state["analysis.svc.rolle"] != nil, "an ancestor was boosted")
    }
}
