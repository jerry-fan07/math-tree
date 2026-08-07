#if DEBUG
    import AppKit
    import Foundation
    import GraphCore
    import SwiftUI

    /// Throwaway verification harness: renders the SwiftUI overlays offscreen so
    /// they can actually be looked at.
    ///
    /// D4.10: the panel is a SwiftUI overlay, so it never appears in the renderer's
    /// Metal snapshots, and `ImageRenderer` leaves `ScrollView` content blank —
    /// which would produce a false pass. `NSHostingView` + `cacheDisplay` is what
    /// works.
    ///
    /// `MATHTREE_PANEL_SHOT=<dir>` writes one PNG per view and exits.
    enum PanelShot {
        @MainActor
        static func runIfRequested() {
            let environment = ProcessInfo.processInfo.environment
            guard let directory = environment["MATHTREE_PANEL_SHOT"], !directory.isEmpty else {
                return
            }
            guard let scene = SceneStore.shared.scene, let scores = SceneStore.shared.scores else {
                FileHandle.standardError.write(
                    Data("panel-shot: \(SceneStore.shared.errorMessage ?? "no scene")\n".utf8))
                exit(3)
            }
            let document = scene.document
            let root = URL(fileURLWithPath: directory)

            func panel(_ id: NodeID) -> AnyView {
                guard let index = document.index(of: id) else { return AnyView(EmptyView()) }
                return AnyView(
                    NodePanel(
                        node: document[index], document: document, scores: scores,
                        onSelect: { _ in }, onClose: {}
                    )
                    .background(PanelTheme.background))
            }

            // A learned node with history, a frontier node, a decayed node, and a
            // structural one — the four states the section can be in.
            for id: NodeID in [
                "analysis.svc.mvt", "analysis.svc.ivt", "analysis.svc.def-riemann-sum",
                "analysis.svc",
            ] {
                write(panel(id), to: root.appendingPathComponent("panel-\(id.rawValue).png"),
                    size: CGSize(width: 360, height: 900))
            }

            write(
                AnyView(
                    ReviewSidebar(
                        document: document, scores: scores, onSelect: { _ in }, onClose: {}
                    )
                    .background(PanelTheme.background)),
                to: root.appendingPathComponent("sidebar.png"),
                size: CGSize(width: 268, height: 720))

            // Phase 7: the focus view over the same goal the fixture story is
            // about. Rendered like every overlay before it — NSHostingView +
            // cacheDisplay (D4.10; ImageRenderer blanks ScrollView content).
            write(
                AnyView(
                    FocusView(
                        goal: "analysis.svc.ftc-part-2", document: document, scores: scores,
                        onSelect: { _ in }, onExit: {})),
                to: root.appendingPathComponent("focus-ftc-part-2.png"),
                size: CGSize(width: 1200, height: 760))

            assessment(document: document, scores: scores, into: root)

            if let target = environment["MATHTREE_PANEL_SHOT_REPORT"] {
                selfReport(target, document: document, into: root)
            }

            print("panel-shot: wrote to \(root.path)")
            fflush(stdout)
            exit(0)
        }

        /// Phase 8's overlays. Every phase since Phase 4 has rendered its new
        /// overlays offscreen and every one of them found a real defect that
        /// compiled and previewed cleanly (D4.10, D6.9, D7.5), so this is not
        /// optional diligence.
        ///
        /// The three problem-sheet states are the three the user actually sees, and
        /// the last two are only reachable through button presses that cannot be
        /// driven headlessly — hence `startRevealed` / `startDiagnosing`.
        @MainActor
        private static func assessment(
            document: GraphDocument, scores: ScoreStore, into root: URL
        ) {
            // FTC Part II over the fixture user: heavy math in the statement, a
            // real chain below it, and the node the Phase 8 exit criterion is about.
            guard let problem = scores.nextProblem(for: "analysis.svc.ftc-part-2") else {
                FileHandle.standardError.write(
                    Data("panel-shot: no problem for ftc-part-2 — is problems.json built?\n".utf8))
                return
            }
            let size = CGSize(width: 660, height: 720)
            for (name, revealed, diagnosing) in [
                ("problem-attempt", false, false),
                ("problem-answer", true, false),
                ("problem-diagnosis", false, true),
            ] {
                write(
                    AnyView(
                        ProblemSheet(
                            problem: problem, subject: "analysis.svc.ftc-part-2",
                            document: document, scores: scores,
                            onGrade: { _, _ in }, onDismiss: {},
                            startRevealed: revealed, startDiagnosing: diagnosing)),
                    to: root.appendingPathComponent("\(name).png"), size: size)
            }

            placement(document: document, scores: scores, into: root)
        }

        /// §5.3's flow, and the app-level write path that goes with it.
        ///
        /// Drives a real `PlacementStore` over *copies* of the log and the session
        /// file — the same trick D6.9 used to close the one link no snapshot can
        /// reach. A scripted solver answers every probe from the fixture user's
        /// actual knowledge state, so the summary shown is one the app produced
        /// rather than one assembled for the picture.
        @MainActor
        private static func placement(
            document: GraphDocument, scores: ScoreStore, into root: URL
        ) {
            let logCopy = root.appendingPathComponent("placement-evidence.jsonl")
            let sessionCopy = root.appendingPathComponent("placement-session.json")
            for url in [logCopy, sessionCopy] { try? FileManager.default.removeItem(at: url) }
            let source = scores.log.url
            if FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.copyItem(at: source, to: logCopy)
            }

            let writable = ScoreStore(
                document: document,
                problems: SceneStore.shared.problems.bank,
                environment: [
                    "MATHTREE_EVIDENCE_LOG": logCopy.path,
                    "MATHTREE_NOW": ProcessInfo.processInfo.environment["MATHTREE_NOW"] ?? "",
                ],
                arguments: [])
            let store = PlacementStore(
                scores: writable, bank: SceneStore.shared.problems.bank,
                environment: ["MATHTREE_PLACEMENT": sessionCopy.path])

            write(
                AnyView(
                    PlacementView(
                        document: document, scores: writable, placement: store,
                        onSelect: { _ in }, onExit: {})),
                to: root.appendingPathComponent("placement-intro.png"),
                size: CGSize(width: 620, height: 660))

            // A solver who knows exactly what the fixture user has learned. A miss
            // localizes to the shallowest node whose own prerequisites are all
            // known — the first rung they could not climb.
            store.start(claiming: ["analysis.svc"])
            var answered = 0
            while let probe = store.nextProbe {
                let knows = { (id: NodeID) in writable.isLearned(id) }
                let passes = probe.problem.targets.allSatisfy(knows)
                let gap =
                    passes
                    ? nil
                    : (probe.problem.targets + probe.problem.targets.flatMap {
                        writable.graph.requiresAncestors(of: $0)
                    })
                    .filter { writable.graph[$0]?.kind.isContent == true && !knows($0) }
                    .filter { writable.graph.prerequisites(of: $0).allSatisfy(knows) }
                    .sorted().first
                store.record(
                    passes ? .solved : .missed, on: probe.problem, node: probe.node,
                    localizedTo: gap)
                answered += 1
            }
            let committed = store.commit()
            print(
                "panel-shot: placement answered=\(answered) known=\(store.belief?.known.count ?? 0) "
                    + "unresolved=\(store.belief?.unresolved.count ?? 0) inferred=\(committed) "
                    + "frontier=\(writable.frontier.count)")

            write(
                AnyView(
                    PlacementView(
                        document: document, scores: writable, placement: store,
                        onSelect: { _ in }, onExit: {})),
                to: root.appendingPathComponent("placement-summary.png"),
                size: CGSize(width: 620, height: 660))
        }

        /// Exercises the *write* path a button press takes — append, refold,
        /// repaint — which no snapshot can reach, because input cannot be driven
        /// headlessly. Runs against a copy of the log so the fixture it started
        /// from is untouched, and leaves the resulting log where it can be diffed
        /// against `fixtures/fixture-user-reviewed.jsonl`: if they match, the
        /// button writes exactly what the tests assert about.
        ///
        /// `MATHTREE_PANEL_SHOT_REPORT=<node id>:<shaky|solid|fluent>`
        @MainActor
        private static func selfReport(_ target: String, document: GraphDocument, into root: URL) {
            let parts = target.split(separator: ":")
            guard parts.count == 2, let confidence = SelfReportConfidence(rawValue: String(parts[1]))
            else {
                FileHandle.standardError.write(Data("panel-shot: bad report spec \(target)\n".utf8))
                return
            }
            let id = NodeID(String(parts[0]))

            let copy = root.appendingPathComponent("after-report.jsonl")
            try? FileManager.default.removeItem(at: copy)
            guard let source = SceneStore.shared.scores?.log.url,
                (try? FileManager.default.copyItem(at: source, to: copy)) != nil
            else { return }

            // A store of its own over the copy, with no read-only environment, so
            // this is the ordinary writable path rather than a special case.
            let store = ScoreStore(
                document: document,
                environment: [
                    "MATHTREE_EVIDENCE_LOG": copy.path,
                    "MATHTREE_NOW": ProcessInfo.processInfo.environment["MATHTREE_NOW"] ?? "",
                ],
                arguments: [])
            let before = store.color(of: id).hex
            let recorded = store.record(confidence, on: id)
            print(
                "panel-shot: report \(id) \(confidence.rawValue) recorded=\(recorded) "
                    + "\(before) -> \(store.color(of: id).hex) "
                    + "frontier \(store.frontier.count) events \(store.events.count)")

            write(
                AnyView(
                    NodePanel(
                        node: document[document.index(of: id) ?? 0], document: document,
                        scores: store, onSelect: { _ in }, onClose: {}
                    )
                    .background(PanelTheme.background)),
                to: root.appendingPathComponent("panel-after-report.png"),
                size: CGSize(width: 360, height: 900))

            // The focus view over the post-report state: §6.2's compression made
            // visible — reviewing the goal collapses its syllabus to whatever
            // propagation could not reach.
            write(
                AnyView(
                    FocusView(
                        goal: id, document: document, scores: store,
                        onSelect: { _ in }, onExit: {})),
                to: root.appendingPathComponent("focus-after-report.png"),
                size: CGSize(width: 1200, height: 760))
        }

        @MainActor
        private static func write(_ view: AnyView, to url: URL, size: CGSize) {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            host.frame = CGRect(origin: .zero, size: size)
            host.appearance = NSAppearance(named: .darkAqua)
            host.layoutSubtreeIfNeeded()
            // Let SwiftUI settle its layout pass before the bitmap is taken.
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            host.layoutSubtreeIfNeeded()

            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
#endif
