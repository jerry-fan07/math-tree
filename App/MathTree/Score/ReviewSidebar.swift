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
    /// §6.5's entry point. `nil` in previews, where there is no map to fly.
    var onLearnSubject: ((NodeID) -> Void)?
    var onClose: () -> Void

    private static let upcomingLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(PanelTheme.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    placementBanner
                    // Below the queue on purpose: this file's header calls review
                    // surfacing "the loop the product is for", and twelve subject
                    // rows above it would push the first due node off a 720-point
                    // sidebar. Subjects sit beside the frontier instead, which is
                    // the other forward-looking list.
                    dueList
                    subjectList
                    frontierList
                    upcomingList
                    diagnostics
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
        }
        .background(PanelTheme.background.opacity(0.86))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Review")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PanelTheme.primaryText)
            Spacer(minLength: 0)
            // A pinned clock is a deliberately frozen run; saying so beats letting
            // someone read a fixture snapshot as today's state.
            if scores.isClockPinned {
                Text("clock pinned")
                    .font(.system(size: 10))
                    .foregroundStyle(PanelTheme.tertiaryText)
                    .help("MATHTREE_NOW froze the clock at \(scores.evaluatedAt.formatted())")
            }
            SidebarCloseButton(action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Placement

    /// §5.3's entry point, and D6.10's answer: a fresh map is almost entirely grey,
    /// which is correct but carries no information. Offered while it would help,
    /// resumable while it is running, and gone once it is done — a questionnaire
    /// that lingers after it is answered is clutter.
    @ViewBuilder
    private var placementBanner: some View {
        if let placement, placement.canPlace, !placement.isReadOnly,
            placement.session?.isCommitted != true
        {
            VStack(alignment: .leading, spacing: 7) {
                Text(placement.isActive ? "Placement in progress" : "Start somewhere")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PanelTheme.primaryText)
                Text(
                    placement.isActive
                        ? "\(placement.progress?.unresolved ?? 0) nodes still to settle."
                        : scores.state.nodes.isEmpty
                            ? "Answer a handful of problems and the map fills in around what you know."
                            : "Answer a handful of problems to fill in the rest of the map."
                )
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                SheetButton(
                    title: placement.isActive ? "Continue" : "Place me", isProminent: true,
                    action: onPlace)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(PanelTheme.accent.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(PanelTheme.accent.opacity(0.22), lineWidth: 1))
        }
    }

    // MARK: - Lists

    /// §6.5: "learn linear algebra" as something you can *ask for by name*. The
    /// map already contains every branch as a hub, but finding one on a graph you
    /// do not know yet is the wrong first step for someone whose whole question is
    /// where to start.
    ///
    /// Only authored subjects are listed. §7.1 puts the outline in before the
    /// content, so most branches would otherwise appear as offers that lead to an
    /// empty path — `validate` already reports the outline's coverage, and this is
    /// not the place to relitigate it.
    @ViewBuilder
    private var subjectList: some View {
        let authored = orderedSubjects
        if let onLearnSubject, !authored.isEmpty {
            section("Learn a subject", count: authored.count) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(authored, id: \.id) { summary in
                        SubjectRow(
                            summary: summary,
                            title: title(of: summary.id),
                            action: { onLearnSubject(summary.id) })
                    }
                }
                .padding(.horizontal, -7)
            }
        }
    }

    /// Least-known first: the list is a place to start, and a branch already at 90 %
    /// is not where starting happens. Ties by title, so the order is stable.
    private var orderedSubjects: [SubjectSummary] {
        scores.subjects
            .filter(\.isAuthored)
            .sorted { left, right in
                if left.fraction != right.fraction { return left.fraction < right.fraction }
                return title(of: left.id).localizedStandardCompare(title(of: right.id))
                    == .orderedAscending
            }
    }

    private func title(of id: NodeID) -> String {
        document.index(of: id).map { document[$0].title } ?? id.rawValue
    }

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

    @ViewBuilder
    private var upcomingList: some View {
        let upcoming = scores.upcoming
        if !upcoming.isEmpty {
            section("Scheduled", count: upcoming.count) {
                rows(upcoming.prefix(Self.upcomingLimit).map(\.id))
                if upcoming.count > Self.upcomingLimit {
                    note("+ \(upcoming.count - Self.upcomingLimit) more")
                }
            }
        }
    }

    /// Log corruption and fold defects (D5.8) surface here rather than in a log
    /// nobody reads — an event the fold could not apply is a score that is quietly
    /// missing.
    @ViewBuilder
    private var diagnostics: some View {
        // Placement's own defects (an unreadable or unwritable session file) join
        // them: reporting into a property nothing displays is the same as
        // swallowing it.
        let messages = scores.diagnostics + (placement?.diagnostics ?? [])
        if !messages.isEmpty {
            section("Diagnostics", count: messages.count) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(messages, id: \.self) { message in
                        Text(message)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(PanelTheme.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, count: Int, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(PanelTheme.tertiaryText)
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(PanelTheme.tertiaryText.opacity(0.7))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rows(_ ids: [NodeID]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(ids, id: \.self) { id in
                ReviewRow(
                    id: id, document: document, scores: scores, onSelect: onSelect,
                    // §5.4's routing rule: a node the bank can ask about gets a
                    // problem; everything else keeps the self-report in the panel.
                    onReview: scores.canProbe(id) ? onReview : nil)
            }
        }
        .padding(.horizontal, -7)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(PanelTheme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One subject offer: name, how much of it is already held, and one click into
/// §6.5's path.
private struct SubjectRow: View {
    let summary: SubjectSummary
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: summary.isComplete ? "checkmark.seal" : "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 10))
                    .foregroundStyle(
                        summary.isComplete ? PanelTheme.accent : PanelTheme.tertiaryText)
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(PanelTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if isHovering {
                    Text("path")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PanelTheme.accent)
                } else {
                    SubjectProgressBar(
                        met: summary.met, total: summary.total, width: 52, isCompact: true)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? PanelTheme.rowHighlight : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("\(summary.met) of \(summary.total) nodes mastered — open the guided path")
        .accessibilityLabel("Learn \(title), \(summary.met) of \(summary.total) mastered")
    }
}

/// One queue entry. Selecting it centres the node on the map, so reviewing from
/// the sidebar and reviewing from the graph are the same act.
private struct ReviewRow: View {
    let id: NodeID
    let document: GraphDocument
    let scores: ScoreStore
    let onSelect: (NodeID) -> Void
    /// Present only when the bank can ask about this node (§5.4).
    var onReview: ((NodeID) -> Void)?
    @State private var isHovering = false

    private var title: String {
        document.index(of: id).map { document[$0].title } ?? id.rawValue
    }

    var body: some View {
        Button {
            onSelect(id)
        } label: {
            HStack(spacing: 8) {
                swatch
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(PanelTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                // Revealed on hover so the row stays a list rather than a control
                // panel, but present on every probeable node — this is the shortest
                // path from "this is due" to actually reviewing it.
                if isHovering, let onReview {
                    Button { onReview(id) } label: {
                        Text("problem")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(PanelTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Review this with a problem")
                } else {
                    Text(trailing)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(PanelTheme.tertiaryText)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? PanelTheme.rowHighlight : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(id.rawValue)
    }

    private var swatch: some View {
        ZStack {
            Circle()
                .fill(ScoreFormat.color(of: id, in: scores))
                .frame(width: 8, height: 8)
            if scores.isFrontier(id) {
                Circle()
                    .strokeBorder(Color(ScoreRamp.frontierAccent), lineWidth: 1.2)
                    .frame(width: 14, height: 14)
            }
        }
        .frame(width: 15, height: 15)
    }

    /// Frontier rows have no score to show, so they show what they are waiting to
    /// become; scored rows show the number the colour encodes.
    ///
    /// Routed through `ScoreFormat.state` rather than reading retrievability
    /// directly, because a node that was missed and never learned has a
    /// retrievability — a high one, right after the attempt — that means nothing.
    /// Printing "100%" beside a grey swatch would be the sidebar contradicting the
    /// map (D8.3).
    private var trailing: String {
        switch ScoreFormat.state(of: id, in: scores) {
        case .unlearned, .frontier: "new"
        case .attempted: "missed"
        case let .learned(retrievability): ScoreFormat.percent(retrievability)
        }
    }
}

/// Shared by the sidebar and by Phase 8's modal sheets, so "close this" is one
/// affordance in one place rather than three that drift.
struct SidebarCloseButton: View {
    var symbol = "sidebar.leading"
    var label = "Hide the review sidebar"
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering ? PanelTheme.primaryText : PanelTheme.tertiaryText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isHovering ? PanelTheme.rowHighlight : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
    }
}
