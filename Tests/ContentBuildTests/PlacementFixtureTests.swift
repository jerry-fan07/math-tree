import Foundation
import GraphCore
import Testing

@testable import ContentBuild

/// Phase 8's exit criterion, over the *real* content and the *real* problem bank:
///
/// > on a seeded persona ("knows calc through derivatives"), placement converges
/// > to the expected knowledge boundary within a bounded number of probes; a
/// > failed FTC problem localizes to the seeded gap.
///
/// Both halves are asserted against a persona defined here as data — the
/// knowledge set is written down, and everything the test checks is recomputed
/// from it independently of `Placement`'s internals.
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func loadCorpus() throws -> (KnowledgeGraph, ProblemBank) {
    let content = try ContentLoader.load(
        root: repoRoot.appendingPathComponent("content"), relativeTo: repoRoot)
    let problems = try ProblemLoader.load(
        root: repoRoot.appendingPathComponent("problems"), relativeTo: repoRoot)
    return (KnowledgeGraph(nodes: content.nodes), ProblemBank(problems: problems.problems))
}

/// A simulated solver. Answers a probe from a fixed knowledge set, and localizes a
/// miss the way a person would: to the first place the chain actually broke.
struct Persona: Sendable {
    let name: String
    let knows: Set<NodeID>

    /// A problem is solved only if the persona knows *every* node it targets — a
    /// multi-target problem is a claim about all of them, which is why the belief
    /// credits all of them (D8.5).
    func outcome(on problem: Problem) -> ProblemOutcome {
        problem.targets.allSatisfy(knows.contains) ? .solved : .missed
    }

    /// Where this persona says the failure was. The honest answer is the *lowest*
    /// unknown node in the targets' ancestry whose own prerequisites are all
    /// known — the first rung of the ladder they could not climb. Smallest id when
    /// several are tied, so the simulation is deterministic.
    func localization(for problem: Problem, in graph: KnowledgeGraph) -> NodeID? {
        let reachable = problem.targets + problem.targets.flatMap { graph.requiresAncestors(of: $0) }
        return
            reachable
            .filter { graph[$0]?.kind.isContent == true && !knows.contains($0) }
            .filter { graph.prerequisites(of: $0).allSatisfy(knows.contains) }
            .sorted().first
    }

    /// The answer this persona would give to one probe.
    func answer(_ probe: (node: NodeID, problem: Problem), in graph: KnowledgeGraph, at now: Date)
        -> ProbeAnswer
    {
        let outcome = outcome(on: probe.problem)
        return ProbeAnswer(
            problem: probe.problem.id,
            node: probe.node,
            outcome: outcome,
            at: now,
            localizedTo: outcome.isPass ? nil : localization(for: probe.problem, in: graph))
    }

    /// Nodes the persona knows that have at least one dependent it does not — the
    /// edge of what it has learned, recomputed here rather than taken from
    /// `Placement`.
    func boundary(in graph: KnowledgeGraph) -> [NodeID] {
        knows.filter { id in
            graph.dependents(of: id)
                .filter { graph[$0]?.kind.isContent == true }
                .contains { !knows.contains($0) }
        }.sorted()
    }
}

/// "Knows calc through derivatives": limits, continuity, the two continuity
/// theorems, the derivative and what falls straight out of it — and nothing about
/// the mean-value theorems, integration, or the Fundamental Theorem.
///
/// Downward-closed under `requires` by construction, which is what makes it a
/// coherent state of knowledge rather than an arbitrary set: every prerequisite of
/// something known is itself known.
private let throughDerivatives = Persona(
    name: "knows calc through derivatives",
    knows: [
        "foundations.real.sup-inf",
        "foundations.real.completeness",
        "analysis.svc.def-limit",
        "analysis.svc.def-continuity",
        "analysis.svc.evt",
        "analysis.svc.ivt",
        "analysis.svc.def-derivative",
        "analysis.svc.intuition-linearization",
        "analysis.svc.diff-implies-cont",
    ])

private let placementNow = Date(timeIntervalSince1970: 1_785_000_000)

/// Drive a placement session to completion against a persona.
private func runPlacement(
    _ persona: Persona,
    seed: PlacementSeed = PlacementSeed(),
    graph: KnowledgeGraph,
    bank: ProblemBank,
    config: PlacementConfig = PlacementConfig()
) -> (session: PlacementSession, probes: [NodeID]) {
    var session = PlacementSession(seed: seed)
    var probes: [NodeID] = []
    while let probe = Placement.nextProbe(for: session, graph: graph, bank: bank, config: config) {
        probes.append(probe.node)
        session.record(persona.answer(probe, in: graph, at: placementNow))
    }
    return (session, probes)
}

