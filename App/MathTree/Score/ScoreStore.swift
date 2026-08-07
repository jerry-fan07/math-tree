import Foundation
import GraphCore
import Observation

/// The user-state half of the app: evidence log in, colours and queues out.
///
/// The shape follows §3.2 literally — the log is ground truth and everything here
/// is a cache of a fold over it. So **every mutation is an append followed by a
/// full refold**, never an incremental update of `state`. That costs nothing at
/// this scale and buys the thing Phase 6's exit criterion asks for: the path the
/// UI takes *is* the replay path, so "relaunching reproduces identical colours"
/// and "replaying the log reproduces identical scores" are the same claim.
///
/// Two environment overrides, both existing so the phase is verifiable rather
/// than merely claimed (and following D3.7 — configuration reaches an AppKit
/// process through the environment, never through `--flag value`):
///
/// - `MATHTREE_EVIDENCE_LOG` — read/write this log instead of the one in
///   Application Support. Fixture users live here.
/// - `MATHTREE_NOW` — pin the clock to an ISO-8601 instant (`2026-08-07`,
///   `2026-08-07T12:00:00Z`, or with fractional seconds). Retrievability decays
///   continuously against the wall clock (§4.1), so without a pinned clock two
///   runs *should* differ and a determinism check has nothing to compare.
@MainActor
@Observable
final class ScoreStore {
    let graph: KnowledgeGraph
    /// §5.2's evidence instrument. Empty when no bank was compiled, which is a
    /// legal state — self-report stays available for any node it cannot ask about.
    let bank: ProblemBank
    let config: ScoringConfig
    let fsrs: FSRS
    let log: EvidenceLog
    /// Non-nil when `MATHTREE_NOW` froze the clock.
    let pinnedNow: Date?
    /// Set for `--probe`, `--smoke-test` and snapshot runs. A verification run
    /// that appended to the developer's own history would corrupt it *and* stop
    /// being repeatable — the two things it exists to protect.
    let isReadOnly: Bool

    /// The whole log, in fold order. Kept because the panel's history read-out
    /// needs the events, not just the state they folded to.
    private(set) var events: [EvidenceEvent] = []
    private(set) var state = ScoreState()
    private(set) var frontier: Set<NodeID> = []
    /// Every scored node, most overdue first (§5.4's scheduler read-out).
    private(set) var schedule: [ScheduledReview] = []
    /// Log corruption and fold defects, surfaced rather than swallowed (D5.8).
    private(set) var diagnostics: [String] = []
    /// The instant this snapshot was evaluated at. Every colour, due flag and
    /// frontier membership in it shares this clock — a snapshot is consistent
    /// even though retrievability moves continuously.
    private(set) var evaluatedAt: Date
    /// Bumped on every recompute, so a view can observe "scores changed" without
    /// diffing dictionaries.
    private(set) var revision = 0

    /// Called after every recompute — how the renderer learns to repaint.
    var onChange: (() -> Void)?

    var isClockPinned: Bool { pinnedNow != nil }
    var now: Date { pinnedNow ?? Date() }

