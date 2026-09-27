import AppKit
import AVFoundation
import Observation
import SwiftUI

/// Listens to the microphone and publishes loudness plus frequency bands for the Sound widget.
/// The mic only runs while the widget is on screen and not paused (macOS shows its orange
/// mic dot whenever it is on).
@MainActor
@Observable
final class SoundMeter {
    enum Access { case unknown, granted, denied, noMicrophone }

    static let shared = SoundMeter()
    static let bandCount = 28

    /// Not observed: the bars are pushed straight into their layers through `onBands`, so
    /// 15 fps of movement never makes SwiftUI rebuild (and WindowServer re-blur) the card.
    @ObservationIgnored private(set) var bands = [Float](repeating: 0, count: SoundMeter.bandCount)
    @ObservationIgnored var onBands: (([Float]) -> Void)?
    /// Observed, but only refreshed a few times a second for the text and level meter.
    private(set) var dbfs: Float = -90
    private(set) var isListening = false
    private(set) var access: Access

    /// The user's pause button.
    var isPaused = UserDefaults.standard.bool(forKey: "soundPaused") {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: "soundPaused")
            updateEngine()
        }
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var stopWork: DispatchWorkItem?
    @ObservationIgnored private var lastLevelUpdate = Date.distantPast

    private init() {
        access = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }

    /// Called as the widget's window becomes visible or gets covered. Stopping is delayed a
    /// little so briefly flicking a window over the desktop doesn't bounce the mic on and off.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        stopWork?.cancel()
        if visible {
            updateEngine()
        } else {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.updateEngine() }
            }
            stopWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
    }

    func requestAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let meter = SoundMeter.shared
                    meter.access = granted ? .granted : .denied
                    meter.updateEngine()
                }
            }
        }
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    private func updateEngine() {
        let shouldListen = isVisible && !isPaused
        if shouldListen, access == .unknown {
            requestAccess()
            return
        }
        if shouldListen, access == .granted, !isListening {
            start()
        } else if !shouldListen, isListening {
            stop()
        }
    }

    private func start() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            access = .noMicrophone
            return
        }
        let analyzer = SpectrumAnalyzer(bandCount: Self.bandCount)
        let sampleRate = format.sampleRate
        var lastPublish = Date.distantPast
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(SpectrumAnalyzer.size), format: format) { buffer, _ in
            // Audio thread: analyse every block, but hand the UI at most 15 frames a second.
            guard let samples = buffer.floatChannelData?[0],
                  let result = analyzer.analyze(samples, count: Int(buffer.frameLength), sampleRate: sampleRate) else { return }
            let now = Date()
            guard now.timeIntervalSince(lastPublish) >= 1.0 / 15 else { return }
            lastPublish = now
            DispatchQueue.main.async {
                MainActor.assumeIsolated { SoundMeter.shared.publish(result.dbfs, result.bands) }
            }
        }
        do {
            try engine.start()
            isListening = true
        } catch {
            input.removeTap(onBus: 0)
            NSLog("GlassDesk: could not start microphone: \(error)")
        }
    }

    private func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isListening = false
        bands = [Float](repeating: 0, count: Self.bandCount)
        onBands?(bands)
        dbfs = -90
    }

    private func publish(_ level: Float, _ fresh: [Float]) {
        guard isListening else { return }
        // Bars jump up instantly and fall back gently, like a VU meter.
        var next = bands
        for index in next.indices {
            next[index] = max(fresh[index], next[index] * 0.82)
            if next[index] < 0.01 { next[index] = 0 }
        }
        // Skip redraws while the room is silent.
        if next != bands {
            bands = next
            onBands?(next)
        }
        let now = Date()
        if now.timeIntervalSince(lastLevelUpdate) >= 0.25 {
            lastLevelUpdate = now
            let rounded = level.rounded()
            if rounded != dbfs { dbfs = rounded }
        }
    }
}

/// A live visualiser: mirrored frequency bars, a loudness meter and a word for the vibe.
struct SoundWidget: View {
    private let meter = SoundMeter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(Palette.mint)
                Text("Sound")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text(meter.isListening ? mood : "Paused")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                if meter.access == .granted || meter.access == .unknown {
                    Button {
                        meter.isPaused.toggle()
                    } label: {
                        Image(systemName: meter.isPaused ? "mic.slash.fill" : "mic.fill")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help(meter.isPaused ? "Start listening" : "Stop listening")
                }
            }

            switch meter.access {
            case .denied:
                message("Microphone access is off", button: "Open Privacy Settings", action: SoundMeter.openPrivacySettings)
            case .noMicrophone:
                message("No microphone found", button: nil, action: {})
            case .granted, .unknown:
                SpectrumBars()
                    .frame(height: 84)
                LevelMeter(dbfs: meter.dbfs)
            }
        }
    }

    private var mood: String {
        switch meter.dbfs {
        case ..<(-55): "Silent"
        case ..<(-42): "Quiet"
        case ..<(-30): "Chatty"
        case ..<(-18): "Loud"
        default: "Very loud!"
        }
    }

    private func message(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            if let button {
                Button(button, action: action).buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }
}

/// Bars mirrored about a centre line, coloured from mint (soft) through gold to rose (loud).
/// Plain Core Animation layers updated in place, bypassing SwiftUI for the per-frame work.
private struct SpectrumBars: NSViewRepresentable {
    func makeNSView(context: Context) -> SpectrumBarsView {
        let view = SpectrumBarsView(count: SoundMeter.bandCount)
        SoundMeter.shared.onBands = { [weak view] in view?.show($0) }
        return view
    }

    func updateNSView(_ nsView: SpectrumBarsView, context: Context) {}
}

final class SpectrumBarsView: NSView {
    private var bars: [CALayer] = []
    private var levels: [Float]
    /// Pre-mixed colours so a frame never converts colour spaces.
    private static let colors: [CGColor] = (0...32).map { step in
        let t = Double(step) / 32
        let (from, to, local) = t < 0.5 ? (Palette.mint, Palette.sun, t * 2) : (Palette.sun, Palette.rose, (t - 0.5) * 2)
        let a = NSColor(from).usingColorSpace(.sRGB)!, b = NSColor(to).usingColorSpace(.sRGB)!
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * local,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * local,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * local,
                       alpha: 1).cgColor
    }

    init(count: Int) {
        levels = [Float](repeating: 0, count: count)
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        for _ in 0..<count {
            let bar = CALayer()
            bar.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull(), "cornerRadius": NSNull()]
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }  // let drags move the widget

    override func layout() {
        super.layout()
        show(levels)
    }

    func show(_ newLevels: [Float]) {
        levels = newLevels
        let gap: CGFloat = 3
        let count = CGFloat(bars.count)
        let width = (bounds.width - gap * (count - 1)) / count
        guard width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let level = CGFloat(index < levels.count ? levels[index] : 0)
            let height = max(3, level * bounds.height)
            bar.frame = CGRect(x: CGFloat(index) * (width + gap), y: (bounds.height - height) / 2, width: width, height: height)
            bar.cornerRadius = width / 2
            bar.backgroundColor = Self.colors[Int((level * 32).rounded())]
        }
        CATransaction.commit()
    }
}

private struct LevelMeter: View {
    let dbfs: Float

    var body: some View {
        // -60 dBFS (near silence) … 0 dBFS (digital full scale).
        let fraction = CGFloat(min(max((dbfs + 60) / 60, 0), 1))
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.mint, Palette.sun, Palette.rose],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, proxy.size.width * fraction))
                }
            }
            .frame(height: 6)
            Text("\(Int(dbfs)) dB")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
    }
}
