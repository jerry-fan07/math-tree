import Foundation
import Testing

@testable import GraphCore

private let graph = KnowledgeGraph(nodes: Fixtures.clean)
private let now = Date(timeIntervalSince1970: 1_780_000_000)

private func problem(
    _ id: ProblemID,
    targets: [NodeID],
    exercises: [NodeID] = [],
    connects: [String] = [],
    difficulty: Problem.Difficulty = .standard
) -> Problem {
    Problem(
        id: id, kind: .work, statement: "statement", answer: "answer", rubric: ["criterion"],
        targets: targets, exercises: exercises, connects: connects, difficulty: difficulty)
}

@Suite("Problem bank")
struct ProblemBankTests {
    @Test func targetsAreIndexedButExercisedNodesAreNotProbeTargets() {
        let bank = ProblemBank(problems: [
            problem("p-mvt", targets: ["analysis.svc.mvt"], exercises: ["analysis.svc.rolle"])
        ])
        #expect(bank.problems(targeting: "analysis.svc.mvt").map(\.id) == ["p-mvt"])
        // A problem that merely drills Rolle in passing is not a *test of* Rolle:
        // probing it there would attribute a failure to the wrong node.
        #expect(bank.problems(targeting: "analysis.svc.rolle").isEmpty)
        #expect(bank.problemsByExercised["analysis.svc.rolle"] == ["p-mvt"])
    }

    @Test func problemsForANodeComeEasiestFirst() {
        let bank = ProblemBank(problems: [
            problem("p-hard", targets: ["analysis.svc.mvt"], difficulty: .demanding),
            problem("p-easy", targets: ["analysis.svc.mvt"], difficulty: .routine),
            problem("p-mid", targets: ["analysis.svc.mvt"], difficulty: .standard),
        ])
        #expect(bank.problems(targeting: "analysis.svc.mvt").map(\.id) == ["p-easy", "p-mid", "p-hard"])
    }

    @Test func bankLoadsDeterministicallyEvenWithDuplicateIDs() {
        let a = ProblemBank(problems: [
            problem("b", targets: ["analysis.svc.mvt"]),
            problem("a", targets: ["analysis.svc.mvt"]),
            problem("a", targets: ["analysis.svc.rolle"]),
        ])
        let b = ProblemBank(problems: [
            problem("a", targets: ["analysis.svc.mvt"]),
            problem("a", targets: ["analysis.svc.rolle"]),
            problem("b", targets: ["analysis.svc.mvt"]),
        ])
        #expect(a.problems.map(\.id) == b.problems.map(\.id))
        #expect(a.problemsByID["a"]?.targets == b.problemsByID["a"]?.targets)
    }

    @Test func problemRoundTripsThroughJSON() throws {
        let original = problem(
            "p-round", targets: ["analysis.svc.mvt"], exercises: ["analysis.svc.rolle"],
            connects: ["analysis.svc.mvt ~ analysis.mvc.leibniz-rule"])
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Problem.self, from: data) == original)
    }
}

@Suite("Problem validation")
struct ProblemValidationTests {
    private func diagnostics(_ problems: [Problem]) -> [Diagnostic] {
        ProblemValidator.validate(problems: problems, against: graph)
    }

    @Test func aWellFormedProblemIsClean() {
        let found = diagnostics([
            problem("svc-mvt-01", targets: ["analysis.svc.mvt"], exercises: ["analysis.svc.rolle"])
        ])
        #expect(found.isEmpty, "\(found)")
    }

    @Test func danglingAndStructuralTargetsAreRejected() {
        let found = diagnostics([
            problem("p-dangling", targets: ["analysis.svc.no-such-node"]),
            problem("p-structural", targets: ["analysis.svc"]),
        ])
        #expect(found.contains { $0.rule == .danglingProblemTarget })
        #expect(found.contains { $0.rule == .problemTargetNotContent })
    }

    /// §5.2 calls these "exercised *prerequisite* nodes". `u-sub` requires `mvt`,
    /// not the other way round, so this tag is inverted — the mistake §7.1 calls
    /// worse than a missing node, because it validates cleanly everywhere else.
    @Test func exercisingADependentRatherThanAPrerequisiteIsRejected() {
        let found = diagnostics([
            problem("p-inverted", targets: ["analysis.svc.mvt"], exercises: ["analysis.svc.u-sub"])
        ])
        #expect(found.contains { $0.rule == .problemExercisesNotPrerequisite })
    }

