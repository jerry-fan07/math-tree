import GraphCore
import SwiftUI

/// §6.7's player: one node's lesson, one card at a time.
///
/// §6.6 shipped the course as a book — a chapter is a scroll, and the reader's
/// only act is scrolling. This is the same corpus with the interaction the word
/// "teach" implies: a card lands, the reader dismisses it, and every few cards a
/// **check** asks something with a right answer the app can actually verify. The
/// lesson ends on a **mastery set** — the bank's hardest problems for this node,
/// through §5.2's sheet, writing real evidence.
///
/// Three rules from the design are load-bearing here and each is easy to break by
/// accident:
///
/// - **Checks write nothing** (D13.2). Answering one resolves it and renders
///   feedback. Evidence comes from the mastery set and from the self-report at the
///   foot, which are the two instruments §5 already defines. Card position and
///   verdicts are `@State` and persist nowhere — the *bookmark* is
///   `ProgramPlan.resume`, which is derived, and a second notion of position would
///   contradict it.
/// - **Nothing gates** (D13.5). `continue` is always live; a skipped check simply
///   resolves to nothing. What is enforced is the house rhythm: the verdict and the
///   feedback appear only once the reader commits.
/// - **Every lesson plays** (D13.1). `Lesson.cards` falls back to a paging derived
///   from the prose, so a node nobody has authored cards for is still bite-sized —
///   it just cannot check anything, which the player says rather than hides.
struct LessonPlayer: View {
    let node: Node
    let lesson: Lesson
    /// The chapter this node is taught in, for the eyebrow. `nil` outside a spine.
    var unitTitle: String?
    let document: GraphDocument
    let scores: ScoreStore
    /// §6.7's mastery set — `ProblemBank.masterySet(for:)`, hardest first (D13.6).
    /// Empty where the bank cannot yet ask about this node, which leaves
    /// self-report as the only instrument (§5.4's "whenever possible" cuts both
    /// ways).
    var mastery: [Problem] = []
    /// Open a mastery problem in §5.2's sheet, over the player.
    var onAttempt: ((Problem, NodeID) -> Void)?
    /// §6.6's reader, for the whole chapter around this one step.
    var onRead: ((NodeID) -> Void)?
    var onExit: () -> Void
    /// Offscreen-render seams, the same ones `ProblemSheet` needed and for the same
    /// reason: input cannot be driven headlessly, so the only way to *look at* a
    /// resolved check is to open the player already showing one. Set by
    /// `PanelShot`; nothing in the app sets them.
    var startCard = 0
    var startResolved = false

    @State private var index = 0
    /// Card index → the choice row the reader picked.
    @State private var picked: [Int: Int] = [:]
    /// Card index → what the reader typed.
    @State private var typed: [Int: String] = [:]
    /// Cards whose check has been committed. Resolution is per card, not a single
    /// flag, so paging back to a check shows the verdict it already gave.
    @State private var resolved: Set<Int> = []
    @State private var hinted: Set<Int> = []
    /// The live text field, mirrored into `typed` on commit.
    @State private var draft = ""

    @FocusState private var isTypingFocused: Bool

    private var cards: [LessonCard] { lesson.cards }

    /// One past the last card: the mastery set and the self-report, which is where
    /// a lesson *ends* rather than a card it contains.
    private var isFinish: Bool { index >= cards.count }

    private var card: LessonCard? { cards.indices.contains(index) ? cards[index] : nil }

