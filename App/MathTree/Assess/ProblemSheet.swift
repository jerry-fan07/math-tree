import GraphCore
import SwiftUI

/// §5.2's evidence instrument, on screen: a problem, an attempt, a self-grade
/// against the rubric, and — on a miss — §5.4's localization.
///
/// The sheet is deliberately **dumb about policy**. It presents, it collects, and
/// it calls back; deciding what to write is the owner's job, because a probe
/// answered inside placement must reach `PlacementStore` and a review answered
/// from the sidebar must reach `ScoreStore`, and those are the same interaction
/// with different consequences.
///
/// The shape of the interaction is the design constraint. Math free response
/// cannot be machine-graded, so the grade is the solver's own — which only means
/// anything if the answer stays hidden until they commit to having tried, and if
/// what they grade against is the *rubric* rather than a vibe. Hence: attempt,
/// reveal, then grade.
struct ProblemSheet: View {
    let problem: Problem
    /// The node this problem is being asked *about*. A multi-target problem tests
    /// them all, but one of them is why it was chosen, and that is the one the
    /// header names.
    let subject: NodeID
    let document: GraphDocument
    let scores: ScoreStore
    /// Shown above the problem while placement is running (§5.3).
    var progress: String?
    var onGrade: (ProblemOutcome, NodeID?) -> Void
    /// §5.4's other half: "let the user (**or a follow-up micro-problem**) localize
    /// the gap". Selecting a candidate from the chain asserts the gap; this asks a
    /// problem about it instead. `nil` where switching problems makes no sense.
    var onProbe: ((ProblemID, NodeID) -> Void)?
    var onDismiss: () -> Void
    /// Offscreen-render seams. Input cannot be driven headlessly (every phase
    /// since Phase 4 has recorded this), so the only way to *look at* the revealed
    /// and diagnosing states is to open the sheet already in them. Set by
    /// `PanelShot`; nothing in the app sets them.
    var startRevealed = false
    var startDiagnosing = false

    @State private var isAnswerVisible = false
    @State private var chain: [Diagnosis.Candidate]?