    init(
        document: GraphDocument,
        problems: ProblemBank = ProblemBank(problems: []),
        config: ScoringConfig = ScoringConfig(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) {
        // `GraphDocument` is the renderer's flat view of the content; propagation,
        // the frontier and the fold's unknown-id check all want the indexed graph,
        // so it is rebuilt once here rather than per query.
        graph = KnowledgeGraph(nodes: document.nodes)
        bank = problems
        self.config = config
        fsrs = FSRS(parameters: config.fsrs)
        pinnedNow = environment["MATHTREE_NOW"].flatMap(Self.parseInstant)
        isReadOnly =
            environment["MATHTREE_SNAPSHOT"] != nil || environment["MATHTREE_PANEL_SHOT"] != nil
            || arguments.contains("--probe") || arguments.contains("--smoke-test")
        evaluatedAt = pinnedNow ?? Date()

        var diagnostics: [String] = []
        let url: URL
        if let override = environment["MATHTREE_EVIDENCE_LOG"], !override.isEmpty {
            url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        } else if let standard = try? EvidenceLog.defaultURL() {
            url = standard
        } else {
            // Nowhere to persist is not fatal: the map still renders, reviews just
            // will not survive the session, and the panel says so.
            url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mathtree-evidence.jsonl")
            diagnostics.append("could not locate Application Support; using \(url.path)")
        }
        log = EvidenceLog(url: url)
        self.diagnostics = diagnostics

        reload()
    }

    // MARK: - Recompute

    /// Re-read the log and refold from scratch.
    func reload() {
        var diagnostics: [String] = []
        do {
            let contents = try log.read()
            events = contents.events
            diagnostics += contents.defects.map { "log \($0.description)" }
            if let header = contents.header, header.algorithm != FSRSVersion.algorithm {
                // §4.2/§3.2: the log records its algorithm precisely so a mismatch
                // can be seen instead of silently rescoring old history.
                diagnostics.append(
                    "log was written under \(header.algorithm); this build is \(FSRSVersion.algorithm)")
            }
        } catch {
            events = []
            diagnostics.append("could not read \(log.url.lastPathComponent): \(error)")
        }

        let folded = ScoreFold.fold(events, graph: graph, config: config)
        state = folded.state
        diagnostics += folded.defects.map(\.description)
        self.diagnostics = diagnostics
        evaluate()
    }

    /// Recompute everything that depends on the clock. The fold does not — FSRS
    /// state is a function of the log alone — so a decay tick is this, not a
    /// reload.
    func evaluate() {
        let now = now
        evaluatedAt = now
        frontier = Set(Frontier.compute(graph: graph, state: state, at: now, config: config))
        schedule = ReviewQueue.all(graph: graph, state: state, at: now, config: config)
        revision += 1
        onChange?()
    }

    // MARK: - Reading

    /// §4.1's score. `nil` means unlearned — which is *not* zero, and the
    /// difference is exactly what §4.5's grey encodes.
    func retrievability(of id: NodeID) -> Double? {
        state.retrievability(of: id, at: evaluatedAt, fsrs: fsrs)
    }

    func retrievability(ofEdge key: String) -> Double? {
        state.retrievability(ofEdge: key, at: evaluatedAt, fsrs: fsrs)
    }

    func color(of id: NodeID) -> ScoreColor {
        ScoreRamp.color(for: state[id], learned: isLearned(id), at: evaluatedAt, fsrs: fsrs)
    }

    /// Whether the node has ever been retrieved successfully. `false` with a
    /// non-nil score means "attempted and missed" — grey and on the frontier, not
    /// deep blue (D8.3).
    func isLearned(_ id: NodeID) -> Bool { state.isLearned(id) }

    /// §5.4 routes review "via problems, not flashcard-style restatement, whenever
    /// possible". This is the "whenever possible" — a routing rule, not a
    /// preference: a node the bank can ask about gets a problem, everything else
    /// falls back to self-report.
    func problems(targeting id: NodeID) -> [Problem] { bank.problems(targeting: id) }

    func canProbe(_ id: NodeID) -> Bool { !bank.problems(targeting: id).isEmpty }

    /// The easiest problem for this node that the log has no evidence from yet,
    /// falling back to the easiest overall once they have all been seen.
    func nextProblem(for id: NodeID) -> Problem? {
        let seen = Set(events.compactMap(\.problem))
        let candidates = bank.problems(targeting: id)
        return candidates.first { !seen.contains($0.id.rawValue) } ?? candidates.first
    }

    func nextDue(of id: NodeID) -> Date? {
        state[id].map { fsrs.nextDue(after: $0) }
    }

    func isFrontier(_ id: NodeID) -> Bool { frontier.contains(id) }

    func isDue(_ id: NodeID) -> Bool {
        guard let due = nextDue(of: id) else { return false }
        return due <= evaluatedAt
    }

    /// Reviews the scheduler says are owed now.
    var due: [ScheduledReview] { schedule.filter { $0.isDue(at: evaluatedAt) } }

    /// Scheduled but not yet owed, soonest first.
    var upcoming: [ScheduledReview] { schedule.filter { !$0.isDue(at: evaluatedAt) } }

    /// The frontier as a stable list — §4.5's "what you could learn next".
    var frontierList: [NodeID] { frontier.sorted() }

    /// This node's review history, for the panel's sparkline.
    func history(of id: NodeID) -> [ScoreFold.ReviewPoint] {
        ScoreFold.trajectory(of: .node(id), in: events, config: config)
    }

    // MARK: - Writing

    /// §5.1's `self-report` evidence, plus the implicit reviews it induces.
    ///
    /// Expansion happens here, at write time, because the log has to *contain* the
    /// implicit events for them to be auditable and replayable — if the fold
    /// derived them as well, every replay would double-count (D5.5).
    @discardableResult
    func record(_ confidence: SelfReportConfidence, on id: NodeID) -> Bool {
        guard !isReadOnly else {
            diagnostics.append("read-only run: refused to record a review on \(id)")
            return false
        }
        guard let node = graph[id], node.kind.isContent else {
            diagnostics.append("\(id) is not a learnable node")
            return false
        }

        let event = confidence.event(on: id, at: now)
        return append(Propagation.expanded(event, in: graph, config: config))
    }

    /// §5.2's evidence instrument: a graded problem.
    ///
    /// A **miss writes nothing** unless it has been localized (§5.4) — the caller
    /// runs `diagnosisChain` and offers the choice first. That is not a UI nicety:
    /// `Grading.evidence` returns an empty batch for an unlocalized miss, so an
    /// abandoned diagnosis leaves the log exactly as it was.
    @discardableResult
    func record(
        _ outcome: ProblemOutcome, on problem: Problem, localizedTo: NodeID? = nil
    ) -> Bool {
        guard !isReadOnly else {
            diagnostics.append("read-only run: refused to grade \(problem.id)")
            return false
        }
        let batch = Grading.evidence(
            for: problem, outcome: outcome, in: graph, at: now, localizedTo: localizedTo,
            config: config)
        guard !batch.isEmpty else { return false }
        return append(batch)
    }

    /// §5.4's retest flag made concrete: what a miss puts back in question.
    func diagnosisChain(after problem: Problem) -> [Diagnosis.Candidate] {
        Diagnosis.chain(
            after: problem, graph: graph, state: state, at: evaluatedAt, bank: bank, config: config)
    }

    /// The one write path. Append, then re-read and refold the whole log — never an
    /// incremental update (D6.5). Appended events can share a timestamp with
    /// existing ones and the fold's total order only holds over the whole log
    /// (D5.7), and making the UI path *be* the replay path is what collapses
    /// "relaunching reproduces identical colours" and "replaying the log reproduces
    /// identical scores" into one claim.
    @discardableResult
    func append(_ batch: [EvidenceEvent]) -> Bool {
        guard !isReadOnly else {
            diagnostics.append("read-only run: refused to append \(batch.count) events")
            return false
        }
        guard !batch.isEmpty else { return false }
        do {
            try log.append(batch)
        } catch {
            diagnostics.append("could not append to \(log.url.lastPathComponent): \(error)")
            return false
        }
        reload()
        return true
    }

    // MARK: - Clock

    private static func parseInstant(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // Bare dates are allowed because fixture logs are hand-authored and
        // `MATHTREE_NOW=2026-08-07` is what someone actually types.
        let normalized = trimmed.contains("T") ? trimmed : trimmed + "T00:00:00Z"
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt)
        let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false, timeZone: .gmt)
        return (try? withFraction.parse(normalized)) ?? (try? plain.parse(normalized))
    }
}