@Suite("Phase 8 exit criterion — placement converges")
struct PlacementConvergenceTests {

    @Test func thePersonaIsACoherentKnowledgeState() throws {
        let (graph, _) = try loadCorpus()
        for id in throughDerivatives.knows {
            #expect(graph[id]?.kind.isContent == true, "\(id) is not a content node")
            for prerequisite in graph.prerequisites(of: id) {
                #expect(
                    throughDerivatives.knows.contains(prerequisite),
                    "persona knows \(id) but not its prerequisite \(prerequisite)")
            }
        }
    }

    /// The criterion, with the bound pinned at the *measured* value rather than a
    /// comfortable one. 22 content nodes resolve in 8 probes because a bisecting
    /// probe settles a whole cone at a time: the first pass fixes everything below
    /// the derivative, and each later miss sinks a subtree. A change that pushes
    /// this up is a policy regression and should have to be looked at.
    @Test func placementConvergesToTheSeededBoundaryInEightProbes() throws {
        let (graph, bank) = try loadCorpus()
        let (session, probes) = runPlacement(throughDerivatives, graph: graph, bank: bank)

        #expect(probes.count <= 8, "took \(probes.count) probes: \(probes)")

        let belief = Placement.belief(for: session, graph: graph, bank: bank)
        #expect(belief.unresolved.isEmpty, "unresolved: \(belief.unresolved)")
        #expect(Set(belief.known) == throughDerivatives.knows)
        #expect(
            belief.boundary(in: graph) == throughDerivatives.boundary(in: graph),
            "boundary \(belief.boundary(in: graph)) vs \(throughDerivatives.boundary(in: graph))")
    }

    /// A check that cannot fail proves nothing (D6.6). A different persona must
    /// converge somewhere different — otherwise the assertion above is measuring
    /// the graph, not the placement.
    @Test func adifferentPersonaConvergesSomewhereElse() throws {
        let (graph, bank) = try loadCorpus()
        let novice = Persona(name: "knows only the reals", knows: ["foundations.real.sup-inf"])
        let (session, _) = runPlacement(novice, graph: graph, bank: bank)
        let belief = Placement.belief(for: session, graph: graph, bank: bank)

        #expect(Set(belief.known) == novice.knows)
        #expect(Set(belief.known) != throughDerivatives.knows)
        #expect(belief.boundary(in: graph) == novice.boundary(in: graph))
    }

    /// §5.3 step 1: a coarse claim should *save* probes, not change the answer.
    @Test func claimedFrontierSeedingCostsFewerProbesAndLandsInTheSamePlace() throws {
        let (graph, bank) = try loadCorpus()
        let cold = runPlacement(throughDerivatives, graph: graph, bank: bank)
        let seeded = runPlacement(
            throughDerivatives,
            seed: PlacementSeed(claimed: ["analysis.svc.def-derivative"]),
            graph: graph, bank: bank)

        #expect(seeded.probes.count <= cold.probes.count)
        let a = Placement.belief(for: cold.session, graph: graph, bank: bank)
        let b = Placement.belief(for: seeded.session, graph: graph, bank: bank)
        #expect(Set(a.known) == Set(b.known))
    }

    @Test func aPartialSessionResumesToTheSameStateItWasSavedIn() throws {
        let (graph, bank) = try loadCorpus()
        var session = PlacementSession()
        for _ in 0..<3 {
            let probe = try #require(Placement.nextProbe(for: session, graph: graph, bank: bank))
            session.record(throughDerivatives.answer(probe, in: graph, at: placementNow))
        }
        let data = try JSONEncoder().encode(session)
        var resumed = try JSONDecoder().decode(PlacementSession.self, from: data)

        // Finish both, from the same point, and require the same conclusion.
        func finish(_ session: inout PlacementSession) -> [NodeID] {
            var probes: [NodeID] = []
            while let probe = Placement.nextProbe(for: session, graph: graph, bank: bank) {
                probes.append(probe.node)
                session.record(throughDerivatives.answer(probe, in: graph, at: placementNow))
            }
            return probes
        }
        var original = session
        #expect(finish(&original) == finish(&resumed))
        #expect(
            Set(Placement.belief(for: original, graph: graph, bank: bank).known)
                == Set(Placement.belief(for: resumed, graph: graph, bank: bank).known))
    }

    /// The committed evidence has to reproduce the belief when folded — otherwise
    /// placement tells the user one thing and paints the map another.
    @Test func committedInferredEvidenceReproducesThePersonaOnTheMap() throws {
        let (graph, bank) = try loadCorpus()
        let (session, _) = runPlacement(throughDerivatives, graph: graph, bank: bank)

        // Everything the session wrote: the graded probes, plus §5.3's inferred tier.
        var events: [EvidenceEvent] = []
        for answer in session.answers {
            let problem = try #require(bank[answer.problem])
            events += Grading.evidence(
                for: problem, outcome: answer.outcome, in: graph, at: answer.at,
                localizedTo: answer.localizedTo)
        }
        events += Placement.inferredEvidence(for: session, graph: graph, bank: bank, at: placementNow)

        let (state, defects) = ScoreFold.fold(events, graph: graph)
        #expect(defects.isEmpty, "\(defects)")

        // Every node the persona knows has learned state; nothing it does not
        // know does. This is the claim that placement "filled in the picture".
        for id in throughDerivatives.knows {
            #expect(state.isLearned(id), "placement left \(id) unlearned")
        }
        let known = throughDerivatives.knows
        for node in graph.nodes where node.kind.isContent && !known.contains(node.id) {
            #expect(!state.isLearned(node.id), "placement claimed \(node.id) was learned")
        }
    }

    /// A miss must never write knowledge, and must never write it on the chain.
    @Test func missesDuringPlacementLandOnOneNodeEach() throws {
        let (graph, bank) = try loadCorpus()
        let (session, _) = runPlacement(throughDerivatives, graph: graph, bank: bank)

        for answer in session.answers where !answer.outcome.isPass {
            let problem = try #require(bank[answer.problem])
            let events = Grading.evidence(
                for: problem, outcome: answer.outcome, in: graph, at: answer.at,
                localizedTo: answer.localizedTo)
            #expect(events.count == 1, "a miss wrote \(events.count) events")
            #expect(events.first?.grade == .again)
            #expect(events.first?.target == .node(answer.localizedTo ?? answer.node))
        }
    }
}

