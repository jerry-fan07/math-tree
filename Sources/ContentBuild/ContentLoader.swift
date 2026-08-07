import Foundation
import GraphCore
import Yams

/// Where an authored node came from, so validator diagnostics can point at a
/// file and line instead of just an id.
struct SourceLocation: Sendable {
    var file: String
    var line: Int

    var display: String { "\(file):\(line)" }
}

struct LoadedContent: Sendable {
    var nodes: [GraphCore.Node]
    var locations: [NodeID: SourceLocation]
    /// Ids that appeared in more than one place — the validator reports the
    /// duplication, this just records where else to look.
    var extraLocations: [(NodeID, SourceLocation)]
}

enum ContentLoadError: Error, CustomStringConvertible {
    case unreadable(path: String, underlying: any Error)
    case malformed(path: String, message: String)

    var description: String {
        switch self {
        case let .unreadable(path, underlying):
            return "\(path): cannot read — \(underlying)"
        case let .malformed(path, message):
            return "\(path): \(message)"
        }
    }
}

enum ContentLoader {
    /// Every `content/**/*.yaml` file is the same shape: a single `nodes:` list
    /// (see content/README.md). Directory names are organizational only.
    private struct NodeFile: Decodable {
        var nodes: [GraphCore.Node]
    }

    static func yamlFiles(in root: URL) throws -> [URL] {
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else {
            throw ContentLoadError.unreadable(
                path: root.path,
                underlying: CocoaError(.fileReadNoSuchFile))
        }
        var files: [URL] = []
        for case let url as URL in walker where url.pathExtension == "yaml" {
            files.append(url)
        }
        // Sorted so the build is byte-stable regardless of directory order.
        return files.sorted { $0.path < $1.path }
    }

    static func load(root: URL, relativeTo base: URL) throws -> LoadedContent {
        var nodes: [GraphCore.Node] = []
        var locations: [NodeID: SourceLocation] = [:]
        var extraLocations: [(NodeID, SourceLocation)] = []

        for file in try yamlFiles(in: root) {
            let text: String
            do {
                text = try String(contentsOf: file, encoding: .utf8)
            } catch {
                throw ContentLoadError.unreadable(path: file.path, underlying: error)
            }
            let relative = relativePath(of: file, to: base)

            do {
                let decoded = try YAMLDecoder().decode(NodeFile.self, from: text)
                nodes.append(contentsOf: decoded.nodes)
            } catch let error as DecodingError {
                throw ContentLoadError.malformed(
                    path: relative, message: describe(error))
            } catch {
                throw ContentLoadError.malformed(
                    path: relative, message: "\(error)")
            }

            // Decoding gives values; composing gives source marks. Two passes
            // over the same text is cheap and keeps the decode path standard.
            for (id, line) in try nodeLines(in: text, path: relative) {
                let location = SourceLocation(file: relative, line: line)
                if locations[id] == nil {
                    locations[id] = location
                } else {
                    extraLocations.append((id, location))
                }
            }
        }

        return LoadedContent(
            nodes: nodes, locations: locations, extraLocations: extraLocations)
    }

    /// Map each authored `id:` to its 1-based line, via Yams' composed tree.
    private static func nodeLines(in text: String, path: String) throws -> [(NodeID, Int)] {
        guard let root = try Yams.compose(yaml: text) else { return [] }
        guard let list = root.mapping?["nodes"]?.sequence else {
            throw ContentLoadError.malformed(
                path: path, message: "expected a top-level `nodes:` list")
        }
        var result: [(NodeID, Int)] = []
        for entry in list {
            guard let mapping = entry.mapping else { continue }
            // The mark of the `id` *key* is the line a reader would jump to.
            for (key, value) in mapping
            where key.string == "id" {
                if let id = value.string, let mark = key.mark {
                    result.append((NodeID(id), mark.line))
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
