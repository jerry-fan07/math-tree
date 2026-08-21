import Foundation

/// Authoring hints — the half of §7.1's review checklist a machine can *guess* at.
///
/// Deliberately separate from `GraphValidator`, and deliberately not fatal. The
/// validator encodes rules that are true or false: a dangling id is wrong, a cycle
/// is wrong, and CI must stop. Everything here is a heuristic about the things
/// §2.2 says "can't be fully automated" — atomicity above all — and a heuristic
/// that blocks a merge is a heuristic that gets worked around. So `lint` prints
/// and exits 0 unless asked to be strict.
///
/// The rules earn their place by what they catch *at scale*. Six subbranches can
/// be read end to end by a person; a hundred cannot, and the failures that show up
/// then are not exotic — a concept authored twice under two branches, a node
/// nothing requires and that requires nothing, a branch that landed without its
/// integration pass. Those are the ones here.
public struct LintHint: Hashable, Sendable, CustomStringConvertible {
    // A `conjunctive-title` rule — "a title joining two things is usually two
    // nodes" — was written, tested against the seed subgraph, and **deleted after
    // measurement**. On the first real corpus it fired 38 times with, on reading,
    // no true positives: "Domain and range of a relation", "Upper and lower bounds
    // in a poset", "Kernel and image of a homomorphism" are dual notions that are
    // one piece of knowledge, and mathematical English names them in pairs
    // constantly. Every attempt to tighten it (word counts either side, dropping
    // "with") either kept the false positives or lost the case it was written for.
    // A rule with no precision is worse than no rule: it teaches an author to skim
    // past the whole report, including `duplicate-title` underneath it, which on
    // the same run found two genuine duplicated concepts.
    public enum Rule: String, Hashable, Sendable, CaseIterable {
        /// "Moreover", "Furthermore" — a second fact bolted onto the first.
        case compoundStatement = "compound-statement"
        /// Far longer than the corpus norm.
        case oversizedStatement = "oversized-statement"
        /// A content node that states nothing.
        case missingStatement = "missing-statement"
        /// So many direct prerequisites that the node is probably a bundle.
        case widePrerequisiteFan = "wide-prerequisite-fan"
        /// Requires nothing, is required by nothing, relates to nothing.
        case isolatedNode = "isolated-node"
        /// The same concept authored twice.
        case duplicateTitle = "duplicate-title"
        /// Prominence 2 is a landmark; a file full of landmarks has none.
        case landmarkInflation = "landmark-inflation"
        /// A `relates` note too short to say what the connection *is* (§2.3).
        case thinRelatesNote = "thin-relates-note"
        /// Outlined but not yet authored.
        case emptySubbranch = "empty-subbranch"
        /// A branch with no `requires` edge crossing into or out of it — the
        /// cross-branch integration pass has not run.
        case unintegratedBranch = "unintegrated-branch"
        /// A lesson (§6.6) whose node's kind promises a computation, with no
        /// `worked` section. Advisory, not a validator rule: forcing the section
        /// would manufacture filler on the nodes where it does not fit.
        case lessonMissingWorked = "lesson-missing-worked"
        /// A lesson explanation shorter than a lesson — the section exists but
        /// does not teach.
        case thinLesson = "thin-lesson"
        /// A lesson far past the corpus norm — probably teaching two nodes.
        case oversizedLesson = "oversized-lesson"
    }

    public var rule: Rule
    /// The node the hint is about, so the CLI can print its file and line.
    public var subject: NodeID?
    public var message: String
    /// Other nodes involved (the other half of a duplicate pair, say).
    public var nodes: [NodeID]

    public init(rule: Rule, subject: NodeID? = nil, message: String, nodes: [NodeID] = []) {
        self.rule = rule
        self.subject = subject
        self.message = message
        self.nodes = nodes
    }

    public var description: String { "[\(rule.rawValue)] \(message)" }
}

