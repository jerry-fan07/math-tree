import GraphCore
import SwiftUI

/// §6.6's program: the authored curriculum over a whole tree, read as a book.
///
/// Two panes under one header, in turn 1's grammar. The left pane is the table
/// of contents — parts as eyebrows, units as rows with their met-of-total — and
/// the right pane is the open unit as a *chapter*: its opening paragraph, then
/// every step in the plan's teaching order as title · statement · lesson, with
/// the self-report action at each lesson's foot so the loop closes without
/// leaving the page.
///
/// Two starting points, one derivation (§6.6): "show everything" renders every
/// step in full; the default adapts to what the user knows by compressing met
/// steps to one quiet line each — expandable, because compression is an answer
/// to "where do I start", never a lock. The bookmark (`ProgramPlan.resume`) is
/// the first *never-learned* step, deliberately not the first unmet one: decay
/// re-enters the work by un-compressing, not by moving the bookmark.
///
/// The view recomputes its plan whenever the score snapshot changes, so grading
/// a lesson visibly compresses it away (in adaptive mode), advances the
/// bookmark, and moves every progress read-out — the product's loop, closed
/// inside one screen.
struct ProgramView: View {
    let program: Program
    let document: GraphDocument
    let scores: ScoreStore
    /// A node to open the program *at* — the panel's "read the lesson" jump.
    var target: NodeID?
    /// Open the node panel over the reader (details, history, prerequisites).
    var onSelect: (NodeID) -> Void
    var onExit: () -> Void

    /// nil until the reader navigates: the open unit follows the bookmark.
    @State private var openUnit: NodeID?
    /// Met steps the user chose to reread in adaptive mode.
    @State private var expanded: Set<NodeID> = []
    /// Scroll request for the chapter pane, consumed after layout.
    @State private var reveal: NodeID?
    /// §6.6's "from the beginning" — every step in full, no compression.
    @AppStorage("MathTree.program.showEverything") private var showEverything = false

