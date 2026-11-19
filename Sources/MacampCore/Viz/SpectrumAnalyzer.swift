import Accelerate
import Foundation

/// Turns a window of audio samples into bar levels.
public final class SpectrumAnalyzer {
    public static let fftSize = 2048
    static let minHz = 50.0
    static let maxHz = 16000.0
    /// Bars read 0 at this level and 1 at full scale.
    static let floorDB: Float = -60
    /// Music carries less energy up high, so higher bands get a gentle boost to keep them visible.
    static let tiltDBPerOctave: Float = 2

    private let log2n = vDSP_Length(11)
    private let setup: FFTSetup
    private var window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]

    public init() {
        let n = Self.fftSize
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        windowed = [Float](repeating: 0, count: n)
        real = [Float](repeating: 0, count: n / 2)
        imag = [Float](repeating: 0, count: n / 2)
        magnitudes = [Float](repeating: 0, count: n / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// `count + 1` frequencies bounding `count` bands, spaced evenly on a log scale.
    public static func bandEdges(count: Int, sampleRate: Double) -> [Double] {
        guard count > 0 else { return [] }
        let top = min(maxHz, sampleRate / 2)
        let low = min(minHz, top / 2)
        let ratio = pow(top / low, 1 / Double(count))
        return (0...count).map { low * pow(ratio, Double($0)) }
    }

    /// Levels from 0 to 1, one per band. Uses the first `fftSize` samples and pads with silence if there are fewer.
    public func bands(samples: UnsafeBufferPointer<Float>, sampleRate: Double, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard sampleRate > 0, sampleRate.isFinite else { return [Float](repeating: 0, count: count) }
        let n = Self.fftSize, half = n / 2
        let available = min(n, samples.count)
        for i in 0..<n {
            let s = i < available ? samples[i] : 0
            windowed[i] = (s.isFinite ? s : 0) * window[i]
        }
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        // A full-scale sine reads n/2 here: the transform doubles it and the Hann window halves it.
        let fullScale = Float(n) / 2
        let binHz = sampleRate / Double(n)
        let edges = Self.bandEdges(count: count, sampleRate: sampleRate)
        var out = [Float](repeating: 0, count: count)
        for band in 0..<count {
            let lo = edges[band] / binHz, hi = edges[band + 1] / binHz
            var magnitude: Float
            if hi - lo < 1 {
                // Narrower than one bin: read between the two nearest bins instead of repeating one.
                let center = (lo + hi) / 2
                let a = min(half - 1, max(1, Int(center.rounded(.down))))
                let b = min(half - 1, a + 1)
                let t = Float(center - Double(a))
                magnitude = magnitudes[a] * (1 - t) + magnitudes[b] * t
            } else {
                let first = min(half - 1, max(1, Int(lo.rounded())))
                let last = min(half - 1, max(first, Int(hi.rounded()) - 1))
                magnitude = magnitudes[first...last].max() ?? 0
            }
            guard magnitude > 0 else { continue }
            let center = Float((edges[band] * edges[band + 1]).squareRoot())
            let db = 20 * log10(magnitude / fullScale) + Self.tiltDBPerOctave * log2(center / 1000)
            out[band] = min(1, max(0, (db - Self.floorDB) / -Self.floorDB))
        }
        return out
    }
}
