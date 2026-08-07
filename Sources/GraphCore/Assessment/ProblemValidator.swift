import Foundation

/// Enforces the problem-bank invariants of §5.2 against an already-loaded graph.
///
/// Same shape and the same contract as `GraphValidator`: never throws, never stops
/// at the first problem, emits typed `Diagnostic`s so `ContentBuild` can annotate
/// them with file and line. A problem is content — authored, reviewed, gated in CI
/// by the same step — so it gets the same treatment rather than a softer one.
///
/// The bank is validated *against* the graph, which is why this cannot live in the
/// graph validator: a dangling target is a fact about the pair, and running it on
/// a broken graph would report noise. `ContentBuild` validates content first.
public enum ProblemValidator {
    public static func validate(problems: [Problem], against graph: KnowledgeGraph) -> [Diagnostic] {
        validate(ProblemBank(problems: problems), against: graph)
    }

    public static func validate(_ bank: ProblemBank, against graph: KnowledgeGraph) -> [Diagnostic] {
        var out: [Diagnostic] = []
        out += duplicateIDs(bank)
        for problem in bank.problems {
            out += checks(problem, graph: graph)
        }
        out.sort()
        return out
    }

    // MARK: Identity

    private static func duplicateIDs(_ bank: ProblemBank) -> [Diagnostic] {
        var counts: [ProblemID: Int] = [:]
        for problem in bank.problems { counts[problem.id, default: 0] += 1 }
        return counts.filter { $0.value > 1 }
            .sorted { $0.key < $1.key }
            .map { id, count in
                Diagnostic(
                    rule: .duplicateProblemID,
                    message: "problem id `\(id)` is declared \(count) times; ids must be unique",
                    nodes: [],
                    problem: id
                )
            }
    }

    // MARK: Per-problem checks

    private static func checks(_ problem: Problem, graph: KnowledgeGraph) -> [Diagnostic] {
        var out: [Diagnostic] = []

        func report(
            _ rule: DiagnosticRule, _ message: String, nodes: [NodeID] = [], path: [NodeID] = []
        ) {
            out.append(
                Diagnostic(
                    rule: rule, message: message, nodes: nodes, path: path, problem: problem.id))
        }

        // Ids are permanent (§3.1's rule, inherited): lowercase kebab, hyphen-joined.
        if !GraphValidator.isKebabComponent(problem.id.rawValue[...]) {
            report(
                .malformedProblemID,
                "problem id `\(problem.id)` is not lowercase-kebab (`[a-z0-9]+(-[a-z0-9]+)*`)")
        }

        if problem.statement.trimmed.isEmpty {
            report(.emptyProblemStatement, "problem `\(problem.id)` has an empty statement")
        }
        if problem.answer.trimmed.isEmpty {
            report(.emptyProblemAnswer, "problem `\(problem.id)` has an empty answer")
        }
        // A rubric is not decoration. Grading is the solver's own call (§5.4 wants
        // problems, not flashcards), and a bare answer invites "close enough" —
        // the criteria are what makes a self-grade a measurement.
        if problem.rubric.isEmpty || problem.rubric.contains(where: { $0.trimmed.isEmpty }) {
            report(
                .emptyProblemRubric,
                "problem `\(problem.id)` needs a rubric: one non-empty criterion per line that a "
                    + "correct solution must satisfy")
        }

        if problem.targets.isEmpty {
            report(
                .problemMissingTargets,
                "problem `\(problem.id)` names no target node; §5.2 requires at least one")
        }

        out += duplicates(problem.targets, in: problem, label: "targets")
        out += duplicates(problem.exercises, in: problem, label: "exercises")

        let tagLists: [(String, [NodeID], DiagnosticRule, DiagnosticRule)] = [
            ("targets", problem.targets, .danglingProblemTarget, .problemTargetNotContent),
            ("exercises", problem.exercises, .danglingProblemExercises, .problemExercisesNotContent),
        ]
        for (label, ids, dangling, notContent) in tagLists {
            for id in ids {
                guard let node = graph[id] else {
                    report(dangling, "problem `\(problem.id)` \(label) unknown node `\(id)`", nodes: [id])
                    continue
                }
                // §2.1: structural nodes are not learnable and carry no score, so
                // evidence about one is evidence about nothing.
                if node.kind.isStructural {
                    report(
                        notContent,
                        "problem `\(problem.id)` \(label) `\(id)`, which is a \(node.kind.rawValue) "
                            + "— structural nodes are not learnable (§2.1)",
                        nodes: [id])
                }
            }
        }

        // A node cannot be both primarily tested and merely drilled in passing: the
        // two receive different evidence (§5.2), so the overlap has no meaning and
        // `Grading` would have to pick one arbitrarily.
        for id in Set(problem.targets).intersection(problem.exercises).sorted() {
            report(
                .problemTargetAlsoExercised,
                "problem `\(problem.id)` lists `\(id)` as both a target and exercised; a target "
                    + "already receives the graded review",
                nodes: [id])
        }

        // §5.2 calls these "exercised *prerequisite* nodes". An exercised node that
        // no target depends on is one of two authoring mistakes: a mis-tag, or a
        // `requires` edge missing from the content. Both are worth stopping for —
        // §7.1's rule is that wrong edges are worse than missing nodes.
        let ancestry = Set(problem.targets.flatMap { graph.requiresAncestors(of: $0) })
        for id in problem.exercises
        where graph.contains(id) && !ancestry.contains(id) && !problem.targets.contains(id) {
            report(
                .problemExercisesNotPrerequisite,
                "problem `\(problem.id)` exercises `\(id)`, which is not a prerequisite of any of "
                    + "its targets — either the tag is wrong or content is missing a `requires` edge",
                nodes: [id],
                path: problem.targets)
        }

        // §4.4: an edge review happens when a problem explicitly exercises the
        // connection. The key must name a real authored `relates` edge...
        let edgeKeys = Set(graph.relatesEdges.map(\.key))
        let tagged = Set(problem.taggedNodes)
        for key in problem.connects {
            guard edgeKeys.contains(key) else {
                report(
                    .danglingProblemConnects,
                    "problem `\(problem.id)` connects `\(key)`, which is not an authored `relates` "
                        + "edge (keys are canonical `a ~ b`)")
                continue
            }
            // ...and the problem must actually touch both ends. A connection the
            // problem does not exercise on both sides is not a connection it tested.
            let endpoints = key.split(separator: "~").map {
                NodeID($0.trimmingCharacters(in: .whitespaces))
            }
            for endpoint in endpoints where !tagged.contains(endpoint) {
                report(
                    .problemConnectsUntaggedEndpoint,
                    "problem `\(problem.id)` connects `\(key)` but neither targets nor exercises "
                        + "`\(endpoint)`; an edge review means the problem worked both ends (§4.4)",
                    nodes: [endpoint])
            }
        }

        return out
    }

    private static func duplicates(
        _ ids: [NodeID], in problem: Problem, label: String
    ) -> [Diagnostic] {
        var counts: [NodeID: Int] = [:]
        for id in ids { counts[id, default: 0] += 1 }
        return counts.filter { $0.value > 1 }
            .sorted { $0.key < $1.key }
            .map { id, count in
                Diagnostic(
                    rule: .duplicateProblemTag,
                    message: "problem `\(problem.id)` lists `\(id)` \(count) times in `\(label)`",
                    nodes: [id],
                    problem: problem.id)
            }
    }
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
