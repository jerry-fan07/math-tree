import Foundation

/// Deterministic offline graph layout (§6.4: "the map always looks the same").
/// Fruchterman–Reingold with Barnes–Hut repulsion and taxonomy gravity, driven
/// by a seeded PRNG so the same content always produces the same coordinates.
///
/// Deliberately decoupled from `GraphCore`: it sees indices and springs, not
/// nodes and edge kinds, which keeps it testable in isolation.

/// SplitMix64. `SystemRandomNumberGenerator` cannot be seeded, and byte-stable
/// output is a Phase 2 exit criterion.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}

public struct Spring: Sendable {
    public var a: Int
    public var b: Int
    public var weight: Double

    public init(a: Int, b: Int, weight: Double) {
        self.a = a
        self.b = b
        self.weight = weight
    }
}

public struct LayoutParameters: Sendable {
    /// Fixed rather than convergence-based: a tolerance test would make the
    /// output depend on floating-point noise.
    public var iterations = 600
    public var seed: UInt64 = 0x5EED_1EAF
    /// Barnes–Hut opening angle. 0 = exact all-pairs, larger = coarser/faster.
    public var theta = 0.9
    /// Pull toward the origin; keeps disconnected components from drifting off.
    public var gravity = 0.02
    /// Pull toward the node's cluster centroid — this is what makes branches
    /// form the visible galaxies of §6.1.
    public var clusterGravity = 0.05
    /// Starting temperature as a fraction of the layout's nominal width.
    public var initialTemperature = 0.12
    /// Coordinates are rounded to this many decimals on the way out, so
    /// last-bit differences can never reach the artifact.
    public var outputDecimals = 4

    public init() {}
}

public struct LayoutResult: Sendable {
    public var x: [Double]
    public var y: [Double]
}

public enum Layout {
    /// - Parameters:
    ///   - count: number of nodes; positions come back in the same index order.
    ///   - springs: attractive edges, already deduplicated by the caller.
    ///   - clusters: cluster index per node (its branch), or nil for none.
    public static func compute(
        count: Int,
        springs: [Spring],
        clusters: [Int?],
        parameters: LayoutParameters = LayoutParameters()
    ) -> LayoutResult {
        precondition(clusters.count == count, "one cluster slot per node")
        guard count > 1 else {
            return LayoutResult(
                x: [Double](repeating: 0, count: count),
                y: [Double](repeating: 0, count: count))
        }

        // FR convention: k = sqrt(area / n) is the ideal edge length.
        let width = 1000.0 * (Double(count) / 100.0).squareRoot()
        let k = width / Double(count).squareRoot()
        let k2 = k * k

        var rng = SplitMix64(seed: parameters.seed)
        var x = [Double](repeating: 0, count: count)
        var y = [Double](repeating: 0, count: count)
        // A jittered golden-angle spiral rather than a uniform random cloud:
        // the cloud needs far more iterations to untangle, and the spiral's
        // even density gives Barnes–Hut a well-shaped tree from step one.
        for i in 0..<count {
            let t = Double(i)
            let angle = t * 2.399_963_229_728_653
            let radius = width * 0.5 * (t / Double(count)).squareRoot()
            x[i] = radius * cos(angle) + (rng.unit() - 0.5) * k * 0.1
            y[i] = radius * sin(angle) + (rng.unit() - 0.5) * k * 0.1
        }

        let clusterCount = clusters.compactMap { $0 }.max().map { $0 + 1 } ?? 0
        var dx = [Double](repeating: 0, count: count)
        var dy = [Double](repeating: 0, count: count)
        var sumX = [Double](repeating: 0, count: max(clusterCount, 1))
        var sumY = [Double](repeating: 0, count: max(clusterCount, 1))
        var clusterSize = [Double](repeating: 0, count: max(clusterCount, 1))
        var tree = QuadTree()

        var temperature = width * parameters.initialTemperature
        let cooling = temperature / Double(parameters.iterations)

        for _ in 0..<parameters.iterations {
            for i in 0..<count {
                dx[i] = 0
                dy[i] = 0
            }

            tree.build(x: x, y: y, count: count)
            tree.accumulateRepulsion(x: x, y: y, count: count, k2: k2, theta: parameters.theta,
                                     dx: &dx, dy: &dy)

            // Attraction along springs: FR's d²/k, scaled by edge weight.
            for spring in springs {
                let ax = x[spring.a] - x[spring.b]
                let ay = y[spring.a] - y[spring.b]
                let distance = max((ax * ax + ay * ay).squareRoot(), 1e-9)
                let force = (distance * distance / k) * spring.weight
                let ux = ax / distance
                let uy = ay / distance
                dx[spring.a] -= ux * force
                dy[spring.a] -= uy * force
                dx[spring.b] += ux * force
                dy[spring.b] += uy * force
            }

            // Cluster centroids, recomputed each step — they move with the graph.
            if clusterCount > 0 && parameters.clusterGravity > 0 {
                for c in 0..<clusterCount {
                    sumX[c] = 0
                    sumY[c] = 0
                    clusterSize[c] = 0
                }
                for i in 0..<count {
                    guard let c = clusters[i] else { continue }
                    sumX[c] += x[i]
                    sumY[c] += y[i]
                    clusterSize[c] += 1
                }
                for i in 0..<count {
                    guard let c = clusters[i], clusterSize[c] > 0 else { continue }
                    dx[i] += (sumX[c] / clusterSize[c] - x[i]) * parameters.clusterGravity * k
                    dy[i] += (sumY[c] / clusterSize[c] - y[i]) * parameters.clusterGravity * k
                }
            }

            if parameters.gravity > 0 {
                for i in 0..<count {
                    dx[i] -= x[i] * parameters.gravity
                    dy[i] -= y[i] * parameters.gravity
                }
            }

            // Displace, capped by the temperature.
            for i in 0..<count {
                let magnitude = (dx[i] * dx[i] + dy[i] * dy[i]).squareRoot()
                guard magnitude > 1e-12 else { continue }
                let step = min(magnitude, temperature)
                x[i] += dx[i] / magnitude * step
                y[i] += dy[i] / magnitude * step
            }
            temperature = max(temperature - cooling, 0)
        }

        return normalize(x: x, y: y, decimals: parameters.outputDecimals)
    }

