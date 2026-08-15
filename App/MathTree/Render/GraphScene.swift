import GraphCore
import simd

/// The static GPU scene: three instance arrays built once from `GraphDocument`
/// and never rebuilt. Pan, zoom and level-of-detail are a uniform and three
/// instance counts (D3.4).
///
/// World space here is *screen-oriented*: the layout's y is negated at build
/// time so that +y is down everywhere downstream — shaders, picking and label
/// offsets all share one convention.
struct GraphScene {
    /// One label's text and the styling that follows from its tier. Rasterised
    /// by `LabelAtlas`, tier by tier — the overview tier eagerly at load, the
    /// rest lazily per zoom band (D3.5).
    struct LabelSpec {
        var text: String
        var documentIndex: Int
        var tier: LODTier
        var anchor: SIMD2<Float>
        /// Vertical gap from the node centre to the label box. Chosen by
        /// `LabelCull` — the preferred position is under the dot, but a label that
        /// would collide there takes one of two alternates.
        var offsetPt: Float
        /// `bandT` at which this label first has room. `LabelCull.neverFits` for
        /// one the layout has no space for at any zoom.
        var fadeStart: Float
    }

    enum EdgeClass: Int, CaseIterable {
        case contains = 0
        case requires = 1
        case relates = 2

        var name: String {
            switch self {
            case .contains: "contains"
            case .requires: "requires"
            case .relates: "relates"
            }
        }
    }

    let document: GraphDocument

    /// Tier-sorted; index into this array is the GPU instance index.
    private(set) var nodeInstances: [NodeInstance] = []
    /// Instance index → index into `document.nodes`.
    private(set) var documentIndexByInstance: [Int] = []
    /// Index into `document.nodes` → instance index.
    private(set) var instanceIndexByDocument: [Int] = []
    /// Screen-oriented world positions, parallel to `document.nodes`.
    private(set) var worldPositions: [SIMD2<Float>] = []
    private(set) var tierByDocumentIndex: [LODTier] = []
    private(set) var hueByDocumentIndex: [Float] = []

    private(set) var edges: [[EdgeInstance]] = Array(repeating: [], count: EdgeClass.allCases.count)
    /// Document indexes behind each edge instance, parallel to `edges`. Phase 6
    /// needs them: an edge's colour is its endpoints' scores (§6.1), and the
    /// instance itself only carries positions.
    private(set) var edgeEndpoints: [[(from: Int, to: Int)]] = Array(
        repeating: [], count: EdgeClass.allCases.count)
    /// Index into `document.relatesEdges` per `relates` instance — how an edge
    /// finds the FSRS state it carries in its own right (§4.4).
    private(set) var relatesSourceByInstance: [Int] = []
    private(set) var labelSpecs: [LabelSpec] = []

    /// Node instance counts per tier, in tier order — the LOD prefix table.
    private(set) var nodeCountByTier: [Int] = Array(repeating: 0, count: LODTier.allCases.count)
    private(set) var labelCountByTier: [Int] = Array(repeating: 0, count: LODTier.allCases.count)

    private(set) var boundsMin = SIMD2<Float>(0, 0)
    private(set) var boundsMax = SIMD2<Float>(0, 0)
    private(set) var pickGrid = PickGrid.empty

    /// Largest node radius in points, used to pad the fit-to-view margin so hubs
    /// never clip against the window edge.
    private(set) var maxNodeRadiusPt: Float = 0

    /// The appearance the instance buffers were baked with. Only the initial one
    /// matters: `GraphRenderer.setTheme` rewrites every colour word in place when
    /// it changes, so this is the starting state rather than a standing dependency.
    private let theme: Theme

    init(document: GraphDocument, theme: Theme) {
        self.document = document
        self.theme = theme
        buildTaxonomy()
        buildNodes()
        buildEdges()
        buildLabels()
        pickGrid = PickGrid(positions: worldPositions)
    }

    /// The branch hue a node inherits, by id — how the chrome paints a score dot
    /// in the same colour the map does.
    func hue(of id: NodeID) -> Float? {
        document.index(of: id).map { hueByDocumentIndex[$0] }
    }

    // MARK: - Build

    private mutating func buildTaxonomy() {
        let count = document.nodes.count
        worldPositions = document.positions.map { SIMD2($0.x, -$0.y) }
        tierByDocumentIndex = document.nodes.map { LODTier(node: $0) }

        // Branch hue assignment is by sorted branch id, so the map keeps its
        // colours across rebuilds (ground rule 5 — same inputs, same map).
        let branchIDs = document.nodes.filter { $0.kind == .branch }.map(\.id).sorted()
        var hueByBranch: [NodeID: Float] = [:]
        for (index, id) in branchIDs.enumerated() {
            hueByBranch[id] = Palette.hue(forBranchIndex: index)
        }

        hueByDocumentIndex = Array(repeating: Palette.hue(forBranchIndex: 0), count: count)
        for index in 0..<count {
            var cursor = document.nodes[index]
            var guardCount = 0
            while cursor.kind != .branch, let parent = cursor.parent,
                let parentIndex = document.index(of: parent), guardCount < 64
            {
                cursor = document.nodes[parentIndex]
                guardCount += 1
            }
            hueByDocumentIndex[index] = hueByBranch[cursor.id] ?? Palette.hue(forBranchIndex: 0)
        }
    }