public struct LintConfig: Sendable {
    /// A statement this many times the corpus median is worth a second look.
    public var oversizeFactor = 3.0
    /// …but never below this, so a corpus of one-line stubs does not flag itself.
    public var oversizeFloor = 900
    public var prerequisiteFanLimit = 6
    public var relatesNoteMinimumCharacters = 20
    /// Landmarks above this share of a subbranch's content nodes…
    public var landmarkShareLimit = 0.25
    /// …once it has at least this many.
    public var landmarkSampleFloor = 4
    /// A lesson explanation below this many characters is probably a summary
    /// wearing a lesson's clothes.
    public var thinLessonFloor = 400
    /// All sections together above this is probably two lessons.
    public var oversizedLessonCeiling = 6000

    public init() {}
}

public enum ContentLint {
    public static func hints(for graph: KnowledgeGraph, config: LintConfig = LintConfig())
        -> [LintHint]
    {
        var hints: [LintHint] = []
        let content = graph.nodes.filter { $0.kind.isContent }

        // MARK: per-node shape

        let median = medianStatementLength(of: content)
        let oversize = max(config.oversizeFloor, Int(Double(median) * config.oversizeFactor))

        for node in content.sorted(by: { $0.id < $1.id }) {
            let statement = node.statement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if statement.isEmpty {
                hints.append(
                    .init(
                        rule: .missingStatement, subject: node.id,
                        message: "\(node.id) is a \(node.kind.rawValue) with no statement"))
            } else {
                if statement.count > oversize {
                    hints.append(
                        .init(
                            rule: .oversizedStatement, subject: node.id,
                            message:
                                "\(node.id): statement is \(statement.count) characters "
                                + "(corpus median \(median)) — candidate for splitting (§2.2)"))
                }
                if let marker = compoundMarkers.first(where: { statement.contains($0) }) {
                    hints.append(
                        .init(
                            rule: .compoundStatement, subject: node.id,
                            message:
                                "\(node.id): statement contains \"\(marker.trimmingCharacters(in: .whitespaces))\" "
                                + "— is the second half knowledge a consumer could need alone?"))
                }
            }

            let prerequisites = graph.prerequisites(of: node.id)
            if prerequisites.count > config.prerequisiteFanLimit {
                hints.append(
                    .init(
                        rule: .widePrerequisiteFan, subject: node.id,
                        message:
                            "\(node.id) has \(prerequisites.count) direct prerequisites — either a "
                            + "bundle of several nodes, or an intermediate node is missing",
                        nodes: prerequisites))
            }

            if prerequisites.isEmpty, graph.dependents(of: node.id).isEmpty,
                graph.related(to: node.id).isEmpty,
                !graph.relatesEdges.contains(where: { $0.a == node.id || $0.b == node.id })
            {
                hints.append(
                    .init(
                        rule: .isolatedNode, subject: node.id,
                        message:
                            "\(node.id) requires nothing, is required by nothing and relates to "
                            + "nothing — nothing in the graph can reach it"))
            }

            for reference in node.relates
            where reference.note.trimmingCharacters(in: .whitespacesAndNewlines).count
                < config.relatesNoteMinimumCharacters {
                hints.append(
                    .init(
                        rule: .thinRelatesNote, subject: node.id,
                        message:
                            "\(node.id) ~ \(reference.id): the note is scored knowledge in its own "
                            + "right (§4.4) and has to say what the connection is",
                        nodes: [reference.id]))
            }
        }

        // MARK: duplicates

        var byTitle: [String: [NodeID]] = [:]
        for node in content {
            byTitle[normalize(node.title), default: []].append(node.id)
        }
        for (_, ids) in byTitle.sorted(by: { $0.key < $1.key }) where ids.count > 1 {
            let sorted = ids.sorted()
            hints.append(
                .init(
                    rule: .duplicateTitle, subject: sorted[0],
                    message:
                        "\(sorted.count) nodes share the title \"\(graph[sorted[0]]?.title ?? "")\" "
                        + "— one concept, or one concept authored twice?",
                    nodes: sorted))
        }

        // MARK: per-subbranch

        for node in graph.nodes.sorted(by: { $0.id < $1.id }) where node.kind == .subbranch {
            let children = graph.containedChildren(of: node.id)
                .compactMap { graph[$0] }
                .filter { $0.kind.isContent }
            if children.isEmpty {
                hints.append(
                    .init(
                        rule: .emptySubbranch, subject: node.id,
                        message: "\(node.id) is outlined but holds no content nodes yet"))
                continue
            }
            let landmarks = children.filter { $0.prominence == .landmark }.count
            if children.count >= config.landmarkSampleFloor,
                Double(landmarks) / Double(children.count) > config.landmarkShareLimit
            {
                hints.append(
                    .init(
                        rule: .landmarkInflation, subject: node.id,
                        message:
                            "\(node.id): \(landmarks) of \(children.count) content nodes are "
                            + "prominence 2 — a map where everything is a landmark has none"))
            }
        }

        // MARK: per-branch integration

        for branch in graph.branches.sorted() {
            let members = Set(
                graph.nodes.filter { $0.id.components.first.map(String.init) == branch.rawValue }
                    .map(\.id))
            guard members.contains(where: { graph[$0]?.kind.isContent == true }) else { continue }
            let crosses = members.contains { id in
                graph.prerequisites(of: id).contains { !members.contains($0) }
                    || graph.dependents(of: id).contains { !members.contains($0) }
            }
            if !crosses {
                hints.append(
                    .init(
                        rule: .unintegratedBranch, subject: branch,
                        message:
                            "\(branch) has content but no `requires` edge crossing its boundary — "
                            + "the cross-branch integration pass has not run on it"))
            }
        }

        return hints
    }

