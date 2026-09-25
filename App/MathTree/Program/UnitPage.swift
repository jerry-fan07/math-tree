import GraphCore
import SwiftUI

/// One unit of the course: what it is for, how it is going, and its skills in
/// teaching order with the actions each one takes.
///
/// A skill row is the unit page's whole argument. Each carries its rung on the
/// ladder (§6.8) as a dot and a word, and on hover the three things you can do
/// with it — learn (§6.7's player), practice (§5.2's problem), details (the
/// panel). The unit test sits at the foot because that is where a unit ends.
struct UnitPage: View {
    let program: Program
    let plan: ProgramPlan
    let unit: ProgramPlan.Unit
    let document: GraphDocument
    let scores: ScoreStore
    var onSelect: (NodeID) -> Void
    var onPlay: ((NodeID) -> Void)?
    var onPractice: ((NodeID) -> Void)?
    var onUnitTest: ((NodeID) -> Void)?
    var onReadChapter: () -> Void

    var body: some View {
        let theme = ThemeStore.shared.theme
        let summary = scores.masterySummary(of: unit.steps.map(\.id))
        let paper = UnitTest.paper(
            for: unit.steps, bank: scores.bank, level: { scores.level(of: $0) },
            attempted: scores.attemptedProblems)
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                opening(theme)
                if unit.isAuthored {
                    ladder(summary, theme)
                    actions(paper, theme)
                    forwardNote(theme)
                    skills(theme)
                    testSection(paper, theme)
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
    }

    private func title(of id: NodeID) -> String {
        document.index(of: id).map { document[$0].title } ?? id.rawValue
    }

    private func node(_ id: NodeID) -> Node? {
        document.index(of: id).map { document[$0] }
    }

    // MARK: - Head

    private func opening(_ theme: Theme) -> some View {
        let part = plan.parts.first { $0.units.contains(where: { $0.id == unit.id }) }
        let text = program.opening(of: unit.id) ?? node(unit.id)?.summary ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            Text(
                "UNIT \(unit.index + 1) OF \(plan.units.count) · \(part?.title.uppercased() ?? "") · "
                    + "\(unit.steps.count) SKILL\(unit.steps.count == 1 ? "" : "S")"
            )
            .font(Typeface.mono(10))
            .tracking(Typeface.tracking(0.16, at: 10))
            .foregroundStyle(theme.eyebrow.fading(0.7).color)
            ForEach(paragraphs(text), id: \.self) {
                MathTextView(
                    source: $0, size: theme.isDark ? 14.5 : 15.5,
                    color: theme.ink.color, face: theme.isDark ? .sans : .serif)
                .lineSpacing(theme.isDark ? 6 : 7)
            }
        }
    }

