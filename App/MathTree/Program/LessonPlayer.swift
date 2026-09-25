import GraphCore
import SwiftUI

/// Where a lesson sits in its course (§6.8): the eyebrow's "unit 4 of 58 ·
/// skill 3 of 18", and the step the finish offers next. `nil` for a node
/// played outside any spine.
struct LessonContext: Equatable {
    var unit: NodeID
    var unitTitle: String
    var unitIndex: Int
    var unitCount: Int
    var skillIndex: Int
    var skillCount: Int
    /// The next step of the unit in teaching order; `nil` on the last.
    var next: NodeID?
    var nextTitle: String?
}

/// §6.9's player: one node's lesson, played as a Socratic dialogue.
///
/// §6.7 shipped the lesson as a deck — one card on screen, dismissed with a click
/// — and the deck taught the way a textbook does: a beat says the idea, a check
/// asks for it back. A dialogue reverses the order, and the surface has to
/// follow: the question comes *before* the idea, and every later question leans
/// on a situation set up earlier, so the lesson is a **transcript** that grows.
/// Everything up to the first unanswered question is on the page; answering it
/// unfolds the next stretch (D16.1). The model is the competitive-programming
/// tutor's dialogue view, in this app's grammar.
///
/// The rules that are load-bearing, and easy to break by accident:
///
/// - **Checks write nothing** (D13.2). The session is `@State` and dies with the
///   player; evidence still comes only from the mastery set and the self-report
///   at the foot. The bookmark stays `ProgramPlan.resume`.
/// - **A question is a gate, never a lock** (D16.1, amending D13.5). The next
///   stretch waits for an answer — that is what makes the reader reach before
///   being told — but "show me" is on every question, and a reflection accepts
///   whatever is written, including nothing.
/// - **A wrong answer stays on the page** (D16.3). A wrong row is ruled out with
///   its authored feedback beneath it and the reader picks again; a wrong typed
///   value is listed with which way it missed. The distractor's feedback is read
///   exactly when it teaches most.
/// - **Every lesson plays** (D13.1). `Lesson.cards` falls back from `dialogue` to
///   `steps` to a paging derived from the prose, and all three play through the
///   same transcript — a steps lesson simply has no part titles, and a derived
///   one asks nothing and so shows whole.
struct LessonPlayer: View {
    let node: Node
    let lesson: Lesson
    /// The chapter this node is taught in, for the eyebrow. `nil` outside a spine.
    var unitTitle: String?
    /// §6.8's position in the course, and what comes next.
    var context: LessonContext?
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
    /// §6.8: the unit page this lesson belongs to.
    var onUnit: ((NodeID) -> Void)?
    /// §6.8: play the next step of the unit — the loop a course is built on.
    var onNext: ((NodeID) -> Void)?
    var onExit: () -> Void
    /// Escape, while the player holds the keyboard. The owner decides what it
    /// closes — a problem sheet over the player goes first — so this defaults to
    /// closing the lesson only where no owner says otherwise.
    var onEscape: (() -> Void)?
    /// Offscreen-render seams, the same ones `ProblemSheet` needed and for the same
    /// reason: input cannot be driven headlessly, so the only way to *look at* a
    /// dialogue part-way through is to open it there. `startCard` answers every
    /// question before that card correctly; `startResolved` answers that card too;
    /// `startMiss` records one wrong attempt on it; `startWriting` is what a
    /// resolved reflection shows as the reader's own words. Set by `PanelShot`;
    /// nothing in the app sets them.
    var startCard = 0
    var startResolved = false
    var startMiss = false
    var startWriting = ""

    @State private var session = DialogueSession(cards: [])
    /// The live input of the question at the gate — a typed value or a reflection.
    @State private var draft = ""
    /// Set when a typed answer did not read as a number: a spelling problem, said
    /// once, and not counted as an attempt.
    @State private var unreadable = false
    /// The card whose resolution the transcript should bring into view next.
    @State private var scrollTarget: Int?

    private enum Field: Hashable { case typed, reflection, keys }
    @FocusState private var focus: Field?

    private var cards: [LessonCard] { session.cards }

