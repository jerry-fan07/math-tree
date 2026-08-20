import Foundation
import GraphCore
import Yams

struct LoadedProgram: Sendable {
    var program: Program
    /// Where each spine unit was declared in `program.yaml`.
    var spineLocations: [NodeID: SourceLocation]
    /// Where each lesson (`node:`) and each unit file (`unit:`) was authored
    /// under `lessons/`.
    var lessonLocations: [NodeID: SourceLocation]
    /// Whether a `program.yaml` was found at all — a tree without one has no
    /// program, which is a state, not an error.
    var exists: Bool

    static let empty = LoadedProgram(
        program: Program(spine: ProgramSpine(parts: [])),
        spineLocations: [:], lessonLocations: [:], exists: false)

    /// The right place to send an author for one diagnostic: lesson rules point
    /// into `lessons/`, spine rules into `program.yaml`.
    func location(of diagnostic: Diagnostic) -> SourceLocation? {
        guard let subject = diagnostic.subject else { return nil }
        switch diagnostic.rule {
        case .lessonUnitNotInProgram, .lessonUnitMissingOpening, .lessonUnitIncomplete,
            .danglingLessonNode, .lessonNodeNotContent, .lessonNodeOutsideUnit,
            .duplicateLesson, .lessonMissingSection:
            return lessonLocations[subject] ?? spineLocations[subject]
        default:
            return spineLocations[subject] ?? lessonLocations[subject]
        }
    }
}

/// Loads a program root: `program.yaml` (the spine) plus `lessons/*.yaml` (one
/// file per unit). Structurally the same as `ContentLoader` and `ProblemLoader`
/// — decode for values, compose for source marks — because the program is
/// authored under the same rules as content and should fail the same way.
enum ProgramLoader {
    private struct SpineFile: Decodable {
        var parts: [ProgramSpine.Part]
    }

    private struct UnitFile: Decodable {
        var unit: NodeID
        var opening: String
        var lessons: [Lesson]
    }

    static func load(root: URL, relativeTo base: URL) throws -> LoadedProgram {
        // A missing directory or spine is not an error: the program is an
        // optional layer, and a tree without one still builds and runs.
        let spineURL = root.appendingPathComponent("program.yaml")
        guard FileManager.default.fileExists(atPath: spineURL.path) else { return .empty }

        let spineText: String
        do {
            spineText = try String(contentsOf: spineURL, encoding: .utf8)
        } catch {
            throw ContentLoadError.unreadable(path: spineURL.path, underlying: error)
        }
        let spinePath = relativePath(of: spineURL, to: base)

        let spine: ProgramSpine
        do {
            spine = ProgramSpine(
                parts: try YAMLDecoder().decode(SpineFile.self, from: spineText).parts)
        } catch let error as DecodingError {
            throw ContentLoadError.malformed(path: spinePath, message: describe(error))
        } catch {
            throw ContentLoadError.malformed(path: spinePath, message: "\(error)")
        }

        var spineLocations: [NodeID: SourceLocation] = [:]
        for (id, line) in try unitLines(in: spineText, path: spinePath) {
            if spineLocations[id] == nil {
                spineLocations[id] = SourceLocation(file: spinePath, line: line)
            }
        }

        var units: [LessonUnit] = []
        var lessonLocations: [NodeID: SourceLocation] = [:]
        let lessonsRoot = root.appendingPathComponent("lessons")
        if FileManager.default.fileExists(atPath: lessonsRoot.path) {
            for file in try ContentLoader.yamlFiles(in: lessonsRoot) {
                let text: String
                do {
                    text = try String(contentsOf: file, encoding: .utf8)
                } catch {
                    throw ContentLoadError.unreadable(path: file.path, underlying: error)
                }
                let relative = relativePath(of: file, to: base)

                do {
                    let decoded = try YAMLDecoder().decode(UnitFile.self, from: text)
                    units.append(
                        LessonUnit(
                            unit: decoded.unit, opening: decoded.opening,
                            lessons: decoded.lessons))
                } catch let error as DecodingError {
                    throw ContentLoadError.malformed(path: relative, message: describe(error))
                } catch {
                    throw ContentLoadError.malformed(path: relative, message: "\(error)")
                }

                for (id, line) in try lessonLines(in: text, path: relative)
                where lessonLocations[id] == nil {
                    lessonLocations[id] = SourceLocation(file: relative, line: line)
                }
            }
        }

        return LoadedProgram(
            program: Program(spine: spine, lessonUnits: units),
            spineLocations: spineLocations,
            lessonLocations: lessonLocations,
            exists: true)
    }

    /// Map each unit id in the spine to its 1-based line, via Yams' composed tree.
    private static func unitLines(in text: String, path: String) throws -> [(NodeID, Int)] {
        guard let root = try Yams.compose(yaml: text) else { return [] }
        guard let parts = root.mapping?["parts"]?.sequence else {
            throw ContentLoadError.malformed(
                path: path, message: "expected a top-level `parts:` list")
        }
        var result: [(NodeID, Int)] = []
        for part in parts {
            for unit in part.mapping?["units"]?.sequence ?? [] {
                if let id = unit.string, let mark = unit.mark {
                    result.append((NodeID(id), mark.line))
                }
            }
        }
        return result
    }

    /// Map the file's `unit:` id and each lesson's `node:` id to their lines.
    private static func lessonLines(in text: String, path: String) throws -> [(NodeID, Int)] {
        guard let root = try Yams.compose(yaml: text), let mapping = root.mapping else { return [] }
        var result: [(NodeID, Int)] = []
        for (key, value) in mapping where key.string == "unit" {
            if let id = value.string, let mark = key.mark {
                result.append((NodeID(id), mark.line))
            }
        }
        for entry in mapping["lessons"]?.sequence ?? [] {
            guard let lesson = entry.mapping else { continue }
            for (key, value) in lesson where key.string == "node" {
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
