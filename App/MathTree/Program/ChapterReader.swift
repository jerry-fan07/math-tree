import GraphCore
import SwiftUI

/// Phase 12's reader, kept whole: the unit as a *chapter* — its opening, then
/// every step in the plan's teaching order as title · statement · lesson, with
/// the self-report action at each lesson's foot so the loop closes without
/// leaving the page.
///
/// Two starting points, one derivation (§6.6): "show everything" renders every
/// step in full; the default adapts to what the user knows by compressing met
/// steps to one quiet line each — expandable, because compression is an answer
/// to "where do I start", never a lock.
struct ChapterReader: View {
    let program: Program
    let plan: ProgramPlan
    let unit: ProgramPlan.Unit
    /// A node to scroll to on appear — the panel's "read the lesson" jump.
    var target: NodeID?
    let document: GraphDocument
    let scores: ScoreStore
    var onSelect: (NodeID) -> Void
    var onPlay: ((NodeID) -> Void)?

    /// Met steps the user chose to reread in adaptive mode.
    @State private var expanded: Set<NodeID> = []
    /// §6.6's "from the beginning" — every step in full, no compression.
    @AppStorage("MathTree.program.showEverything") private var showEverything = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    chapterHead(theme)
                    if unit.isAuthored {
                        let compressed = compressedCount()
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
            .onAppear {
                if let target {
                    expanded.insert(target)
                    // Layout has to settle before the anchor exists to scroll to.
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func title(of id: NodeID) -> String {
        document.index(of: id).map { document[$0].title } ?? id.rawValue
    }

    private func chapterHead(_ theme: Theme) -> some View {
        let part = plan.parts.first { $0.units.contains(where: { $0.id == unit.id }) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("UNIT \(unit.index + 1) · \(part?.title.uppercased() ?? "") · AS A CHAPTER")
                    .font(Typeface.mono(10))
                    .tracking(Typeface.tracking(0.16, at: 10))
                    .foregroundStyle(theme.eyebrow.fading(0.7).color)
                Spacer(minLength: 0)
                // The other starting point, one click away — a mode, not a fork.
                Button {
                    showEverything.toggle()
                } label: {
                    Text(showEverything ? "adapt to what I know" : "show everything")
                        .font(Typeface.mono(10.5))
                        .foregroundStyle(theme.statEmphasis.color)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(
                    showEverything
                        ? "Compress the steps you already hold to one line each"
                        : "Show every step in full, from the beginning")
            }
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
                    Text("\(unit.metCount) / \(unit.steps.count) proficient")
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

    private func compressedCount() -> Int {
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
                MasteryDot(level: scores.level(of: step.id), diameter: 5)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                MathTextView(source: title(of: step.id), size: 12, color: theme.inkMuted.color)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(scores.level(of: step.id).title.lowercased())
                    .font(Typeface.mono(10))
                    .foregroundStyle(theme.eyebrowCount.color)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Held — open to reread")
    }

    private func stateLabel(_ step: ProgramPlan.Step) -> String {
        let level = scores.level(of: step.id)
        if step.isDecayed { return "DECAYED · \(level.title.uppercased())" }
        return level.title.uppercased()
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

                if !step.forward.isEmpty {
                    Text(
                        "Uses " + step.forward.map { title(of: $0) }.joined(separator: ", ")
                            + ", taught in a later unit — take it on trust here."
                    )
                    .font(Typeface.mono(10))
                    .foregroundStyle(theme.inkFaint.fading(0.8).color)
                    .fixedSize(horizontal: false, vertical: true)
                }

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

    /// The step's foot: play it, record what just happened, or step out to the
    /// panel. Grading recomputes the plan, so in adaptive mode the step
    /// compresses away and the bookmark advances — visibly.
    private func actions(_ step: ProgramPlan.Step, theme: Theme) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if let onPlay, program.lesson(for: step.id) != nil {
                TextAction(
                    title: "Play this step →", size: 11.5,
                    accessibilityHint:
                        "Teaches this step one card at a time, ending in problems"
                ) { onPlay(step.id) }
            }
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

    /// Folded YAML scalars keep a blank line as `\n`, so a lesson's paragraphs
    /// arrive newline-separated; `MathTextView` draws one paragraph.
    private func paragraphs(_ text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