    private mutating func buildNodes() {
        let count = document.nodes.count
        // (tier, id) — a total order, so the instance buffer is byte-identical
        // for identical content.
        let order = (0..<count).sorted {
            let (a, b) = (tierByDocumentIndex[$0], tierByDocumentIndex[$1])
            if a != b { return a < b }
            return document.nodes[$0].id < document.nodes[$1].id
        }

        documentIndexByInstance = order
        instanceIndexByDocument = Array(repeating: 0, count: count)
        nodeInstances.reserveCapacity(count)

        for (instance, documentIndex) in order.enumerated() {
            instanceIndexByDocument[documentIndex] = instance
            let tier = tierByDocumentIndex[documentIndex]
            let radii = tier.radiiPt
            nodeCountByTier[tier.rawValue] += 1
            maxNodeRadiusPt = max(maxNodeRadiusPt, radii.overview, radii.detail)
            nodeInstances.append(
                NodeInstance(
                    pos: worldPositions[documentIndex],
                    radii: SIMD2(Float16(radii.overview), Float16(radii.detail)),
                    rgba: Palette.nodeColor(
                        hue: hueByDocumentIndex[documentIndex], tier: tier, theme: theme)))
        }

        if let first = worldPositions.first {
            boundsMin = first
            boundsMax = first
            for position in worldPositions {
                boundsMin = simd_min(boundsMin, position)
                boundsMax = simd_max(boundsMax, position)
            }
        }
    }

    /// An edge before it becomes an instance. `source` is the index into
    /// `document.relatesEdges`, carried through the sort so a `relates` instance
    /// can still find the authored edge whose score it shows.
    private struct EdgePair {
        var from: Int
        var to: Int
        var weightA: Float
        var weightB: Float
        var source: Int = -1
    }

    private mutating func buildEdges() {
        // Sorted by the more prominent endpoint so the reveal ramp lights the
        // taxonomy filaments before the leaf detail (§6.4).
        func append(_ edgeClass: EdgeClass, _ pairs: [EdgePair]) {
            let sorted = pairs.sorted {
                let a = min(
                    tierByDocumentIndex[$0.from].rawValue, tierByDocumentIndex[$0.to].rawValue)
                let b = min(
                    tierByDocumentIndex[$1.from].rawValue, tierByDocumentIndex[$1.to].rawValue)
                if a != b { return a < b }
                return (document.nodes[$0.from].id, document.nodes[$0.to].id)
                    < (document.nodes[$1.from].id, document.nodes[$1.to].id)
            }
            edges[edgeClass.rawValue] = sorted.map { pair in
                EdgeInstance(
                    a: worldPositions[pair.from],
                    b: worldPositions[pair.to],
                    rgbaA: Palette.edgeColor(edgeClass, weight: pair.weightA, theme: theme),
                    rgbaB: Palette.edgeColor(edgeClass, weight: pair.weightB, theme: theme))
            }
            edgeEndpoints[edgeClass.rawValue] = sorted.map { (from: $0.from, to: $0.to) }
            if edgeClass == .relates { relatesSourceByInstance = sorted.map(\.source) }
        }

        var contains: [EdgePair] = []
        for (parent, children) in document.children {
            guard let parentIndex = document.index(of: parent) else { continue }
            for child in children {
                guard let childIndex = document.index(of: child) else { continue }
                // Bright at the hub, fading outward: the filament reads as
                // belonging to the branch, which is what makes galaxies.
                contains.append(
                    EdgePair(from: parentIndex, to: childIndex, weightA: 0.95, weightB: 0.40))
            }
        }
        append(.contains, contains)

        append(
            .requires,
            document.requiresEdges.compactMap { edge in
                guard let from = document.index(of: edge.from), let to = document.index(of: edge.to)
                else { return nil }
                return EdgePair(from: from, to: to, weightA: 0.55, weightB: 1.0)
            })

        append(
            .relates,
            document.relatesEdges.enumerated().compactMap { source, edge in
                guard let a = document.index(of: edge.a), let b = document.index(of: edge.b)
                else { return nil }
                return EdgePair(from: a, to: b, weightA: 0.85, weightB: 0.85, source: source)
            })
    }

