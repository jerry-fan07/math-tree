import Foundation
import GraphCore

/// Phase 10's integration test double: everything Shifu would do, minus Shifu.
///
/// The phase has to complete without the other program existing, and §8.2 says the
/// boundary is a data contract — so the honest stand-in is something that produces
/// documents in the contract's format and drops them where Shifu would. It shares
/// no code with the intake beyond the wire format itself, which is the point: if
/// `ShifuIntake` and this disagree, the contract is what is wrong.
enum ShifuSim {

    struct Settings {
        var intake: URL
        var log: URL
        var streams: [URL]
        var dropOnly: Bool
        var quiet: Bool
    }

    /// Documents shipped in the repo as the canned stream. Authored rather than
    /// generated so the rejection cases are *reviewable*: a generator that emits
    /// its own bad input tends to emit only the badness it was written to expect.
    static let cannedStream = "fixtures/shifu"

    static func run(_ settings: Settings, graph: KnowledgeGraph) -> Int32 {
        let manager = FileManager.default
        let directory = IntakeDirectory(root: settings.intake)

        do {
            try manager.createDirectory(at: settings.intake, withIntermediateDirectories: true)
        } catch {
            report("cannot create intake directory \(settings.intake.path): \(error)")
            return 2
        }

        guard !settings.streams.isEmpty else {
            report("no documents to replay — pass --stream, or run from a repo with \(cannedStream)/")
            return 2
        }

        // Drop the documents in, exactly as Shifu would: never written in place
        // under their final name (a drain could read a half-written file), always
        // renamed into it.
        for source in settings.streams {
            let staged = settings.intake.appendingPathComponent(
                source.lastPathComponent + ".part")
            let final = settings.intake.appendingPathComponent(source.lastPathComponent)
            do {
                if manager.fileExists(atPath: staged.path) { try manager.removeItem(at: staged) }
                if manager.fileExists(atPath: final.path) { try manager.removeItem(at: final) }
                try manager.copyItem(at: source, to: staged)
                try manager.moveItem(at: staged, to: final)
            } catch {
                report("cannot stage \(source.lastPathComponent): \(error)")
                return 2
            }
        }
        note("dropped \(settings.streams.count) document(s) into \(settings.intake.path)",
            quiet: settings.quiet)

        if settings.dropOnly { return 0 }

        let log = EvidenceLog(url: settings.log)
        let before = (try? log.read())?.events.count ?? 0

        let result: IntakeDirectory.DrainResult
        do {
            result = try directory.drain(graph: graph, log: log)
        } catch {
            report("intake failed: \(error)")
            return 2
        }

        for outcome in result.outcomes {
            let verdict =
                outcome.failure.map { "FAILED (\($0))" }
                ?? "\(outcome.filedUnder) — \(outcome.report.accepted) accepted, "
                    + "\(outcome.report.rejected) rejected, \(outcome.appended) event(s) appended"
            print("\(outcome.file): \(verdict)")
            for diagnostic in outcome.report.diagnostics {
                let mark = diagnostic.severity == .error ? "  reject " : "  note   "
                print("\(mark)\(diagnostic.description)")
            }
        }
        for name in result.interrupted {
            print("interrupted ingest, not re-read: accepted/\(name)")
        }

        let after = (try? log.read())?.events.count ?? 0
        print(result.summary)
        print("evidence log \(settings.log.path): \(before) -> \(after) events")

        // A canned stream that produced nothing is a broken test double, not a
        // clean run: the whole point is that something reaches the log.
        return result.appended > 0 ? 0 : 1
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }

    private static func note(_ message: String, quiet: Bool) {
        if !quiet { print(message) }
    }
}
