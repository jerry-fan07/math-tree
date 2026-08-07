import Foundation
import GraphCore
import SwiftUI

/// The node's retrievability over time (§4.1 decays it; §4.2's reviews step it
/// back up), drawn small enough to sit inside the panel.
///
/// The curve is stroked with the §4.5 ramp itself — the line is literally the
/// colour the node wore on the map at that moment — so the history and the map
/// cannot say different things. Review instants are marked, with implicit reviews
/// (§4.3 propagation) hollow, so a boost is visibly not a retrieval the user did.
///
/// One `Canvas` rather than a `ZStack` of shapes: positioned subviews inside a
/// `GeometryReader` claimed layout space beyond the frame, which left a visible
/// gap under the chart, and drawing edge markers as subviews clipped them at the
/// bounds. A canvas has neither problem and costs one draw.
struct ScoreSparkline: View {
    let history: [ScoreFold.ReviewPoint]
    let fsrs: FSRS
    let now: Date
    /// τ — the line above which a prerequisite counts as mastered (§4.5).
    let threshold: Double

    /// Enough to look continuous at panel width; the cost is one `pow` each.
    private let sampleCount = 72
    private let height: CGFloat = 40
    /// Keeps a marker at either end, and a curve pinned at 1.0, off the edge.
    private let inset: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(
                x: inset, y: inset,
                width: max(size.width - inset * 2, 1), height: max(size.height - inset * 2, 1))
            draw(in: &context, plot: plot)
        }
        .frame(height: height)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Geometry

    private var start: Date { history.first?.event.at ?? now }

    private var span: TimeInterval { max(now.timeIntervalSince(start), 1) }

    private func point(_ date: Date, _ retrievability: Double, in plot: CGRect) -> CGPoint {
        // The axis is a fixed 0…1 rather than fitted to the data: a node's history
        // has to be comparable with the next node's, and an auto-scaled axis would
        // make a 2 % dip look like a collapse.
        CGPoint(
            x: plot.minX + CGFloat(date.timeIntervalSince(start) / span) * plot.width,
            y: plot.minY + (1 - CGFloat(min(max(retrievability, 0), 1))) * plot.height)
    }

    /// Retrievability sampled on a uniform time grid. The state in force at a
    /// sample is the last review at or before it — a step function of state, a
    /// continuous function of time, which is exactly §4.1's model.
    private func samples() -> [(date: Date, value: Double)] {
        guard !history.isEmpty else { return [] }
        var result: [(Date, Double)] = []
        result.reserveCapacity(sampleCount + 1)
        var cursor = 0
        for step in 0...sampleCount {
            let date = start.addingTimeInterval(span * Double(step) / Double(sampleCount))
            while cursor + 1 < history.count, history[cursor + 1].event.at <= date { cursor += 1 }
            let state = history[cursor].state
            // Before the first review there is no state at all; the curve starts
            // where the evidence does.
            guard state.lastReview <= date else { continue }
            result.append((date, fsrs.retrievability(of: state, at: date)))
        }
        return result
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, plot: CGRect) {
        var line = Path()
        let level = point(start, threshold, in: plot).y
        line.move(to: CGPoint(x: plot.minX, y: level))
        line.addLine(to: CGPoint(x: plot.maxX, y: level))
        context.stroke(
            line, with: .color(PanelTheme.tertiaryText.opacity(0.30)),
            style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

        let samples = samples()
        guard samples.count > 1 else { return }

        var curve = Path()
        for (index, sample) in samples.enumerated() {
            let position = point(sample.date, sample.value, in: plot)
            if index == 0 { curve.move(to: position) } else { curve.addLine(to: position) }
        }
        let stops = samples.enumerated().map { index, sample in
            Gradient.Stop(
                color: Color(ScoreRamp.color(forRetrievability: sample.value)),
                location: Double(index) / Double(samples.count - 1))
        }
        context.stroke(
            curve,
            with: .linearGradient(
                Gradient(stops: stops),
                startPoint: CGPoint(x: plot.minX, y: plot.midY),
                endPoint: CGPoint(x: plot.maxX, y: plot.midY)),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

        for review in history {
            let centre = point(
                review.event.at,
                fsrs.retrievability(of: review.state, at: review.event.at), in: plot)
            let dot = Path(
                ellipseIn: CGRect(x: centre.x - 2.5, y: centre.y - 2.5, width: 5, height: 5))
            let colour = Color(ScoreRamp.color(forRetrievability: 1))
            if review.event.source == .implicit {
                // Hollow: a prerequisite exercised in passing (§4.3), not a
                // retrieval the user performed.
                context.stroke(dot, with: .color(colour.opacity(0.75)), lineWidth: 1.2)
            } else {
                context.fill(dot, with: .color(colour))
            }
        }
    }

    private var accessibilityDescription: String {
        guard let last = history.last else { return "No review history" }
        let current = fsrs.retrievability(of: last.state, at: now)
        return "Retrievability history, \(history.count) events, now \(ScoreFormat.percent(current))"
    }
}
