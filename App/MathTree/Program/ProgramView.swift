import GraphCore
import SwiftUI

/// Where the program opens, from outside: the course home, one unit's page, or
/// the chapter reader scrolled to one node (the panel's "read the lesson").
enum ProgramEntry: Equatable {
    case course
    case unit(NodeID)
    case chapter(NodeID)
}

/// §6.6's program, restructured as §6.8's **course**.
///
/// Phase 12 shipped the program as a book: a table-of-contents rail beside one
/// long chapter. Read as a course it had no front door — nothing said *where
/// you are*, *what to do next*, or *how a unit is going* before you were inside
/// a scroll of prose. This is the same data (spine, lessons, evidence log) with
/// the hierarchy every course app puts first:
///
/// - **Course home** — the continue action at the top, the mastery measure over
///   the whole course, then every part with its units as rows carrying their
///   own mastery bar. Units nobody has authored are stated per part in one
///   quiet line rather than listed as 67 dashes.
/// - **Unit page** — the unit's opening, its ladder, and its skills in teaching
///   order, each with its rung and its actions; the unit test at the foot.
/// - **Chapter reader** — Phase 12's reader, unchanged, one click away as
///   "read as a chapter".
///
/// Navigation state is view state; position and progress are still derived
/// from the evidence log alone (§6.6), and the view recomputes its plan on
/// every score change so a graded problem moves every read-out it is under.
struct ProgramView: View {
    let program: Program
    let document: GraphDocument
    let scores: ScoreStore
    /// The window's name, used when the spine carries no title of its own.
    var fallbackTitle = "The Program"
    var entry: ProgramEntry = .course
    /// Open the node panel over the course (details, history, prerequisites).
    var onSelect: (NodeID) -> Void
    /// §6.7: play this step as cards.
    var onPlay: ((NodeID) -> Void)?
    /// §5.2: open a problem targeting this node.
    var onPractice: ((NodeID) -> Void)?
    /// §6.8: sit this unit's test.
    var onUnitTest: ((NodeID) -> Void)?
    var onExit: () -> Void

    enum Page: Equatable {
        case course
        case unit(NodeID)
        case chapter(unit: NodeID, target: NodeID?)
    }

    @State private var page: Page = .course

    var body: some View {
        // Read on purpose: registers observation of the snapshot, so a recorded
        // review recomputes the plan and every read-out under it.
        _ = scores.revision
        let theme = ThemeStore.shared.theme
        let plan = ProgramPlan.compute(
            spine: program.spine, graph: scores.graph, state: scores.state,
            at: scores.evaluatedAt, config: scores.config)

        return VStack(spacing: 0) {
            header(plan, theme)
            Rule()
            switch page {
            case .course:
                CourseHome(
                    program: program, plan: plan, document: document, scores: scores,
                    onOpenUnit: { open(.unit($0)) },
                    onPlay: onPlay)
            case let .unit(id):
                if let unit = plan.unit(id) {
                    UnitPage(
                        program: program, plan: plan, unit: unit, document: document,
                        scores: scores,
                        onSelect: onSelect, onPlay: onPlay, onPractice: onPractice,
                        onUnitTest: onUnitTest,
                        onReadChapter: { open(.chapter(unit: id, target: nil)) })
                } else {
                    missing(theme)
                }
            case let .chapter(id, target):
                if let unit = plan.unit(id) {
                    ChapterReader(
                        program: program, plan: plan, unit: unit, target: target,
                        document: document, scores: scores,
                        onSelect: onSelect, onPlay: onPlay)
                } else {
                    missing(theme)
                }
            }
            foot(plan, theme)
        }
        .background(theme.canvasEdge.color)
        .background(.ultraThinMaterial)
        .onAppear { page = resolved(entry, plan: plan) }
        .onChange(of: entry) { page = resolved(entry, plan: plan) }
    }

    private func resolved(_ entry: ProgramEntry, plan: ProgramPlan) -> Page {
        switch entry {
        case .course: return .course
        case let .unit(id): return .unit(id)
        case let .chapter(target):
            guard let step = plan.step(for: target) else { return .course }
            return .chapter(unit: step.unit, target: target)
        }
    }

    private func open(_ next: Page) {
        withAnimation(.easeInOut(duration: 0.2)) { page = next }
    }

