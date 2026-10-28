import SwiftUI

/// A line+fill sparkline drawn with `Path`, not Swift Charts, so the Overview
/// tiles stay cheap to redraw every tick. Values normalize to their own min/max.
struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        ZStack {
            SparklinePath(values: values, closed: true)
                .fill(LinearGradient(
                    colors: [tint.opacity(0.22), tint.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
            SparklinePath(values: values, closed: false)
                .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}

private struct SparklinePath: Shape {
    let values: [Double]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = points(in: rect.size)
        guard let first = points.first, let last = points.last else { return path }
        if closed {
            path.move(to: CGPoint(x: first.x, y: rect.height))
            for point in points {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: last.x, y: rect.height))
            path.closeSubpath()
        } else {
            path.addLines(points)
        }
        return path
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
}
