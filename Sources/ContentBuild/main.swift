import Foundation
import GraphCore

// ContentBuild: YAML in, validated graph.json + deterministic layout out.
//
// Argument parsing is hand-rolled — three subcommands and four flags do not
// justify a dependency the plan didn't sanction (ground rule 3).

let usage = """
usage: ContentBuild <command> [options]

commands:
  validate    parse content/**.yaml and problems/**.yaml, run the GraphCore
              validators, report diagnostics with file/line context; non-zero
              exit on failure
  lint        validate, then report §7.1 authoring hints — heuristics about the
              things a validator cannot decide (atomicity above all). Advisory:
              exits 0 unless --strict
  build       validate, then compile to graph.json + problems.json
  layout      validate, then compute deterministic coordinates to layout.json
  shifu-sim   replay a Shifu evidence-event stream through §8.2's intake — the
              integration test double for Phase 10

options:
  --content <dir>    content root (default: ./content)
  --problems <dir>   problem-bank root (default: ./problems; optional on disk)
  --program <dir>    program root — program.yaml + lessons/ (§6.6; default:
                     ./program; optional on disk)
  --out <dir>        artifact directory (default: ./build/content)
  --seed <n>         layout PRNG seed (default: \(LayoutParameters().seed))
  --iterations <n>   layout iterations (default: \(LayoutParameters().iterations))
  --baseline <file>  a previously built graph.json; validate/lint then report what
                     this content did to the *graph*, and scope lint to the nodes
                     the change touched
  --diff-limit <n>   ids to list per diff section (default: 40)
  --strict           lint: exit non-zero on any hint
  --quiet            only report failures

shifu-sim options:
  --intake <dir>     drop-directory (default: ./build/shifu/intake)
  --log <file>       evidence log to append to (default: ./build/shifu/evidence.jsonl)
  --stream <file>    a document to drop; repeatable
                     (default: every *.json in ./\(ShifuSim.cannedStream))
  --drop-only        stage the documents and stop, without draining
"""

struct Options {
    var command = ""
    var contentRoot = URL(fileURLWithPath: "content")
    var problemRoot = URL(fileURLWithPath: "problems")
    var programRoot = URL(fileURLWithPath: "program")
    var outputDirectory = URL(fileURLWithPath: "build/content")
    var seed = LayoutParameters().seed
    var iterations = LayoutParameters().iterations
    var quiet = false
    var intakeRoot = URL(fileURLWithPath: "build/shifu/intake")
    var evidenceLog = URL(fileURLWithPath: "build/shifu/evidence.jsonl")
    var streams: [URL] = []
    var dropOnly = false
    var baseline: URL?
    var diffLimit = 40
    var strict = false
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first, !command.hasPrefix("-") else {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        exit(2)
    }
    options.command = command
    arguments.removeFirst()

    func value(_ flag: String) -> String {
        guard let next = arguments.first else {
            fail("\(flag) requires a value")
        }
        arguments.removeFirst()
        return next
    }

    while let flag = arguments.first {
        arguments.removeFirst()
        switch flag {
        case "--content": options.contentRoot = URL(fileURLWithPath: value(flag))
        case "--problems": options.problemRoot = URL(fileURLWithPath: value(flag))
        case "--program": options.programRoot = URL(fileURLWithPath: value(flag))
        case "--out": options.outputDirectory = URL(fileURLWithPath: value(flag))
        case "--seed":
            guard let seed = UInt64(value(flag)) else { fail("--seed must be an integer") }
            options.seed = seed
        case "--iterations":
            guard let iterations = Int(value(flag)), iterations > 0 else {
                fail("--iterations must be a positive integer")
            }
            options.iterations = iterations
        case "--baseline": options.baseline = URL(fileURLWithPath: value(flag))
        case "--diff-limit":
            guard let limit = Int(value(flag)), limit > 0 else {
                fail("--diff-limit must be a positive integer")
            }
            options.diffLimit = limit
        case "--strict": options.strict = true
        case "--intake": options.intakeRoot = URL(fileURLWithPath: value(flag))
        case "--log": options.evidenceLog = URL(fileURLWithPath: value(flag))
        case "--stream": options.streams.append(URL(fileURLWithPath: value(flag)))
        case "--drop-only": options.dropOnly = true
        case "--quiet": options.quiet = true
        case "-h", "--help":
            print(usage)
            exit(0)
        default: fail("unknown option \(flag)")
        }
    }
    return options
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(2)
}

