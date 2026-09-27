import AppKit
import SwiftUI

/// Big friendly clock with a time-of-day greeting and a bar that fills over each hour.
/// Redraws once a minute: every redraw makes WindowServer re-blur the glass behind it.
struct ClockWidget: View {
    private let firstName = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    private let uses12Hour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false

    var body: some View {
        TimelineView(.everyMinute) { context in
            let date = context.date
            let time = date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
            let minute = Calendar.current.component(.minute, from: date)

            VStack(alignment: .leading, spacing: 4) {
                Text(greeting(for: date))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(time)
                        .font(.system(size: 66, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if uses12Hour {
                        Text(date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))).filter(\.isLetter))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(.snappy, value: time)

                Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 15, weight: .medium, design: .rounded))

                HourBar(fraction: Double(minute) / 60)
                    .padding(.top, 8)
            }
        }
    }

    private func greeting(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Up late"
        }
        return firstName.isEmpty ? part : "\(part), \(firstName)"
    }
}

private struct HourBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [Palette.sky, Palette.grape, Palette.rose],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(5, proxy.size.width * fraction))
                    .animation(fraction == 0 ? nil : .easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 5)
    }
}

/// Shared accent colours for the widgets.
enum Palette {
    static let rose = Color(red: 1.00, green: 0.22, blue: 0.45)
    static let lime = Color(red: 0.62, green: 1.00, blue: 0.22)
    static let sky = Color(red: 0.20, green: 0.82, blue: 1.00)
    static let sun = Color(red: 1.00, green: 0.80, blue: 0.20)
    static let orange = Color(red: 1.00, green: 0.55, blue: 0.20)
    static let grape = Color(red: 0.62, green: 0.42, blue: 1.00)
    static let mint = Color(red: 0.25, green: 0.92, blue: 0.70)
}
