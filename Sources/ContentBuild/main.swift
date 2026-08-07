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
  build       validate, then compile to graph.json + problems.json
  layout      validate, then compute deterministic coordinates to layout.json

options:
  --content <dir>    content root (default: ./content)
  --problems <dir>   problem-bank root (default: ./problems; optional on disk)
  --out <dir>        artifact directory (default: ./build/content)
  --seed <n>         layout PRNG seed (default: \(LayoutParameters().seed))
  --iterations <n>   layout iterations (default: \(LayoutParameters().iterations))
  --quiet            only report failures
"""

struct Options {
    var command = ""
    var contentRoot = URL(fileURLWithPath: "content")
    var problemRoot = URL(fileURLWithPath: "problems")
    var outputDirectory = URL(fileURLWithPath: "build/content")
    var seed = LayoutParameters().seed
    var iterations = LayoutParameters().iterations
    var quiet = false
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
        case "--out": options.outputDirectory = URL(fileURLWithPath: value(flag))
        case "--seed":
            guard let seed = UInt64(value(flag)) else { fail("--seed must be an integer") }
            options.seed = seed
        case "--iterations":
            guard let iterations = Int(value(flag)), iterations > 0 else {
                fail("--iterations must be a positive integer")
            }
            options.iterations = iterations
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
func loadValidated(_ options: Options) -> (KnowledgeGraph, LoadedContent, ProblemBank, LoadedProblems)
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

    return (graph, content, bank, problems)
}

let options = parseOptions()

switch options.command {
case "validate":
    let (graph, _, bank, _) = loadValidated(options)
    let content = graph.nodes.filter { $0.kind.isContent }
    note(
        "ok: \(graph.nodes.count) nodes, "
            + "\(graph.nodes.reduce(0) { $0 + $1.requires.count }) requires edges, "
            + "\(graph.relatesEdges.count) relates edges, "
            + "\(bank.count) problems covering "
            + "\(content.filter { !bank.problems(targeting: $0.id).isEmpty }.count)"
            + "/\(content.count) content nodes",
        quiet: options.quiet)

case "build":
    let (graph, _, bank, _) = loadValidated(options)
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

case "layout":
    let (graph, _, _, _) = loadValidated(options)
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

default:
    fail("unknown command \(options.command)\n\n\(usage)")
}