    @Test func aTargetCannotAlsoBeExercised() {
        let found = diagnostics([
            problem("p-both", targets: ["analysis.svc.mvt"], exercises: ["analysis.svc.mvt"])
        ])
        #expect(found.contains { $0.rule == .problemTargetAlsoExercised })
    }

    @Test func connectsMustNameARealEdgeAndTouchBothEnds() {
        let real = graph.relatesEdges.first { $0.key.contains("leibniz") }!.key
        let found = diagnostics([
            problem("p-nonedge", targets: ["analysis.svc.mvt"], connects: ["a ~ b"]),
            problem("p-untagged", targets: ["analysis.svc.mvt"], connects: [real]),
        ])
        #expect(found.contains { $0.rule == .danglingProblemConnects })
        #expect(found.contains { $0.rule == .problemConnectsUntaggedEndpoint })

        // Tagging both endpoints clears it.
        let clean = diagnostics([
            problem(
                "p-tagged", targets: ["analysis.svc.mvt", "analysis.mvc.leibniz-rule"],
                connects: [real])
        ])
        #expect(clean.isEmpty, "\(clean)")
    }

    @Test func aProblemWithoutARubricIsRejected() {
        let bare = Problem(
            id: "p-bare", kind: .work, statement: "s", answer: "a", rubric: [],
            targets: ["analysis.svc.mvt"])
        #expect(diagnostics([bare]).contains { $0.rule == .emptyProblemRubric })
    }

    @Test func diagnosticsSortContentBeforeProblems() {
        let content = Diagnostic(rule: .duplicateID, message: "m", nodes: ["z"])
        let bank = Diagnostic(rule: .duplicateProblemID, message: "m", nodes: [], problem: "a")
        #expect([bank, content].sorted() == [content, bank])
    }
}

@Suite("Grading (§5.2)")
struct GradingTests {
    /// The trap this type exists for: expanding propagation per target and
    /// concatenating emits several implicit events for the same ancestor at the
    /// same instant, and the fold applies each one — stability compounds past what
    /// any single review could produce. The joint expansion emits exactly one.
    @Test func multiTargetProblemsEmitOneImplicitEventPerAncestor() {
        // `rolle` and `mvt` share the whole ancestry below Rolle.
        let p = problem("p-multi", targets: ["analysis.svc.rolle", "analysis.svc.mvt"])
        let events = Grading.evidence(for: p, outcome: .solved, in: graph, at: now)

        let implicit = events.filter { $0.source == .implicit }
        let keys = implicit.map(\.target.key)
        #expect(Set(keys).count == keys.count, "duplicate implicit targets: \(keys)")

        // And the naive version really would have duplicated — otherwise this test
        // proves nothing.
        let naive = p.targets.flatMap {
            Propagation.expand(
                EvidenceEvent(at: now, target: .node($0), grade: .good, source: .test),
                in: graph)
        }
        let naiveKeys = naive.map(\.target.key)
        #expect(Set(naiveKeys).count < naiveKeys.count)
    }

    @Test func jointExpansionTakesTheMinimumDepthAcrossTargets() {
        // diff-implies-cont is 1 hop below rolle and 2 below mvt.
        let p = problem("p-multi", targets: ["analysis.svc.rolle", "analysis.svc.mvt"])
        let events = Grading.evidence(for: p, outcome: .solved, in: graph, at: now)
        let event = events.first { $0.target == .node("analysis.svc.diff-implies-cont") }
        #expect(event?.depth == 1)
        #expect(event?.origin == "analysis.svc.rolle")
    }

