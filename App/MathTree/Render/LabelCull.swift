import simd

/// Greedy label placement, computed once at scene build.
///
/// The design's frames are legible because its prototype culls: labels are placed
/// in tier order, each trying its preferred offset and then two alternates, and
/// dropped when nothing clears what is already placed or a node dot. Without it
/// the map's hub and subbranch names pile on top of each other wherever the
/// layout clusters — which is everywhere, because `contains` clustering is what
/// makes branches read as galaxies in the first place.
///
/// It runs over a **ladder of zoom ratios** rather than once, because the app
/// zooms continuously where the prototype had two fixed frames. Labels are
/// screen-space sized, so zooming in separates the anchors without growing the
/// boxes: a name that has nowhere to go at overview usually has room by mid zoom.
/// Each label therefore comes out with the zoom at which it first fits, which is
/// exactly the shape §6.1 already asks for ("`prominence ≥ 1` labels appear" as
/// the band deepens) — only per label instead of per tier.
///
/// Deterministic by construction: the ladder is fixed, the iteration order is the
/// scene's own tier-then-id order, and the geometry is the shipped layout. Same
/// content, same map (ground rule 5).
enum LabelCull {
    /// The frame the design is drawn at, and the snapshot default. Collisions are
    /// resolved in *relative* geometry, so this only sets the fit-to-view scale
    /// the ladder is anchored to — a wider window shows the same labels, more
    /// spread out.
    static let nominalViewportPt = SIMD2<Float>(1280, 800)

    /// Zoom ratios to solve at, as multiples of fit-to-view. Denser than the three
    /// bands so labels arrive gradually rather than in three lurches.
    static let ladder: [Float] = [1.0, 1.4, 2.0, 2.8, 4.0, 5.6, 8.0]

    /// Padding around a placed label before it counts as clear, and around a node
    /// dot. The dot's is smaller: a label is *meant* to sit close to its node.
    private static let labelPadding: Float = 4
    private static let nodePadding: Float = 1.5

    struct Placement {
        /// `bandT` at which this label first fits. `neverFits` when it does not fit
        /// anywhere on the ladder.
        var fadeStart: Float
        /// Vertical gap from the node centre to the label box, in points. Negative
        /// puts the label above the node.
        var offsetPt: Float
    }

    /// Beyond any `bandT` the camera can reach (which saturates at 1), so the
    /// shader's `smoothstep(fadeStart, fadeStart + 0.10, bandT)` is always zero.
    static let neverFits: Float = 2

    struct Rect {
        var minX: Float
        var minY: Float
        var maxX: Float
        var maxY: Float

        func overlaps(_ other: Rect, padding: Float) -> Bool {
            !(maxX + padding < other.minX || other.maxX + padding < minX
                || maxY + padding < other.minY || other.maxY + padding < minY)
        }
    }

    /// A uniform spatial hash over rectangles. The naive all-pairs test is O(n²)
    /// per ladder step, which is fine at seed scale and is not fine at D3.6's
    /// 10,000 nodes — and this is build-time work on the first-paint path (§6.4).
    private struct Grid {
        private let cell: Float
        private var buckets: [SIMD2<Int32>: [Rect]] = [:]

        init(cell: Float) { self.cell = max(cell, 1) }

        private func cells(_ rect: Rect, padding: Float) -> [SIMD2<Int32>] {
            let x0 = Int32(((rect.minX - padding) / cell).rounded(.down))
            let x1 = Int32(((rect.maxX + padding) / cell).rounded(.down))
            let y0 = Int32(((rect.minY - padding) / cell).rounded(.down))
            let y1 = Int32(((rect.maxY + padding) / cell).rounded(.down))
            var out: [SIMD2<Int32>] = []
            out.reserveCapacity(Int((x1 - x0 + 1) * (y1 - y0 + 1)))
            for x in x0...x1 {
                for y in y0...y1 { out.append(SIMD2(x, y)) }
            }
            return out
        }

        mutating func insert(_ rect: Rect) {
            for key in cells(rect, padding: 0) { buckets[key, default: []].append(rect) }
        }

        func hits(_ rect: Rect, padding: Float) -> Bool {
            for key in cells(rect, padding: padding) {
                guard let bucket = buckets[key] else { continue }
                for other in bucket where rect.overlaps(other, padding: padding) { return true }
            }
            return false
        }
    }

    /// One label's box, if it sat at `offset` below the anchor.
    private static func box(
        anchor: SIMD2<Float>, width: Float, height: Float, offset: Float
    ) -> Rect {
        Rect(
            minX: anchor.x - width / 2, minY: anchor.y + offset,
            maxX: anchor.x + width / 2, maxY: anchor.y + offset + height)
    }

