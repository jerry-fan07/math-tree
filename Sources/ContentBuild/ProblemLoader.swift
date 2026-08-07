import Foundation
import GraphCore
import Yams

struct LoadedProblems: Sendable {
    var problems: [GraphCore.Problem]
    var locations: [ProblemID: SourceLocation]
    /// Ids that appeared in more than one place — the validator reports the
    /// duplication, this just records where else to look.
    var extraLocations: [(ProblemID, SourceLocation)]

    static let empty = LoadedProblems(problems: [], locations: [:], extraLocations: [])
}

/// Loads `problems/**/*.yaml`. Structurally the same as `ContentLoader` — one
/// top-level list per file, decode for values, compose for source marks — because
/// the bank is authored under the same rules as content and should fail the same
/// way.
enum ProblemLoader {
    private struct ProblemFile: Decodable {
        var problems: [GraphCore.Problem]
    }

    static func load(root: URL, relativeTo base: URL) throws -> LoadedProblems {
        // A missing directory is not an error: `problems/` is optional, and a
        // corpus with no bank still builds and runs (self-report remains the
        // fallback instrument, §5.4's "whenever possible").
        guard FileManager.default.fileExists(atPath: root.path) else { return .empty }

        var problems: [GraphCore.Problem] = []
        var locations: [ProblemID: SourceLocation] = [:]
        var extraLocations: [(ProblemID, SourceLocation)] = []

        for file in try ContentLoader.yamlFiles(in: root) {
            let text: String
            do {
                text = try String(contentsOf: file, encoding: .utf8)
            } catch {
                throw ContentLoadError.unreadable(path: file.path, underlying: error)
            }
            let relative = relativePath(of: file, to: base)

            do {
                let decoded = try YAMLDecoder().decode(ProblemFile.self, from: text)
                problems.append(contentsOf: decoded.problems)
            } catch let error as DecodingError {
                throw ContentLoadError.malformed(path: relative, message: describe(error))
            } catch {
                throw ContentLoadError.malformed(path: relative, message: "\(error)")
            }

            for (id, line) in try problemLines(in: text, path: relative) {
                let location = SourceLocation(file: relative, line: line)
                if locations[id] == nil {
                    locations[id] = location
                } else {
                    extraLocations.append((id, location))
                }
            }
        }

        return LoadedProblems(
            problems: problems, locations: locations, extraLocations: extraLocations)
    }

    /// Map each authored `id:` to its 1-based line, via Yams' composed tree.
    private static func problemLines(in text: String, path: String) throws -> [(ProblemID, Int)] {
        guard let root = try Yams.compose(yaml: text) else { return [] }
        guard let list = root.mapping?["problems"]?.sequence else {
            throw ContentLoadError.malformed(
                path: path, message: "expected a top-level `problems:` list")
        }
        var result: [(ProblemID, Int)] = []
        for entry in list {
            guard let mapping = entry.mapping else { continue }
            for (key, value) in mapping where key.string == "id" {
                if let id = value.string, let mark = key.mark {
                    result.append((ProblemID(id), mark.line))
                }
            }
        }
        return result
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            return "missing required field `\(key.stringValue)`\(pathSuffix(context))"
        case let .typeMismatch(type, context):
            return "field has the wrong type (expected \(type))\(pathSuffix(context))"
        case let .valueNotFound(type, context):
            return "missing value of type \(type)\(pathSuffix(context))"
        case let .dataCorrupted(context):
            return "\(context.debugDescription)\(pathSuffix(context))"
        @unknown default:
            return "\(error)"
        }
    }

    private static func pathSuffix(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }
            .joined()
        return path.isEmpty ? "" : " at \(path)"
    }

    private static func relativePath(of url: URL, to base: URL) -> String {
        let full = url.standardizedFileURL.path
        let prefix = base.standardizedFileURL.path + "/"
        return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full
    }
}