    @Test func targetsGetTheGradeAndExercisedNodesGetFullStrength() {
        let p = problem(
            "p-ftc", targets: ["analysis.svc.ftc-2"],
            exercises: ["analysis.svc.def-riemann-sum", "foundations.real.sup-inf"])
        let events = Grading.evidence(for: p, outcome: .fluent, in: graph, at: now)

        let target = events.first { $0.target == .node("analysis.svc.ftc-2") }
        #expect(target?.source == .test)
        #expect(target?.grade == .easy)
        #expect(target?.problem == "p-ftc")

        // §4.3: "explicitly-exercised nodes get full-strength implicit reviews
        // regardless of graph distance" — sup-inf is five hops away.
        for id in p.exercises {
            let event = events.first { $0.target == .node(id) }
            #expect(event?.depth == 0, "\(id)")
            #expect(event?.weight == 1.0, "\(id)")
            #expect(event?.source == .implicit)
        }
    }

    @Test func exercisedNodesOutrankTheDampedDepthTheTraversalFound() {
        // def-continuity sits 2 hops below rolle; naming it exercised must lift it
        // to full strength rather than leaving it at γ².
        let damped = Grading.evidence(
            for: problem("p-a", targets: ["analysis.svc.rolle"]),
            outcome: .solved, in: graph, at: now)
        let lifted = Grading.evidence(
            for: problem(
                "p-b", targets: ["analysis.svc.rolle"], exercises: ["analysis.svc.def-continuity"]),
            outcome: .solved, in: graph, at: now)

        #expect(damped.first { $0.target == .node("analysis.svc.def-continuity") }?.depth == 2)
        #expect(lifted.first { $0.target == .node("analysis.svc.def-continuity") }?.depth == 0)
        #expect(lifted.first { $0.target == .node("analysis.svc.def-continuity") }?.weight == 1.0)
    }

    /// §4.4: `relates` edges carry their own state, and an edge review happens when
    /// a problem exercises the connection. Phase 6 could build the render path but
    /// never write the evidence (D6.11); this is the writer.
    @Test func connectsProducesEdgeEvidence() {
        let key = graph.relatesEdges.first { $0.key.contains("leibniz") }!.key
        let p = problem(
            "p-edge", targets: ["analysis.svc.mvt", "analysis.mvc.leibniz-rule"], connects: [key])
        let events = Grading.evidence(for: p, outcome: .solved, in: graph, at: now)
        let edge = events.first { $0.target == .edge(key) }
        #expect(edge?.grade == .good)
        #expect(edge?.source == .test)

        let (state, defects) = ScoreFold.fold(events, graph: graph)
        #expect(defects.isEmpty, "\(defects)")
        #expect(state.edges[key] != nil)
    }

    @Test func anUnlocalizedMissWritesNothing() {
        let p = problem("p-miss", targets: ["analysis.svc.mvt"])
        #expect(Grading.evidence(for: p, outcome: .missed, in: graph, at: now).isEmpty)
    }

    /// §5.4: "The failure evidence lands on the localized node, not automatically
    /// on the whole chain." And §4.3: failure never propagates as a penalty.
    @Test func aLocalizedMissWritesExactlyOneEvent() {
        let p = problem("p-miss", targets: ["analysis.svc.ftc-2"])
        let events = Grading.evidence(
            for: p, outcome: .missed, in: graph, at: now, localizedTo: "analysis.svc.rolle")
        #expect(events.count == 1)
        #expect(events[0].target == .node("analysis.svc.rolle"))
        #expect(events[0].grade == .again)
        #expect(events[0].source == .test)
    }
}

@Suite("Failure diagnosis (§5.4)")
struct DiagnosisTests {
    /// The seeded gap: everything FTC Part II needs except `def-antiderivative`.
    private func gappedState(gap: NodeID) -> ScoreState {
        let known = graph.requiresAncestors(of: "analysis.svc.ftc-2").filter { $0 != gap }
        let events = known.map {
            EvidenceEvent(
                at: now.addingTimeInterval(-86_400), target: .node($0), grade: .easy,
                source: .selfReport)
        }
        return ScoreFold.fold(events, graph: graph).state
    }

    @Test func theChainRanksTheSeededGapFirst() {
        let gap: NodeID = "analysis.svc.def-antiderivative"
        let chain = Diagnosis.chain(
            forTargets: ["analysis.svc.ftc-2"], graph: graph, state: gappedState(gap: gap),
            at: now)
        #expect(chain.first?.id == gap)
        #expect(chain.first?.isLearned == false)
        // Every learned node ranks below every unlearned one.
        let firstLearned = chain.firstIndex { $0.isLearned } ?? chain.count
        #expect(chain.prefix(firstLearned).allSatisfy { !$0.isLearned })
        #expect(chain.dropFirst(firstLearned).allSatisfy { $0.isLearned })
    }