@Suite("Phase 8 exit criterion — a failed FTC problem localizes to the gap")
struct FTCLocalizationTests {
    /// Someone ready for the Fundamental Theorem in every respect but one: they
    /// never learned what an antiderivative is. Everything else FTC Part II needs
    /// is solid.
    private static let gap: NodeID = "analysis.svc.def-antiderivative"

    private func seededState(in graph: KnowledgeGraph) -> ScoreState {
        let events = graph.requiresAncestors(of: "analysis.svc.ftc-part-2")
            .filter { $0 != Self.gap }
            .map {
                EvidenceEvent(
                    at: placementNow.addingTimeInterval(-2 * 86_400), target: .node($0),
                    grade: .easy, source: .selfReport)
            }
        return ScoreFold.fold(events, graph: graph).state
    }

    @Test func theChainOffersTheSeededGapFirst() throws {
        let (graph, bank) = try loadCorpus()
        let problem = try #require(bank["svc-ftc-part-2-01"])
        let chain = Diagnosis.chain(
            after: problem, graph: graph, state: seededState(in: graph), at: placementNow,
            bank: bank)

        #expect(chain.first?.id == Self.gap)
        #expect(chain.first?.isLearned == false)
        // And it offers a micro-problem to confirm it, rather than only asking the
        // user to introspect (§5.4).
        #expect(chain.first?.probe != nil)
        // The problem that was just missed is never offered back.
        #expect(!chain.contains { $0.probe == problem.id })
    }

    @Test func localizingWritesTheFailureOnTheGapAndNowhereElse() throws {
        let (graph, bank) = try loadCorpus()
        let problem = try #require(bank["svc-ftc-part-2-01"])
        let events = Diagnosis.evidence(
            for: problem, localizedTo: Self.gap, in: graph, at: placementNow)

        #expect(events.count == 1)
        #expect(events[0].target == .node(Self.gap))
        #expect(events[0].grade == .again)
        #expect(events[0].source == .test)
        #expect(events[0].problem == problem.id.rawValue)

        // §4.3: failure is a retest flag, never a penalty. Nothing on the chain
        // moved, including the target the problem was actually about.
        let before = seededState(in: graph)
        let after = ScoreFold.fold(events, graph: graph, state: before).state
        for id in graph.requiresAncestors(of: "analysis.svc.ftc-part-2") where id != Self.gap {
            #expect(after[id]?.stability == before[id]?.stability, "\(id) moved")
        }
        #expect(after[NodeID("analysis.svc.ftc-part-2")] == nil)
    }