    var body: some View {
        let theme = ThemeStore.shared.theme
        // Read on purpose: a mastery problem graded in the sheet above this view
        // must move the read-outs at its foot.
        _ = scores.revision

        return VStack(spacing: 0) {
            header(theme)
            Rule()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isFinish {
                        finish(theme)
                    } else if let card {
                        cardBody(card, theme)
                    } else {
                        // A lesson with no prose and no steps cannot happen in a
                        // validated corpus (hook, explanation and recap are
                        // required), so this states the impossible rather than
                        // rendering an empty column.
                        Text("This lesson has no cards to show.")
                            .font(Typeface.sans(13))
                            .foregroundStyle(theme.inkMuted.color)
                    }
                }
                .frame(maxWidth: 660, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, theme.isDark ? 40 : 44)
                .padding(.top, 30)
                .padding(.bottom, 34)
                // The card is the unit of attention: crossfading rather than
                // sliding keeps the reading position fixed, which is what makes a
                // sequence of cards feel like one lesson instead of a carousel.
                .id(index)
                .transition(.opacity)
            }
            Rule()
            foot(theme)
        }
        .background(theme.canvasEdge.color)
        .background(.ultraThinMaterial)
        .onAppear {
            index = min(max(startCard, 0), cards.count)
            if startResolved, cards.indices.contains(index) {
                // Whatever the authored answer is, so the shot shows a *correct*
                // resolution rather than an arbitrary one.
                if let correct = cards[index].check?.correctIndex { picked[index] = correct }
                if let expects = cards[index].check?.expects { typed[index] = expects }
                resolved.insert(index)
            }
        }
    }

    // MARK: - Header

    private func header(_ theme: Theme) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: theme.isDark ? 9 : 10) {
                Text(eyebrowText)
                    .font(Typeface.mono(10.5))
                    .tracking(Typeface.tracking(0.18, at: 10.5))
                    .foregroundStyle(theme.eyebrow.color)
                MathTextView(
                    source: node.title,
                    size: theme.isDark ? 24 : 26,
                    weight: theme.isDark ? .light : .regular,
                    color: theme.inkStrong.color,
                    face: theme.isDark ? .sans : .serif
                )
                .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            HStack(spacing: 22) {
                Text(counter)
                if let onRead {
                    Button { onRead(node.id) } label: {
                        Text("read the chapter")
                            .foregroundStyle(theme.statEmphasis.color)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open the program's reader at this node, in its chapter")
                }
                Button(action: onExit) {
                    Text("esc — close")
                        .foregroundStyle(theme.statEmphasis.color)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the lesson")
            }
            .font(Typeface.mono(11))
            .foregroundStyle(theme.stat.color)
            .fixedSize()
        }
        .padding(.horizontal, theme.isDark ? 40 : 44)
        .padding(.top, theme.isDark ? 30 : 32)
        .padding(.bottom, theme.isDark ? 20 : 22)
    }

    private var eyebrowText: String {
        let kind = node.kind.rawValue.uppercased()
        guard let unitTitle else { return "LESSON · \(kind)" }
        return "LESSON · \(kind) · \(unitTitle.uppercased())"
    }

    private var counter: String {
        isFinish ? "mastery" : "\(index + 1) / \(cards.count)"
    }

    // MARK: - Cards

    @ViewBuilder
    private func cardBody(_ card: LessonCard, _ theme: Theme) -> some View {
        if let check = card.check {
            checkCard(card, check: check, theme)
        } else {
            teachCard(card, theme)
        }
    }

    /// A teaching beat. One idea, set at reading size with nothing else on screen —
    /// which is the entire mechanism: prose invites skimming, a card the reader has
    /// to dismiss does not.
    private func teachCard(_ card: LessonCard, _ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            MathTextView(
                source: card.teach ?? "",
                size: theme.isDark ? 16.5 : 17.5,
                color: theme.ink.color,
                face: theme.isDark ? .sans : .serif
            )
            .lineSpacing(theme.isDark ? 8 : 9)
            .textSelection(.enabled)
            if index == 0, !lesson.isInteractive {
                derivedNote(theme)
            }
        }
    }

    /// D13.1's honesty: a lesson nobody has authored cards for is paged off its
    /// written form. Saying so is the difference between a coverage gradient the
    /// reader understands and a surface that seems inexplicably passive.
    private func derivedNote(_ theme: Theme) -> some View {
        Text(
            "This lesson is paged from its written form — it reads one idea at a time, "
                + "but no checks are authored for it yet."
        )
        .font(Typeface.mono(10))
        .foregroundStyle(theme.inkFaint.fading(0.7).color)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 8)
    }

    /// A check. The question, the way to answer it, and — only once the reader
    /// commits — the verdict and the authored feedback (D13.5).
    private func checkCard(_ card: LessonCard, check: AnswerCheck, _ theme: Theme) -> some View {
        let isResolved = resolved.contains(index)
        return VStack(alignment: .leading, spacing: 18) {
            Text("CHECK")
                .font(Typeface.mono(10, .medium))
                .tracking(Typeface.tracking(0.18, at: 10))
                .foregroundStyle(theme.attention.fading(0.9).color)

            MathTextView(
                source: card.ask ?? "",
                size: theme.isDark ? 16 : 17,
                color: theme.inkStrong.color,
                face: theme.isDark ? .sans : .serif
            )
            .lineSpacing(theme.isDark ? 7 : 8)
            .textSelection(.enabled)

            switch check.form {
            case .choice:
                choiceRows(check, isResolved: isResolved, theme)
            case .typed:
                typedField(check, isResolved: isResolved, theme)
            }

            if let hint = card.hint, !hint.isEmpty, !isResolved {
                if hinted.contains(index) {
                    labelled("HINT", hint, tint: theme.attention, theme)
                } else {
                    TextAction(
                        title: "need a hint?", size: 11.5, weight: .regular, isQuiet: true,
                        accessibilityHint: "Reveals a hint without revealing the answer"
                    ) { hinted.insert(index) }
                }
            }

            if isResolved {
                verdict(check, theme)
            }
        }
    }

    private func choiceRows(_ check: AnswerCheck, isResolved: Bool, _ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(check.choices.enumerated()), id: \.offset) { position, choice in
                ChoiceRow(
                    label: Self.letters[position % Self.letters.count],
                    choice: choice,
                    isPicked: picked[index] == position,
                    isResolved: isResolved,
                    onPick: {
                        guard !isResolved else { return }
                        picked[index] = position
                    })
            }
        }
    }

    private static let letters = ["A", "B", "C", "D", "E", "F"]

    private func typedField(_ check: AnswerCheck, isResolved: Bool, _ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isResolved {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("you answered")
                        .font(Typeface.mono(10))
                        .foregroundStyle(theme.eyebrowCount.color)
                    Text(typed[index]?.isEmpty == false ? typed[index]! : "—")
                        .font(Typeface.mono(13))
                        .foregroundStyle(theme.inkStrong.color)
                        .textSelection(.enabled)
                }
            } else {
                HStack(spacing: 12) {
                    TextField("your answer", text: $draft)
                        .textFieldStyle(.plain)
                        .font(Typeface.mono(14))
                        .foregroundStyle(theme.inkStrong.color)
                        .focused($isTypingFocused)
                        .frame(maxWidth: 220)
                        .onSubmit { commit(check) }
                        .accessibilityLabel("Your answer")
                    Rectangle()
                        .fill(theme.hairline.color)
                        .frame(height: 1)
                }
                .overlay(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(theme.rule.color)
                        .frame(width: 220, height: 1)
                        .offset(y: 6)
                }
                Text("A fraction, a decimal or a percentage — $7/15$, $0.4667$ and $46.67\\%$ all read the same.")
                    .font(Typeface.mono(9.5))
                    .foregroundStyle(theme.inkFaint.fading(0.7).color)
                    .padding(.top, 6)
            }
        }
    }

    /// Right or wrong, said plainly, then the reason. A reader who guessed
    /// correctly still needs the reason, which is why `feedback` is required of
    /// every check rather than only of the wrong rows.
    private func verdict(_ check: AnswerCheck, _ theme: Theme) -> some View {
        let correct = isAnswerCorrect(check)
        let skipped = !hasAnswer(check)
        return VStack(alignment: .leading, spacing: 10) {
            Rule()
            Text(skipped ? "Skipped." : (correct ? "Correct." : "Not quite."))
                .font(Typeface.sans(13.5, .medium))
                .foregroundStyle((skipped ? theme.inkMuted : (correct ? theme.action : theme.warning)).color)
                .padding(.top, 12)
            if check.form == .typed, let expects = check.expects, !correct {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("the answer is")
                        .font(Typeface.mono(10))
                        .foregroundStyle(theme.eyebrowCount.color)
                    MathTextView(source: expects, size: 13, color: theme.inkStrong.color)
                }
            }
            MathTextView(
                source: feedbackText(check), size: 13.5, color: theme.ink.color,
                face: theme.isDark ? .sans : .serif
            )
            .lineSpacing(theme.isDark ? 6 : 7)
            .textSelection(.enabled)
        }
    }

    private func feedbackText(_ check: AnswerCheck) -> String {
        if check.form == .choice, let choice = picked[index] {
            return check.feedback(forChoiceAt: choice)
        }
        return check.feedback
    }

    private func labelled(
        _ label: String, _ text: String, tint: ThemeColor, _ theme: Theme
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(Typeface.mono(9.5, .medium))
                .tracking(Typeface.tracking(0.16, at: 9.5))
                .foregroundStyle(tint.fading(0.75).color)
            MathTextView(source: text, size: 13, color: theme.ink.color)
                .lineSpacing(theme.isDark ? 5 : 6)
        }
    }

    // MARK: - Answering

    private func hasAnswer(_ check: AnswerCheck) -> Bool {
        switch check.form {
        case .choice: return picked[index] != nil
        case .typed: return !(typed[index] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func isAnswerCorrect(_ check: AnswerCheck) -> Bool {
        switch check.form {
        case .choice:
            guard let choice = picked[index] else { return false }
            return check.isCorrect(choiceAt: choice)
        case .typed:
            guard let answer = typed[index] else { return false }
            return check.isCorrect(typed: answer)
        }
    }

    private func commit(_ check: AnswerCheck) {
        if check.form == .typed { typed[index] = draft }
        guard hasAnswer(check) else { return }
        isTypingFocused = false
        withAnimation(.easeOut(duration: 0.18)) { _ = resolved.insert(index) }
    }

    // MARK: - Finish

    /// Where a lesson ends: the mastery set, and the self-report beside it.
    ///
    /// The set is offered, never required (D13.5) — the point of putting it here is
    /// that the reader has just been taught the thing, which is the moment a hard
    /// problem measures the most, not a toll gate on leaving.
    private func finish(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("MASTERY")
                    .font(Typeface.mono(10, .medium))
                    .tracking(Typeface.tracking(0.18, at: 10))
                    .foregroundStyle(theme.eyebrow.color)
                MathTextView(
                    source: lesson.recap, size: theme.isDark ? 16 : 17,
                    color: theme.inkStrong.color, face: theme.isDark ? .sans : .serif
                )
                .lineSpacing(theme.isDark ? 7 : 8)
            }

            if mastery.isEmpty {
                Text(
                    "No problem in the bank targets this node yet, so the only instrument here "
                        + "is your own report."
                )
                .font(Typeface.sans(12.5))
                .foregroundStyle(theme.inkMuted.color)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "\(mastery.count) problem\(mastery.count == 1 ? "" : "s") that test this, "
                            + "hardest first. Passing one records a review here and, more weakly, "
                            + "on its prerequisites."
                    )
                    .font(Typeface.sans(12.5))
                    .foregroundStyle(theme.inkMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(mastery) { problem in
                            MasteryRow(
                                problem: problem,
                                isAttempted: scores.hasAttempted(problem.id),
                                onStart: { onAttempt?(problem, node.id) })
                        }
                    }
                }
            }

            Rule()
            selfReport(theme)
        }
    }

    private func selfReport(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(scores.isLearned(node.id) ? "review this:" : "how did that land?")
                .font(Typeface.sans(11.5))
                .foregroundStyle(theme.inkFaint.color)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                ForEach(SelfReportConfidence.allCases, id: \.self) { confidence in
                    TextAction(
                        title: confidence.title.lowercased(), size: 12, isQuiet: true,
                        accessibilityHint: confidence.detail
                    ) {
                        scores.record(confidence, on: node.id)
                    }
                }
                Spacer(minLength: 12)
                TextAction(
                    title: "done →", size: 12, weight: .regular, isQuiet: true,
                    accessibilityHint: "Closes the lesson"
                ) { onExit() }
            }
            Text(
                "A self-report is a claim about a feeling; the problems above are a "
                    + "measurement. Both land in the same log."
            )
            .font(Typeface.mono(9.5))
            .foregroundStyle(theme.inkFaint.fading(0.7).color)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Foot

    private func foot(_ theme: Theme) -> some View {
        let check = card?.check
        let isResolved = resolved.contains(index)
        return HStack(spacing: 18) {
            TextAction(
                title: "← back", size: 11.5, weight: .regular, isQuiet: true,
                accessibilityHint: "The previous card"
            ) { step(by: -1) }
            .opacity(index == 0 ? 0.25 : 1)
            .disabled(index == 0)

            MeasureBar(
                value: Double(index) / Double(max(cards.count, 1)), height: 2,
                tint: isFinish ? theme.action : nil)

            if let check, !isResolved {
                // Attempt, then reveal — but `continue` stays live beside it, so
                // the rhythm is enforced without the gate (D13.5).
                if hasAnswer(check) || !draft.isEmpty {
                    TextAction(
                        title: "check", size: 12,
                        accessibilityHint: "Reveals whether that is right, and why"
                    ) { commit(check) }
                } else {
                    TextAction(
                        title: "skip →", size: 11.5, weight: .regular, isQuiet: true,
                        accessibilityHint: "Moves on without answering"
                    ) { step(by: 1) }
                }
            } else if !isFinish {
                TextAction(
                    title: index == cards.count - 1 ? "finish →" : "continue →", size: 12,
                    accessibilityHint: "The next card"
                ) { step(by: 1) }
            } else {
                Text("\(resolved.count) of \(checkCount) checks answered")
                    .font(Typeface.mono(10))
                    .foregroundStyle(theme.stat.color)
                    .fixedSize()
            }
        }
        .padding(.horizontal, theme.isDark ? 40 : 44)
        .padding(.top, 14)
        .padding(.bottom, theme.isDark ? 24 : 26)
    }

    private var checkCount: Int { cards.count(where: \.isCheck) }

    private func step(by delta: Int) {
        let next = min(max(index + delta, 0), cards.count)
        guard next != index else { return }
        withAnimation(.easeInOut(duration: 0.2)) { index = next }
        draft = typed[next] ?? ""
        // A check the reader has arrived at is the one place in the app that wants
        // the keyboard without being asked for it.
        isTypingFocused = cards.indices.contains(next) && cards[next].check?.form == .typed
            && !resolved.contains(next)
    }
}

