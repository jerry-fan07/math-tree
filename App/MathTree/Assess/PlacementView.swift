import GraphCore
import SwiftUI

/// §5.3's adaptive placement, on screen.
///
/// Three states, matching the spec's three steps: claim a coarse frontier, answer
/// probes until the picture stabilises, then commit what was inferred. The middle
/// state reuses `ProblemSheet` unchanged — a probe *is* a problem, and making it
/// look like a different thing would be a lie about what is being measured.
///
/// D6.10 is why this exists at all: with no evidence the map is entirely grey with
/// a single gold ring. That reads as an instruction rather than an empty state,
/// but it carries almost no information, and §5.3's placement is the designed
/// answer.
struct PlacementView: View {
    let document: GraphDocument
    let scores: ScoreStore
    let placement: PlacementStore
    var onSelect: (NodeID) -> Void
    var onExit: () -> Void

    /// Claims are made against subbranches: "finished single-variable calculus" is
    /// the coarse unit §5.3 asks for, and asking a user to tick 22 individual
    /// nodes would be the assessment it is meant to replace.
    @State private var claimed: Set<NodeID> = []

    private var subbranches: [Node] {
        document.nodes.filter { $0.kind == .subbranch }.sorted { $0.id < $1.id }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()

            if let probe = placement.nextProbe {
                ProblemSheet(
                    problem: probe.problem,
                    subject: probe.node,
                    document: document,
                    scores: scores,
                    progress: progressLabel,
                    onGrade: { outcome, localized in
                        placement.record(
                            outcome, on: probe.problem, node: probe.node, localizedTo: localized)
                    },
                    onDismiss: onExit)
            } else {
                // `session != nil`, not `isActive`: `isActive` is false once the
                // session is committed, which sent a *committed* session back to
                // the claim screen — the one state the "Placed" branch exists for
                // was unreachable. Found by rendering it (D8.9).
                SheetCard(width: 620, maxHeight: 620) {
                    if placement.session != nil { summary } else { intro }
                }
            }
        }
    }

    private var progressLabel: String? {
        guard let progress = placement.progress else { return nil }
        return "PLACEMENT · \(progress.probesAnswered + 1) · \(progress.unresolved) LEFT TO SETTLE"
    }

    // MARK: - Step 1: the claimed frontier

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Where are you?")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PanelTheme.primaryText)
                    Spacer(minLength: 0)
                    SidebarCloseButton(symbol: "xmark", label: "Close placement", action: onExit)
                }
                Text(
                    "Tell it roughly what you have studied, then answer a handful of "
                        + "problems. Each answer settles a whole region of the map, so this "
                        + "is short — a pass says you have the prerequisites too, and a miss "
                        + "says where to look next."
                )
                .font(.system(size: 12.5))
                .foregroundStyle(PanelTheme.secondaryText)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(subbranches, id: \.id) { node in
                        ClaimRow(
                            node: node,
                            isClaimed: claimed.contains(node.id),
                            toggle: {
                                if claimed.contains(node.id) {
                                    claimed.remove(node.id)
                                } else {
                                    claimed.insert(node.id)
                                }
                            })
                    }
                }

                if !placement.canPlace {
                    Text(
                        "No problem bank is loaded, so there is nothing to probe with. "
                            + "Run: swift run ContentBuild build"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(PanelTheme.warning)
                }

                HStack(spacing: 8) {
                    SheetButton(title: "Start", isProminent: true) {
                        placement.start(claiming: claimed.sorted())
                    }
                    .disabled(!placement.canPlace)
                    SheetButton(title: "Skip") { onExit() }
                    Spacer(minLength: 0)
                }
                // §5.3: "Placement is optional and resumable." Both halves said out
                // loud, because a questionnaire that looks mandatory is one.
            Text("Optional, and resumable — you can close this and pick it up later.")
                .font(.system(size: 10.5))
                .foregroundStyle(PanelTheme.tertiaryText)
        }
    }

    // MARK: - Step 3: what it concluded

    private var summary: some View {
        let belief = placement.belief
        let known = belief?.known ?? []
        let boundary = belief.map { $0.boundary(in: scores.graph) } ?? []
        let unresolved = belief?.unresolved ?? []

        return VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(placement.session?.isCommitted == true ? "Placed" : "That is enough")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PanelTheme.primaryText)
                    Spacer(minLength: 0)
                    SidebarCloseButton(symbol: "xmark", label: "Close placement", action: onExit)
                }

                Text(
                    "\(placement.session?.answers.count ?? 0) problems settled \(known.count) "
                        + "nodes. Your edge sits here:"
                )
                .font(.system(size: 12.5))
                .foregroundStyle(PanelTheme.secondaryText)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(boundary, id: \.self) { id in
                        NodeReferenceRow(
                            id: id, document: document, scores: scores, onSelect: onSelect)
                    }
                }

                // Reported, not rounded: a node no problem targets can end here
                // through no fault of the policy, and pretending otherwise would
                // paint the map with a confidence nothing earned.
                if !unresolved.isEmpty {
                    Text(
                        "\(unresolved.count) node\(unresolved.count == 1 ? "" : "s") could not be "
                            + "settled — no problem in the bank targets them. They stay unlearned "
                            + "until something asks."
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelTheme.tertiaryText)
                }

                if placement.session?.isCommitted == true {
                    Text("Recorded. Everything above it is on the map.")
                        .font(.system(size: 11))
                        .foregroundStyle(PanelTheme.secondaryText)
                    SheetButton(title: "Back to the map", isProminent: true) { onExit() }
                } else {
                    HStack(spacing: 8) {
                        SheetButton(title: "Record this", isProminent: true) {
                            placement.commit()
                        }
                        SheetButton(title: "Discard") {
                            placement.discard()
                            onExit()
                        }
                        Spacer(minLength: 0)
                    }
                    // The honest description of the inferred tier. §5.3 stores it
                    // as low-confidence evidence that decays faster until a direct
                    // test confirms it, and the user is entitled to know their map
                    // is partly inference.
                    Text(
                        "What you were not asked directly is recorded as inference — it decays "
                            + "faster than a real review until a problem confirms it. The problems "
                            + "you answered are already recorded either way."
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelTheme.tertiaryText)
                }
        }
    }
}

private struct ClaimRow: View {
    let node: Node
    let isClaimed: Bool
    let toggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: isClaimed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(isClaimed ? PanelTheme.accent : PanelTheme.tertiaryText)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                VStack(alignment: .leading, spacing: 3) {
                    MathTextView(
                        source: node.title, size: 13,
                        color: isHovering || isClaimed ? .white : PanelTheme.primaryText)
                    if let summary = node.summary, !summary.isEmpty {
                        MathTextView(source: summary, size: 10.5, color: PanelTheme.tertiaryText)
                    }
                }
                Spacer(minLength: 0)
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
}