func note(_ message: String, quiet: Bool) {
    if !quiet { print(message) }
}

/// Load + validate content and the problem bank. Returns both, or exits non-zero
/// having printed every diagnostic with the file and line it was authored on.
///
/// Content is validated first and the bank second, deliberately: the bank
/// references the graph, so its diagnostics are only meaningful over a graph that
/// already holds together. Both are reported in one pass when content is clean —
/// an author wants the whole list, not one violation per run.
func loadValidated(_ options: Options)
    -> (KnowledgeGraph, LoadedContent, ProblemBank, LoadedProblems, LoadedProgram)
{
    let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let content: LoadedContent
    do {
        content = try ContentLoader.load(root: options.contentRoot, relativeTo: workingDirectory)
    } catch {
        fail("\(error)")
    }

    guard !content.nodes.isEmpty else {
        fail("no nodes found under \(options.contentRoot.path)")
    }

    let graph = KnowledgeGraph(nodes: content.nodes)

    func report(_ diagnostics: [Diagnostic], scope: String, subjects: Int, noun: String) {
        for diagnostic in diagnostics {
            let where_ =
                diagnostic.problem.flatMap { problems.locations[$0] }?.display
                ?? diagnostic.subject.flatMap { content.locations[$0] }?.display
                ?? scope
            var line = "\(where_): [\(diagnostic.rule.rawValue)] \(diagnostic.message)"
            if let problem = diagnostic.problem {
                line += "\n    problem: \(problem.rawValue)"
            }
            if !diagnostic.nodes.isEmpty {
                line += "\n    nodes: \(diagnostic.nodes.map(\.rawValue).joined(separator: ", "))"
            }
            if !diagnostic.path.isEmpty {
                line += "\n    path:  \(diagnostic.path.map(\.rawValue).joined(separator: " → "))"
            }
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
        let count = diagnostics.count
        FileHandle.standardError.write(
            Data("\n\(count) violation\(count == 1 ? "" : "s") in \(subjects) \(noun)\n".utf8))
        exit(1)
    }

    // `problems` has to exist before `report` can reference its locations, but the
    // content diagnostics must be reported before the bank is even loaded — a
    // dangling target against a graph with a cycle is noise. Hence the empty
    // placeholder and the reassignment.
    var problems = LoadedProblems.empty

    let contentDiagnostics = GraphValidator.validate(graph)
    if !contentDiagnostics.isEmpty {
        report(contentDiagnostics, scope: "content", subjects: content.nodes.count, noun: "nodes")
    }

    do {
        problems = try ProblemLoader.load(root: options.problemRoot, relativeTo: workingDirectory)
    } catch {
        fail("\(error)")
    }

    let bank = ProblemBank(problems: problems.problems)
    let bankDiagnostics = ProblemValidator.validate(bank, against: graph)
    if !bankDiagnostics.isEmpty {
        report(bankDiagnostics, scope: "problems", subjects: bank.count, noun: "problems")
    }

    // The program (§6.6) is validated last, for the same reason the bank is
    // second: it references the graph, and a spine diagnostic against a graph
    // with a cycle is noise.
    let program: LoadedProgram
    do {
        program = try ProgramLoader.load(root: options.programRoot, relativeTo: workingDirectory)
    } catch {
        fail("\(error)")
    }
    if program.exists {
        let programDiagnostics = ProgramValidator.validate(program.program, against: graph)
        if !programDiagnostics.isEmpty {
            for diagnostic in programDiagnostics {
                let where_ = program.location(of: diagnostic)?.display ?? "program"
                var line = "\(where_): [\(diagnostic.rule.rawValue)] \(diagnostic.message)"
                if !diagnostic.nodes.isEmpty {
                    line +=
                        "\n    nodes: \(diagnostic.nodes.map(\.rawValue).joined(separator: ", "))"
                }
                FileHandle.standardError.write(Data((line + "\n").utf8))
            }
            let count = programDiagnostics.count
            let footer =
                "\n\(count) violation\(count == 1 ? "" : "s") in the program "
                + "(\(program.program.spine.units.count) units)\n"
            FileHandle.standardError.write(Data(footer.utf8))
            exit(1)
        }
    }

    return (graph, content, bank, problems, program)
}

/// One line saying how much of §6.6's program exists — printed by `validate` the
/// way subbranch and bank coverage are, because coverage grows batch by batch and
/// must be *seen* on every run rather than asserted once.
func programSummary(_ program: Program, graph: KnowledgeGraph) -> String {
    let units = program.spine.units
    var taught = 0
    var expected = 0
    var complete = 0
    for unit in units {
        let members = graph.children(of: unit).filter { graph[$0]?.kind.isContent == true }
        let lessons = program.lessonUnits[unit].map { unit in Set(unit.lessons.map(\.node)) } ?? []
        expected += members.count
        let covered = members.filter(lessons.contains).count
        taught += covered
        if !members.isEmpty, covered == members.count { complete += 1 }
    }
    return "program: \(units.count) units in \(program.spine.parts.count) parts, "
        + "lessons cover \(taught)/\(expected) content nodes "
        + "(\(complete)/\(units.count) units complete)"
}

let options = parseOptions()

switch options.command {
case "validate", "lint":
    let (graph, content, bank, _, program) = loadValidated(options)
    let contentNodes = graph.nodes.filter { $0.kind.isContent }
    let subbranches = graph.nodes.filter { $0.kind == .subbranch }
    let authored = subbranches.filter { subbranch in
        graph.containedChildren(of: subbranch.id).contains { graph[$0]?.kind.isContent == true }
    }
    note(
        "ok: \(graph.nodes.count) nodes, "
            + "\(graph.nodes.reduce(0) { $0 + $1.requires.count }) requires edges, "
            + "\(graph.relatesEdges.count) relates edges, "
            + "\(authored.count)/\(subbranches.count) subbranches authored, "
            + "\(bank.count) problems covering "
            + "\(contentNodes.filter { !bank.problems(targeting: $0.id).isEmpty }.count)"
            + "/\(contentNodes.count) content nodes",
        quiet: options.quiet)
    if program.exists {
        note(programSummary(program.program, graph: graph), quiet: options.quiet)
    }

    // The diff read-out, when a baseline was named. Printed for `validate` too:
    // "what did this do to the graph" is a review question, not a lint question.
    var touched: Set<NodeID>?
    if let baselineURL = options.baseline {
        do {
            let baseline = try GraphDiff.load(baselineURL)
            let diff = GraphDiff.compare(baseline: baseline, with: graph)
            touched = diff.touched
            print("")
            print("against \(baselineURL.path):")
            print(GraphDiff.report(diff, graph: graph, limit: options.diffLimit))
        } catch {
            fail("cannot read baseline \(baselineURL.path): \(error)")
        }
    }

    if options.command == "lint" {
        var hints = ContentLint.hints(for: graph)
        if program.exists {
            hints += ContentLint.hints(for: program.program, graph: graph)
        }
        if let touched {
            // Scoped to the change, so a review of one subbranch is not buried
            // under the corpus's standing hints. Branch- and subbranch-level hints
            // survive the filter when the change is inside them.
            let before = hints.count
            hints = hints.filter { hint in
                guard let subject = hint.subject else { return true }
                return touched.contains(subject)
                    || touched.contains { $0.rawValue.hasPrefix(subject.rawValue + ".") }
                    || hint.nodes.contains(where: touched.contains)
            }
            print("")
            print(
                "\(hints.count) hint(s) on what this change touched "
                    + "(\(before - hints.count) elsewhere in the corpus, not shown)")
        }

        // Lesson hints point into `lessons/`, everything else into `content/` —
        // a lesson's subject is a content node, so the *rule* has to pick.
        let lessonRules: Set<LintHint.Rule> = [
            .lessonMissingWorked, .thinLesson, .oversizedLesson,
        ]
        print("")
        for hint in hints {
            let where_ =
                hint.subject.flatMap {
                    lessonRules.contains(hint.rule)
                        ? program.lessonLocations[$0] : content.locations[$0]
                }?.display ?? "content"
            print("\(where_): \(hint.description)")
            if !hint.nodes.isEmpty {
                print("    nodes: \(hint.nodes.map(\.rawValue).joined(separator: ", "))")
            }
        }
        var byRule: [String: Int] = [:]
        for hint in hints { byRule[hint.rule.rawValue, default: 0] += 1 }
        print(
            hints.isEmpty
                ? "lint: no hints"
                : "lint: \(hints.count) hint(s) — "
                    + byRule.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
                        .joined(separator: ", "))
        print(
            "hints are advisory (§7.1: atomicity \"can't be fully automated\") — "
                + "a reviewer decides")
        if options.strict, !hints.isEmpty { exit(1) }
    }

case "build":
    let (graph, _, bank, _, program) = loadValidated(options)
    let url = options.outputDirectory.appendingPathComponent("graph.json")
    do {
        try Artifacts.write(GraphArtifact(graph), to: url)
    } catch {
        fail("cannot write \(url.path): \(error)")
    }
    note("wrote \(url.path) (\(graph.nodes.count) nodes)", quiet: options.quiet)

    // Always written, even when empty: the app distinguishes "no bank compiled"
    // from "a bank with no problems", and a stale artifact from a previous build
    // would silently answer the wrong one.
    let problemsURL = options.outputDirectory.appendingPathComponent("problems.json")
    do {
        try Artifacts.write(ProblemArtifact(bank), to: problemsURL)
    } catch {
        fail("cannot write \(problemsURL.path): \(error)")
    }
    note("wrote \(problemsURL.path) (\(bank.count) problems)", quiet: options.quiet)

    // Same rule as the bank: always written, even when no program is authored,
    // so a stale artifact cannot answer "is there a program?" wrongly.
    let programURL = options.outputDirectory.appendingPathComponent("program.json")
    do {
        try Artifacts.write(ProgramArtifact(program.program), to: programURL)
    } catch {
        fail("cannot write \(programURL.path): \(error)")
    }
    note(
        "wrote \(programURL.path) (\(program.program.spine.units.count) units, "
            + "\(program.program.lessonsByNode.count) lessons)",
        quiet: options.quiet)

case "layout":
    let (graph, _, _, _, _) = loadValidated(options)
    let order = graph.nodes.map(\.id).sorted()
    let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })

    var parameters = LayoutParameters()
    parameters.seed = options.seed
    parameters.iterations = options.iterations

    let result = Layout.compute(
        count: order.count,
        springs: Artifacts.springs(for: graph, index: index),
        clusters: Artifacts.clusters(for: graph, order: order),
        parameters: parameters)

    let artifact = LayoutArtifact(
        version: ContentFormat.version,
        seed: parameters.seed,
        iterations: parameters.iterations,
        positions: order.enumerated().map {
            LayoutArtifact.Position(id: $0.element, x: result.x[$0.offset], y: result.y[$0.offset])
        })

    let url = options.outputDirectory.appendingPathComponent("layout.json")
    do {
        try Artifacts.write(artifact, to: url)
    } catch {
        fail("cannot write \(url.path): \(error)")
    }
    note("wrote \(url.path) (\(order.count) positions, seed \(parameters.seed))", quiet: options.quiet)

case "shifu-sim":
    // Validated first, and against the real content: §8.2's contract is *about*
    // this graph, and "unknown-id events are rejected" is only a meaningful claim
    // when the set of known ids is the shipping one.
    let (graph, _, _, _, _) = loadValidated(options)

    var streams = options.streams
    if streams.isEmpty {
        let canned = URL(fileURLWithPath: ShifuSim.cannedStream)
        streams =
            ((try? FileManager.default.contentsOfDirectory(
                at: canned, includingPropertiesForKeys: nil, options: [])) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    exit(
        ShifuSim.run(
            .init(
                intake: options.intakeRoot, log: options.evidenceLog, streams: streams,
                dropOnly: options.dropOnly, quiet: options.quiet),
            graph: graph))

default:
    fail("unknown command \(options.command)\n\n\(usage)")
}
