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
    ///
    /// The one exception is a forward reference the spine *declares* (D15.2):
    /// that edge is accepted, surfaced to the reader by `ProgramPlan.Step.forward`
    /// rather than hidden, and held to being real — a declaration that names no
    /// forward edge is `program-forward-stale`, so the list cannot rot.
    private static func orderChecks(_ spine: ProgramSpine, graph: KnowledgeGraph) -> [Diagnostic] {
        let position = Dictionary(
            spine.units.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first })

        func unitPosition(of node: Node) -> (unit: NodeID, position: Int)? {
            guard let parent = node.parent else { return nil }
            return position[parent].map { (parent, $0) }
        }

        let declared = Set(spine.forward.map { Edge(node: $0.node, requires: $0.requires) })
        var found = Set<Edge>()

        var out: [Diagnostic] = []
        for node in graph.nodes where node.kind.isContent {
            guard let home = unitPosition(of: node) else { continue }
            for prerequisite in node.requires {
                guard let required = graph[prerequisite],
                    let away = unitPosition(of: required),
                    away.position > home.position
                else { continue }
                let edge = Edge(node: node.id, requires: prerequisite)
                found.insert(edge)
                if declared.contains(edge) { continue }
                out.append(
                    Diagnostic(
                        rule: .programOrderViolation,
                        message:
                            "`\(node.id)` (unit \(home.position + 1), `\(home.unit)`) requires "
                            + "`\(prerequisite)` (unit \(away.position + 1), `\(away.unit)`) — "
                            + "the program order must be a linear extension of cross-unit "
                            + "requires, or the spine must declare this edge under `forward:`",
                        nodes: [node.id, prerequisite],
                        path: [home.unit, away.unit]))
            }
        }

        for reference in spine.forward {
            let edge = Edge(node: reference.node, requires: reference.requires)
            if !found.contains(edge) {
                out.append(
                    Diagnostic(
                        rule: .programForwardStale,
                        message:
                            "the spine accepts `\(reference.node)` requiring `\(reference.requires)` "
                            + "as a forward reference, but under this order it is not one — "
                            + "delete the declaration",
                        nodes: [reference.node, reference.requires]))
            }
            if reference.note.trimmed.isEmpty {
                out.append(
                    Diagnostic(
                        rule: .programForwardUnexplained,
                        message:
                            "the forward reference `\(reference.node)` → `\(reference.requires)` "
                            + "has no note — say what the reader is expected to bring to the "
                            + "earlier step",
                        nodes: [reference.node, reference.requires]))
            }
        }
        return out
    }

    private struct Edge: Hashable {
        let node: NodeID
        let requires: NodeID
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

            out += cardChecks(lesson, unit: unit.unit)
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

    // MARK: - Cards

    /// §6.9's dialogue contract, as numbers. Named so the Python checker's
    /// constants have one thing to agree with.
    public enum DialogueContract {
        /// Beats in a row before the dialogue must ask something — the rule that
        /// keeps a dialogue from being a textbook with a quiz stapled on.
        public static let maxBeatsInARow = 2
        /// Questions (checks plus reflections) a dialogue asks at least.
        public static let minQuestions = 5
        /// Parts a dialogue has at least: the question, and where it leads.
        public static let minParts = 2
    }

    /// §6.7's per-card rules, errors like every other per-file lesson rule: a
    /// `steps` list that exists must be playable, and the failure modes are all
    /// silent ones — a card with nothing on it renders blank, a check with no
    /// correct row can never be answered right, and an `expects` the parser cannot
    /// read tells a correct reader they are wrong (D13.4).
    ///
    /// A lesson with *no* `steps` is not checked and not reported here: paging
    /// falls back to the prose (D13.1), and interactivity coverage is a lint hint
    /// plus a `validate` report, exactly as lesson coverage is (D12.4).
    ///
    /// §6.9's `dialogue` is held to the same per-card rules and, on top, to the
    /// dialogue contract — which is an error rather than a hint because a lesson
    /// only reaches it by opting in (D16.2).
    private static func cardChecks(_ lesson: Lesson, unit: NodeID) -> [Diagnostic] {
        var out: [Diagnostic] = []
        let nodes = [lesson.node, unit]

        func report(_ rule: DiagnosticRule, _ message: String) {
            out.append(
                Diagnostic(
                    rule: rule, message: "lesson `\(lesson.node)` " + message, nodes: nodes))
        }

        if !lesson.steps.isEmpty && !lesson.dialogue.isEmpty {
            report(
                .lessonStepsAndDialogue,
                "carries both `steps` and `dialogue` — a dialogue replaces the steps; "
                    + "delete the `steps`")
        }

        for (list, cards) in [("card", lesson.steps), ("dialogue step", lesson.dialogue)] {
            for (index, card) in cards.enumerated() {
                cardFaults(card, position: "\(list) \(index + 1)", report: report)
            }
        }

        guard lesson.isDialogue else { return out }
        let dialogue = lesson.dialogue

        if dialogue.first?.partTitle == nil {
            report(
                .dialogueOpensWithoutPart,
                "opens its dialogue without a `part:` — the first step names the first part")
        }

        var beats = 0
        for (index, card) in dialogue.enumerated() {
            beats = card.isQuestion ? 0 : beats + 1
            if beats == DialogueContract.maxBeatsInARow + 1 {
                report(
                    .dialogueLecture,
                    "has \(beats) `teach` steps in a row ending at dialogue step \(index + 1) — "
                        + "ask something before the third beat")
            }
        }

        let questions = dialogue.count(where: \.isQuestion)
        let parts = dialogue.count { $0.partTitle != nil }
        if questions < DialogueContract.minQuestions || parts < DialogueContract.minParts {
            report(
                .dialogueThin,
                "has \(questions) question(s) in \(parts) part(s) — a dialogue asks at least "
                    + "\(DialogueContract.minQuestions) across at least "
                    + "\(DialogueContract.minParts) parts")
        }

        if !dialogue.contains(where: \.isReflection) {
            report(
                .dialogueNoReflection,
                "has no `reflect` step — somewhere the reader must put the idea in their own "
                    + "words before it is named")
        }

        for (index, card) in dialogue.enumerated() where card.isCheck {
            let silent = card.choices.indices.filter {
                (card.choices[$0].feedback ?? "").trimmed.isEmpty
            }
            if !silent.isEmpty {
                report(
                    .dialogueChoiceWithoutWhy,
                    "dialogue step \(index + 1) has choice(s) "
                        + silent.map { "\($0 + 1)" }.joined(separator: ", ")
                        + " with no `feedback` — a wrong pick is where a dialogue teaches")
            }
        }

        return out
    }

    /// The rules one card is held to wherever it appears.
    private static func cardFaults(
        _ card: LessonCard, position: String, report: (DiagnosticRule, String) -> Void
    ) {
        let teaches = !(card.teach ?? "").trimmed.isEmpty
        let asks = !(card.ask ?? "").trimmed.isEmpty
        let reflects = !(card.reflect ?? "").trimmed.isEmpty
        let hasAnswer = !(card.answer ?? "").trimmed.isEmpty

        switch [teaches, asks, reflects].count(where: { $0 }) {
        case 0:
            report(.lessonCardEmpty, "\(position) has none of `teach`, `ask` or `reflect`")
            return
        case 1:
            break
        default:
            report(
                .lessonCardAmbiguous,
                "\(position) combines "
                    + [("teach", teaches), ("ask", asks), ("reflect", reflects)]
                    .filter(\.1).map { "`\($0.0)`" }.joined(separator: " and ")
                    + " — a card is one beat, one check or one reflection")
        }

        if reflects && !hasAnswer {
            report(
                .lessonReflectionMissingAnswer,
                "\(position) is a `reflect` with no `answer` — the reader compares theirs "
                    + "with the tutor's")
        }
        if hasAnswer && !reflects {
            report(
                .lessonStrayAnswer,
                "\(position) carries an `answer` but no `reflect` — `answer` is a reflection's "
                    + "model answer; a check's explanation is `feedback`")
        }

        if !asks {
            // Answer fields on a beat or a reflection are always a mistake, and
            // always the same mistake: an author wrote a check and deleted the
            // question instead of the card.
            var stranded: [String] = []
            if !card.choices.isEmpty { stranded.append("choices") }
            if card.expects != nil { stranded.append("expects") }
            if card.tolerance != nil { stranded.append("tolerance") }
            if card.feedback != nil { stranded.append("feedback") }
            if !stranded.isEmpty {
                report(
                    .lessonTeachCardAnswerable,
                    "\(position) is a `\(reflects ? "reflect" : "teach")` card carrying "
                        + "\(stranded.map { "`\($0)`" }.joined(separator: ", "))"
                        + " — add an `ask`, or delete the answer fields")
            }
            return
        }

        for fault in AnswerCheck.faults(
            choices: card.choices, expects: card.expects, tolerance: card.tolerance,
            feedback: card.feedback, isRequired: true)
        {
            report(fault.rule, "\(position) \(fault.detail)")
        }
    }
}