    /// §6.6's lesson heuristics — the judgements `ProgramValidator` deliberately
    /// leaves to a reviewer. `worked`, `interview` and `pitfalls` are optional by
    /// design (an `intuition` node forced to produce a computation produces
    /// filler), but a `theorem` or `example` lesson *without* one is usually an
    /// author who stopped early, and at 58 units nobody reads the corpus end to
    /// end — which is exactly when lint earns its keep.
    public static func hints(
        for program: Program, graph: KnowledgeGraph, config: LintConfig = LintConfig()
    ) -> [LintHint] {
        var hints: [LintHint] = []
        let wantsWorked: Set<NodeKind> = [
            .theorem, .proposition, .lemma, .corollary, .technique, .example,
        ]

        for unit in program.lessonUnits.values.sorted(by: { $0.unit < $1.unit }) {
            for lesson in unit.lessons {
                guard let node = graph[lesson.node] else { continue }

                if wantsWorked.contains(node.kind),
                    lesson.worked?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                {
                    hints.append(
                        .init(
                            rule: .lessonMissingWorked, subject: lesson.node,
                            message:
                                "\(lesson.node) is a \(node.kind.rawValue) whose lesson has no "
                                + "`worked` section — where is the number?"))
                }

                let explanation = lesson.explanation
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if explanation.count < config.thinLessonFloor {
                    hints.append(
                        .init(
                            rule: .thinLesson, subject: lesson.node,
                            message:
                                "\(lesson.node): explanation is \(explanation.count) characters — "
                                + "a lesson teaches, a summary the node already has"))
                }

                let total = [
                    lesson.hook, lesson.explanation, lesson.worked ?? "",
                    lesson.interview ?? "", lesson.pitfalls ?? "", lesson.recap,
                ].reduce(0) { $0 + $1.count }
                if total > config.oversizedLessonCeiling {
                    hints.append(
                        .init(
                            rule: .oversizedLesson, subject: lesson.node,
                            message:
                                "\(lesson.node): lesson totals \(total) characters — "
                                + "probably teaching two nodes (§2.2 applies to lessons too)"))
                }
            }
        }
        return hints
    }

    // MARK: - Helpers

    private static let compoundMarkers = [
        "Moreover,", "Furthermore,", "In addition,", "Separately,", "Additionally,",
    ]

    private static func normalize(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func medianStatementLength(of nodes: [Node]) -> Int {
        let lengths = nodes.compactMap {
            $0.statement?.trimmingCharacters(in: .whitespacesAndNewlines).count
        }
        .filter { $0 > 0 }
        .sorted()
        guard !lengths.isEmpty else { return 0 }
        return lengths[lengths.count / 2]
    }
}