    /// The failed target is itself unlearned, so a naive "weakest first" would
    /// offer it before the prerequisite that actually broke — the misattribution
    /// §5.4 exists to prevent. The deepest-first tie-break is what stops it.
    @Test func theFailedTargetRanksBelowTheDeeperGap() {
        let gap: NodeID = "analysis.svc.def-antiderivative"
        let chain = Diagnosis.chain(
            forTargets: ["analysis.svc.ftc-2"], graph: graph, state: gappedState(gap: gap),
            at: now)
        let gapIndex = try! #require(chain.firstIndex { $0.id == gap })
        let targetIndex = try! #require(chain.firstIndex { $0.id == "analysis.svc.ftc-2" })
        #expect(gapIndex < targetIndex)
    }

    @Test func withNothingLearnedTheChainStartsAtTheFoundations() {
        let chain = Diagnosis.chain(
            forTargets: ["analysis.svc.ftc-2"], graph: graph, state: ScoreState(), at: now)
        #expect(chain.first?.id == "foundations.real.sup-inf")
        #expect(chain.last?.id == "analysis.svc.ftc-2")
    }

    @Test func theChainReachesPastDMax() {
        // sup-inf is 6 hops below FTC Part II — beyond D_max = 3. Damping caps how
        // far credit spreads; a gap can sit anywhere.
        let chain = Diagnosis.chain(
            forTargets: ["analysis.svc.ftc-2"], graph: graph, state: ScoreState(), at: now)
        #expect(chain.contains { $0.id == "foundations.real.sup-inf" })
        #expect(chain.allSatisfy { graph[$0.id]?.kind.isContent == true })
    }

    @Test func candidatesCarryAMicroProblemButNeverTheOneJustMissed() {
        let bank = ProblemBank(problems: [
            problem("p-missed", targets: ["analysis.svc.ftc-2"]),
            problem("p-followup", targets: ["analysis.svc.ftc-2"]),
            problem("p-anti", targets: ["analysis.svc.def-antiderivative"]),
        ])
        let chain = Diagnosis.chain(
            after: bank["p-missed"]!, graph: graph, state: ScoreState(), at: now, bank: bank)
        #expect(chain.first { $0.id == "analysis.svc.ftc-2" }?.probe == "p-followup")
        #expect(chain.first { $0.id == "analysis.svc.def-antiderivative" }?.probe == "p-anti")
        #expect(chain.first { $0.id == "analysis.svc.mvt" }?.probe == nil)
    }
}

@Suite("Failed-only nodes stay unlearned (D8.3)")
struct FailedOnlyNodeTests {
    private func afterMiss(on id: NodeID) -> ScoreState {
        // Every prerequisite mastered, then a miss on the node itself.
        let mastered = graph.requiresAncestors(of: id).map {
            EvidenceEvent(
                at: now.addingTimeInterval(-3600), target: .node($0), grade: .easy,
                source: .selfReport)
        }
        let miss = EvidenceEvent(
            at: now, target: .node(id), grade: .again, source: .test, problem: "p")
        return ScoreFold.fold(mastered + [miss], graph: graph).state
    }

    @Test func aMissCreatesStateWithoutCountingAsLearned() {
        let state = afterMiss(on: "analysis.svc.def-continuity")
        #expect(state[NodeID("analysis.svc.def-continuity")] != nil)
        #expect(state.isLearned("analysis.svc.def-continuity") == false)
    }

    /// The reason the distinction had to exist: without it, being measured as
    /// *not knowing* something would delete it from "what you could learn next".
    @Test func aMissedNodeStaysOnTheFrontier() {
        let state = afterMiss(on: "analysis.svc.def-continuity")
        let frontier = Frontier.compute(graph: graph, state: state, at: now)
        #expect(frontier.contains("analysis.svc.def-continuity"))
    }

