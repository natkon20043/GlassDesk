import AppKit
import Observation
import SwiftUI

/// Classic Pomodoro: 25 min focus, 5 min break, a long 15 min break after every 4th focus.
@MainActor
@Observable
final class FocusTimer {
    enum Mode {
        case focus, shortBreak, longBreak

        var duration: TimeInterval {
            switch self {
            case .focus: 25 * 60
            case .shortBreak: 5 * 60
            case .longBreak: 15 * 60
            }
        }

        var title: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Break"
            case .longBreak: "Long break"
            }
        }

        var colors: [Color] {
            switch self {
            case .focus: [Palette.orange, Palette.rose]
            case .shortBreak: [Palette.lime, Palette.mint]
            case .longBreak: [Palette.sky, Palette.grape]
            }
        }
    }

    static let shared = FocusTimer()
    static let sessionsPerRound = 4

    private(set) var mode: Mode = .focus
    private(set) var remaining: TimeInterval = Mode.focus.duration
    private(set) var isRunning = false
    private(set) var completedFocusSessions = 0

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var timer: Timer?

    var progress: Double { 1 - remaining / mode.duration }

    /// Dots lit in the current round of four.
    var roundProgress: Int {
        let done = completedFocusSessions % Self.sessionsPerRound
        return done == 0 && completedFocusSessions > 0 && mode == .longBreak ? Self.sessionsPerRound : done
    }

    func toggle() { isRunning ? pause() : start() }

    func reset() {
        stop()
        remaining = mode.duration
    }

    func skip() { advance(completed: false) }

    private func start() {
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func pause() {
        tick()
        stop()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        isRunning = false
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining == 0 {
            NSSound(named: "Glass")?.play()
            advance(completed: true)
        }
    }

    private func advance(completed: Bool) {
        stop()
        if mode == .focus {
            if completed { completedFocusSessions += 1 }
            let roundDone = completed && completedFocusSessions % Self.sessionsPerRound == 0
            mode = roundDone ? .longBreak : .shortBreak
        } else {
            mode = .focus
        }
        remaining = mode.duration
    }
}

struct FocusWidget: View {
    private let timer = FocusTimer.shared

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(timer.progress, 0.002))
                    .stroke(
                        AngularGradient(colors: timer.mode.colors, center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: timer.mode.colors.last!.opacity(0.5), radius: 4)
                    .animation(.linear(duration: 0.25), value: timer.progress)

                Text(formatted(timer.remaining))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: Int(timer.remaining.rounded(.up)))
            }
            .padding(5)
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(timer.mode.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    HStack(spacing: 6) {
                        ForEach(0..<FocusTimer.sessionsPerRound, id: \.self) { index in
                            Circle()
                                .fill(index < timer.roundProgress ? AnyShapeStyle(timer.mode.colors.last!) : AnyShapeStyle(.white.opacity(0.18)))
                                .frame(width: 8, height: 8)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button(action: timer.toggle) {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(timer.mode.colors.last!)
                    .help(timer.isRunning ? "Pause" : "Start")

                    Button(action: timer.reset) {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Reset")

                    Button(action: timer.skip) {
                        Image(systemName: "forward.end.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .help("Skip to next")
                }
                .buttonBorderShape(.circle)
                .controlSize(.large)
            }
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
