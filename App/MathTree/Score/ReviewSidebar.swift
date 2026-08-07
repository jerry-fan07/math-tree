import GraphCore
import SwiftUI

/// §5.4's review surfacing: "the FSRS scheduler surfaces due reviews", beside
/// §4.5's frontier — "what you could learn next, the actionable set the whole
/// product points at".
///
/// Two lists, because they answer different questions and are computed by
/// different instruments: **Due** is the scheduler's read-out (`nextDue`), and
/// **Ready to learn** is the frontier (unlearned, prerequisites above τ). A node
/// can never be in both — one has FSRS state and the other by definition does not.
struct ReviewSidebar: View {
    let document: GraphDocument
    let scores: ScoreStore
    var onSelect: (NodeID) -> Void
    var onClose: () -> Void

    private static let upcomingLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(PanelTheme.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dueList
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
        if !scores.diagnostics.isEmpty {
            section("Diagnostics", count: scores.diagnostics.count) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(scores.diagnostics, id: \.self) { message in
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
                ReviewRow(id: id, document: document, scores: scores, onSelect: onSelect)
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

/// One queue entry. Selecting it centres the node on the map, so reviewing from
/// the sidebar and reviewing from the graph are the same act.
private struct ReviewRow: View {
    let id: NodeID
    let document: GraphDocument
    let scores: ScoreStore
    let onSelect: (NodeID) -> Void
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
                Text(trailing)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(PanelTheme.tertiaryText)
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
    private var trailing: String {
        guard let retrievability = scores.retrievability(of: id) else { return "new" }
        return ScoreFormat.percent(retrievability)
    }
}

private struct SidebarCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.leading")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering ? PanelTheme.primaryText : PanelTheme.tertiaryText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isHovering ? PanelTheme.rowHighlight : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Hide the review sidebar")
    }
}
