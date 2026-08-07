import simd

/// CPU uniform grid in CSR form, built by a counting sort — the hit-testing
/// structure D3.3 settled on (47 ns mean, 125 ns worst case at 10k, against a
/// 1 ms budget). A quadtree was measured and rejected as over-engineering.
struct PickGrid {
    private let minCorner: SIMD2<Float>
    private let cell: Float
    private let cols: Int
    private let rows: Int
    /// `cols * rows + 1` offsets into `items`.
    private let starts: [Int32]
    private let items: [Int32]
    private let positions: [SIMD2<Float>]

    static let empty = PickGrid(positions: [])

    init(positions: [SIMD2<Float>]) {
        self.positions = positions
        guard let first = positions.first else {
            minCorner = .zero
            cell = 1
            cols = 1
            rows = 1
            starts = [0, 0]
            items = []
            return
        }

        var low = first
        var high = first
        for position in positions {
            low = simd_min(low, position)
            high = simd_max(high, position)
        }
        let size = SIMD2(max(high.x - low.x, 1), max(high.y - low.y, 1))

        // Fruchterman–Reingold's ideal edge length, k = sqrt(area / n) — the same
        // quantity the offline layout spaces nodes by, which is what makes one
        // cell hold O(1) candidates.
        let ideal = (size.x * size.y / Float(max(positions.count, 1))).squareRoot()
        cell = max(ideal, 1e-3)
        minCorner = low
        cols = max(Int((size.x / cell).rounded(.up)), 1)
        rows = max(Int((size.y / cell).rounded(.up)), 1)

        let cellCount = cols * rows
        var counts = [Int32](repeating: 0, count: cellCount + 1)
        var cellOf = [Int32](repeating: 0, count: positions.count)
        for (index, position) in positions.enumerated() {
            let cx = min(max(Int((position.x - low.x) / cell), 0), cols - 1)
            let cy = min(max(Int((position.y - low.y) / cell), 0), rows - 1)
            let id = Int32(cy * cols + cx)
            cellOf[index] = id
            counts[Int(id) + 1] += 1
        }
        for index in 1...cellCount { counts[index] += counts[index - 1] }

        var cursor = counts
        var sorted = [Int32](repeating: 0, count: positions.count)
        for (index, id) in cellOf.enumerated() {
            sorted[Int(cursor[Int(id)])] = Int32(index)
            cursor[Int(id)] += 1
        }
        starts = counts
        items = sorted
    }

    /// Index of the nearest node within `radius` world units, or nil.
    func nearest(to point: SIMD2<Float>, within radius: Float) -> Int? {
        guard !positions.isEmpty, radius > 0 else { return nil }
        let span = Int((radius / cell).rounded(.up))
        let cx = Int((point.x - minCorner.x) / cell)
        let cy = Int((point.y - minCorner.y) / cell)

        var best: Int?
        var bestDistance = radius * radius
        for y in (cy - span)...(cy + span) {
            guard y >= 0, y < rows else { continue }
            for x in (cx - span)...(cx + span) {
                guard x >= 0, x < cols else { continue }
                let id = y * cols + x
                for slot in Int(starts[id])..<Int(starts[id + 1]) {
                    let index = Int(items[slot])
                    let delta = positions[index] - point
                    let distance = simd_length_squared(delta)
                    if distance < bestDistance {
                        bestDistance = distance
                        best = index
                    }
                }
            }
        }
        return best
    }
}
