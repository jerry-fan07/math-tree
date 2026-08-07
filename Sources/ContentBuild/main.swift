import Foundation
import GraphCore

// ContentBuild: YAML in, validated graph.json + deterministic layout out.
//
// Argument parsing is hand-rolled — three subcommands and four flags do not
// justify a dependency the plan didn't sanction (ground rule 3).

let usage = """
usage: ContentBuild <command> [options]

commands:
  validate    parse content/**.yaml, run the GraphCore validator, report
              diagnostics with file/line context; non-zero exit on failure
  build       validate, then compile to graph.json
  layout      validate, then compute deterministic coordinates to layout.json

options:
  --content <dir>    content root (default: ./content)
  --out <dir>        artifact directory (default: ./build/content)
  --seed <n>         layout PRNG seed (default: \(LayoutParameters().seed))
  --iterations <n>   layout iterations (default: \(LayoutParameters().iterations))
  --quiet            only report failures
"""

struct Options {
    var command = ""
    var contentRoot = URL(fileURLWithPath: "content")
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

/// Load + validate. Returns the graph, or exits non-zero having printed every
/// diagnostic with the file and line the offending node was authored on.
func loadValidated(_ options: Options) -> (KnowledgeGraph, LoadedContent) {
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
    let diagnostics = GraphValidator.validate(graph)

    guard diagnostics.isEmpty else {
        for diagnostic in diagnostics {
            let where_ = diagnostic.subject.flatMap { content.locations[$0] }?.display ?? "content"
            var line = "\(where_): [\(diagnostic.rule.rawValue)] \(diagnostic.message)"
            line += "\n    nodes: \(diagnostic.nodes.map(\.rawValue).joined(separator: ", "))"
            if !diagnostic.path.isEmpty {
                line += "\n    path:  \(diagnostic.path.map(\.rawValue).joined(separator: " → "))"
            }
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
        let count = diagnostics.count
        FileHandle.standardError.write(
            Data("\n\(count) violation\(count == 1 ? "" : "s") in \(content.nodes.count) nodes\n".utf8))
        exit(1)
    }

    return (graph, content)
}

let options = parseOptions()

switch options.command {
case "validate":
    let (graph, _) = loadValidated(options)
    note(
        "ok: \(graph.nodes.count) nodes, "
            + "\(graph.nodes.reduce(0) { $0 + $1.requires.count }) requires edges, "
            + "\(graph.relatesEdges.count) relates edges",
        quiet: options.quiet)

case "build":
    let (graph, _) = loadValidated(options)
    let url = options.outputDirectory.appendingPathComponent("graph.json")
    do {
        try Artifacts.write(GraphArtifact(graph), to: url)
    } catch {
        fail("cannot write \(url.path): \(error)")
    }
    note("wrote \(url.path) (\(graph.nodes.count) nodes)", quiet: options.quiet)

case "layout":
    let (graph, _) = loadValidated(options)
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
