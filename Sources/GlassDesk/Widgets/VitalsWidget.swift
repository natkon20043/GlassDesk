import SwiftUI

/// Apple Watch–style activity rings for CPU, memory, disk and battery.
struct VitalsWidget: View {
    private struct Metric: Identifiable {
        let id: String
        let value: Double
        let color: Color
        var detail: String? = nil
    }

    private let stats = SystemStats.shared
    private let ringWidth: CGFloat = 12
    private let ringGap: CGFloat = 3
    private let outerDiameter: CGFloat = 128

    private var metrics: [Metric] {
        var result = [
            Metric(id: "CPU", value: stats.cpu, color: Palette.rose),
            Metric(id: "Memory", value: stats.memory, color: Palette.lime),
            Metric(id: "Disk", value: stats.disk, color: Palette.sky),
        ]
        if let battery = stats.battery {
            result.append(Metric(id: "Battery", value: battery, color: Palette.sun,
                                 detail: stats.charging ? "bolt.fill" : nil))
        }
        return result
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    let diameter = outerDiameter - CGFloat(index) * (ringWidth + ringGap) * 2
                    ActivityRing(progress: metric.value, color: metric.color, lineWidth: ringWidth)
                        .frame(width: diameter, height: diameter)
                }
            }
            .frame(width: outerDiameter, height: outerDiameter)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text(metric.id)
                            if let symbol = metric.detail { Image(systemName: symbol) }
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        Text(metric.value, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(metric.color)
                    }
                }
            }
        }
    }
}

struct ActivityRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        let clamped = min(max(progress, 0.005), 1)
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                // Solid stroke: conic gradients are rasterised on the CPU every animation frame.
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        // Strokes straddle the path; inset so the ring fits inside its frame.
        .padding(lineWidth / 2)
        .animation(.easeInOut(duration: 0.4), value: clamped)
    }
}