    private func title(of id: NodeID) -> String {
        document.index(of: id).map { document[$0].title } ?? id.rawValue
    }

    private var courseTitle: String { program.spine.title ?? fallbackTitle }

    private func missing(_ theme: Theme) -> some View {
        Text("That unit is not in this program.")
            .font(Typeface.sans(13))
            .foregroundStyle(theme.inkMuted.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    /// The breadcrumb is the eyebrow: COURSE › UNIT 04 · TITLE › CHAPTER, each
    /// earlier crumb a way back. Under it, the name of where you are.
    private func header(_ plan: ProgramPlan, _ theme: Theme) -> some View {
        let unit: ProgramPlan.Unit? = {
            switch page {
            case .course: return nil
            case let .unit(id), let .chapter(id, _): return plan.unit(id)
            }
        }()
        return HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: theme.isDark ? 9 : 10) {
                crumbs(plan, unit: unit, theme)
                MathTextView(
                    source: unit.map { title(of: $0.id) } ?? courseTitle,
                    size: theme.isDark ? 26 : 28,
                    weight: theme.isDark ? .light : .regular,
                    color: theme.inkStrong.color,
                    face: theme.isDark ? .sans : .serif
                )
                .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            HStack(spacing: 22) {
                if let unit {
                    Text("unit \(unit.index + 1) of \(plan.units.count)")
                } else {
                    let summary = scores.masterySummary(of: plan.steps.map(\.id))
                    Text("\(summary.count(.mastered)) mastered")
                    Text("\(summary.metCount) / \(plan.stepCount) proficient")
                }
                Button(action: onExit) {
                    Text("esc — full map")
                        .foregroundStyle(theme.statEmphasis.color)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Return to the full map")
            }
            .font(Typeface.mono(11))
            .foregroundStyle(theme.stat.color)
            .fixedSize()
        }
        .padding(.horizontal, theme.isDark ? 40 : 44)
        .padding(.top, theme.isDark ? 30 : 32)
        .padding(.bottom, theme.isDark ? 22 : 24)
    }

    private func crumbs(_ plan: ProgramPlan, unit: ProgramPlan.Unit?, _ theme: Theme) -> some View {
        HStack(spacing: 8) {
            crumb("COURSE", isCurrent: unit == nil, theme) { open(.course) }
            if let unit {
                separator(theme)
                let isChapter: Bool = {
                    if case .chapter = page { return true }
                    return false
                }()
                crumb(
                    "UNIT \(String(format: "%02d", unit.index + 1)) · "
                        + title(of: unit.id).uppercased(),
                    isCurrent: !isChapter, theme
                ) { open(.unit(unit.id)) }
                if isChapter {
                    separator(theme)
                    crumb("CHAPTER", isCurrent: true, theme) {}
                }
            }
        }
        .font(Typeface.mono(10.5))
        .tracking(Typeface.tracking(0.16, at: 10.5))
    }

    private func crumb(
        _ text: String, isCurrent: Bool, _ theme: Theme, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(text)
                .foregroundStyle((isCurrent ? theme.trailCurrent : theme.trail).color)
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .help(isCurrent ? "" : "Back to \(text.capitalized)")
    }

    private func separator(_ theme: Theme) -> some View {
        Text("›").foregroundStyle(theme.trailSeparator.color)
    }

    // MARK: - Foot

    /// The course foots on its mastery points; a unit on its own ladder. Both
    /// carry the bookmark, one click from wherever you are.
    private func foot(_ plan: ProgramPlan, _ theme: Theme) -> some View {
        let ids: [NodeID] = {
            switch page {
            case .course: return plan.steps.map(\.id)
            case let .unit(id), let .chapter(id, _): return plan.unit(id)?.steps.map(\.id) ?? []
            }
        }()
        let summary = scores.masterySummary(of: ids)
        return HStack(spacing: 16) {
            MasteryBar(summary: summary, height: 2)
            if let resume = plan.resume, let onPlay {
                Button {
                    onPlay(resume.id)
                } label: {
                    Text("continue — \(title(of: resume.id))")
                        .font(Typeface.mono(10.5))
                        .foregroundStyle(theme.attention.color)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Play the first lesson you have not learned yet")
                .frame(maxWidth: 360, alignment: .trailing)
            }
            Text(
                page == .course
                    ? "\(MasteryFormat.points(summary)) · \(MasteryFormat.percent(summary))"
                    : "\(summary.metCount) / \(summary.total) proficient"
            )
            .font(Typeface.mono(10.5))
            .foregroundStyle(theme.stat.color)
            .fixedSize()
        }
        .padding(.horizontal, theme.isDark ? 40 : 44)
        .padding(.top, 8)
        .padding(.bottom, theme.isDark ? 26 : 28)
        .accessibilityLabel("\(summary.metCount) of \(summary.total) proficient")
    }
}

// MARK: - Course home

/// The course's front door: continue, the measure, the map of parts and units.
struct CourseHome: View {
    let program: Program
    let plan: ProgramPlan
    let document: GraphDocument
    let scores: ScoreStore
    var onOpenUnit: (NodeID) -> Void
    var onPlay: ((NodeID) -> Void)?

    var body: some View {
        let theme = ThemeStore.shared.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                continueBlock(theme)
                measure(theme)
                ForEach(Array(plan.parts.enumerated()), id: \.offset) { index, part in
                    partSection(part, number: index + 1, theme)
                }
            }
            .padding(.horizontal, theme.isDark ? 40 : 44)
            .padding(.top, 28)
            .padding(.bottom, 34)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func title(of id: NodeID) -> String {
        document.index(of: id).map { document[$0].title } ?? id.rawValue
    }

    /// The one thing a returning reader wants: where they got to, and a way back
    /// in. The bookmark is the first never-learned step (D12.2), which is what
    /// "where I got to" means — a decayed node from three units back is owed in
    /// the rail, not here.
    @ViewBuilder
    private func continueBlock(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            if let resume = plan.resume, let unit = plan.unit(resume.unit) {
                let position = (unit.steps.firstIndex { $0.id == resume.id } ?? 0) + 1
                Eyebrow(title: scores.state.nodes.isEmpty ? "Start here" : "Continue")
                MathTextView(
                    source: title(of: resume.id), size: theme.isDark ? 19 : 21,
                    color: theme.inkStrong.color, face: theme.isDark ? .sans : .serif)
                Text(
                    "Unit \(unit.index + 1) of \(plan.units.count) · \(title(of: unit.id)) · "
                        + "skill \(position) of \(unit.steps.count)"
                )
                .font(Typeface.mono(10.5))
                .foregroundStyle(theme.stat.color)
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    if let onPlay {
                        TextAction(
                            title: scores.state.nodes.isEmpty
                                ? "Start the course →" : "Continue the lesson →",
                            size: 13,
                            accessibilityHint: "Plays the next lesson, one card at a time"
                        ) { onPlay(resume.id) }
                    }
                    TextAction(
                        title: "Open the unit", size: 12, weight: .regular, isQuiet: true,
                        accessibilityHint: "The unit this lesson belongs to"
                    ) { onOpenUnit(unit.id) }
                }
                .padding(.top, 2)
            } else if plan.stepCount > 0 {
                Eyebrow(title: "Every skill learned")
                Text(
                    "You have been through every lesson in the course at least once. "
                        + "What has decayed is owed in the rail; any unit below reopens."
                )
                .font(Typeface.sans(theme.isDark ? 13.5 : 14.5))
                .foregroundStyle(theme.inkMuted.color)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Eyebrow(title: "Nothing authored yet")
                Text("The outline is in place, but no unit of this course has content to teach.")
                    .font(Typeface.sans(theme.isDark ? 13.5 : 14.5))
                    .foregroundStyle(theme.inkMuted.color)
            }
        }
    }

    /// Khan Academy's course measure: points over possible, then the ladder.
    private func measure(_ theme: Theme) -> some View {
        let summary = scores.masterySummary(of: plan.steps.map(\.id))
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("COURSE MASTERY")
                    .font(Typeface.mono(10, .medium))
                    .tracking(Typeface.tracking(0.18, at: 10))
                    .foregroundStyle(theme.eyebrow.color)
                Spacer(minLength: 0)
                Text("\(MasteryFormat.points(summary)) · \(MasteryFormat.percent(summary))")
                    .font(Typeface.mono(10.5))
                    .foregroundStyle(theme.statEmphasis.color)
            }
            MasteryBar(summary: summary, height: 4)
            HStack(alignment: .firstTextBaseline) {
                MasteryLegend(summary: summary)
                Spacer(minLength: 0)
                Text("\(summary.total) skills · \(plan.units.count(where: \.isAuthored)) units")
                    .font(Typeface.mono(10))
                    .foregroundStyle(theme.eyebrowCount.color)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One part: its authored units as rows, and its unauthored ones as one
    /// sentence. A part with nothing authored says so and takes two lines.
    private func partSection(_ part: ProgramPlan.Part, number: Int, _ theme: Theme) -> some View {
        let authored = part.units.filter(\.isAuthored)
        let outlined = part.units.filter { !$0.isAuthored }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("PART \(number)")
                    .font(Typeface.mono(10))
                    .foregroundStyle(theme.eyebrowCount.color)
                Eyebrow(title: part.title, count: authored.isEmpty ? nil : authored.count)
            }
            if !authored.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(authored) { unit in
                        UnitRow(
                            unit: unit,
                            title: title(of: unit.id),
                            summary: scores.masterySummary(of: unit.steps.map(\.id)),
                            isBookmarked: unit.id == plan.resume?.unit,
                            onOpen: { onOpenUnit(unit.id) })
                    }
                }
                .padding(.horizontal, -8)
            }
            if !outlined.isEmpty {
                Text(
                    (authored.isEmpty ? "Outlined, not yet authored: " : "\(outlined.count) more outlined, not yet authored: ")
                        + outlined.map { title(of: $0.id) }.joined(separator: ", ") + "."
                )
                .font(Typeface.mono(10))
                .foregroundStyle(theme.inkFaint.fading(0.75).color)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
            }
        }
    }
}