// MARK: - Rows

/// One row of a multiple-choice check. Unresolved it is a target; resolved it is a
/// read-out — the correct row takes the accent whether or not the reader picked it,
/// and a wrong pick is marked as theirs rather than merely un-highlighted.
private struct ChoiceRow: View {
    let label: String
    let choice: AnswerChoice
    let isPicked: Bool
    let isResolved: Bool
    let onPick: () -> Void

    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        let tint: ThemeColor =
            isResolved
            ? (choice.correct ? theme.action : (isPicked ? theme.warning : theme.inkMuted))
            : (isPicked ? theme.action : theme.ink)
        Button(action: onPick) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text(marker)
                    .font(Typeface.mono(11, .medium))
                    .foregroundStyle(tint.color)
                    .frame(width: 14, alignment: .leading)
                MathTextView(source: choice.text, size: 13.5, color: tint.color)
                Spacer(minLength: 8)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(
                (isPicked || (isResolved && choice.correct))
                    ? theme.rowHighlight.color
                    : (isHovering && !isResolved ? theme.rowHighlight.fading(0.5).color : .clear)
            )
            .overlay(alignment: .leading) {
                // The redesign marks a chosen row with a rule, not a fill or a
                // radio button — the same subtraction as everywhere else.
                Rectangle()
                    .fill(tint.color)
                    .frame(width: 2)
                    .opacity(isPicked || (isResolved && choice.correct) ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isResolved)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Option \(label): \(MathText.plainText(choice.text))")
        .accessibilityAddTraits(isPicked ? [.isSelected] : [])
    }