    /// Center on the centroid and round, so the artifact is stable and the
    /// viewer can treat (0, 0) as the middle of the map.
    private static func normalize(x: [Double], y: [Double], decimals: Int) -> LayoutResult {
        let n = Double(x.count)
        let cx = x.reduce(0, +) / n
        let cy = y.reduce(0, +) / n
        let scale = pow(10.0, Double(decimals))
        return LayoutResult(
            x: x.map { (($0 - cx) * scale).rounded() / scale },
            y: y.map { (($0 - cy) * scale).rounded() / scale }
        )
    }
}

/// Array-backed quadtree. Bodies are inserted in index order, so the tree —
/// and therefore the approximation error — is identical run to run.
private struct QuadTree {
    private struct Cell {
        var centerX = 0.0
        var centerY = 0.0
        var halfSize = 0.0
        var massX = 0.0  // sum of occupant positions
        var massY = 0.0
        var mass = 0.0
        var child0 = -1
        var body = -1  // leaf occupant; -1 when empty or internal
        var isLeaf = true
    }

    /// Coincident bodies would otherwise subdivide forever. At the cap a leaf
    /// keeps accumulating mass without storing further occupants, which treats
    /// the pile as one mass point — the right approximation anyway.
    private static let maxDepth = 48

    private var cells: [Cell] = []
    private var bodyX: [Double] = []
    private var bodyY: [Double] = []
    private var stack: [Int] = []

    mutating func build(x: [Double], y: [Double], count: Int) {
        cells.removeAll(keepingCapacity: true)
        bodyX = x
        bodyY = y

        var minX = x[0], maxX = x[0], minY = y[0], maxY = y[0]
        for i in 1..<count {
            minX = min(minX, x[i]); maxX = max(maxX, x[i])
            minY = min(minY, y[i]); maxY = max(maxY, y[i])
        }
        var root = Cell()
        root.centerX = (minX + maxX) * 0.5
        root.centerY = (minY + maxY) * 0.5
        root.halfSize = max(max(maxX - minX, maxY - minY) * 0.5, 1e-6) * 1.01
        cells.append(root)

        for i in 0..<count { insert(i, into: 0, depth: 0) }
    }

    private mutating func insert(_ body: Int, into cellIndex: Int, depth: Int) {
        var index = cellIndex
        var depth = depth
        while true {
            cells[index].massX += bodyX[body]
            cells[index].massY += bodyY[body]
            cells[index].mass += 1

            if cells[index].isLeaf {
                if cells[index].body == -1 {
                    cells[index].body = body
                    return
                }
                if depth >= Self.maxDepth { return }  // pile-up: mass only
                let tenant = cells[index].body
                cells[index].body = -1
                cells[index].isLeaf = false
                subdivide(index)
                // The tenant's mass is already counted here, so re-seat it from
                // the child level down.
                insert(tenant, into: childIndex(for: tenant, in: index), depth: depth + 1)
            }
            index = childIndex(for: body, in: index)
            depth += 1
        }
    }

    private mutating func subdivide(_ index: Int) {
        let half = cells[index].halfSize * 0.5
        let cx = cells[index].centerX
        let cy = cells[index].centerY
        cells[index].child0 = cells.count
        for quadrant in 0..<4 {
            var cell = Cell()
            cell.halfSize = half
            cell.centerX = cx + (quadrant & 1 == 0 ? -half : half)
            cell.centerY = cy + (quadrant & 2 == 0 ? -half : half)
            cells.append(cell)
        }
    }

    private func childIndex(for body: Int, in index: Int) -> Int {
        let right = bodyX[body] >= cells[index].centerX ? 1 : 0
        let top = bodyY[body] >= cells[index].centerY ? 2 : 0
        return cells[index].child0 + (right | top)
    }

    mutating func accumulateRepulsion(
        x: [Double], y: [Double], count: Int, k2: Double, theta: Double,
        dx: inout [Double], dy: inout [Double]
    ) {
        let thetaSquared = theta * theta
        for i in 0..<count {
            stack.removeAll(keepingCapacity: true)
            stack.append(0)
            var fx = 0.0
            var fy = 0.0
            while let cellIndex = stack.popLast() {
                let cell = cells[cellIndex]
                guard cell.mass > 0 else { continue }
                if cell.isLeaf && cell.body == i && cell.mass == 1 { continue }

                var ax = x[i] - cell.massX / cell.mass
                var ay = y[i] - cell.massY / cell.mass
                var distanceSquared = ax * ax + ay * ay
                let width = cell.halfSize * 2

                if cell.isLeaf || width * width < thetaSquared * distanceSquared {
                    if distanceSquared < 1e-12 {
                        // Coincident: nudge along a fixed axis so the result
                        // stays deterministic.
                        ax = 1e-6
                        ay = 0
                        distanceSquared = 1e-12
                    }
                    let distance = distanceSquared.squareRoot()
                    let force = k2 / distance * cell.mass
                    fx += ax / distance * force
                    fy += ay / distance * force
                } else {
                    stack.append(cell.child0)
                    stack.append(cell.child0 + 1)
                    stack.append(cell.child0 + 2)
                    stack.append(cell.child0 + 3)
                }
            }
            dx[i] += fx
            dy[i] += fy
        }
    }
}
