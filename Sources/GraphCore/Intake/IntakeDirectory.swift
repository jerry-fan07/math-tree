import Foundation

/// §8.2's transport: a watched drop-directory.
///
/// The plan left the mechanism open between an XPC service, a local socket and a
/// watched directory, with the criteria "Shifu runs on the same machine, events
/// are small and append-only". A directory wins on all three and on a fourth the
/// plan did not name:
///
/// - **Same machine** makes a filesystem rendezvous sufficient; there is nothing
///   to route, authenticate or serialise a connection over.
/// - **Small and append-only** means there is no streaming, backpressure or
///   request/response shape for a socket to earn its keep with.
/// - **Neither process needs the other to be running.** XPC and sockets both
///   require both ends up at the same time; Shifu observes usage all day and the
///   map is open for minutes of it, so a live channel would silently drop
///   evidence exactly when the user is not looking at the map. A directory is a
///   queue that survives both processes.
/// - **It is inspectable and testable headlessly.** A document is a file: the
///   accepted and rejected piles can be read, diffed and replayed by hand, and
///   `ContentBuild shifu-sim` needs no IPC to stand in for Shifu.
///
/// ```
/// <Application Support>/MathTree/intake/
///   ├── 2026-08-08T09-15-00Z-session.json   ← Shifu drops documents here
///   ├── accepted/                            ← consumed, with a receipt
///   └── rejected/                            ← not consumed, with diagnostics
/// ```
///
/// **Writers must rename into place.** Only `*.json` directly in the root is
/// consumed, so a producer writes `name.json.part` and renames it to `name.json`
/// when complete. Without that, a drain can read half a document — and would
/// correctly reject it, losing the evidence for a reason that was nobody's fault.
public struct IntakeDirectory: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var acceptedDirectory: URL { root.appendingPathComponent("accepted", isDirectory: true) }
    public var rejectedDirectory: URL { root.appendingPathComponent("rejected", isDirectory: true) }

    /// `~/Library/Application Support/MathTree/intake`, beside the evidence log.
    public static func defaultURL(
        applicationSupport: URL? = nil, bundleName: String = "MathTree"
    ) throws -> URL {
        let base =
            try applicationSupport
            ?? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
        return base.appendingPathComponent(bundleName, isDirectory: true)
            .appendingPathComponent("intake", isDirectory: true)
    }

    /// Documents waiting to be consumed, oldest name first. Sorted by name rather
    /// than by mtime so a drain is reproducible: the events carry their own
    /// timestamps and the fold sorts them anyway, but the *report* should not
    /// depend on filesystem metadata.
    public func pending() throws -> [URL] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return [] }
        return try manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [])
            .filter { $0.pathExtension == "json" }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// One consumed document.
    public struct Outcome: Sendable {
        public var file: String
        public var report: ShifuIntake.Report
        /// Events actually written to the evidence log.
        public var appended: Int
        /// Where the document ended up, relative to the intake root.
        public var filedUnder: String
        /// Set when the document could not be read or moved at all.
        public var failure: String?
    }

    public struct DrainResult: Sendable {
        public var outcomes: [Outcome] = []
        /// Documents found in `accepted/` with no receipt: a previous drain was
        /// interrupted between filing and appending. Reported rather than
        /// re-ingested — see `drain`'s note on ordering.
        public var interrupted: [String] = []

        public var documents: Int { outcomes.count }
        public var appended: Int { outcomes.reduce(0) { $0 + $1.appended } }
        public var acceptedObservations: Int { outcomes.reduce(0) { $0 + $1.report.accepted } }
        public var rejectedObservations: Int { outcomes.reduce(0) { $0 + $1.report.rejected } }
        public var diagnostics: [String] {
            outcomes.flatMap { outcome in
                outcome.report.diagnostics.map { "\(outcome.file) \($0.description)" }
                    + (outcome.failure.map { ["\(outcome.file): \($0)"] } ?? [])
            }
        }

        /// One line for a CLI or the app's diagnostics list.
        public var summary: String {
            "\(documents) document\(documents == 1 ? "" : "s"), "
                + "\(acceptedObservations) observation\(acceptedObservations == 1 ? "" : "s") accepted, "
                + "\(rejectedObservations) rejected, \(appended) event\(appended == 1 ? "" : "s") appended"
        }
    }

    /// Consume everything waiting, appending accepted evidence to `log`.
    ///
    /// Never throws for a bad document — that is what the diagnostics are for.
    /// Throws only when the directory itself cannot be worked with.
    ///
    /// **Ordering: file, then append, then write the receipt.** The alternative
    /// (append first, move second) turns a crash in the window into a document
    /// ingested twice, and two identical observations at one instant compound the
    /// same way D8.2 found multi-target grading compounding — silently, with no
    /// way to notice afterwards. Filing first makes the crash lose at most one
    /// document, which Shifu can re-emit and which is low-confidence evidence
    /// anyway. The receipt is what keeps that loss from being *silent*: a document
    /// in `accepted/` with no `.receipt.txt` beside it is precisely an interrupted
    /// ingest, and the next drain reports it.
    @discardableResult
    public func drain(
        graph: KnowledgeGraph,
        log: EvidenceLog,
        header: EvidenceLogHeader = .init()
    ) throws -> DrainResult {
        var result = DrainResult()
        let manager = FileManager.default
        let waiting = try pending()
        result.interrupted = try interruptedIngests()
        guard !waiting.isEmpty else { return result }

        try manager.createDirectory(at: acceptedDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: rejectedDirectory, withIntermediateDirectories: true)

        for url in waiting {
            let name = url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else {
                result.outcomes.append(
                    Outcome(
                        file: name, report: .init(events: [], diagnostics: [], accepted: 0,
                        rejected: 0, isMalformed: true), appended: 0, filedUnder: ".",
                        failure: "could not be read"))
                continue
            }

            let report = ShifuIntake.parse(data, graph: graph)
            let usable = !report.isMalformed && !report.events.isEmpty
            let destination = (usable ? acceptedDirectory : rejectedDirectory)
                .appendingPathComponent(name)

            var failure: String?
            do {
                try replace(url, with: destination)
            } catch {
                failure = "could not be filed: \(error.localizedDescription)"
            }

            var appended = 0
            if usable, failure == nil {
                do {
                    appended = try log.append(report.events, header: header)
                } catch {
                    failure = "filed but not appended: \(error.localizedDescription)"
                }
            }

            writeReceipt(
                for: name, at: destination, report: report, appended: appended, failure: failure)

            result.outcomes.append(
                Outcome(
                    file: name, report: report, appended: appended,
                    filedUnder: usable ? "accepted" : "rejected", failure: failure))
        }
        return result
    }

    // MARK: - Filing

    private func replace(_ source: URL, with destination: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: source, to: destination)
    }

    private func receiptURL(for destination: URL) -> URL {
        destination.deletingPathExtension().appendingPathExtension("receipt.txt")
    }

    private func writeReceipt(
        for name: String, at destination: URL, report: ShifuIntake.Report, appended: Int,
        failure: String?
    ) {
        var lines = [
            "document: \(name)",
            "schema:   v\(ShifuIntake.schema)",
            "accepted: \(report.accepted) observation(s)",
            "rejected: \(report.rejected) observation(s)",
            "appended: \(appended) evidence event(s)",
        ]
        if let failure { lines.append("failure:  \(failure)") }
        if !report.diagnostics.isEmpty {
            lines.append("")
            lines += report.diagnostics.map { "  " + $0.description }
        }
        try? (lines.joined(separator: "\n") + "\n").write(
            to: receiptURL(for: destination), atomically: true, encoding: .utf8)
    }

    /// Documents in `accepted/` whose receipt is missing — see `drain`'s ordering
    /// note. Never re-ingested automatically: re-reading them risks the double
    /// count the ordering exists to prevent, and a human can tell in one look.
    private func interruptedIngests() throws -> [String] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: acceptedDirectory.path) else { return [] }
        return try manager.contentsOfDirectory(
            at: acceptedDirectory, includingPropertiesForKeys: nil, options: [])
            .filter { $0.pathExtension == "json" }
            .filter { !manager.fileExists(atPath: receiptURL(for: $0).path) }
            .map(\.lastPathComponent)
            .sorted()
    }
}