    var body: some View {
        ZStack {
            // A scrim, so the map behind reads as backdrop rather than as content
            // competing for attention.
            ThemeStore.shared.theme.scrim.color
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            SheetCard(width: 660, maxHeight: 660, header: AnyView(header)) {
                VStack(alignment: .leading, spacing: 18) {
                    if let chain {
                        DiagnosisChainView(
                            problem: problem, chain: chain, document: document, scores: scores,
                            onLocalize: { onGrade(.missed, $0) },
                            onProbe: onProbe,
                            onAbandon: { self.chain = nil })
                    } else {
                        statement
                        if isAnswerVisible {
                            answer
                            rubric
                            grading
                        } else {
                            revealButton
                        }
                    }
                }
            }
        }
        .onAppear {
            if startRevealed || startDiagnosing { isAnswerVisible = true }
            if startDiagnosing { chain = scores.diagnosisChain(after: problem) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let progress {
                    Text(progress)
                        .font(Typeface.mono(10, .medium))
                        .tracking(Typeface.tracking(0.18, at: 10))
                        .foregroundStyle(PanelTheme.accent)
                } else {
                    Text(chain == nil ? "PROBLEM" : "WHERE DID IT BREAK?")
                        .font(Typeface.mono(10, .medium))
                        .tracking(Typeface.tracking(0.18, at: 10))
                        .foregroundStyle(PanelTheme.tertiaryText)
                }
                Spacer(minLength: 0)
                Text(problem.kind.rawValue)
                Text("·")
                Text(problem.difficulty.rawValue)
                Text("·")
                Text(problem.id.rawValue)
            }
            .font(Typeface.sans(10.5))
            .foregroundStyle(PanelTheme.tertiaryText)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let index = document.index(of: subject) {
                    MathTextView(
                        source: document[index].title, size: 16, weight: .medium,
                        color: PanelTheme.primaryText)
                }
                Spacer(minLength: 0)
                SidebarCloseButton(symbol: "xmark", label: "Close this problem", action: onDismiss)
            }
            // A multi-target problem is a claim about all of them, and passing it
            // records a full grade on each (§5.2). Saying so is the difference
            // between an instrument and a black box.
            if problem.targets.count > 1 {
                Text(
                    "Also tests "
                        + problem.targets.filter { $0 != subject }
                        .compactMap { document.index(of: $0).map { document[$0].title } }
                        .joined(separator: ", ")
                )
                .font(Typeface.sans(10.5))
                .foregroundStyle(PanelTheme.tertiaryText)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Problem

    private var statement: some View {
        MathTextView(source: problem.statement, size: 14.5, color: PanelTheme.primaryText)
    }

    private var revealButton: some View {
        VStack(alignment: .leading, spacing: 7) {
            SheetButton(title: "Show the answer", isProminent: true) {
                withAnimation(.easeOut(duration: 0.18)) { isAnswerVisible = true }
            }
            Text("Work it out first — the grade you give yourself is the measurement.")
                .font(Typeface.sans(10.5))
                .foregroundStyle(PanelTheme.tertiaryText)
        }
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ANSWER")
                .font(Typeface.mono(10, .medium))
                .tracking(Typeface.tracking(0.18, at: 10))
                .foregroundStyle(PanelTheme.tertiaryText)
            MathTextView(source: problem.answer, size: 13.5, color: PanelTheme.primaryText)
        }
    }

    @ViewBuilder
    private var rubric: some View {
        if !problem.rubric.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("A CORRECT SOLUTION")
                    .font(Typeface.mono(10, .medium))
                    .tracking(Typeface.tracking(0.18, at: 10))
                    .foregroundStyle(PanelTheme.tertiaryText)
                ForEach(Array(problem.rubric.enumerated()), id: \.offset) { _, criterion in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("—")
                            .font(Typeface.sans(12))
                            .foregroundStyle(PanelTheme.tertiaryText)
                        MathTextView(source: criterion, size: 12.5, color: PanelTheme.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Grading

    private var grading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("How did it go?")
                .font(Typeface.sans(11))
                .foregroundStyle(PanelTheme.secondaryText)
            HStack(spacing: 6) {
                ForEach(ProblemOutcome.allCases, id: \.self) { outcome in
                    SheetButton(
                        title: outcome.title,
                        tint: outcome == .missed ? PanelTheme.warning : nil,
                        help: outcome.detail
                    ) { grade(outcome) }
                }
            }
            Text(
                "A pass records this problem's targets and, more weakly, their "
                    + "prerequisites (§4.3). A miss asks where it broke first."
            )
            .font(Typeface.sans(10.5))
            .foregroundStyle(PanelTheme.tertiaryText)
        }
    }

    /// A miss opens diagnosis instead of writing evidence. §5.4 is explicit that
    /// the failure lands on the localized node, and until one is chosen there is
    /// nothing to land.
    private func grade(_ outcome: ProblemOutcome) {
        guard outcome == .missed else {
            onGrade(outcome, nil)
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            chain = scores.diagnosisChain(after: problem)
        }
    }
}

/// §5.4's gap localization: the prerequisite chain of the failed target, weakest
/// first, and nothing is written until one is chosen.
private struct DiagnosisChainView: View {
    let problem: Problem
    let chain: [Diagnosis.Candidate]
    let document: GraphDocument
    let scores: ScoreStore
    var onLocalize: (NodeID) -> Void
    var onProbe: ((ProblemID, NodeID) -> Void)?
    var onAbandon: () -> Void

    /// The chain can be long on a deep target; the tail is almost always solid
    /// foundations, and burying the actionable rows under them helps nobody.
    private static let visible = 8

    private var targets: Set<NodeID> { Set(problem.targets) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                "A missed problem is evidence about one thing, and which one is the "
                    + "question. Pick where it actually broke — weakest first — or try a "
                    + "problem there instead of deciding."
            )
            .font(Typeface.sans(12.5))
            .foregroundStyle(PanelTheme.secondaryText)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(chain.prefix(Self.visible), id: \.id) { candidate in
                    CandidateRow(
                        candidate: candidate,
                        isTarget: targets.contains(candidate.id),
                        document: document,
                        scores: scores,
                        onSelect: onLocalize,
                        onProbe: onProbe)
                }
            }

            if chain.count > Self.visible {
                Text(
                    "\(chain.count - Self.visible) more prerequisites are not shown — "
                        + "they are further from the failure than anything above."
                )
                .font(Typeface.sans(10.5))
                .foregroundStyle(PanelTheme.tertiaryText)
            }

            HStack(spacing: 8) {
                SheetButton(title: "Back to the problem") { withAnimation { onAbandon() } }
                Spacer(minLength: 0)
            }
            // The honest statement of what walking away does. An abandoned
            // diagnosis writes nothing, by design and by test.
            Text("Closing without choosing records nothing.")
                .font(Typeface.sans(10.5))
                .foregroundStyle(PanelTheme.tertiaryText)
        }
    }
}