    private mutating func buildLabels() {
        let order = documentIndexByInstance  // already tier-sorted
        labelSpecs.reserveCapacity(order.count)
        for documentIndex in order {
            let tier = tierByDocumentIndex[documentIndex]
            labelCountByTier[tier.rawValue] += 1
            let radii = tier.radiiPt
            labelSpecs.append(
                LabelSpec(
                    text: document.nodes[documentIndex].title,
                    documentIndex: documentIndex,
                    tier: tier,
                    anchor: worldPositions[documentIndex],
                    offsetPt: max(radii.overview, radii.detail) + 4.0,
                    fadeStart: tier.labelFadeStart))
        }

        // The design's greedy cull, solved over a ladder of zooms. Without it the
        // map's names pile up wherever the layout clusters, which is exactly where
        // there is most to read.
        let placements = LabelCull.solve(
            specs: labelSpecs, worldPositions: worldPositions, tiers: tierByDocumentIndex,
            fitScale: fitScale(viewportPt: LabelCull.nominalViewportPt))
        for index in labelSpecs.indices {
            labelSpecs[index].offsetPt = placements[index].offsetPt
            // Never earlier than the tier's own gate: culling can only delay a
            // label, never promote one past §6.1's LOD rules.
            labelSpecs[index].fadeStart = max(
                placements[index].fadeStart, labelSpecs[index].tier.labelFadeStart)
        }
    }

    // MARK: - Level of detail

    /// Number of node instances worth drawing at this band. Tier radii are
    /// monotone decreasing in tier order at every band, so "everything at least
    /// this big" really is a prefix. At seed scale nothing is ever culled — the
    /// mechanism exists so that scale (D3.6) is a constant change, not a rewrite.
    func nodePrefix(bandT: Float, backingScale: Float) -> Int {
        var prefix = 0
        for tier in LODTier.allCases {
            let radii = tier.radiiPt
            let radiusPx = (radii.overview + (radii.detail - radii.overview) * bandT) * backingScale
            if radiusPx < 0.75 { break }
            prefix += nodeCountByTier[tier.rawValue]
        }
        return prefix
    }

    /// Labels whose tier has begun to fade in at this band (§6.1's label rules).
    func labelPrefix(bandT: Float) -> Int {
        var prefix = 0
        for tier in LODTier.allCases {
            if tier.labelFadeStart > bandT { break }
            prefix += labelCountByTier[tier.rawValue]
        }
        return prefix
    }

    func visibleLabelTiers(bandT: Float) -> [LODTier] {
        LODTier.allCases.filter { $0.labelFadeStart <= bandT && labelCountByTier[$0.rawValue] > 0 }
    }

    /// The highest tier whose labels are wanted at this band — the tier the atlas
    /// must have rasterised by now.
    func requiredLabelTier(bandT: Float) -> LODTier {
        var required = LODTier.branch
        for tier in LODTier.allCases where tier.labelFadeStart <= bandT { required = tier }
        return required
    }

    /// Edges are never culled by count at this corpus size: D3.6 put the cliff at
    /// ~170k edges, and §7's own estimate tops out near 45k.
    func edgePrefix(_ edgeClass: EdgeClass, bandT: Float) -> Int {
        edges[edgeClass.rawValue].count
    }

    // MARK: - Camera helpers

    var extent: SIMD2<Float> {
        let size = boundsMax - boundsMin
        return SIMD2(max(size.x, 1), max(size.y, 1))
    }

    var center: SIMD2<Float> { (boundsMin + boundsMax) * 0.5 }

    /// A camera anchor that is *derived from the content*, so "mid zoom" and
    /// "detail zoom" mean something definite in a snapshot or a probe without
    /// hard-coding node ids: the busiest subbranch, and the best-connected
    /// content node.
    func anchor(for band: ZoomBand) -> SIMD2<Float> {
        switch band {
        case .overview:
            return center
        case .mid:
            var best: (index: Int, count: Int)?
            for (index, node) in document.nodes.enumerated() where node.kind == .subbranch {
                let count = document.children[node.id]?.count ?? 0
                if best == nil || count > best!.count
                    || (count == best!.count && node.id < document.nodes[best!.index].id)
                {
                    best = (index, count)
                }
            }
            guard let best else { return center }
            var sum = worldPositions[best.index]
            var n: Float = 1
            for child in document.children[document.nodes[best.index].id] ?? [] {
                guard let index = document.index(of: child) else { continue }
                sum += worldPositions[index]
                n += 1
            }
            return sum / n
        case .detail:
            return detailAnchorIndex().map { worldPositions[$0] } ?? center
        }
    }

    /// The best-connected content node — the detail band's camera anchor, and the
    /// goal `--probe` demonstrates focus mode on. Extracted so the probe and the
    /// snapshot camera can never drift onto different nodes.
    func detailAnchorIndex() -> Int? {
        var best: (index: Int, degree: Int)?
        for (index, node) in document.nodes.enumerated() where node.kind.isContent {
            let degree = node.requires.count + document.dependents(of: node.id).count
            if best == nil || degree > best!.degree
                || (degree == best!.degree && node.id < document.nodes[best!.index].id)
            {
                best = (index, degree)
            }
        }
        return best?.index
    }

    /// Points-per-world-unit that frames the whole map with room for hub labels.
    /// Guarded against a degenerate extent so cursor-anchored zoom can never NaN.
    func fitScale(viewportPt: SIMD2<Float>) -> Float {
        let margin = maxNodeRadiusPt * 2.6 + 48
        let usable = SIMD2(
            max(viewportPt.x - margin * 2, 64), max(viewportPt.y - margin * 2, 64))
        let size = extent
        return max(min(usable.x / size.x, usable.y / size.y), 0.0001)
    }
}