    @Test func aMissedNodeIsNotAMetPrerequisite() {
        let state = afterMiss(on: "analysis.svc.def-continuity")
        let plan = FocusPlan.compute(goal: "analysis.svc.evt", graph: graph, state: state, at: now)
        #expect(plan?.syllabus.contains("analysis.svc.def-continuity") == true)
    }

    @Test func aMissedNodePaintsGreyNotDeepBlue() {
        let state = afterMiss(on: "analysis.svc.def-continuity")
        let fsrs = FSRS()
        let colour = ScoreRamp.color(
            for: state[NodeID("analysis.svc.def-continuity")],
            learned: state.isLearned("analysis.svc.def-continuity"), at: now, fsrs: fsrs)
        #expect(colour == ScoreRamp.unlearned)
    }

    /// A passing implicit boost is still learning: §5.3's whole premise is that
    /// exercising a prerequisite is evidence about it.
    @Test func implicitPassesCountAsLearned() {
        let events = Propagation.expanded(
            EvidenceEvent(at: now, target: .node("analysis.svc.mvt"), grade: .good, source: .test),
            in: graph)
        let state = ScoreFold.fold(events, graph: graph).state
        #expect(state.isLearned("analysis.svc.rolle"))
        #expect(!Frontier.compute(graph: graph, state: state, at: now).contains("analysis.svc.rolle"))
    }
}

@Suite("Placement (§5.3)")
struct PlacementTests {
    private let bank = ProblemBank(
        problems: Fixtures.clean.filter(\.kind.isContent).map {
            problem(ProblemID("p-\($0.id.rawValue.replacingOccurrences(of: ".", with: "-"))"),
                targets: [$0.id])
        })

    private func answer(
        _ node: NodeID, _ outcome: ProblemOutcome, localizedTo: NodeID? = nil
    ) -> ProbeAnswer {
        ProbeAnswer(
            problem: bank.problems(targeting: node)[0].id, node: node, outcome: outcome, at: now,
            localizedTo: localizedTo)
    }

    @Test func aStructuralClaimExpandsThroughContains() {
        let seed = PlacementSeed(claimed: ["analysis.svc"])
        let expanded = seed.expanded(in: graph)
        #expect(expanded.contains("analysis.svc.mvt"))
        #expect(expanded.allSatisfy { graph[$0]?.kind.isContent == true })
        #expect(!expanded.contains("foundations.real.sup-inf"))
    }

    @Test func seedingRaisesAncestorsAndLowersDependents() {
        let session = PlacementSession(seed: PlacementSeed(claimed: ["analysis.svc.mvt"]))
        let belief = Placement.belief(for: session, graph: graph)
        // Everything the claim requires is claimed with it.
        #expect(belief.probability(of: "analysis.svc.rolle") > belief.probability(of: "analysis.svc.u-sub"))
        #expect(belief.probability(of: "foundations.real.sup-inf") == PlacementConfig().seedKnown)
        // "started X" implies not yet finished it.
        #expect(belief.probability(of: "analysis.svc.u-sub") == PlacementConfig().seedUnknown)
    }

    @Test func aPassRaisesEveryAncestorRegardlessOfDepth() {
        var session = PlacementSession()
        session.record(answer("analysis.svc.u-sub", .solved))
        let belief = Placement.belief(for: session, graph: graph)
        // sup-inf is 7 hops below u-sub — far past D_max.
        #expect(belief.isKnown("foundations.real.sup-inf"))
        #expect(belief.probability(of: "analysis.svc.mvt") == PlacementConfig().inferredFromPass)
        #expect(belief.probability(of: "analysis.svc.u-sub") == 1)
    }

    @Test func aFailPushesProbingDownAndSinksDependents() {
        var session = PlacementSession()
        session.record(answer("analysis.svc.rolle", .missed))
        let belief = Placement.belief(for: session, graph: graph)
        #expect(belief.probability(of: "analysis.svc.rolle") == 0)
        #expect(belief.probability(of: "analysis.svc.mvt") <= PlacementConfig().inferredFromFail)
        #expect(belief.probability(of: "analysis.svc.u-sub") <= PlacementConfig().inferredFromFail)
        // Prerequisites are untouched — they are exactly what probing should look at next.
        #expect(!belief.isResolved("analysis.svc.def-continuity"))
    }

