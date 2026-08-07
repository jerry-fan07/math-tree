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

            if let target = environment["MATHTREE_PANEL_SHOT_REPORT"] {
                selfReport(target, document: document, into: root)
            }

            print("panel-shot: wrote to \(root.path)")
            fflush(stdout)
            exit(0)
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
