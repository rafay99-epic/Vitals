import Foundation

/// Pure helpers for shaping history before it reaches a chart. Lives in
/// VitalsCore so it can be unit-tested without GTK on any platform.
public enum ChartMath {

    /// Evenly thins `samples` to at most `maxCount` points, always keeping the
    /// first and the newest. The stride steps by more than one whenever thinning
    /// happens, so no sample repeats. Charts can't show more points than pixels,
    /// and a Cairo redraw scales with the point count — so the dashboard draws
    /// from this, not the full history.
    public static func downsample<T>(_ samples: [T], to maxCount: Int) -> [T] {
        guard samples.count > maxCount, maxCount > 1 else { return samples }
        let stride = Double(samples.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { samples[Int((Double($0) * stride).rounded())] }
    }
}
