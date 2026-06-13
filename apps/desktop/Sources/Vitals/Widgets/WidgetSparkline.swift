import SwiftUI

/// A lightweight line+fill sparkline drawn with `Path` — deliberately *not*
/// Swift Charts. These widgets are always on screen, so the chart must be
/// cheap to render every tick. Values are normalized to their own min/max.
struct WidgetSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let points = points(in: geo.size)
            ZStack {
                if points.count >= 2 {
                    fillPath(points, in: geo.size)
                        .fill(LinearGradient(
                            colors: [tint.opacity(0.22), tint.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    linePath(points)
                        .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = hi - lo
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            // Flat series sits on the baseline rather than jumping mid-height.
            let t = span > 0 ? (value - lo) / span : 0
            let y = size.height - CGFloat(t) * size.height
            return CGPoint(x: CGFloat(index) * stepX, y: y)
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    private func fillPath(_ points: [CGPoint], in size: CGSize) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: size.height))
        path.addLine(to: first)
        path.addLines(points)
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.closeSubpath()
        return path
    }
}
