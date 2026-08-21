import Foundation

/// Enforces §6.6's program invariants against an already-loaded graph.
///
/// Same shape and contract as `GraphValidator` and `ProblemValidator`: never
/// throws, never stops at the first finding, emits typed `Diagnostic`s so
/// `ContentBuild` can annotate them with file and line. The program is content —
/// authored, reviewed, gated in CI by the same step.
///
/// Two severities live in one validator, split by *scope* rather than by taste:
///
/// - **Spine rules and per-file lesson rules are errors.** The spine must cover
///   the tree and be a linear extension of cross-unit `requires` — the property
///   `ProgramPlan`'s per-unit ordering silently depends on. A lessons file that
///   *exists* must be internally whole: every node of its unit taught, no
///   foreign or unknown nodes, required sections present. That per-file
///   granularity is what catches a generation batch's omissions at the batch
///   boundary.
/// - **Corpus-wide lesson coverage is not a rule at all.** Most units have no
///   lessons file while the corpus is being written, exactly as most subbranches
///   had no problems while the bank grew (D9.4) — `ContentBuild` *reports*
///   coverage on every run instead.
public enum ProgramValidator {
    public static func validate(_ program: Program, against graph: KnowledgeGraph) -> [Diagnostic] {
        var out: [Diagnostic] = []
        out += spineChecks(program.spine, graph: graph)
        out += orderChecks(program.spine, graph: graph)
        for unit in program.lessonUnits.values.sorted(by: { $0.unit < $1.unit }) {
            out += lessonChecks(unit, spine: program.spine, graph: graph)
        }
        out.sort()
        return out
    }

    // MARK: - Spine

    private static func spineChecks(_ spine: ProgramSpine, graph: KnowledgeGraph) -> [Diagnostic] {
        var out: [Diagnostic] = []

        for part in spine.parts where part.title.trimmed.isEmpty {
            out.append(
                Diagnostic(
                    rule: .emptyProgramPartTitle,
                    message: "a program part holding \(part.units.count) unit(s) has no title",
                    nodes: part.units))
        }

        var counts: [NodeID: Int] = [:]
        for unit in spine.units { counts[unit, default: 0] += 1 }
        for (unit, count) in counts.sorted(by: { $0.key < $1.key }) where count > 1 {
            out.append(
                Diagnostic(
                    rule: .duplicateProgramUnit,
                    message: "the program lists unit `\(unit)` \(count) times; a unit is one chapter",
                    nodes: [unit]))
        }

        for unit in spine.units {
            guard let node = graph[unit] else {
                out.append(
                    Diagnostic(
                        rule: .danglingProgramUnit,
                        message: "the program lists `\(unit)`, which is not in the graph",
                        nodes: [unit]))
                continue
            }
            if node.kind != .subbranch {
                out.append(
                    Diagnostic(
                        rule: .programUnitNotSubbranch,
                        message:
                            "the program lists `\(unit)`, which is a \(node.kind.rawValue) — "
                            + "units are subbranches",
                        nodes: [unit]))
            }
        }

        // The spine covers the *whole* tree, empty subbranches included: an
        // outlined-but-unwritten unit renders as exactly that, and a subbranch
        // the program forgot would otherwise be silently untaught forever.
        let listed = Set(spine.units)
        for node in graph.nodes where node.kind == .subbranch && !listed.contains(node.id) {
            out.append(
                Diagnostic(
                    rule: .programMissingSubbranch,
                    message: "subbranch `\(node.id)` is not in the program; every subbranch is a unit",
                    nodes: [node.id]))
        }

        return out
    }

    /// The load-bearing rule: no node may require a node whose unit comes later
    /// in the program. This is what makes each unit a self-contained chapter —
    /// `ProgramPlan` orders a unit by its *own* edges only, which is complete
    /// precisely because precedence can never arrive from the future.
    private static func orderChecks(_ spine: ProgramSpine, graph: KnowledgeGraph) -> [Diagnostic] {
        let position = Dictionary(
            spine.units.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first })

        func unitPosition(of node: Node) -> (unit: NodeID, position: Int)? {
            guard let parent = node.parent else { return nil }
            return position[parent].map { (parent, $0) }
        }