    /// Solve the whole ladder. `specs` must already be in the scene's tier-then-id
    /// order — placement is greedy, so the order *is* the priority.
    static func solve(
        specs: [GraphScene.LabelSpec], worldPositions: [SIMD2<Float>],
        tiers: [LODTier], fitScale: Float
    ) -> [Placement] {
        var result = specs.map {
            Placement(fadeStart: neverFits, offsetPt: $0.offsetPt)
        }
        guard !specs.isEmpty, fitScale > 0 else { return result }

        // Approximate advance widths. Measuring through Core Text would be exact
        // and would also pull a text engine onto the first-paint path for a
        // decision that only has to be right to within a few points — the cost of
        // being wrong is one label kept or dropped at the margin.
        func width(_ spec: GraphScene.LabelSpec) -> Float {
            let size = Float(spec.tier.labelPointSize)
            let count = Float(min(spec.text.count, 32))
            return count * size * spec.tier.labelAdvanceRatio
        }
        func height(_ spec: GraphScene.LabelSpec) -> Float {
            Float(spec.tier.labelPointSize) * 1.3
        }

        // Once a label has found its place it keeps it: a name that jumped from
        // under its dot to over it as the camera moved would be worse than one
        // that never appeared.
        var resolvedOffset = [Float?](repeating: nil, count: specs.count)
        var unresolved = Set(specs.indices)

        for ratio in ladder {
            if unresolved.isEmpty { break }
            let bandT = ZoomBand.bandT(forRatio: ratio)
            // A label that fits at fit-to-view is visible *from* fit-to-view, and
            // `bandT` is exactly 0 there — which the shader's
            // `smoothstep(fadeStart, fadeStart + 0.10, bandT)` would read as
            // half-way through its own fade-in. The first rung gates at -1, the
            // same "already visible at overview" the tiers use.
            let gate: Float = ratio == ladder.first ? -1 : bandT
            let scale = fitScale * ratio

            // Node dots at this zoom, in points.
            var nodes = Grid(cell: 64)
            for (documentIndex, tier) in tiers.enumerated() {
                let radii = tier.radiiPt
                let radius = radii.overview + (radii.detail - radii.overview) * bandT
                let p = worldPositions[documentIndex] * scale
                nodes.insert(
                    Rect(
                        minX: p.x - radius, minY: p.y - radius,
                        maxX: p.x + radius, maxY: p.y + radius))
            }

            // Everything already placed occupies its space *before* anything new is
            // considered — including labels that come later in the order. A label
            // that found room at an earlier rung has already been shown to the
            // user, so it outranks one still looking, whatever their tiers.
            var placed = Grid(cell: 64)
            for (index, spec) in specs.enumerated() {
                guard spec.tier.labelFadeStart <= bandT, let offset = resolvedOffset[index]
                else { continue }
                let anchor = worldPositions[spec.documentIndex] * scale
                placed.insert(
                    box(anchor: anchor, width: width(spec), height: height(spec), offset: offset))
            }

            for (index, spec) in specs.enumerated() {
                // A tier that has not started fading in yet is not competing for
                // space at this zoom, and must not block a tier that has.
                guard spec.tier.labelFadeStart <= bandT, resolvedOffset[index] == nil else {
                    continue
                }

                let anchor = worldPositions[spec.documentIndex] * scale
                let w = width(spec)
                let h = height(spec)

                // Preferred: just under the dot. Alternates: one line lower, then
                // above it. The same three the prototype tries.
                let preferred = spec.offsetPt
                let candidates = [preferred, preferred + h + 3, -(preferred + h + 3)]

                var chosen: (offset: Float, rect: Rect)?
                for offset in candidates {
                    let rect = box(anchor: anchor, width: w, height: h, offset: offset)
                    if placed.hits(rect, padding: labelPadding) { continue }
                    if nodes.hits(rect, padding: nodePadding) { continue }
                    chosen = (offset, rect)
                    break
                }
                // A branch name is the map's navigation and is never dropped —
                // §6.1 puts hub labels at overview unconditionally. It takes its
                // last candidate and accepts the overlap.
                if chosen == nil, spec.tier == .branch, let offset = candidates.last {
                    chosen = (offset, box(anchor: anchor, width: w, height: h, offset: offset))
                }
                guard let chosen else { continue }

                placed.insert(chosen.rect)
                resolvedOffset[index] = chosen.offset
                unresolved.remove(index)
                result[index] = Placement(fadeStart: gate, offsetPt: chosen.offset)
            }
        }
        return result
    }
}
