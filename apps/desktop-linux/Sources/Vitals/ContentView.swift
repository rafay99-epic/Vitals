import Adwaita
import Foundation
import VitalsCore

/// Phase 0 scaffold + charts spike.
///
/// This window exists to prove the toolchain end to end before the real
/// dashboard is built: that an Adwaita app launches, and that a Cairo-rendered
/// PNG sparkline displays inside Adwaita's `Picture`. The synthetic series is
/// clearly labelled as a placeholder — once Phase 2 lands, real history feeds
/// this exact rendering path.
struct ContentView: View {

    /// Vitals green (#34D85F), matching the macOS app and the website tokens.
    private static let accent = SparklineRenderer.Color(0.204, 0.847, 0.373)

    // Built imperatively with typed sub-expressions — the one-line literal form
    // trips Swift's expression type-checker (it times out on the mixed Int/Double
    // arithmetic). Purely a placeholder waveform, replaced by real history later.
    private static let placeholderSeries: [Double] = {
        var series: [Double] = []
        series.reserveCapacity(300)
        for i in 0..<300 {
            let x = Double(i)
            let slow: Double = sin(x / 13)
            let fast: Double = sin(x / 3)
            series.append(50 + 18 * slow + 7 * fast)
        }
        return series
    }()

    private var sparkline: Data {
        SparklineRenderer.render(
            values: ChartMath.downsample(Self.placeholderSeries, to: 160),
            width: 360,
            height: 90,
            line: Self.accent
        )
    }

    var view: Body {
        VStack {
            Text(BuildInfo.displayName)
                .title1()
                .padding()
            Text("Linux hardware monitor · scaffold \(BuildInfo.version)")
                .padding()
            Picture()
                .data(sparkline)
                .padding()
            Text("Placeholder series — not a real reading")
                .padding()
        }
        .padding()
    }
}