    private var marker: String {
        guard isResolved else { return label }
        if choice.correct { return "✓" }
        return isPicked ? "✗" : label
    }
}

/// One mastery problem, offered. The statement is trimmed to a line — the sheet is
/// where a problem is *read*, and a wall of three full statements here would bury
/// the choice between them.
private struct MasteryRow: View {
    let problem: Problem
    let isAttempted: Bool
    let onStart: () -> Void

    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        Button(action: onStart) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(problem.difficulty.rawValue)
                    .font(Typeface.mono(9.5))
                    .foregroundStyle(
                        (problem.difficulty == .demanding ? theme.attention : theme.eyebrowCount)
                            .color)
                    .frame(width: 68, alignment: .leading)
                MathTextView(
                    source: problem.statement, size: 12.5,
                    color: (isHovering ? theme.inkStrong : theme.rowTitle).color)
                .lineLimit(2)
                Spacer(minLength: 8)
                Text(isAttempted ? "seen" : (problem.isChecked ? "checked" : "self-graded"))
                    .font(Typeface.mono(9.5))
                    .foregroundStyle(theme.rowTrailing.color)
                    .fixedSize()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(isHovering ? theme.rowHighlight.color : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(problem.id.rawValue)
        .accessibilityLabel(
            "\(problem.difficulty.rawValue) problem: \(MathText.plainText(problem.statement))")
    }
}