/// One unit on the course home: number, title, its ladder as a bar, and the
/// count. The number takes the attention colour on the bookmarked unit.
private struct UnitRow: View {
    let unit: ProgramPlan.Unit
    let title: String
    let summary: MasterySummary
    let isBookmarked: Bool
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", unit.index + 1))
                    .font(Typeface.mono(10))
                    .foregroundStyle((isBookmarked ? theme.attention : theme.eyebrowCount).color)
                    .frame(width: 20, alignment: .leading)
                MathTextView(
                    source: title, size: theme.isDark ? 14 : 14.5,
                    color: (isHovering ? theme.inkStrong : theme.ink).color,
                    face: theme.isDark ? .sans : .serif)
                .lineLimit(1)
                Spacer(minLength: 12)
                MasteryBar(summary: summary, height: 3)
                    .frame(width: 120)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                if isHovering {
                    Text("open →")
                        .font(Typeface.sans(10.5, .medium))
                        .foregroundStyle(theme.action.color)
                        .frame(width: 92, alignment: .trailing)
                } else {
                    Text(readout)
                        .font(Typeface.mono(10))
                        .foregroundStyle(
                            (summary.count(.mastered) == summary.total
                                ? theme.action : theme.rowTrailing).color)
                        .frame(width: 92, alignment: .trailing)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isHovering ? theme.rowHighlight.color : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(unit.id.rawValue)
        .accessibilityLabel(
            "Unit \(unit.index + 1), \(title), \(summary.metCount) of \(summary.total) proficient")
    }

    private var readout: String {
        if summary.count(.mastered) == summary.total { return "mastered" }
        if summary.metCount == 0 && summary.count(.familiar) == 0 && summary.count(.attempted) == 0 {
            return "\(summary.total) skills"
        }
        return "\(summary.metCount) / \(summary.total)"
    }
}

// MARK: - Preview

#if DEBUG

#Preview("Course") {
    ProgramView(
        program: Program(
            spine: ProgramSpine(
                title: "A Course",
                parts: [.init(title: "Analysis", units: ["analysis.svc"])]),
            lessonUnits: [
                LessonUnit(
                    unit: "analysis.svc",
                    opening: "One chapter, to preview the course.",
                    lessons: [
                        Lesson(
                            node: "analysis.svc.mvt",
                            hook: "The bridge from local slope to global change.",
                            explanation: "Rolle's theorem plus a tilt.\nThe second paragraph.",
                            recap: "Average slope is attained somewhere inside.")
                    ])
            ]),
        document: NodePanelPreviewData.document,
        scores: NodePanelPreviewData.scores(),
        onSelect: { print("select \($0)") },
        onPlay: { print("play \($0)") },
        onExit: { print("exit") }
    )
    .frame(width: 1280, height: 800)
}

#endif
