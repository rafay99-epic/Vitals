import SwiftUI
import Charts

protocol TimeSeriesSample: Identifiable {
    var time: Date { get }
}

extension VitalsModel.Sample: TimeSeriesSample {}
extension HistorySample: TimeSeriesSample {}

struct ChartSeries<Sample> {
    let name: String
    let color: Color
    var area: Double?
    var lineWidth: CGFloat?
    let value: (Sample) -> Double?
}

struct MetricChart<Sample: TimeSeriesSample, Tooltip: View>: View {
    let samples: [Sample]
    let series: [ChartSeries<Sample>]
    let yLabel: String
    var yDomain: ClosedRange<Double>?
    var legend: [String]?
    var tooltip: ((Sample) -> Tooltip)?

    init(
        samples: [Sample],
        series: [ChartSeries<Sample>],
        yLabel: String,
        yDomain: ClosedRange<Double>? = nil,
        legend: [String]? = nil,
        @ViewBuilder tooltip: @escaping (Sample) -> Tooltip
    ) {
        self.samples = samples
        self.series = series
        self.yLabel = yLabel
        self.yDomain = yDomain
        self.legend = legend
        self.tooltip = tooltip
    }

    var body: some View {
        if let tooltip {
            scaled.chartHover(samples: samples, tooltip: tooltip)
        } else {
            scaled
        }
    }

    @ViewBuilder
    private var scaled: some View {
        if let yDomain {
            styled.chartYScale(domain: yDomain)
        } else {
            styled
        }
    }

    private var styled: some View {
        Chart { marks }
            // Scope the legend/colors to this chart's series only. A global scale
            // would list every series (Memory/Swap) even on the Temp view.
            .chartForegroundStyleScale(domain: legend ?? [], range: legendColors)
            .chartLegend(legend == nil ? .hidden : .visible)
            .chartYAxisLabel(yLabel)
    }

    private var legendColors: [Color] {
        (legend ?? []).compactMap { name in series.first { $0.name == name }?.color }
    }

    @ChartContentBuilder
    private var marks: some ChartContent {
        ForEach(samples) { sample in
            ForEach(series.indices, id: \.self) { index in
                if let value = series[index].value(sample) {
                    mark(series[index], at: sample.time, value)
                }
            }
        }
    }

    @ChartContentBuilder
    private func mark(_ line: ChartSeries<Sample>, at time: Date, _ value: Double) -> some ChartContent {
        if let area = line.area {
            AreaMark(x: .value("Time", time), y: .value(yLabel, value), series: .value("Series", line.name))
                .foregroundStyle(LinearGradient(colors: [line.color.opacity(area), line.color.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
        }
        let mark = LineMark(x: .value("Time", time), y: .value(yLabel, value), series: .value("Series", line.name))
            .interpolationMethod(.catmullRom)
        if let width = line.lineWidth {
            colored(mark, line).lineStyle(StrokeStyle(lineWidth: width))
        } else {
            colored(mark, line)
        }
    }

    @ChartContentBuilder
    private func colored(_ mark: some ChartContent, _ line: ChartSeries<Sample>) -> some ChartContent {
        if legend == nil {
            mark.foregroundStyle(line.color)
        } else {
            mark.foregroundStyle(by: .value("Series", line.name))
        }
    }
}

extension MetricChart where Tooltip == EmptyView {
    init(
        samples: [Sample],
        series: [ChartSeries<Sample>],
        yLabel: String,
        yDomain: ClosedRange<Double>? = nil,
        legend: [String]? = nil
    ) {
        self.samples = samples
        self.series = series
        self.yLabel = yLabel
        self.yDomain = yDomain
        self.legend = legend
        self.tooltip = nil
    }
}

extension Array where Element: TimeSeriesSample {
    func bounds(of series: [ChartSeries<Element>]) -> ClosedRange<Double>? {
        var lower = Double.infinity
        var upper = -Double.infinity
        for sample in self {
            for line in series {
                guard let value = line.value(sample) else { continue }
                lower = Swift.min(lower, value)
                upper = Swift.max(upper, value)
            }
        }
        return lower <= upper ? lower...upper : nil
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    let symbol: String
    var height: CGFloat = 150
    var note: String?
    var legend: [LegendSwatch] = []
    @ViewBuilder let chart: () -> Content

    var body: some View {
        SectionCard(title: title, symbol: symbol) {
            VStack(alignment: .leading, spacing: note == nil ? 10 : 8) {
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Deferred(content: chart).frame(height: height)
                if !legend.isEmpty {
                    HStack(spacing: 16) {
                        ForEach(legend, id: \.label) { $0 }
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Chart hover support

/// Draws the hover rule and tooltip in the chart's overlay. The hover state
/// lives in the overlay, so moving the cursor never rebuilds the chart's marks.
extension View {
    func chartHover<Sample: TimeSeriesSample, Rows: View>(
        samples: [Sample],
        @ViewBuilder tooltip: @escaping (Sample) -> Rows
    ) -> some View {
        chartOverlay { proxy in
            ChartHoverLayer(proxy: proxy, samples: samples, tooltip: tooltip)
        }
    }
}

private struct ChartHoverLayer<Sample: TimeSeriesSample, Rows: View>: View {
    let proxy: ChartProxy
    let samples: [Sample]
    let tooltip: (Sample) -> Rows
    @State private var hoverTime: Date?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            hoverTime = proxy.value(atX: location.x - geometry[plotFrame].origin.x)
                        case .ended:
                            hoverTime = nil
                        }
                    }
                if let plotFrame = proxy.plotFrame,
                   let sample = samples.nearest(to: hoverTime),
                   let x = proxy.position(forX: sample.time) {
                    let frame = geometry[plotFrame]
                    Rectangle()
                        .fill(.secondary.opacity(0.5))
                        .frame(width: 1, height: frame.height)
                        .position(x: frame.minX + x, y: frame.midY)
                        .allowsHitTesting(false)
                    HoverTooltip(time: sample.time) { tooltip(sample) }
                        .fixedSize()
                        .position(x: min(max(frame.minX + x, frame.minX + 70), frame.maxX - 70), y: frame.minY + 24)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

struct HoverTooltip<Rows: View>: View {
    let time: Date
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(time, format: .dateTime.hour().minute().second())
                .foregroundStyle(.secondary)
            rows
        }
        .font(.caption2)
        .monospacedDigit()
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

extension Array where Element: TimeSeriesSample {
    /// Closest sample to `time` by binary search (samples are in ascending time
    /// order). Runs on every hover move over a chart.
    func nearest(to time: Date?) -> Element? {
        guard let time, !isEmpty else { return nil }
        var lo = 0, hi = count - 1
        if time <= self[lo].time { return self[lo] }
        if time >= self[hi].time { return self[hi] }
        while lo < hi {
            let mid = (lo + hi) / 2
            if self[mid].time < time { lo = mid + 1 } else { hi = mid }
        }
        // `lo` is the first index whose time >= target; nearest is it or the one before.
        guard lo > 0 else { return self[lo] }
        let after = self[lo], before = self[lo - 1]
        return abs(before.time.timeIntervalSince(time)) <= abs(after.time.timeIntervalSince(time)) ? before : after
    }
}