private struct CandidateRow: View {
    let candidate: Diagnosis.Candidate
    /// The failed problem's own target — "it was this, I just could not do it" is a
    /// first-class answer, not a fallback, and it needs to say so.
    let isTarget: Bool
    let document: GraphDocument
    let scores: ScoreStore
    var onSelect: (NodeID) -> Void
    var onProbe: ((ProblemID, NodeID) -> Void)?

    @State private var isHovering = false

    var body: some View {
        Button { onSelect(candidate.id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(ScoreFormat.color(of: candidate.id, in: scores))
                    .frame(width: 8, height: 8)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                VStack(alignment: .leading, spacing: 3) {
                    if let index = document.index(of: candidate.id) {
                        MathTextView(
                            source: document[index].title, size: 13,
                            color: isHovering ? .white : PanelTheme.primaryText)
                    } else {
                        Text(candidate.id.rawValue)
                            .font(Typeface.sans(13))
                            .foregroundStyle(PanelTheme.primaryText)
                    }
                    Text(subtitle)
                        .font(Typeface.sans(10.5))
                        .foregroundStyle(PanelTheme.tertiaryText)
                }
                Spacer(minLength: 0)
                // Only on hover: every node in this corpus has a problem, so a
                // permanent "has a problem" badge on every row said nothing and
                // read as noise. Hovering is also when the offer is useful — the
                // user is already considering that row.
                if isHovering, let onProbe, let probe = candidate.probe {
                    Button { onProbe(probe, candidate.id) } label: {
                        Text("test it")
                            .font(Typeface.sans(10, .medium))
                            .foregroundStyle(PanelTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Answer a problem about this instead of deciding")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovering ? PanelTheme.rowHighlight : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var subtitle: String {
        if isTarget { return "the problem itself — I knew the prerequisites" }
        if !candidate.isLearned { return "never learned" }
        guard let retrievability = candidate.retrievability else { return "prerequisite" }
        return "prerequisite · \(ScoreFormat.percent(retrievability))"
    }
}

/// The sheets' action, in the redesign's one affordance shape: a word with a rule
/// under it. `isProminent` now means "takes the accent" rather than "gets a fill",
/// which is the whole substance of turn 1's subtraction — the sheets keep every
/// action they had, and none of them is a box any more.
struct SheetButton: View {
    let title: String
    var isProminent = false
    var tint: Color?
    var help: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        let colour = tint ?? (isProminent ? theme.action.color : theme.inkMuted.color)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Typeface.sans(12.5, isProminent ? .medium : .regular))
                    .foregroundStyle(colour)
                Rectangle()
                    .fill(colour.opacity(isProminent ? (isHovering ? 0.85 : 0.45) : (isHovering ? 0.5 : 0)))
                    .frame(height: 1)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help ?? "")
    }
}