    @Test func aMissLocalizedToAPrerequisiteLeavesTheProbedNodeUnmeasured() {
        var session = PlacementSession()
        session.record(answer("analysis.svc.mvt", .missed, localizedTo: "analysis.svc.rolle"))
        let belief = Placement.belief(for: session, graph: graph)
        #expect(belief.probability(of: "analysis.svc.rolle") == 0)
        #expect(belief.tested.contains("analysis.svc.rolle"))
        #expect(!belief.tested.contains("analysis.svc.mvt"))
        #expect(belief.probability(of: "analysis.svc.mvt") <= PlacementConfig().displacedTarget)
    }

    @Test func beliefIsAPureReplayOfSeedPlusAnswers() {
        var session = PlacementSession(seed: PlacementSeed(claimed: ["analysis.svc.def-derivative"]))
        session.record(answer("analysis.svc.mvt", .missed))
        session.record(answer("analysis.svc.def-continuity", .solved))

        let a = Placement.belief(for: session, graph: graph)
        let b = Placement.belief(for: session, graph: graph)
        #expect(a.probability == b.probability)

        // Resuming from a serialized session is the same computation.
        let data = try! JSONEncoder().encode(session)
        let resumed = try! JSONDecoder().decode(PlacementSession.self, from: data)
        #expect(Placement.belief(for: resumed, graph: graph).probability == a.probability)
    }

    @Test func probeSelectionIsDeterministicAndNeverRepeatsAProblem() {
        var session = PlacementSession()
        var asked: [ProblemID] = []
        while let probe = Placement.nextProbe(for: session, graph: graph, bank: bank) {
            #expect(!asked.contains(probe.problem.id))
            asked.append(probe.problem.id)
            session.record(
                ProbeAnswer(
                    problem: probe.problem.id, node: probe.node, outcome: .solved, at: now))
        }
        #expect(!asked.isEmpty)

        var again = PlacementSession()
        var replay: [ProblemID] = []
        while let probe = Placement.nextProbe(for: again, graph: graph, bank: bank) {
            replay.append(probe.problem.id)
            again.record(
                ProbeAnswer(
                    problem: probe.problem.id, node: probe.node, outcome: .solved, at: now))
        }
        #expect(asked == replay)
    }

    @Test func theFirstProbeBisectsRatherThanStartingAtAnExtreme() {
        let probe = Placement.nextProbe(for: PlacementSession(), graph: graph, bank: bank)
        let id = try! #require(probe?.node)
        // A bisecting choice has unresolved nodes both above and below it; a root
        // or a leaf would have none on one side.
        #expect(!graph.requiresAncestors(of: id).isEmpty)
        #expect(!graph.requiresDescendants(of: id).isEmpty)
    }

    @Test func inferredEvidenceIsConfidenceWeightedAndDepthless() {
        var session = PlacementSession()
        session.record(answer("analysis.svc.u-sub", .solved))
        let events = Placement.inferredEvidence(for: session, graph: graph, at: now)

        #expect(!events.isEmpty)
        // Never for a node a probe measured directly — that has real evidence.
        #expect(!events.contains { $0.target == .node("analysis.svc.u-sub") })
        for event in events {
            #expect(event.source == .implicit)
            #expect(event.confidence == PlacementConfig().inferredFromPass)
            // The §5.3 tier is not §4.3's damped propagation: no hop distance, and
            // the confidence is the discriminator a γ refit must filter on.
            #expect(event.depth == nil)
            #expect(event.weight == nil)
            #expect(event.grade == .good)
        }
    }