    var body: some View {
        let theme = ThemeStore.shared.theme
        // Read on purpose: a mastery problem graded in the sheet above this view
        // must move the read-outs at its foot.
        _ = scores.revision

        return VStack(spacing: 0) {
            header(theme)
            Rule()
            ScrollViewReader { proxy in
                HStack(alignment: .top, spacing: 0) {
                    transcript(theme)
                    Rectangle()
                        .fill(theme.hairline.color)
                        .frame(width: 1)
                    rail(theme, proxy: proxy)
                        .frame(width: 236)
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.08))
                    }
                }
            }
            Rule()
            foot(theme)
        }
        .background(theme.canvasEdge.color)
        .background(.ultraThinMaterial)
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .keys)
        .onKeyPress(phases: .down, action: keyPress)
        .onAppear(perform: start)
    }

    // MARK: - Starting

    private func start() {
        var fresh = DialogueSession(cards: lesson.cards)
        if startCard > 0 { fresh.answerCorrectly(through: startCard - 1) }
        if fresh.cards.indices.contains(startCard) {
            let card = fresh.cards[startCard]
            if startMiss, let check = card.check {
                switch check.form {
                case .choice:
                    if let wrong = check.choices.indices.first(where: { !check.choices[$0].correct }) {
                        fresh.pick(wrong, at: startCard)
                    }
                case .typed:
                    let want = check.expects.flatMap(NumericAnswer.value(of:)) ?? 1
                    fresh.submit(String(format: "%g", want == 0 ? 1 : want * 2), at: startCard)
                }
            }
            if startResolved {
                if card.isReflection {
                    fresh.reflect(startWriting, at: startCard)
                } else {
                    fresh.answerCorrectly(through: startCard)
                }
            }
        }
        session = fresh
        focusGate()
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
                if let onUnit, let context {
                    Button { onUnit(context.unit) } label: {
                        Text("back to the unit")
                            .foregroundStyle(theme.statEmphasis.color)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("The unit page: every skill of \(context.unitTitle), in order")
                }
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
        let form = lesson.isDialogue ? "DIALOGUE" : "LESSON"
        if let context {
            return "UNIT \(String(format: "%02d", context.unitIndex + 1)) OF \(context.unitCount) · "
                + "\(context.unitTitle.uppercased()) · SKILL \(context.skillIndex + 1) OF "
                + "\(context.skillCount) · \(kind)"
        }
        guard let unitTitle else { return "\(form) · \(kind)" }
        return "\(form) · \(kind) · \(unitTitle.uppercased())"
    }

    // MARK: - Transcript

    private func transcript(_ theme: Theme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !lesson.isInteractive {
                    derivedNote(theme)
                }
                if shotStart > 0 {
                    Text("· · · \(shotStart) earlier step\(shotStart == 1 ? "" : "s") above")
                        .font(Typeface.mono(10))
                        .foregroundStyle(theme.inkFaint.color)
                        .padding(.bottom, 22)
                }
                ForEach(shotStart..<session.visibleCount, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 0) {
                        if let title = cards[index].partTitle {
                            partHeading(title, number: partNumber(of: index), theme)
                        }
                        step(index, theme)
                    }
                    .padding(.bottom, cards[index].isQuestion ? 30 : 22)
                    .id(index)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
                if session.isFinished {
                    finish(theme)
                        .id(cards.count)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, theme.isDark ? 40 : 44)
            .padding(.top, 30)
            .padding(.bottom, 60)
        }
    }

    /// Where a seam-opened transcript starts. An offscreen render cannot scroll
    /// (`NSHostingView` + `cacheDisplay` draws a `ScrollView` at its top, and
    /// ignores a default anchor), so a frame opened deep in a dialogue would show
    /// its first screen and pass. The seam instead starts the transcript near its
    /// gate: at the gate's part, or two steps above the gate if the part runs
    /// long, or at the ending. Always 0 in the app — nothing there sets
    /// `startCard`.
    private var shotStart: Int {
        guard startCard > 0, !cards.isEmpty else { return 0 }
        if startCard >= cards.count { return cards.count - 1 }
        let part = session.parts.last { $0.cards.lowerBound <= startCard }?.cards.lowerBound ?? 0
        return startCard - part > 2 ? startCard - 2 : part
    }

    /// Which titled part a card opens, counting from 1.
    private func partNumber(of index: Int) -> Int {
        cards[...index].count { $0.partTitle != nil }
    }

    private func partHeading(_ title: String, number: Int, _ theme: Theme) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(String(format: "%02d", number))
                .font(Typeface.mono(11, .medium))
                .foregroundStyle(theme.eyebrowCount.color)
            MathTextView(
                source: title, size: theme.isDark ? 19 : 20,
                weight: theme.isDark ? .light : .regular,
                color: theme.inkStrong.color, face: theme.isDark ? .sans : .serif)
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, number == 1 ? 0 : 18)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func step(_ index: Int, _ theme: Theme) -> some View {
        let card = cards[index]
        if card.isQuestion {
            question(index, card, theme)
        } else {
            beat(card, theme)
        }
    }

    /// A teaching beat, at reading size. It never waits; it is read on the way to
    /// the next question.
    private func beat(_ card: LessonCard, _ theme: Theme) -> some View {
        MathTextView(
            source: card.teach ?? "",
            size: theme.isDark ? 16 : 17,
            color: theme.ink.color,
            face: theme.isDark ? .sans : .serif
        )
        .lineSpacing(theme.isDark ? 7 : 8)
        .textSelection(.enabled)
    }

    /// D13.1's honesty: a lesson nobody has authored cards for is paged off its
    /// written form, and asks nothing — say so rather than seem inexplicably
    /// passive.
    private func derivedNote(_ theme: Theme) -> some View {
        Text(
            "This lesson is shown from its written form — no questions are authored for it yet."
        )
        .font(Typeface.mono(10))
        .foregroundStyle(theme.inkFaint.fading(0.7).color)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 20)
    }

    // MARK: - Questions

    private func question(_ index: Int, _ card: LessonCard, _ theme: Theme) -> some View {
        let outcome = session.outcomes[index]
        let isGate = session.gate == index
        let rule: ThemeColor =
            switch outcome {
            case nil: theme.attention
            case .answered: theme.action
            case .shown, .reflected: theme.inkFaint
            }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(kindLabel(card))
                    .font(Typeface.mono(9.5, .medium))
                    .tracking(Typeface.tracking(0.18, at: 9.5))
                    .foregroundStyle((outcome == nil ? theme.attention : theme.eyebrow).fading(0.9).color)
                Spacer(minLength: 0)
                if outcome == nil {
                    if card.hint != nil, !session.hinted.contains(index) {
                        TextAction(
                            title: "hint", size: 11, weight: .regular, isQuiet: true,
                            accessibilityHint: "A nudge toward the method, not the answer"
                        ) { session.showHint(at: index) }
                    }
                    if !card.isReflection {
                        TextAction(
                            title: hasAttempted(index) ? "show me" : "skip · show me", size: 11,
                            weight: .regular, isQuiet: true,
                            accessibilityHint: "Shows the answer and moves on"
                        ) { resolve(index) { $0.reveal(at: index) } }
                    }
                }
            }

            MathTextView(
                source: card.prompt,
                size: theme.isDark ? 16 : 17,
                color: theme.inkStrong.color,
                face: theme.isDark ? .sans : .serif
            )
            .lineSpacing(theme.isDark ? 7 : 8)
            .textSelection(.enabled)

            if let check = card.check {
                switch check.form {
                case .choice: choices(index, check, theme)
                case .typed: typed(index, check, isGate: isGate, theme)
                }
            } else if card.isReflection {
                reflection(index, card, isGate: isGate, theme)
            }

            if let hint = card.hint, session.hinted.contains(index), outcome == nil {
                labelled("HINT", hint, tint: theme.attention, theme)
            }

            if let outcome, let check = card.check {
                verdict(outcome, check: check, theme)
            }
        }
        .padding(.leading, 18)
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(rule.fading(outcome == nil ? 0.9 : 0.7).color)
                .frame(width: 2)
        }
    }

    private func kindLabel(_ card: LessonCard) -> String {
        if card.isReflection { return "IN YOUR OWN WORDS" }
        return card.check?.form == .typed ? "WORK IT OUT" : "QUESTION"
    }

    private func hasAttempted(_ index: Int) -> Bool {
        !(session.wrongPicks[index] ?? []).isEmpty || !(session.misses[index] ?? []).isEmpty
    }

    // MARK: Choice

    private func choices(_ index: Int, _ check: AnswerCheck, _ theme: Theme) -> some View {
        let outcome = session.outcomes[index]
        let ruledOut = session.wrongPicks[index] ?? []
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(check.choices.enumerated()), id: \.offset) { position, choice in
                let state: ChoiceRow.State =
                    if ruledOut.contains(position) {
                        .ruledOut
                    } else if outcome != nil {
                        choice.correct
                            ? (outcome == .shown ? .revealed : .right) : .dim
                    } else {
                        .open
                    }
                ChoiceRow(
                    label: Self.letters[position % Self.letters.count],
                    choice: choice,
                    state: state,
                    onPick: { pick(position, at: index) })
            }
        }
    }

    private static let letters = ["A", "B", "C", "D", "E", "F"]

    private func pick(_ row: Int, at index: Int) {
        var next = session
        switch next.pick(row, at: index) {
        case .correct: resolve(index) { $0 = next }
        case .wrong: withAnimation(.easeOut(duration: 0.18)) { session = next }
        case .ignored: break
        }
    }

    // MARK: Typed

    private func typed(
        _ index: Int, _ check: AnswerCheck, isGate: Bool, _ theme: Theme
    ) -> some View {
        let outcome = session.outcomes[index]
        let misses = session.misses[index] ?? []
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(misses.enumerated()), id: \.offset) { _, miss in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("✗")
                        .font(Typeface.mono(11, .medium))
                        .foregroundStyle(theme.warning.color)
                    Text(miss.text)
                        .font(Typeface.mono(13))
                        .foregroundStyle(theme.inkStrong.color)
                    Text(miss.message)
                        .font(Typeface.sans(12.5))
                        .foregroundStyle(theme.inkMuted.color)
                }
            }
            if outcome == nil, isGate {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        // The placeholder is drawn rather than `prompt:` — AppKit
                        // colours a prompt by the *system* appearance, which the
                        // pinned theme does not follow, so it came out white on
                        // the light paper.
                        ZStack(alignment: .leading) {
                            if draft.isEmpty {
                                Text("your answer")
                                    .font(Typeface.mono(14))
                                    .foregroundStyle(theme.inkFaint.fading(0.8).color)
                                    .allowsHitTesting(false)
                            }
                            TextField("", text: $draft)
                                .textFieldStyle(.plain)
                                .font(Typeface.mono(14))
                                .foregroundStyle(theme.inkStrong.color)
                                .focused($focus, equals: .typed)
                                .onSubmit { submit(at: index) }
                                .onChange(of: draft) { unreadable = false }
                                .accessibilityLabel("Your answer")
                        }
                        Rectangle()
                            .fill((focus == .typed ? theme.action : theme.rule).color)
                            .frame(height: 1)
                    }
                    .frame(width: 220)
                    TextAction(
                        title: "check", size: 12,
                        accessibilityHint: "Checks the value; a miss says which way"
                    ) { submit(at: index) }
                    .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
                }
                // Plain prose, no `$…$`: these lines are set with `Text` rather
                // than `MathTextView`, so a math span here would reach the reader
                // as literal dollar signs — which the corpus check would never
                // catch, because the strings are in the app, not the corpus.
                Text(
                    unreadable
                        ? "That did not read as a number — try forms like 7/15, 0.4667 or 46.67%."
                        : "A whole number, a fraction, a decimal to three or more places, or a percentage."
                )
                .font(Typeface.mono(9.5))
                .foregroundStyle((unreadable ? theme.warning : theme.inkFaint.fading(0.7)).color)
            } else if outcome != nil, let expects = check.expects {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(outcome == .shown ? "the answer" : "✓")
                        .font(Typeface.mono(outcome == .shown ? 10 : 11, .medium))
                        .foregroundStyle((outcome == .shown ? theme.eyebrowCount : theme.action).color)
                    MathTextView(source: expects, size: 13.5, color: theme.inkStrong.color)
                }
            }
        }
    }

    private func submit(at index: Int) {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var next = session
        switch next.submit(draft, at: index) {
        case .correct:
            resolve(index) { $0 = next }
        case .wrong:
            withAnimation(.easeOut(duration: 0.18)) { session = next }
            draft = ""
        case .ignored:
            unreadable = true
        }
    }

    // MARK: Reflection

    private func reflection(
        _ index: Int, _ card: LessonCard, isGate: Bool, _ theme: Theme
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.outcomes[index] == nil {
                if isGate {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $draft)
                            .font(Typeface.sans(14))
                            .foregroundStyle(theme.inkStrong.color)
                            .scrollContentBackground(.hidden)
                            .focused($focus, equals: .reflection)
                            .frame(minHeight: 78, maxHeight: 140)
                            .accessibilityLabel("Your answer, in your own words")
                        if draft.isEmpty {
                            Text("Write your idea in a sentence or two, then compare it with the tutor's.")
                                .font(Typeface.sans(14))
                                .foregroundStyle(theme.inkFaint.fading(0.8).color)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(10)
                    .background(theme.rowHighlight.fading(0.6).color)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke((focus == .reflection ? theme.action : theme.rule).color, lineWidth: 1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        TextAction(
                            title: "compare with the tutor", size: 12,
                            accessibilityHint: "Shows the tutor's answer beside yours"
                        ) { resolve(index) { $0.reflect(draft, at: index) } }
                        .keyboardShortcut(.return, modifiers: .command)
                        Text("⌘↵")
                            .font(Typeface.mono(10))
                            .foregroundStyle(theme.inkFaint.color)
                        Spacer(minLength: 0)
                        TextAction(
                            title: "no idea yet — show me", size: 11.5, weight: .regular,
                            isQuiet: true, accessibilityHint: "Shows the tutor's answer"
                        ) { resolve(index) { $0.reveal(at: index) } }
                    }
                }
            } else {
                let mine = session.written[index] ?? ""
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOU WROTE")
                        .font(Typeface.mono(9.5, .medium))
                        .tracking(Typeface.tracking(0.16, at: 9.5))
                        .foregroundStyle(theme.eyebrow.color)
                    Text(mine.isEmpty ? "Nothing — you asked to see it." : mine)
                        .font(mine.isEmpty ? Typeface.sansItalic(13.5) : Typeface.sans(13.5))
                        .foregroundStyle((mine.isEmpty ? theme.inkFaint : theme.ink).color)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("THE TUTOR")
                        .font(Typeface.mono(9.5, .medium))
                        .tracking(Typeface.tracking(0.16, at: 9.5))
                        .foregroundStyle(theme.action.fading(0.9).color)
                    MathTextView(
                        source: card.answer ?? "", size: 14.5, color: theme.ink.color,
                        face: theme.isDark ? .sans : .serif)
                    .lineSpacing(theme.isDark ? 6 : 7)
                    .textSelection(.enabled)
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("your version:")
                        .font(Typeface.sans(11.5))
                        .foregroundStyle(theme.inkFaint.color)
                    ForEach(DialogueSession.Rating.allCases, id: \.self) { rating in
                        let isChosen = session.ratings[index] == rating
                        Button { session.rate(rating, at: index) } label: {
                            Text(rating.title)
                                .font(Typeface.sans(11.5, isChosen ? .medium : .regular))
                                .foregroundStyle((isChosen ? theme.action : theme.inkMuted).color)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(isChosen ? theme.rowHighlight.color : .clear)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
                    }
                }
            }
        }
    }

    // MARK: Resolution

    /// Right, after how many tries, or shown — then the authored consolidation.
    private func verdict(
        _ outcome: DialogueSession.Outcome, check: AnswerCheck, _ theme: Theme
    ) -> some View {
        let line: String
        let tint: ThemeColor
        switch outcome {
        case .answered(let tries):
            line = tries == 1 ? "✓ first try" : "✓ after \(tries) tries"
            tint = theme.action
        case .shown, .reflected:
            line = "shown"
            tint = theme.inkMuted
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(line)
                .font(Typeface.mono(10.5, .medium))
                .foregroundStyle(tint.color)
            if !check.feedback.isEmpty {
                MathTextView(
                    source: check.feedback, size: 14.5, color: theme.ink.color,
                    face: theme.isDark ? .sans : .serif
                )
                .lineSpacing(theme.isDark ? 6 : 7)
                .textSelection(.enabled)
            }
        }
        .padding(.top, 4)
    }

    /// Apply a change that resolves the question at `index`, and bring the
    /// resolution — and the stretch it unfolds beneath it — into view.
    private func resolve(_ index: Int, _ change: (inout DialogueSession) -> Void) {
        withAnimation(.easeOut(duration: 0.22)) { change(&session) }
        draft = ""
        unreadable = false
        scrollTarget = nil
        DispatchQueue.main.async { scrollTarget = index }
        focusGate()
    }

    /// The keyboard follows the gate: a typed question takes the field, a
    /// reflection the editor, a choice the letter keys.
    private func focusGate() {
        DispatchQueue.main.async {
            guard let gate = session.gate else {
                focus = .keys
                return
            }
            let card = cards[gate]
            if card.isReflection {
                focus = .reflection
            } else if card.check?.form == .typed {
                focus = .typed
            } else {
                focus = .keys
            }
        }
    }

    /// A–F or 1–6 picks a row of the choice at the gate; Escape goes to the owner.
    private func keyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            (onEscape ?? onExit)()
            return .handled
        }
        guard focus == .keys, let gate = session.gate, let check = cards[gate].check,
            check.form == .choice, press.modifiers.isEmpty
        else { return .ignored }
        let key = press.characters.lowercased()
        let row: Int? =
            if let digit = Int(key), (1...check.choices.count).contains(digit) {
                digit - 1
            } else if let letter = Self.letters.firstIndex(of: key.uppercased()),
                letter < check.choices.count
            {
                letter
            } else {
                nil
            }
        guard let row else { return .ignored }
        pick(row, at: gate)
        return .handled
    }

    private func labelled(
        _ label: String, _ text: String, tint: ThemeColor, _ theme: Theme
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(Typeface.mono(9.5, .medium))
                .tracking(Typeface.tracking(0.16, at: 9.5))
                .foregroundStyle(tint.fading(0.75).color)
            MathTextView(source: text, size: 13.5, color: theme.ink.color)
                .lineSpacing(theme.isDark ? 5 : 6)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle().fill(tint.fading(0.5).color).frame(width: 1)
        }
    }

    // MARK: - Rail

    private func rail(_ theme: Theme, proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if session.hasTitledParts {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(title: "Outline", count: session.parts.count, spread: true)
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(session.parts.enumerated()), id: \.offset) { position, part in
                                outlineRow(part, number: position + 1, theme, proxy: proxy)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(title: "This lesson")
                    Text(tally)
                        .font(Typeface.mono(10.5))
                        .foregroundStyle(theme.stat.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !prerequisites.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(title: "Builds on", count: prerequisites.count, spread: true)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(prerequisites, id: \.id) { prerequisite in
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    MasteryDot(level: scores.level(of: prerequisite.id))
                                    MathTextView(
                                        source: prerequisite.title, size: 12,
                                        color: theme.rowTitle.color)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 30)
            .padding(.bottom, 30)
        }
    }

    private func outlineRow(
        _ part: DialogueSession.Part, number: Int, _ theme: Theme, proxy: ScrollViewProxy
    ) -> some View {
        let questions = part.cards.filter { cards[$0].isQuestion }
        let resolved = questions.count { session.isResolved($0) }
        let isOpen = part.cards.lowerBound < session.visibleCount
        let isCurrent = session.gate.map { part.cards.contains($0) } ?? false
        return Button {
            guard isOpen else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(part.cards.lowerBound, anchor: .top)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number)")
                    .font(Typeface.mono(10))
                    .foregroundStyle(theme.eyebrowCount.color)
                    .frame(width: 12, alignment: .leading)
                MathTextView(
                    source: part.title ?? "Opening", size: 12,
                    color: (isCurrent ? theme.inkStrong : (isOpen ? theme.rowTitle : theme.inkFaint))
                        .color)
                .lineLimit(2)
                Spacer(minLength: 4)
                Text("\(resolved)/\(questions.count)")
                    .font(Typeface.mono(10))
                    .foregroundStyle(
                        (resolved == questions.count && isOpen ? theme.action : theme.eyebrowCount)
                            .color)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(isCurrent ? theme.rowHighlight.color : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOpen)
    }

    private var tally: String {
        let total = session.questionCount
        guard total > 0 else { return "Nothing to answer — read it through." }
        var parts = ["\(session.resolvedCount) of \(total) answered"]
        if session.firstTryCount > 0 { parts.append("\(session.firstTryCount) first try") }
        if session.shownCount > 0 { parts.append("\(session.shownCount) shown") }
        return parts.joined(separator: " · ")
    }

    /// The node's direct prerequisites, with where the reader stands on each —
    /// the "builds on" a tutor would check before starting.
    private var prerequisites: [Node] {
        node.requires.compactMap { id in document.index(of: id).map { document[$0] } }
    }

    // MARK: - Finish

    /// Where a lesson ends: the recap, the mastery set, and the self-report
    /// beside it.
    ///
    /// The set is offered, never required (D13.5) — the point of putting it here is
    /// that the reader has just been taught the thing, which is the moment a hard
    /// problem measures the most, not a toll gate on leaving.
    private func finish(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Rule()
            VStack(alignment: .leading, spacing: 12) {
                Text(session.questionCount > 0 ? "WHERE THAT LEAVES YOU" : "IN ONE BREATH")
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
                    Eyebrow(title: "Now on your own")
                    Text(
                        "\(mastery.count) problem\(mastery.count == 1 ? "" : "s") that test this, "
                            + "hardest first, with no dialogue to lean on. Passing one records a "
                            + "review here and, more weakly, on its prerequisites."
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
            if context != nil || onUnit != nil {
                Rule()
                next(theme)
            }
        }
        .padding(.top, 8)
    }

    /// §6.8's loop: where you stand on the ladder now, and the next skill. The
    /// rung reads the snapshot, so passing a mastery problem above moves it
    /// while you watch — the one place the ladder and the instrument share a
    /// screen.
    private func next(_ theme: Theme) -> some View {
        let level = scores.level(of: node.id)
        return HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR LEVEL")
                    .font(Typeface.mono(10, .medium))
                    .tracking(Typeface.tracking(0.18, at: 10))
                    .foregroundStyle(theme.eyebrow.color)
                HStack(spacing: 7) {
                    MasteryDot(level: level)
                    Text(level.title)
                        .font(Typeface.sans(13.5, .medium))
                        .foregroundStyle(level.tint(theme).color)
                }
                Text(climb(level))
                    .font(Typeface.mono(10))
                    .foregroundStyle(theme.inkFaint.fading(0.8).color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                if let context, let next = context.next, let onNext {
                    TextAction(
                        title: "Next: \(context.nextTitle ?? next.rawValue) →", size: 13,
                        accessibilityHint: "Plays the next skill of the unit"
                    ) { onNext(next) }
                    Text("skill \(context.skillIndex + 2) of \(context.skillCount)")
                        .font(Typeface.mono(10))
                        .foregroundStyle(theme.eyebrowCount.color)
                } else if let context, let onUnit {
                    TextAction(
                        title: "Unit complete — back to the unit →", size: 13,
                        accessibilityHint: "The unit page, and its test"
                    ) { onUnit(context.unit) }
                    Text("the last skill of \(context.unitTitle)")
                        .font(Typeface.mono(10))
                        .foregroundStyle(theme.eyebrowCount.color)
                        .lineLimit(1)
                }
            }
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

    /// What climbs the ladder from here — said at the foot of the lesson, where
    /// the instruments that climb it are one scroll up.
    private func climb(_ level: MasteryLevel) -> String {
        switch level {
        case .notStarted, .attempted:
            return mastery.isEmpty
                ? "Nothing recorded yet — report how it landed to hold this."
                : "Nothing recorded yet — pass a problem above, or report how it landed."
        case .familiar:
            return "Learned once and decayed — a pass or a report brings it back."
        case .proficient:
            return mastery.isEmpty
                ? "Held and fresh. No problem in the bank can prove it yet."
                : "Held and fresh. Pass a problem above to master it."
        case .mastered:
            return "Held, fresh, and proven by a problem."
        }
    }

    // MARK: - Foot

    private func foot(_ theme: Theme) -> some View {
        let total = session.questionCount
        return HStack(spacing: 18) {
            MeasureBar(
                value: total == 0 ? 1 : Double(session.resolvedCount) / Double(total), height: 2,
                tint: session.isFinished ? theme.action : nil)
            Text(total == 0 ? "reading" : "\(session.resolvedCount) / \(total) questions")
                .font(Typeface.mono(10.5))
                .foregroundStyle(theme.stat.color)
                .fixedSize()
            Text(keyHint)
                .font(Typeface.mono(10))
                .foregroundStyle(theme.inkFaint.fading(0.8).color)
                .fixedSize()
        }
        .padding(.horizontal, theme.isDark ? 40 : 44)
        .padding(.top, 14)
        .padding(.bottom, theme.isDark ? 22 : 24)
    }

    private var keyHint: String {
        guard let gate = session.gate else {
            return session.questionCount == 0 ? "" : "answered through — the mastery set is below"
        }
        let card = cards[gate]
        if card.isReflection { return "⌘↵ compares with the tutor" }
        if card.check?.form == .typed { return "↵ checks" }
        let count = card.check?.choices.count ?? 0
        return "A–\(Self.letters[max(count - 1, 0)]) picks"
    }
}

// MARK: - Rows

/// One row of a choice question. Open, it is a target; ruled out, it keeps its
/// authored feedback beneath it — the reader picked it, and the reason it is
/// wrong is the thing worth reading; resolved, the right row takes the accent
/// and carries its own feedback.
private struct ChoiceRow: View {
    enum State: Equatable {
        case open
        /// Picked, wrong, and kept on the page.
        case ruledOut
        /// The reader found it.
        case right
        /// The reader asked to be shown.
        case revealed
        /// Resolved, and neither picked nor right.
        case dim
    }

    let label: String
    let choice: AnswerChoice
    let state: State
    let onPick: () -> Void

    @SwiftUI.State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        let tint: ThemeColor =
            switch state {
            case .open: theme.ink
            case .ruledOut: theme.warning
            case .right, .revealed: theme.action
            case .dim: theme.inkMuted
            }
        let isMarked = state == .ruledOut || state == .right || state == .revealed
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onPick) {
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text(marker)
                        .font(Typeface.mono(11, .medium))
                        .foregroundStyle(tint.color)
                        .frame(width: 14, alignment: .leading)
                    MathTextView(
                        source: choice.text, size: 14,
                        color: (state == .dim ? theme.inkMuted.fading(0.8) : tint).color)
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 10)
                .background(
                    isMarked
                        ? theme.rowHighlight.color
                        : (isHovering && state == .open ? theme.rowHighlight.fading(0.5).color : .clear)
                )
                .overlay(alignment: .leading) {
                    // The redesign marks a chosen row with a rule, not a fill or a
                    // radio button — the same subtraction as everywhere else.
                    Rectangle()
                        .fill(tint.color)
                        .frame(width: 2)
                        .opacity(isMarked ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state != .open)
            .onHover { isHovering = $0 }
            .accessibilityLabel("Option \(label): \(MathText.plainText(choice.text))")
            .accessibilityAddTraits(isMarked ? [.isSelected] : [])

            if let why, state == .ruledOut || state == .right || state == .revealed {
                MathTextView(source: why, size: 13, color: theme.inkMuted.color)
                    .lineSpacing(theme.isDark ? 5 : 6)
                    .padding(.leading, 35)
                    .padding(.trailing, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
    }

    private var why: String? {
        guard let feedback = choice.feedback?.trimmingCharacters(in: .whitespacesAndNewlines),
            !feedback.isEmpty
        else { return nil }
        return feedback
    }

    private var marker: String {
        switch state {
        case .open, .dim: label
        case .ruledOut: "✗"
        case .right, .revealed: "✓"
        }
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

    #Preview("Lesson player — dialogue") {
        LessonPlayer(
            node: NodePanelPreviewData.document[
                NodePanelPreviewData.document.index(of: "analysis.svc.mvt") ?? 0],
            lesson: Lesson(
                node: "analysis.svc.mvt",
                hook: "The bridge from local slope to global change.",
                explanation: "Rolle's theorem plus a tilt.",
                recap: "Average slope is attained somewhere inside.",
                dialogue: [
                    LessonCard(
                        teach: "Drive $150$ km in $1.5$ hours.", part: "Two photographs"),
                    LessonCard(
                        ask: "What was your average speed?", expects: "100",
                        feedback: "$150 / 1.5 = 100$."),
                    LessonCard(
                        reflect: "What could you subtract so the endpoints agree?",
                        answer: "The secant line, $S\\,(x - a)$."),
                    LessonCard(
                        ask: "Which hypothesis does $|x|$ on $[-1, 1]$ break?",
                        part: "Where it breaks",
                        choices: [
                            AnswerChoice(
                                text: "Continuity on $[-1, 1]$",
                                feedback: "$|x|$ is continuous everywhere."),
                            AnswerChoice(
                                text: "Differentiability on $(-1, 1)$", correct: true,
                                feedback: "The corner at $0$ is inside the open interval."),
                        ],
                        feedback: "Differentiability is required on the open interval."),
                ]),
            unitTitle: "Single-variable calculus",
            document: NodePanelPreviewData.document,
            scores: NodePanelPreviewData.scores(),
            onExit: { print("exit") }
        )
        .frame(width: 1100, height: 760)
    }

#endif
