import Foundation
import GraphCore
import Observation

/// §5.3's placement session, persisted so it is resumable.
///
/// The session is not the evidence. Every probe writes its own graded evidence to
/// the log the moment it is answered — that is a real measurement and belongs
/// there whether or not the session is ever finished. What lives here is the
/// *probing state*: the claimed frontier and the ordered answers, which is
/// everything `Placement.belief` needs to reconstruct where the session had got
/// to. Losing this file costs the user their place in the questionnaire, never
/// their knowledge state.
///
/// It follows the same discipline as `ScoreStore`, for the same reasons:
///
/// - `MATHTREE_PLACEMENT` redirects the file, like `MATHTREE_EVIDENCE_LOG`.
/// - `--probe`, `--smoke-test` and snapshot runs are **read-only**. A verification
///   run that started a placement session would write into the developer's own
///   state and stop being repeatable (D6.6).
/// - Every timestamp comes from `ScoreStore.now`, so `MATHTREE_NOW` pins probe
///   answers exactly as it pins reviews. A `Date()` here would make a pinned run
///   non-reproducible in a way nothing else would catch.
@MainActor
@Observable
final class PlacementStore {
    private let scores: ScoreStore
    private let bank: ProblemBank
    private let config: PlacementConfig
    let url: URL?

    private(set) var session: PlacementSession?
    private(set) var diagnostics: [String] = []

    var isReadOnly: Bool { scores.isReadOnly }
    var isActive: Bool { session != nil && !(session?.isCommitted ?? true) }
    var canPlace: Bool { !bank.isEmpty }

    init(
        scores: ScoreStore,
        bank: ProblemBank,
        config: PlacementConfig = PlacementConfig(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.scores = scores
        self.bank = bank
        self.config = config

        if let override = environment["MATHTREE_PLACEMENT"], !override.isEmpty {
            url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        } else if let base = try? EvidenceLog.defaultURL() {
            url = base.deletingLastPathComponent().appendingPathComponent("placement.json")
        } else {
            url = nil
        }
        load()
    }

    // MARK: - Reading

    var belief: Placement.Belief? {
        session.map { Placement.belief(for: $0, graph: scores.graph, bank: bank, config: config) }
    }

    var progress: Placement.Progress? {
        session.map { Placement.progress(for: $0, graph: scores.graph, bank: bank, config: config) }
    }

    /// The question to ask next, or `nil` when the session has converged.
    var nextProbe: (node: NodeID, problem: Problem)? {
        guard let session, !session.isCommitted else { return nil }
        return Placement.nextProbe(
            for: session, graph: scores.graph, bank: bank, config: config)
    }

    // MARK: - Writing

    /// §5.3 step 1. Claims may name subbranches — "finished single-variable
    /// calculus" is `analysis.svc` — and an empty claim is legal: placement then
    /// starts from the uniform prior, which is slower but not wrong.
    func start(claiming claimed: [NodeID]) {
        guard !isReadOnly else {
            diagnostics.append("read-only run: refused to start placement")
            return
        }
        session = PlacementSession(seed: PlacementSeed(claimed: claimed))
        save()
    }

    /// Record one answered probe: its evidence to the log, its answer to the
    /// session. Evidence first — if the process dies between the two, the
    /// measurement survives and only the questionnaire's place is lost.
    ///
    /// A miss with no `localizedTo` writes no evidence at all (§5.4) but *is*
    /// recorded in the session, and the belief treats the probed node itself as the
    /// failure — the user was asked, said they could not do it, and named nowhere
    /// else. That is a measurement of the probed node, so the two disagree by
    /// construction: the belief knows something the log does not.
    ///
    /// The UI cannot currently produce this — `ProblemSheet` opens the diagnosis
    /// chain on a miss and only calls back once a candidate is chosen — but the
    /// API can, so it is stated rather than assumed away. Closing that gap means
    /// writing the `again` on the probed node when nothing is localized, which is
    /// §5.4's "the failure evidence lands on the localized node" read the other
    /// way; it waits for a UI that can actually reach the state.
    func record(
        _ outcome: ProblemOutcome, on problem: Problem, node: NodeID, localizedTo: NodeID? = nil
    ) {
        guard !isReadOnly else {
            diagnostics.append("read-only run: refused to record a probe")
            return
        }
        guard session != nil else { return }
        scores.record(outcome, on: problem, localizedTo: localizedTo)
        session?.record(
            ProbeAnswer(
                problem: problem.id, node: node, outcome: outcome, at: scores.now,
                localizedTo: localizedTo))
        save()
    }

    /// §5.3's third clause: commit the untested-but-inferred knowledge as
    /// low-confidence evidence. Idempotent — `committedAt` is what stops a resumed
    /// session from committing twice, and it is set here and nowhere else.
    @discardableResult
    func commit() -> Int {
        guard !isReadOnly, var current = session, !current.isCommitted else { return 0 }
        let events = Placement.inferredEvidence(
            for: current, graph: scores.graph, bank: bank, at: scores.now, config: config)
        // Stamp the session before appending: a commit that wrote evidence and then
        // failed to record that it had would double-count on the next launch, which
        // is the one failure mode worth being asymmetric about.
        current.committedAt = scores.now
        session = current
        save()
        if !events.isEmpty { scores.append(events) }
        return events.count
    }

    /// Abandon the questionnaire. The evidence the answered probes produced stays —
    /// it was measured.
    func discard() {
        guard !isReadOnly else { return }
        session = nil
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Persistence

    private func load() {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            session = try decoder.decode(PlacementSession.self, from: Data(contentsOf: url))
        } catch {
            // A corrupt session is not worth a crash and not worth silence: the
            // evidence it produced is in the log regardless.
            diagnostics.append("could not read \(url.lastPathComponent): \(error)")
        }
    }

    private func save() {
        guard !isReadOnly, let url, let session else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(session).write(to: url, options: .atomic)
        } catch {
            diagnostics.append("could not write \(url.lastPathComponent): \(error)")
        }
    }
}