    /// §5.3: inferred knowledge "decays faster until confirmed by a direct test".
    /// With no second decay model in the system, that has to fall out of the
    /// weight — and it does.
    @Test func inferredEvidenceDecaysFasterThanARealReview() {
        let id: NodeID = "analysis.svc.mvt"
        var session = PlacementSession()
        session.record(answer("analysis.svc.u-sub", .solved))
        let inferred = Placement.inferredEvidence(for: session, graph: graph, at: now)
            .filter { $0.target == .node(id) }
        #expect(inferred.count == 1)

        let fsrs = FSRS()
        let inferredState = ScoreFold.fold(inferred, graph: graph).state
        let testedState = ScoreFold.fold(
            [EvidenceEvent(at: now, target: .node(id), grade: .good, source: .test)],
            graph: graph
        ).state

        let inferredStability = inferredState[id]!.stability
        let testedStability = testedState[id]!.stability
        #expect(inferredStability < testedStability)

        let later = now.addingTimeInterval(30 * 86_400)
        #expect(
            fsrs.retrievability(of: inferredState[id]!, at: later)
                < fsrs.retrievability(of: testedState[id]!, at: later))
    }

    @Test func aDirectTestOverridesInferredEvidence() {
        let id: NodeID = "analysis.svc.mvt"
        var session = PlacementSession()
        session.record(answer("analysis.svc.u-sub", .solved))
        let inferred = Placement.inferredEvidence(for: session, graph: graph, at: now)

        let confirmed = ScoreFold.fold(
            inferred + [
                EvidenceEvent(
                    at: now.addingTimeInterval(86_400), target: .node(id), grade: .good,
                    source: .test)
            ], graph: graph
        ).state
        let inferredOnly = ScoreFold.fold(inferred, graph: graph).state
        #expect(confirmed[id]!.stability > inferredOnly[id]!.stability)
    }

    /// The belief and the map must not be able to disagree. `Grading.evidence`
    /// writes a full graded review on *every* target of a problem (§5.2), so a
    /// belief that credited only the node placement picked the problem for would
    /// call a node unknown that the evidence log had just recorded as learned.
    @Test func aMultiTargetProbeCreditsEveryTargetItGraded() {
        let multi = problem(
            "p-multi", targets: ["analysis.svc.def-antiderivative", "analysis.svc.zero-deriv-const"])
        let bank = ProblemBank(problems: [multi])
        var session = PlacementSession()
        session.record(
            ProbeAnswer(
                problem: multi.id, node: "analysis.svc.def-antiderivative", outcome: .solved,
                at: now))

        let belief = Placement.belief(for: session, graph: graph, bank: bank)
        for target in multi.targets {
            #expect(belief.tested.contains(target), "\(target) was graded but not credited")
            #expect(belief.probability(of: target) == 1)
        }

        // And the map agrees, which is the property that matters.
        let state = ScoreFold.fold(
            Grading.evidence(for: multi, outcome: .solved, in: graph, at: now), graph: graph
        ).state
        for target in multi.targets {
            #expect(state.isLearned(target) == belief.isKnown(target))
        }

        // Without the bank the second target is invisible — which is exactly why
        // callers must pass it, and why this asserts the difference rather than
        // trusting the parameter's default.
        #expect(
            !Placement.belief(for: session, graph: graph).tested
                .contains("analysis.svc.zero-deriv-const"))
    }

    @Test func aMultiTargetMissLeavesEveryUnfailedTargetUnmeasured() {
        let multi = problem(
            "p-multi", targets: ["analysis.svc.def-antiderivative", "analysis.svc.zero-deriv-const"])
        let bank = ProblemBank(problems: [multi])
        var session = PlacementSession()
        session.record(
            ProbeAnswer(
                problem: multi.id, node: "analysis.svc.def-antiderivative", outcome: .missed,
                at: now, localizedTo: "analysis.svc.mvt"))

        let belief = Placement.belief(for: session, graph: graph, bank: bank)
        #expect(belief.probability(of: "analysis.svc.mvt") == 0)
        for target in multi.targets {
            #expect(!belief.tested.contains(target))
            #expect(belief.probability(of: target) <= PlacementConfig().displacedTarget)
        }
    }

    @Test func sessionsTerminateAtTheProbeBudget() {
        var config = PlacementConfig()
        config.maxProbes = 2
        var session = PlacementSession()
        for _ in 0..<2 {
            let probe = Placement.nextProbe(for: session, graph: graph, bank: bank, config: config)
            session.record(
                ProbeAnswer(
                    problem: probe!.problem.id, node: probe!.node, outcome: .solved, at: now))
        }
        #expect(Placement.nextProbe(for: session, graph: graph, bank: bank, config: config) == nil)
    }
}