        var out: [Diagnostic] = []
        for node in graph.nodes where node.kind.isContent {
            guard let home = unitPosition(of: node) else { continue }
            for prerequisite in node.requires {
                guard let required = graph[prerequisite],
                    let away = unitPosition(of: required),
                    away.position > home.position
                else { continue }
                out.append(
                    Diagnostic(
                        rule: .programOrderViolation,
                        message:
                            "`\(node.id)` (unit \(home.position + 1), `\(home.unit)`) requires "
                            + "`\(prerequisite)` (unit \(away.position + 1), `\(away.unit)`) — "
                            + "the program order must be a linear extension of cross-unit requires",
                        nodes: [node.id, prerequisite],
                        path: [home.unit, away.unit]))
            }
        }
        return out
    }

    // MARK: - Lessons

    private static func lessonChecks(
        _ unit: LessonUnit, spine: ProgramSpine, graph: KnowledgeGraph
    ) -> [Diagnostic] {
        var out: [Diagnostic] = []

        func report(_ rule: DiagnosticRule, _ message: String, nodes: [NodeID]) {
            out.append(Diagnostic(rule: rule, message: message, nodes: nodes))
        }

        if !spine.units.contains(unit.unit) {
            report(
                .lessonUnitNotInProgram,
                "lessons are authored for `\(unit.unit)`, which is not a unit of the program",
                nodes: [unit.unit])
        }

        if unit.opening.trimmed.isEmpty {
            report(
                .lessonUnitMissingOpening,
                "unit `\(unit.unit)` has no opening — a chapter starts with a paragraph",
                nodes: [unit.unit])
        }

        var counts: [NodeID: Int] = [:]
        for lesson in unit.lessons { counts[lesson.node, default: 0] += 1 }
        for (node, count) in counts.sorted(by: { $0.key < $1.key }) where count > 1 {
            report(
                .duplicateLesson,
                "unit `\(unit.unit)` teaches `\(node)` \(count) times",
                nodes: [node, unit.unit])
        }

        // Membership is by *primary* parent: the program teaches each node once,
        // in its home unit; a cross-listed node is taught where it lives.
        for lesson in unit.lessons {
            guard let node = graph[lesson.node] else {
                report(
                    .danglingLessonNode,
                    "unit `\(unit.unit)` has a lesson for `\(lesson.node)`, which is not in the graph",
                    nodes: [lesson.node, unit.unit])
                continue
            }
            if !node.kind.isContent {
                report(
                    .lessonNodeNotContent,
                    "unit `\(unit.unit)` has a lesson for `\(lesson.node)`, which is a "
                        + "\(node.kind.rawValue) — only content nodes are taught (§2.1)",
                    nodes: [lesson.node, unit.unit])
            } else if node.parent != unit.unit {
                report(
                    .lessonNodeOutsideUnit,
                    "unit `\(unit.unit)` has a lesson for `\(lesson.node)`, whose home unit is "
                        + "`\(node.parent?.rawValue ?? "—")` — a node is taught once, where it lives",
                    nodes: [lesson.node, unit.unit])
            }

            for (section, text) in [
                ("hook", lesson.hook), ("explanation", lesson.explanation), ("recap", lesson.recap),
            ] where text.trimmed.isEmpty {
                report(
                    .lessonMissingSection,
                    "lesson `\(lesson.node)` has an empty `\(section)` — "
                        + "hook, explanation and recap are required",
                    nodes: [lesson.node, unit.unit])
            }
        }

        // A file that exists teaches its whole unit — the per-file granularity
        // that catches a generation batch's omissions at the batch boundary.
        let taught = Set(unit.lessons.map(\.node))
        let expected = graph.children(of: unit.unit)
            .filter { graph[$0]?.kind.isContent == true }
        let missing = expected.filter { !taught.contains($0) }.sorted()
        if !missing.isEmpty {
            report(
                .lessonUnitIncomplete,
                "unit `\(unit.unit)` has lessons but misses \(missing.count) of its "
                    + "\(expected.count) node(s)",
                nodes: [unit.unit] + missing)
        }

        return out
    }
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