// MARK: - Preview

#if DEBUG

    #Preview("Lesson player") {
        LessonPlayer(
            node: NodePanelPreviewData.document[
                NodePanelPreviewData.document.index(of: "analysis.svc.mvt") ?? 0],
            lesson: Lesson(
                node: "analysis.svc.mvt",
                hook: "The bridge from local slope to global change.",
                explanation: "Rolle's theorem plus a tilt.\nThe second paragraph.",
                worked: "With $f(x) = x^2$ on $[0,2]$: $c = 1$.",
                recap: "Average slope is attained somewhere inside.",
                steps: [
                    LessonCard(
                        teach: "Rolle's theorem is the flat case: equal endpoints force a "
                            + "stationary point strictly inside."),
                    LessonCard(
                        ask: "For $f(x) = x^2$ on $[0, 2]$, which $c$ does the theorem produce?",
                        expects: "1",
                        feedback: "The average slope is $2$, and $f'(c) = 2c = 2$ gives $c = 1$."),
                    LessonCard(
                        ask: "Which hypothesis does $f(x) = |x|$ on $[-1, 1]$ break?",
                        choices: [
                            AnswerChoice(
                                text: "Continuity on $[-1, 1]$",
                                feedback: "$|x|$ is continuous everywhere."),
                            AnswerChoice(
                                text: "Differentiability on $(-1, 1)$", correct: true,
                                feedback: "The corner at $0$ is inside the open interval."),
                        ],
                        feedback: "Differentiability is required on the *open* interval only, "
                            + "and $0$ is in it."),
                ]),
            unitTitle: "Single-variable calculus",
            document: NodePanelPreviewData.document,
            scores: NodePanelPreviewData.scores(),
            onExit: { print("exit") }
        )
        .frame(width: 1100, height: 760)
    }

#endif
