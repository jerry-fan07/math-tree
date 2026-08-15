import GraphCore
import SwiftUI

/// §5.4's review surfacing: "the FSRS scheduler surfaces due reviews", beside
/// §4.5's frontier — "what you could learn next, the actionable set the whole
/// product points at".
///
/// Two lists, because they answer different questions and are computed by
/// different instruments: **Due** is the scheduler's read-out (`nextDue`), and
/// **Ready to learn** is the frontier (never successfully retrieved, prerequisites
/// above τ).
///
/// Before Phase 8 a node could not be in both, because "has FSRS state" and "has
/// been learned" were the same fact. D8.3 separated them, deliberately: a node
/// that a diagnosis localized a miss onto has state (so the scheduler wants it
/// back) and has never been retrieved (so it is still what to learn next). Seeing
/// it in both lists is those two read-outs agreeing, not a double-count.
///
/// The redesign turns it from a panel into a **scrim**: no header bar, no card
/// around placement, no filled button, no border on the trailing edge. Sections
/// are separated by hairlines and the whole thing fades out over the map, so the
/// map reads as one continuous surface running underneath the reading column.
struct ReviewSidebar: View {
    let document: GraphDocument
    let scores: ScoreStore
    /// §5.3's placement, when the app has a bank to probe with.
    var placement: PlacementStore?
    var onSelect: (NodeID) -> Void
    /// §5.4: review "via problems ... whenever possible". The owner routes to a
    /// problem sheet or to self-report; the sidebar only asks.
    var onReview: (NodeID) -> Void = { _ in }
    var onPlace: () -> Void = {}
    var onClose: () -> Void

    private static let upcomingLimit = 8

    var body: some View {
        let theme = ThemeStore.shared.theme
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                // Rules lead their section rather than trailing it, so the last
                // section never leaves a hairline hanging under nothing — which is
                // what happens when placement has been answered and there are no
                // diagnostics, i.e. the common case.
                VStack(alignment: .leading, spacing: 22) {
                    dueList
                    Rule()
                    frontierList
                    upcomingList
                    placementSection
                    diagnostics
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.isDark ? 20 : 22)
                .padding(.top, 22)
                .padding(.bottom, 18)
            }
            Spacer(minLength: 0)
            hints
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // The scrim: opaque where the text is, thinning toward the map. The
            // design's `linear-gradient(90deg, …0.94, …0.88 78%, …0.6)`.
            LinearGradient(
                stops: [
                    .init(color: theme.railScrimNear.color, location: 0),
                    .init(color: theme.railScrimNear.fading(0.94).color, location: 0.78),
                    .init(color: theme.railScrimFar.color, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing)
        }
    }

    // MARK: - Lists

    private var dueList: some View {
        section("Due now", count: scores.due.count) {
            if scores.due.isEmpty {
                note(
                    scores.schedule.isEmpty
                        ? "Nothing reviewed yet. Mark something you know to start."
                        : "Nothing owed — everything reviewed is still fresh.")
            } else {
                rows(scores.due.map(\.id))
            }
        }
    }

    private var frontierList: some View {
        section("Ready to learn", count: scores.frontier.count) {
            if scores.frontier.isEmpty {
                note("No unlearned node has all its prerequisites above the threshold yet.")
            } else {
                rows(scores.frontierList)
            }
        }
    }

    /// Kept, though the design's frame does not draw it: it is the only place the
    /// app says when the *next* review is coming, and dropping it would lose a
    /// read-out rather than a decoration.
    @ViewBuilder
    private var upcomingList: some View {
        let upcoming = scores.upcoming
        if !upcoming.isEmpty {
            Rule()
            section("Scheduled", count: upcoming.count) {
                rows(upcoming.prefix(Self.upcomingLimit).map(\.id))
                if upcoming.count > Self.upcomingLimit {
                    note("+ \(upcoming.count - Self.upcomingLimit) more")
                }
            }
        }
    }

    // MARK: - Placement

    /// §5.3's entry point, and D6.10's answer: a fresh map is almost entirely grey,
    /// which is correct but carries no information. Offered while it would help,
    /// resumable while it is running, and gone once it is done — a questionnaire
    /// that lingers after it is answered is clutter.
    ///
    /// The card is gone with the rest of them. What is left is what it was always
    /// saying: a heading, a sentence, and one underlined action.
    @ViewBuilder
    private var placementSection: some View {
        if let placement, placement.canPlace, !placement.isReadOnly,
            placement.session?.isCommitted != true
        {
            Rule()
            VStack(alignment: .leading, spacing: 9) {
                Eyebrow(title: "Placement")
                note(
                    placement.isActive
                        ? "\(placement.progress?.unresolved ?? 0) nodes still to settle."
                        : scores.state.nodes.isEmpty
                            ? "Answer a handful of problems and the map fills in around what you know."
                            : "Answer a handful of problems to fill in the rest of the map.")
                TextAction(
                    title: placement.isActive ? "Continue" : "Place me",
                    size: 11.5,
                    accessibilityHint: "Starts §5.3's adaptive placement",
                    action: onPlace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Log corruption and fold defects (D5.8) surface here rather than in a log
    /// nobody reads — an event the fold could not apply is a score that is quietly
    /// missing. Placement's own defects join them.
    @ViewBuilder
    private var diagnostics: some View {
        let messages = scores.diagnostics + (placement?.diagnostics ?? [])
        if !messages.isEmpty {
            Rule()
            section("Diagnostics", count: messages.count) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(messages, id: \.self) { message in
                        Text(message)
                            .font(Typeface.mono(10))
                            .foregroundStyle(ThemeStore.shared.theme.warning.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    /// The keyboard map, which used to float over the bottom-left of the graph. It
    /// belongs to the chrome, not to the canvas, and the design moves it here.
    private var hints: some View {
        let theme = ThemeStore.shared.theme
        return VStack(alignment: .leading, spacing: 3) {
            Text("scroll pan · ⌘scroll zoom")
            Text("f fit · r review · esc close")
            if scores.isClockPinned {
                // A pinned clock is a deliberately frozen run; saying so beats
                // letting someone read a fixture snapshot as today's state.
                Text("clock pinned")
                    .foregroundStyle(theme.attention.color)
                    .help("MATHTREE_NOW froze the clock at \(scores.evaluatedAt.formatted())")
            }
        }
        .font(Typeface.mono(10.5))
        .foregroundStyle(theme.inkFaint.fading(0.7).color)
        .padding(.horizontal, theme.isDark ? 20 : 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, count: Int, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Eyebrow(title: title, count: count, spread: true)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rows(_ ids: [NodeID]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(ids, id: \.self) { id in
                NodeRow(
                    id: id, document: document, scores: scores,
                    // §5.4's routing rule: a node the bank can ask about gets a
                    // problem; everything else keeps the self-report in the panel.
                    onReview: scores.canProbe(id) ? onReview : nil,
                    onSelect: onSelect)
            }
        }
        .padding(.horizontal, -4)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typeface.sans(12))
            .lineSpacing(3)
            .foregroundStyle(ThemeStore.shared.theme.inkMuted.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shared by Phase 8's modal sheets, so "close this" is one affordance in one
/// place rather than three that drift. The rail no longer has one: the redesign
/// gives it no header to put a control in, and `⌘\` still toggles it.
struct SidebarCloseButton: View {
    var symbol = "xmark"
    var label = "Close"
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let theme = ThemeStore.shared.theme
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle((isHovering ? theme.ink : theme.inkFaint).color)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
    }
}