    var body: some View {
        // Read on purpose: registers observation of the snapshot, so a recorded
        // review recomputes the plan (compression, bookmark, progress).
        _ = scores.revision
        let theme = ThemeStore.shared.theme
        let plan = ProgramPlan.compute(
            spine: program.spine, graph: scores.graph, state: scores.state,
            at: scores.evaluatedAt, config: scores.config)
        let unit = currentUnit(plan)

        return VStack(spacing: 0) {
            header(plan, unit: unit, theme)
            Rule()
            HStack(spacing: 0) {
                contents(plan, open: unit, theme)
                Rectangle().fill(theme.hairline.color).frame(width: 1)
                if let unit {
                    chapter(plan, unit: unit, theme)
                } else {
                    Text("The program has no units.")
                        .font(Typeface.sans(13))
                        .foregroundStyle(theme.inkMuted.color)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            progress(plan, theme)
        }
        .background(theme.canvasEdge.color)
        .background(.ultraThinMaterial)
        .onAppear {
            if let target, let step = plan.step(for: target) {
                openUnit = step.unit
                expanded.insert(target)
                reveal = target
            } else if let resume = plan.resume {
                openUnit = resume.unit
                reveal = resume.id
            }
        }
    }

    private func currentUnit(_ plan: ProgramPlan) -> ProgramPlan.Unit? {
        if let openUnit, let unit = plan.unit(openUnit) { return unit }
        if let resume = plan.resume { return plan.unit(resume.unit) }
        return plan.units.first
    }

    private func title(of id: NodeID) -> String {
        document.index(of: id).map { document[$0].title } ?? id.rawValue
    }

    // MARK: - Header

    private func header(_ plan: ProgramPlan, unit: ProgramPlan.Unit?, _ theme: Theme) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: theme.isDark ? 9 : 10) {
                Text("PROGRAM")
                    .font(Typeface.mono(10.5))
                    .tracking(Typeface.tracking(0.18, at: 10.5))
                    .foregroundStyle(theme.eyebrow.color)
                MathTextView(
                    source: unit.map { title(of: $0.id) } ?? "The Program",
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
                    Text("unit \(unit.index + 1) / \(plan.units.count)")
                }
                Text("\(plan.metCount) / \(plan.stepCount) mastered")
                // The other starting point, one click away — a mode, not a fork.
                Button {
                    showEverything.toggle()
                } label: {
                    Text(showEverything ? "adapt to what I know" : "show everything")
                        .foregroundStyle(theme.statEmphasis.color)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(
                    showEverything
                        ? "Compress the steps you already hold to one line each"
                        : "Show every step in full, from the beginning")
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

    // MARK: - Contents

    /// The table of contents: every part, every unit, the whole tree at a
    /// glance. This is where "learn specific topics at whatever time" lives —
    /// any unit is one click, whatever the bookmark says.
    private func contents(
        _ plan: ProgramPlan, open: ProgramPlan.Unit?, _ theme: Theme
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(plan.parts.enumerated()), id: \.offset) { _, part in
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(title: part.title)
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(part.units) { unit in
                                unitRow(
                                    unit, isOpen: unit.id == open?.id,
                                    isBookmarked: unit.id == plan.resume?.unit, theme: theme)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, theme.isDark ? 20 : 22)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: theme.railWidth + 24)
    }

    private func unitRow(
        _ unit: ProgramPlan.Unit, isOpen: Bool, isBookmarked: Bool, theme: Theme
    ) -> some View {
        Button {
            openUnit = unit.id
            reveal = nil
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%02d", unit.index + 1))
                    .font(Typeface.mono(10))
                    .foregroundStyle(
                        (isBookmarked ? theme.attention : theme.eyebrowCount).color)
                MathTextView(
                    source: title(of: unit.id), size: 12.5,
                    color: (isOpen ? theme.inkStrong : theme.rowTitle).color)
                .lineLimit(1)
                Spacer(minLength: 8)
                Text(readout(of: unit))
                    .font(Typeface.mono(10))
                    .foregroundStyle(
                        (unit.isComplete ? theme.statEmphasis : theme.rowTrailing).color)
            }
            .padding(.vertical, 2.5)
            .padding(.horizontal, 6)
            .background(isOpen ? theme.rowHighlight.color : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(unit.id.rawValue)
        .accessibilityLabel(
            "Unit \(unit.index + 1), \(title(of: unit.id)), \(readout(of: unit))"
        )
    }

    private func readout(of unit: ProgramPlan.Unit) -> String {
        guard unit.isAuthored else { return "—" }
        if unit.isComplete { return "✓" }
        return "\(unit.metCount)/\(unit.steps.count)"
    }

    // MARK: - Chapter

    private func chapter(_ plan: ProgramPlan, unit: ProgramPlan.Unit, _ theme: Theme) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    chapterHead(plan, unit: unit, theme)
                    if unit.isAuthored {
                        let compressed = compressedCount(unit)
                        if compressed > 0 {
                            Text(
                                "\(compressed) step\(compressed == 1 ? "" : "s") you already hold "
                                    + "\(compressed == 1 ? "is" : "are") compressed — open one to "
                                    + "reread it"
                            )
                            .font(Typeface.mono(10))
                            .foregroundStyle(theme.inkFaint.fading(0.7).color)
                            .padding(.bottom, 14)
                        }
                        ForEach(Array(unit.steps.enumerated()), id: \.element.id) { index, step in
                            stepView(step, number: index + 1, theme: theme)
                                .id(step.id)
                        }
                    } else {
                        Text(
                            "\(title(of: unit.id)) is outlined but has no content authored yet, "
                                + "so there is nothing to teach here."
                        )
                        .font(Typeface.sans(theme.isDark ? 14 : 15))
                        .foregroundStyle(theme.inkMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560, alignment: .leading)
                    }
                }
                .padding(.horizontal, theme.isDark ? 40 : 44)
                .padding(.top, 26)
                .padding(.bottom, 34)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: reveal) {
                guard let reveal else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(reveal, anchor: .top) }
            }
            .onAppear {
                // Layout has to settle before the anchor exists to scroll to.
                if let reveal {
                    DispatchQueue.main.async {
                        proxy.scrollTo(reveal, anchor: .top)
                    }
                }
            }
        }
    }

    private func chapterHead(
        _ plan: ProgramPlan, unit: ProgramPlan.Unit, _ theme: Theme
    ) -> some View {
        let part = plan.parts.first { $0.units.contains(where: { $0.id == unit.id }) }
        return VStack(alignment: .leading, spacing: 12) {
            Text("UNIT \(unit.index + 1) · \(part?.title.uppercased() ?? "")")
                .font(Typeface.mono(10))
                .tracking(Typeface.tracking(0.16, at: 10))
                .foregroundStyle(theme.eyebrow.fading(0.7).color)
            ForEach(paragraphs(program.opening(of: unit.id) ?? summary(of: unit.id)), id: \.self) {
                MathTextView(
                    source: $0, size: theme.isDark ? 14.5 : 15.5,
                    color: theme.ink.color, face: theme.isDark ? .sans : .serif)
                .lineSpacing(theme.isDark ? 6 : 7)
            }
            if unit.isAuthored {
                HStack(spacing: 14) {
                    MeasureBar(
                        value: Double(unit.metCount) / Double(unit.steps.count), height: 2,
                        tint: unit.isComplete ? theme.action : nil
                    )
                    .frame(width: 160)
                    Text("\(unit.metCount) / \(unit.steps.count) mastered")
                        .font(Typeface.mono(10.5))
                        .foregroundStyle(theme.stat.color)
                        .fixedSize()
                }
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 22)
    }

    private func summary(of id: NodeID) -> String {
        document.index(of: id).flatMap { document[$0].summary } ?? ""
    }

    private func compressedCount(_ unit: ProgramPlan.Unit) -> Int {
        guard !showEverything else { return 0 }
        return unit.steps.count { isCompressed($0) }
    }

    private func isCompressed(_ step: ProgramPlan.Step) -> Bool {
        !showEverything && step.isMet && !expanded.contains(step.id)
    }

    // MARK: - Steps

    @ViewBuilder
    private func stepView(_ step: ProgramPlan.Step, number: Int, theme: Theme) -> some View {
        if isCompressed(step) {
            compressedRow(step, number: number, theme: theme)
        } else {
            lessonView(step, number: number, theme: theme)
        }
    }

    /// §6.2's compression, applied to a chapter: a met step is present, small
    /// and quiet — one line saying it is held — and one click reopens it.
    private func compressedRow(
        _ step: ProgramPlan.Step, number: Int, theme: Theme
    ) -> some View {
        Button {
            expanded.insert(step.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(String(format: "%02d", number))
                    .font(Typeface.mono(9.5))
                    .foregroundStyle(theme.eyebrowCount.fading(0.8).color)
                ScoreDot(id: step.id, scores: scores, diameter: 5)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                MathTextView(source: title(of: step.id), size: 12, color: theme.inkMuted.color)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(scoreReadout(step))
                    .font(Typeface.mono(10))
                    .foregroundStyle(theme.eyebrowCount.color)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Mastered — open to reread")
    }

    private func scoreReadout(_ step: ProgramPlan.Step) -> String {
        switch ScoreFormat.state(of: step.id, in: scores) {
        case let .learned(retrievability):
            return "\(Int((min(max(retrievability, 0), 1) * 100).rounded()))"
        case .frontier: return "ready"
        case .attempted: return "missed"
        case .unlearned: return "new"
        }
    }

    private func stateLabel(_ step: ProgramPlan.Step) -> String {
        if step.isMet { return "MET · \(scoreReadout(step))" }
        if step.isDecayed { return "DECAYED · \(scoreReadout(step))" }
        return scoreReadout(step).uppercased()
    }

    /// One step, in full: what to know (the node), then how to come to know it
    /// (the lesson), then the action that records that you now do.
    private func lessonView(_ step: ProgramPlan.Step, number: Int, theme: Theme) -> some View {
        let node = document.index(of: step.id).map { document[$0] }
        let lesson = program.lesson(for: step.id)
        return VStack(alignment: .leading, spacing: 0) {
            Rule()
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    "STEP \(String(format: "%02d", number)) · "
                        + "\(node?.kind.rawValue.uppercased() ?? "") · \(stateLabel(step))"
                )
                .font(Typeface.mono(10))
                .tracking(Typeface.tracking(0.14, at: 10))
                .foregroundStyle(
                    (step.isDecayed ? theme.attention : theme.eyebrow).fading(0.85).color)
                .padding(.top, 20)

                MathTextView(
                    source: node?.title ?? step.id.rawValue,
                    size: theme.isDark ? 18 : 20,
                    color: theme.inkStrong.color,
                    face: theme.isDark ? .sans : .serif)

                if let statement = node?.statement, !statement.isEmpty {
                    MathTextView(
                        source: statement, size: theme.isDark ? 13.5 : 14.5,
                        color: theme.ink.color, face: theme.isDark ? .sans : .serif
                    )
                    .lineSpacing(theme.isDark ? 6 : 7)
                    .textSelection(.enabled)
                }

                if let lesson {
                    lessonBody(lesson, theme: theme)
                } else {
                    // Stated rather than hidden: the statement above is real
                    // content, and pretending the step is not in the program
                    // would make coverage gaps invisible exactly where they bite.
                    Text("No lesson authored for this step yet — the statement is the content.")
                        .font(Typeface.mono(10.5))
                        .foregroundStyle(theme.inkFaint.color)
                }

                actions(step, theme: theme)
            }
            .padding(.bottom, 22)
        }
    }

    /// The lesson, §6.6's rhythm: the hook as a lead, the explanation as body
    /// prose, then the labelled sections — worked, interview, pitfalls — and the
    /// recap last. Only what is authored renders; no empty eyebrows.
    private func lessonBody(_ lesson: Lesson, theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(paragraphs(lesson.hook), id: \.self) {
                MathTextView(
                    source: $0, size: theme.isDark ? 13 : 14,
                    color: theme.inkMuted.color, face: theme.isDark ? .sans : .serif)
                .lineSpacing(5)
            }
            ForEach(paragraphs(lesson.explanation), id: \.self) {
                MathTextView(source: $0, size: 13, color: theme.ink.color)
                    .lineSpacing(theme.isDark ? 5 : 6)
                    .textSelection(.enabled)
            }
            section("Worked example", lesson.worked, theme)
            section("In the interview", lesson.interview, theme)
            section("Pitfalls", lesson.pitfalls, theme)
            section("Recap", lesson.recap, theme)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func section(_ label: String, _ text: String?, _ theme: Theme) -> some View {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(label.uppercased())
                    .font(Typeface.mono(9.5, .medium))
                    .tracking(Typeface.tracking(0.16, at: 9.5))
                    .foregroundStyle(theme.eyebrow.fading(0.75).color)
                ForEach(paragraphs(trimmed), id: \.self) {
                    MathTextView(source: $0, size: 13, color: theme.ink.color)
                        .lineSpacing(theme.isDark ? 5 : 6)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 4)
        }
    }

    /// The step's foot: record what just happened, or step out to the panel.
    /// Same three confidence words as everywhere else (D6.3 governs their shape);
    /// grading recomputes the plan, so in adaptive mode the step compresses away
    /// and the bookmark advances — visibly.
    private func actions(_ step: ProgramPlan.Step, theme: Theme) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(step.isLearned ? "review:" : "got it?")
                .font(Typeface.sans(11))
                .foregroundStyle(theme.inkFaint.color)
            ForEach(SelfReportConfidence.allCases, id: \.self) { confidence in
                TextAction(
                    title: confidence.title.lowercased(), size: 11.5, isQuiet: true,
                    accessibilityHint: confidence.detail
                ) {
                    if scores.record(confidence, on: step.id) {
                        expanded.remove(step.id)
                    }
                }
            }
            Spacer(minLength: 12)
            TextAction(
                title: "details →", size: 11, weight: .regular, isQuiet: true,
                accessibilityHint: "Opens the node panel: score, history, prerequisites"
            ) { onSelect(step.id) }
        }
        .padding(.top, 6)
    }

    // MARK: - Progress

    private func progress(_ plan: ProgramPlan, _ theme: Theme) -> some View {
        HStack(spacing: 16) {
            MeasureBar(
                value: plan.stepCount == 0
                    ? 0 : Double(plan.metCount) / Double(plan.stepCount),
                height: 2, tint: theme.measure)
            if let resume = plan.resume {
                Button {
                    openUnit = resume.unit
                    reveal = resume.id
                } label: {
                    Text("resume — \(title(of: resume.unit))")
                        .font(Typeface.mono(10.5))
                        .foregroundStyle(theme.attention.color)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Jump to the first step you have not learned yet")
                .fixedSize()
            }
            Text("\(plan.metCount) / \(plan.stepCount) mastered")
                .font(Typeface.mono(10.5))
                .foregroundStyle(theme.stat.color)
                .fixedSize()
        }
        .padding(.horizontal, theme.isDark ? 40 : 44)
        .padding(.top, 8)
        .padding(.bottom, theme.isDark ? 26 : 28)
        .accessibilityLabel("\(plan.metCount) of \(plan.stepCount) mastered")
    }

    // MARK: - Helpers

    /// Folded YAML scalars keep a blank line as `\n`, so a lesson's paragraphs
    /// arrive newline-separated; `MathTextView` draws one paragraph.
    private func paragraphs(_ text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Preview

#if DEBUG

#Preview("Program") {
    ProgramView(
        program: Program(
            spine: ProgramSpine(parts: [
                .init(title: "Analysis", units: ["analysis.svc"])
            ]),
            lessonUnits: [
                LessonUnit(
                    unit: "analysis.svc",
                    opening: "One chapter, to preview the reader.",
                    lessons: [
                        Lesson(
                            node: "analysis.svc.mvt",
                            hook: "The bridge from local slope to global change.",
                            explanation:
                                "Rolle's theorem plus a tilt.\nThe second paragraph.",
                            worked: "With $f(x) = x^2$ on $[0,2]$: $c = 1$.",
                            interview: "State the hypotheses before the formula.",
                            pitfalls: "Continuity on the closed interval, "
                                + "differentiability on the open one.",
                            recap: "Average slope is attained somewhere inside.")
                    ])
            ]),
        document: NodePanelPreviewData.document,
        scores: NodePanelPreviewData.scores(),
        onSelect: { print("select \($0)") },
        onExit: { print("exit") }
    )
    .frame(width: 1280, height: 800)
}

#endif