    /// The consequence the frontier rule exists for (D8.3): being measured as not
    /// knowing the gap must not remove it from "what you could learn next".
    @Test func theLocalizedGapStaysOnTheFrontierAndBecomesDue() throws {
        let (graph, bank) = try loadCorpus()
        let problem = try #require(bank["svc-ftc-part-2-01"])
        let events = Diagnosis.evidence(
            for: problem, localizedTo: Self.gap, in: graph, at: placementNow)
        let state = ScoreFold.fold(events, graph: graph, state: seededState(in: graph)).state

        #expect(state[Self.gap] != nil, "the failure was recorded")
        #expect(state.isLearned(Self.gap) == false)
        #expect(Frontier.compute(graph: graph, state: state, at: placementNow).contains(Self.gap))
        #expect(
            ReviewQueue.due(graph: graph, state: state, at: placementNow.addingTimeInterval(86_400))
                .contains { $0.id == Self.gap })
    }

    /// And the syllabus agrees with the map, which D7.1 makes a hard requirement.
    @Test func theGapAppearsInTheFTCSyllabus() throws {
        let (graph, bank) = try loadCorpus()
        let problem = try #require(bank["svc-ftc-part-2-01"])
        let events = Diagnosis.evidence(
            for: problem, localizedTo: Self.gap, in: graph, at: placementNow)
        let state = ScoreFold.fold(events, graph: graph, state: seededState(in: graph)).state

        let plan = try #require(
            FocusPlan.compute(
                goal: "analysis.svc.ftc-part-2", graph: graph, state: state, at: placementNow))
        #expect(plan.syllabus.contains(Self.gap))
        // The gap and the goal, and nothing else: everything else was mastered.
        #expect(plan.syllabus == [Self.gap])
    }
}

@Suite("The authored problem bank")
struct ProblemBankFixtureTests {
    @Test func theBankValidatesCleanAgainstRealContent() throws {
        let (graph, bank) = try loadCorpus()
        let diagnostics = ProblemValidator.validate(bank, against: graph)
        #expect(diagnostics.isEmpty, "\(diagnostics)")
    }

    /// Placement can only resolve what the bank can ask about. Coverage is a
    /// property of the corpus, so it is asserted rather than assumed.
    @Test func everyContentNodeHasAProblem() throws {
        let (graph, bank) = try loadCorpus()
        for node in graph.nodes where node.kind.isContent {
            #expect(
                !bank.problems(targeting: node.id).isEmpty,
                "no problem targets \(node.id) — placement cannot probe it")
        }
    }

    @Test func everyProblemHasASourceLocation() throws {
        let problems = try ProblemLoader.load(
            root: repoRoot.appendingPathComponent("problems"), relativeTo: repoRoot)
        #expect(problems.extraLocations.isEmpty)
        for problem in problems.problems {
            let location = problems.locations[problem.id]
            #expect(location != nil, "no source location for \(problem.id)")
            #expect(location?.file.hasPrefix("problems/") == true)
        }
    }

    /// §4.4's edge scores are unreachable without a problem that works both ends
    /// of a `relates` connection — Phase 6 recorded that as a known gap (D6.11).
    @Test func theBankCanScoreTheRelatesEdge() throws {
        let (graph, bank) = try loadCorpus()
        let edge = try #require(graph.relatesEdges.first)
        let problem = try #require(bank.problems.first { $0.connects.contains(edge.key) })

        let events = Grading.evidence(
            for: problem, outcome: .solved, in: graph, at: placementNow)
        let (state, defects) = ScoreFold.fold(events, graph: graph)
        #expect(defects.isEmpty, "\(defects)")
        #expect(state.edges[edge.key] != nil)
    }

    @Test func compiledArtifactRoundTripsAndIsByteStable() throws {
        let (_, bank) = try loadCorpus()
        let first = try Artifacts.encoder().encode(ProblemArtifact(bank))
        let second = try Artifacts.encoder().encode(ProblemArtifact(bank))
        #expect(first == second)

        struct Decoded: Decodable {
            let version: Int
            let problems: [Problem]
            let byTarget: [String: [ProblemID]]
        }
        let decoded = try JSONDecoder().decode(Decoded.self, from: first)
        #expect(decoded.version == ContentFormat.version)
        #expect(decoded.problems.count == bank.count)
        #expect(decoded.byTarget.count == bank.probeableNodes.count)
    }
}
