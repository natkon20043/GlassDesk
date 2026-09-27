import Accelerate
import Foundation

/// Turns blocks of microphone samples into loudness plus log-spaced frequency bands, the way
/// a music visualiser does. Runs on the audio thread, so it allocates everything up front.
final class SpectrumAnalyzer {
    static let size = 1024
    let bandCount: Int

    private let log2n = vDSP_Length(10)
    private let setup: FFTSetup
    private var window = [Float](repeating: 0, count: SpectrumAnalyzer.size)
    private var windowed = [Float](repeating: 0, count: SpectrumAnalyzer.size)
    private var real = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
    private var imaginary = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
    private var power = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)

    /// Band levels are mapped from this dB range onto 0…1. Calibrated so ordinary speech at
    /// arm's length fills roughly half the height and a clap nearly tops out.
    private let floorDB: Float = -95
    private let ceilingDB: Float = -35

    init(bandCount: Int) {
        self.bandCount = bandCount
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.size), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// - Returns: RMS level in dBFS and `bandCount` band levels in 0…1, or nil if the block
    ///   is too short.
    func analyze(_ samples: UnsafePointer<Float>, count: Int, sampleRate: Double) -> (dbfs: Float, bands: [Float])? {
        let n = Self.size
        guard count >= n else { return nil }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(n))
        let dbfs = 20 * log10(max(rms, 1e-7))

        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(n))
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
            }
        }
        // zrip output is scaled by 2 and grows with n; normalise so levels don't depend on size.
        var scale = 1 / Float(n * n)
        vDSP_vsmul(power, 1, &scale, &power, 1, vDSP_Length(n / 2))

        // Log-spaced bands from 60 Hz up to 14 kHz (or Nyquist), like the ear hears them.
        let binWidth = sampleRate / Double(n)
        let low = 60.0, high = min(14_000, sampleRate / 2)
        var bands = [Float](repeating: 0, count: bandCount)
        for band in 0..<bandCount {
            let from = low * pow(high / low, Double(band) / Double(bandCount))
            let to = low * pow(high / low, Double(band + 1) / Double(bandCount))
            let first = max(1, Int(from / binWidth))
            let last = min(n / 2 - 1, max(first, Int(to / binWidth)))
            var sum: Float = 0
            for bin in first...last { sum += power[bin] }
            let db = 10 * log10(max(sum / Float(last - first + 1), 1e-15))
            bands[band] = min(max((db - floorDB) / (ceilingDB - floorDB), 0), 1)
        }
        return (dbfs, bands)
    }
}
