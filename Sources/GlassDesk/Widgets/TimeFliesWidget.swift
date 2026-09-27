import SwiftUI

/// How much of today, this week, this month and this year is already gone.
struct TimeFliesWidget: View {
    private struct Row: Identifiable {
        let id: String
        let fraction: Double
        let colors: [Color]
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("Time flies")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    Image(systemName: "hourglass")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows(at: context.date)) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(row.id)
                            Spacer()
                            Text(row.fraction, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.12))
                                Capsule()
                                    .fill(LinearGradient(colors: row.colors, startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(8, proxy.size.width * row.fraction))
                                    .shadow(color: row.colors.last!.opacity(0.5), radius: 3)
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
    }

    private func rows(at date: Date) -> [Row] {
        let calendar = Calendar.current
        func fraction(_ component: Calendar.Component) -> Double {
            guard let interval = calendar.dateInterval(of: component, for: date) else { return 0 }
            return date.timeIntervalSince(interval.start) / interval.duration
        }
        return [
            Row(id: "Today", fraction: fraction(.day), colors: [Palette.rose, Palette.orange]),
            Row(id: "This week", fraction: fraction(.weekOfYear), colors: [Palette.orange, Palette.sun]),
            Row(id: date.formatted(.dateTime.month(.wide)), fraction: fraction(.month), colors: [Palette.lime, Palette.mint]),
            Row(id: date.formatted(.dateTime.year()), fraction: fraction(.year), colors: [Palette.sky, Palette.grape]),
        ]
    }
}
