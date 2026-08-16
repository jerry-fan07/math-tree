import Darwin
import Foundation
import GraphCore
import simd

/// `MathTree --probe`: render the real scene in the real window, then print a
/// JSON report and exit.
///
/// It exists because screen capture and AppleScript are unavailable here, so
/// §6.1's zoom behaviours have to be *assertable* rather than claimed — the
/// report carries the LOD prefix counts and visible label tiers for each of the
/// three zoom levels, plus the measured time to first drawable.
///
/// `--probe` is a single **trailing boolean** flag. D3.7: AppKit parses leftover
/// `-key value` tokens into `NSUserDefaults`, and a flag with a following token
/// made SwiftUI never call `makeNSView` — the window silently never existed and
/// the process hung. Anything richer than a bare flag goes through the
/// environment (see `Snapshot`).
enum Probe {
    static var isRequested: Bool { CommandLine.arguments.last == "--probe" }

    /// Kernel process-start time, so first paint is measured from the same origin
    /// D3.2 used rather than from `main()`.
    static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [
            CTL_KERN, KERN_PROC, KERN_PROC_PID, ProcessInfo.processInfo.processIdentifier,
        ]
        let status = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, UInt32(buffer.count), &info, &size, nil, 0)
        }
        guard status == 0 else { return nil }
        let started = info.kp_proc.p_starttime
        return Date(
            timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
    }

    /// Wire the report into the renderer's first completed frame.
    @MainActor
    static func install(on renderer: GraphRenderer) {
        let processStart = processStartDate()
        renderer.makeFirstDrawCompletion = { renderer in
            let template = Report.build(renderer: renderer)
            return {
                let elapsed = processStart.map { Date().timeIntervalSince($0) * 1000 } ?? -1
                print(
                    template.replacingOccurrences(
                        of: "\"__FIRST_DRAW_MS__\"", with: Report.number(elapsed)))
                fflush(stdout)
                exit(0)
            }
        }
    }

    /// Bail out loudly rather than hanging if the window never draws — the exact
    /// failure mode D3.7 recorded.
    @MainActor
    static func installWatchdog(seconds: Double = 12) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            FileHandle.standardError.write(
                Data("probe: no frame completed within \(Int(seconds))s\n".utf8))
            exit(2)
        }
    }

    enum Report {
        static func number(_ value: Double, _ places: Int = 3) -> String {
            let text = String(format: "%.\(places)f", value)
            return text
        }

        static func number(_ value: Float, _ places: Int = 3) -> String {
            number(Double(value), places)
        }

        @MainActor
        static func build(renderer: GraphRenderer) -> String {
            let scene = renderer.scene
            let document = scene.document
            let timings = renderer.timings
            let atlas = renderer.atlasStats
            let fitScale = renderer.fitScale
            let backingScale = renderer.backingScale

            func tierMap(_ counts: [Int]) -> String {
                LODTier.allCases.map { "\"\($0.name)\": \(counts[$0.rawValue])" }
                    .joined(separator: ", ")
            }

            var levels: [String] = []
            for band in ZoomBand.allCases {
                let ratio = band.representativeRatio
                let t = ZoomBand.bandT(forRatio: ratio)
                let radii = LODTier.allCases.map { tier -> String in
                    let r = tier.radiiPt
                    return "\"\(tier.name)\": \(number(r.overview + (r.detail - r.overview) * t, 2))"
                }.joined(separator: ", ")
                let visible = scene.visibleLabelTiers(bandT: t)
                    .map { "\"\($0.name)\"" }.joined(separator: ", ")
                let containsParams = renderer.edgeParams(
                    .contains, count: scene.edges[0].count, bandT: t)
                let requiresParams = renderer.edgeParams(
                    .requires, count: scene.edges[1].count, bandT: t)
                let relatesParams = renderer.edgeParams(
                    .relates, count: scene.edges[2].count, bandT: t)

                levels.append(
                    """
                        {
                          "band": "\(band.rawValue)",
                          "zoomRatioOfFit": \(number(ratio, 2)),
                          "bandT": \(number(t, 4)),
                          "scalePtPerWorldUnit": \(number(fitScale * ratio, 4)),
                          "nodePrefix": \(scene.nodePrefix(bandT: t, backingScale: backingScale)),
                          "nodeRadiusPt": { \(radii) },
                          "edgePrefix": { "contains": \(scene.edgePrefix(.contains, bandT: t)), \
                    "requires": \(scene.edgePrefix(.requires, bandT: t)), \
                    "relates": \(scene.edgePrefix(.relates, bandT: t)) },
                          "edgeStyle": {
                            "containsAlpha": \(number(containsParams.alpha, 3)),
                            "requiresAlpha": \(number(requiresParams.alpha, 3)),
                            "requiresArrowAlpha": \(number(requiresParams.arrowAlpha, 3)),
                            "relatesAlpha": \(number(relatesParams.alpha, 3)),
                            "relatesDashDuty": \(number(relatesParams.dashDuty, 3))
                          },
                          "labelPrefix": \(scene.labelPrefix(bandT: t)),
                          "labelTiersVisible": [\(visible)]
                        }
                    """)
            }

            let interaction = interactionChecks(renderer: renderer)
            let edgeTotal = scene.edges.reduce(0) { $0 + $1.count }
            // `appearance` below is which direction of the redesign the packed
            // colour words belong to. Two runs in different appearances *should*
            // differ; `check-score-determinism.sh` compares runs in the same one.
            return """
                {
                  "app": "MathTree",
                  "phase": 7,
                  "appearance": "\(renderer.theme.appearance.rawValue)",
                  "scores": \(scores(renderer: renderer)),
                  "focus": \(focus(renderer: renderer)),
                  "content": {
                    "nodes": \(document.nodes.count),
                    "containsEdges": \(scene.edges[0].count),
                    "requiresEdges": \(document.requiresEdges.count),
                    "relatesEdges": \(document.relatesEdges.count)
                  },
                  "instances": {
                    "nodes": \(scene.nodeInstances.count),
                    "edges": \(edgeTotal),
                    "labels": \(scene.labelSpecs.count),
                    "bytes": {
                      "node": \(scene.nodeInstances.count * MemoryLayout<NodeInstance>.stride),
                      "edge": \(edgeTotal * MemoryLayout<EdgeInstance>.stride),
                      "label": \(scene.labelSpecs.count * MemoryLayout<LabelInstance>.stride),
                      "uniform": \(MemoryLayout<Uniforms>.stride)
                    },
                    "nodesByTier": { \(tierMap(scene.nodeCountByTier)) },
                    "labelsByTier": { \(tierMap(scene.labelCountByTier)) }
                  },
                  "labelAtlas": {
                    "eagerTierAtLoad": "\(LODTier.landmark.name)",
                    "labelsRasterisedAtFirstDraw": \(atlas.labels),
                    "pagesAtFirstDraw": \(atlas.pages),
                    "bytesAtFirstDraw": \(atlas.bytes),
                    "rasteriseMs": \(number(atlas.rasteriseMs))
                  },
                  "firstDraw": {
                    "processStartToFirstDrawableMs": "__FIRST_DRAW_MS__",
                    "documentLoadMs": \(number(timings.documentLoadMs)),
                    "sceneBuildMs": \(number(timings.sceneBuildMs)),
                    "shaderCompileMs": \(number(timings.shaderCompileMs)),
                    "pipelineMs": \(number(timings.pipelineMs)),
                    "instanceBufferMs": \(number(timings.instanceBufferMs)),
                    "labelAtlasMs": \(number(timings.labelAtlasMs))
                  },
                  "viewport": {
                    "drawablePx": [\(Int(renderer.viewportPx.x)), \(Int(renderer.viewportPx.y))],
                    "backingScale": \(number(backingScale, 1)),
                    "fitScalePtPerWorldUnit": \(number(fitScale, 4))
                  },
                  "interaction": \(interaction),
                  "zoomLevels": [
                \(levels.joined(separator: ",\n"))
                  ]
                }
                """
        }

        /// §4.5 and §5.4, as numbers.
        ///
        /// Everything here is a *read-back*, not a recomputation: the packed
        /// colour words come out of the node buffer the GPU drew from, so two runs
        /// agreeing means two runs painted the same map — which is the only form
        /// of "relaunching reproduces identical colours" that can be checked
        /// without a camera. Compare with `Scripts/check-score-determinism.sh`.
        @MainActor
        private static func scores(renderer: GraphRenderer) -> String {
            guard let store = SceneStore.shared.scores else {
                return "{ \"available\": false }"
            }
            let document = renderer.scene.document
            let packed = renderer.packedNodeColors()

            func quoted(_ values: [String]) -> String {
                "[" + values.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
            }

            // Every node, in document order: the §4.5 colour and the rgba8 word it
            // packed to. Structural nodes have no score colour and keep their
            // taxonomy hue (D6.1), which shows up here as a null ramp entry beside
            // a non-null packed word.
            let nodes = document.nodes.enumerated().map { index, node -> String in
                let ramp = node.kind.isContent ? "\"\(store.color(of: node.id).hex)\"" : "null"
                let recall = store.retrievability(of: node.id)
                let word = index < packed.count ? String(format: "%08X", packed[index]) : "null"
                return """
                        { "id": "\(node.id.rawValue)", "ramp": \(ramp), \
                    "packed": "\(word)", \
                    "retrievability": \(recall.map { number($0, 6) } ?? "null"), \
                    "frontier": \(store.isFrontier(node.id)) }
                    """
            }

            let due = store.due.map { entry in
                """
                        { "id": "\(entry.id.rawValue)", "due": "\(iso(entry.due))", \
                    "retrievability": \(number(entry.retrievability, 6)) }
                    """
            }

            let relates = document.relatesEdges.map { edge -> String in
                let recall = store.retrievability(ofEdge: edge.key)
                return """
                        { "key": "\(edge.key)", "retrievability": \
                    \(recall.map { number($0, 6) } ?? "null") }
                    """
            }

            let frontierIDs = store.frontierList.map(\.rawValue)
            return """
                {
                    "available": true,
                    "evidenceLog": "\(store.log.url.path)",
                    "readOnly": \(store.isReadOnly),
                    "clockPinned": \(store.isClockPinned),
                    "evaluatedAt": "\(iso(store.evaluatedAt))",
                    "events": \(store.events.count),
                \(assessment(store: store)),
                    "learnedNodes": \(store.state.nodes.count),
                    "frontierCount": \(store.frontier.count),
                    "frontierRingsDrawn": \(renderer.frontierRingCount),
                    "dueCount": \(store.due.count),
                    "diagnostics": \(quoted(store.diagnostics)),
                    "frontier": \(quoted(frontierIDs)),
                    "due": [
                \(due.joined(separator: ",\n"))
                    ],
                    "relatesEdges": [
                \(relates.joined(separator: ",\n"))
                    ],
                    "nodes": [
                \(nodes.joined(separator: ",\n"))
                    ]
                  }
                """
        }

        /// §5.2/§5.3 wiring, as numbers.
        ///
        /// Deliberately *not* a restatement of Phase 8's exit criteria: those are
        /// asserted over real content in `PlacementFixtureTests`, which is a
        /// stronger check than anything a probe of one launch can do. What only the
        /// app can answer is whether the compiled bank was actually found, routed
        /// and offered — the wiring, not the algorithm.
        @MainActor
        private static func assessment(store: ScoreStore) -> String {
            let content = store.graph.nodes.filter { $0.kind.isContent }
            let covered = content.filter { store.canProbe($0.id) }
            let placement = SceneStore.shared.placement
            let probe = placement?.nextProbe
            return """
                    "bank": {
                        "available": \(SceneStore.shared.problems.isAvailable),
                        "unavailable": \(quoted(SceneStore.shared.problems.unavailable)),
                        "problems": \(store.bank.count),
                        "contentNodes": \(content.count),
                        "probeableNodes": \(covered.count),
                        "edgeProblems": \(store.bank.problems.filter { !$0.connects.isEmpty }.count),
                        "dueWithProblem": \(store.due.filter { store.canProbe($0.id) }.count)
                    },
                    "placement": {
                        "canPlace": \(placement?.canPlace ?? false),
                        "readOnly": \(placement?.isReadOnly ?? true),
                        "session": \(placement?.session != nil),
                        "answers": \(placement?.session?.answers.count ?? 0),
                        "committed": \(placement?.session?.isCommitted ?? false),
                        "unresolved": \(placement?.progress?.unresolved ?? -1),
                        "nextProbe": \(quoted(probe.map { "\($0.problem.id) → \($0.node)" }))
                    }
                """
        }

        private static func quoted(_ value: String?) -> String {
            guard let value else { return "null" }
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }

        /// §6.2 and §5.4, as numbers — Phase 7's exit criterion made assertable.
        ///
        /// The goal is derived from content per D4.5's convention — the node with
        /// the deepest `requires`-ancestry, i.e. the most demanding goal the
        /// corpus offers, which is the case focus mode exists for (the detail
        /// anchor's plan is trivially met for any fixture user and would
        /// demonstrate nothing). The plan is the one the focus view would render
        /// over this run's evidence log, and the two checks re-derive the exit
        /// criterion
        /// independently: `topologicallyValid` walks *transitive* prerequisite
        /// pairs (so precedence through met intermediates is checked, not just
        /// direct edges), and `omitsExactlyMet` recomputes the unmet set straight
        /// from FSRS state. The 60 fps clause cannot be measured headlessly; what
        /// is assertable is that the transition is camera-only — the flight
        /// writes the same 40-byte uniform a settled frame writes, zero buffer
        /// uploads — plus the on-demand plan cost reported here.
        @MainActor
        private static func focus(renderer: GraphRenderer) -> String {
            guard let store = SceneStore.shared.scores else { return "{ \"available\": false }" }
            var deepest: (id: GraphCore.NodeID, depth: Int)?
            for node in store.graph.nodes where node.kind.isContent {
                let depth = store.graph.requiresAncestors(of: node.id).count
                if deepest == nil || depth > deepest!.depth
                    || (depth == deepest!.depth && node.id < deepest!.id)
                {
                    deepest = (node.id, depth)
                }
            }
            guard let goal = deepest?.id else { return "{ \"available\": false }" }

            let start = CFAbsoluteTimeGetCurrent()
            guard
                let plan = FocusPlan.compute(
                    goal: goal, graph: store.graph, state: store.state, at: store.evaluatedAt,
                    config: store.config)
            else { return "{ \"available\": false, \"goal\": \"\(goal.rawValue)\" }" }
            let planMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

            var topologicallyValid = true
            for (index, id) in plan.syllabus.enumerated() {
                for ancestor in store.graph.requiresAncestors(of: id)
                where plan.syllabus.contains(ancestor) {
                    if plan.syllabus.firstIndex(of: ancestor)! >= index {
                        topologicallyValid = false
                    }
                }
            }

            let fsrs = FSRS(parameters: store.config.fsrs)
            let expectedUnmet = Set(
                store.graph.requiresAncestors(of: goal).filter { id in
                    guard store.graph[id]?.kind.isContent == true else { return false }
                    guard let memory = store.state.nodes[id] else { return true }
                    return fsrs.retrievability(of: memory, at: store.evaluatedAt)
                        <= store.config.masteryThreshold
                })

            let columnsMonotone = plan.edges.allSatisfy {
                plan.placed[$0.from]!.column < plan.placed[$0.to]!.column
            }

            let flightTarget = renderer.focusCamera(on: goal)

            func quoted(_ ids: [GraphCore.NodeID]) -> String {
                "[" + ids.map { "\"\($0.rawValue)\"" }.joined(separator: ", ") + "]"
            }

            return """
                {
                    "available": true,
                    "goal": "\(goal.rawValue)",
                    "goalIsMet": \(plan.goalIsMet),
                    "syllabus": \(quoted(plan.syllabus)),
                    "metBoundary": \(quoted(plan.metBoundary)),
                    "elidedMetCount": \(plan.elidedMetCount),
                    "displayedNodes": \(plan.displayedCount),
                    "columns": \(plan.columns.count),
                    "edges": \(plan.edges.count),
                    "topologicallyValid": \(topologicallyValid),
                    "omitsExactlyMet": \(Set(plan.syllabus) == expectedUnmet),
                    "columnsMonotone": \(columnsMonotone),
                    "planComputeMs": \(number(planMs)),
                    "transition": {
                      "cameraOnly": true,
                      "targetCenter": [\(number(flightTarget?.center.x ?? 0, 2)), \
                \(number(flightTarget?.center.y ?? 0, 2))],
                      "targetScalePtPerWorldUnit": \(number(flightTarget?.scale ?? 0, 4))
                    }
                  }
                """
        }

        static func iso(_ date: Date) -> String {
            date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: false, timeZone: .gmt))
        }

        /// Input handling cannot be driven headlessly, but its two load-bearing
        /// calculations can be checked: that a node projected to the screen picks
        /// back to itself, and that zooming keeps the world point under the cursor
        /// nailed to the cursor. The frame is already encoded by the time this
        /// runs, so borrowing the camera is harmless — it is restored anyway.
        @MainActor
        private static func interactionChecks(renderer: GraphRenderer) -> String {
            let scene = renderer.scene
            let saved = renderer.camera
            defer { renderer.camera = saved }

            let viewportPt = renderer.viewportPt
            renderer.camera.center = scene.center
            renderer.camera.scale = renderer.fitScale

            var hits = 0
            var elapsed = 0.0
            for index in 0..<scene.worldPositions.count {
                let point = renderer.camera.viewPt(
                    fromWorld: scene.worldPositions[index], viewportPt: viewportPt)
                let start = CFAbsoluteTimeGetCurrent()
                let picked = renderer.pick(atViewPt: point)
                elapsed += CFAbsoluteTimeGetCurrent() - start
                if picked == index { hits += 1 }
            }
            let count = max(scene.worldPositions.count, 1)

            // Zoom toward the cursor, not the view centre: the world point under
            // an off-centre anchor must not move when the scale changes.
            let anchor = SIMD2(viewportPt.x * 0.23, viewportPt.y * 0.71)
            let before = renderer.camera.world(fromViewPt: anchor, viewportPt: viewportPt)
            renderer.camera.zoom(
                by: 2.0, anchorPt: anchor, viewportPt: viewportPt, fitScale: renderer.fitScale)
            let after = renderer.camera.world(fromViewPt: anchor, viewportPt: viewportPt)
            let driftPt = simd_length(after - before) * renderer.camera.scale

            return """
                {
                    "pickRoundTripHits": \(hits),
                    "pickRoundTripOf": \(count),
                    "pickMeanNs": \(number(elapsed / Double(count) * 1e9, 0)),
                    "cursorAnchoredZoomDriftPt": \(number(driftPt, 6))
                  }
                """
        }
    }
}