    private func ladder(_ summary: MasterySummary, _ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            MasteryBar(summary: summary, height: 4)
            HStack(alignment: .firstTextBaseline) {
                MasteryLegend(summary: summary)
                Spacer(minLength: 0)
                Text("\(MasteryFormat.points(summary)) · \(MasteryFormat.percent(summary))")
                    .font(Typeface.mono(10.5))
                    .foregroundStyle(theme.statEmphasis.color)
            }
        }
    }

    /// The unit's first step that has never been learned, else its first that
    /// is not mastered, else its first — "continue" always has somewhere to go.
    private var continueStep: ProgramPlan.Step? {
        unit.steps.first { !$0.isLearned }
            ?? unit.steps.first { scores.level(of: $0.id) < .mastered }
            ?? unit.steps.first
    }

    private func actions(_ paper: UnitTest.Paper, _ theme: Theme) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            if let onPlay, let step = continueStep {
                TextAction(
                    title: unit.learnedCount == 0
                        ? "Start the unit →"
                        : (unit.learnedCount == unit.steps.count
                            ? "Review the unit →" : "Continue the unit →"),
                    size: 13,
                    accessibilityHint: "Plays \(title(of: step.id)), one card at a time"
                ) { onPlay(step.id) }
            }
            if let onUnitTest, !paper.isEmpty {
                TextAction(
                    title: "Unit test · \(paper.questions.count) problem\(paper.questions.count == 1 ? "" : "s")",
                    size: 12.5, weight: .regular, isQuiet: true,
                    accessibilityHint: "One problem per skill, in order; passes write real evidence"
                ) { onUnitTest(unit.id) }
            }
            TextAction(
                title: "Read as a chapter", size: 12.5, weight: .regular, isQuiet: true,
                accessibilityHint: "The unit as one continuous text"
            ) { onReadChapter() }
        }
    }

    /// D15.2's honesty on the page: a step that leans on a later unit says so
    /// once, up here, and again on its row.
    @ViewBuilder
    private func forwardNote(_ theme: Theme) -> some View {
        let forward = unit.steps.filter { !$0.forward.isEmpty }
        if !forward.isEmpty {
            Text(
                "\(forward.count) skill\(forward.count == 1 ? "" : "s") here use\(forward.count == 1 ? "s" : "") "
                    + "an idea taught in a later unit — the lesson names it and asks you to take it on "
                    + "trust for now."
            )
            .font(Typeface.mono(10))
            .foregroundStyle(theme.inkFaint.fading(0.75).color)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Skills

    private func skills(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(title: "Skills, in teaching order", count: unit.steps.count)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(unit.steps.enumerated()), id: \.element.id) { index, step in
                    SkillRow(
                        number: index + 1,
                        step: step,
                        node: node(step.id),
                        level: scores.level(of: step.id),
                        isBookmarked: step.id == plan.resume?.id,
                        canPlay: onPlay != nil && program.lesson(for: step.id) != nil,
                        isDialogue: program.lesson(for: step.id)?.isDialogue == true,
                        canPractice: onPractice != nil && scores.canProbe(step.id),
                        forwardTitles: step.forward.map { title(of: $0) },
                        onPlay: { onPlay?(step.id) },
                        onPractice: { onPractice?(step.id) },
                        onSelect: { onSelect(step.id) })
                }
            }
            .padding(.horizontal, -8)
        }
    }

    // MARK: - Unit test

    @ViewBuilder
    private func testSection(_ paper: UnitTest.Paper, _ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rule()
            Eyebrow(title: "Unit test")
                .padding(.top, 8)
            if paper.isEmpty {
                Text(
                    "No problem in the bank targets any skill of this unit yet, so there is no "
                        + "test to sit — each lesson ends on your own report instead."
                )
                .font(Typeface.sans(12.5))
                .foregroundStyle(theme.inkMuted.color)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(testDescription(paper))
                    .font(Typeface.sans(12.5))
                    .foregroundStyle(theme.inkMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let onUnitTest {
                    TextAction(
                        title: "Start the unit test →", size: 13,
                        accessibilityHint: "One problem per skill, in teaching order"
                    ) { onUnitTest(unit.id) }
                }
            }
        }
    }

    private func testDescription(_ paper: UnitTest.Paper) -> String {
        var text =
            "\(paper.questions.count) problem\(paper.questions.count == 1 ? "" : "s"), one per skill in "
            + "teaching order, at standard difficulty. A pass records a review on the skill and, "
            + "more weakly, on its prerequisites; a miss asks where it broke."
        if !paper.omitted.isEmpty {
            text +=
                " Skills you have already mastered are left out when the paper would run past "
                + "\(UnitTest.defaultLimit)."
        }
        if !paper.unaskable.isEmpty {
            text +=
                " \(paper.unaskable.count) skill\(paper.unaskable.count == 1 ? " has" : "s have") no "
                + "problem in the bank yet and \(paper.unaskable.count == 1 ? "is" : "are") skipped."
        }
        return text
    }

    private func paragraphs(_ text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// One skill: number, rung, title, kind — and on hover, what to do with it.
private struct SkillRow: View {
    let number: Int
    let step: ProgramPlan.Step
    let node: Node?
    let level: MasteryLevel
    let isBookmarked: Bool
    let canPlay: Bool
    /// §6.9: taught question-first, as a dialogue, rather than as cards.
    let isDialogue: Bool
    let canPractice: Bool
    let forwardTitles: [String]
    let onPlay: () -> Void
    let onPractice: () -> Void
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        Button(action: canPlay ? onPlay : onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", number))
                    .font(Typeface.mono(10))
                    .foregroundStyle((isBookmarked ? theme.attention : theme.eyebrowCount).color)
                    .frame(width: 20, alignment: .leading)
                MasteryDot(level: level)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                VStack(alignment: .leading, spacing: 4) {
                    MathTextView(
                        source: node?.title ?? step.id.rawValue,
                        size: theme.isDark ? 14 : 14.5,
                        color: (isHovering ? theme.inkStrong : theme.ink).color,
                        face: theme.isDark ? .sans : .serif)
                    Text(meta)
                        .font(Typeface.mono(9.5))
                        .tracking(Typeface.tracking(0.1, at: 9.5))
                        .foregroundStyle(
                            (step.isDecayed ? theme.attention : theme.inkFaint).fading(0.9).color)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if isHovering {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        if canPlay {
                            Text("learn →")
                                .font(Typeface.sans(10.5, .medium))
                                .foregroundStyle(theme.action.color)
                        }
                        if canPractice {
                            Button(action: onPractice) {
                                Text("practice")
                                    .font(Typeface.sans(10.5, .medium))
                                    .foregroundStyle(theme.inkMuted.color)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Review this skill with a problem")
                        }
                        Button(action: onSelect) {
                            Text("details")
                                .font(Typeface.sans(10.5, .medium))
                                .foregroundStyle(theme.inkMuted.color)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Score, history, prerequisites")
                    }
                } else {
                    Text(level.title.lowercased())
                        .font(Typeface.mono(10.5))
                        .foregroundStyle(level.tint(theme).color)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(isHovering ? theme.rowHighlight.color : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(level.detail)
        .accessibilityLabel(
            "Skill \(number), \(node?.title ?? step.id.rawValue), \(level.title)")
    }

    private var meta: String {
        var parts = [node?.kind.rawValue.uppercased() ?? ""]
        if isDialogue { parts.append("DIALOGUE") }
        if step.isDecayed { parts.append("DECAYED · DUE") }
        if !forwardTitles.isEmpty {
            parts.append("USES " + forwardTitles.joined(separator: ", ").uppercased() + " (LATER)")
        }
        return parts.joined(separator: " · ")
    }
}
