import Foundation
import Testing
@testable import MacampCore

private func sine(_ hz: Double, rate: Double = 44100, amplitude: Float = 1) -> [Float] {
    (0..<SpectrumAnalyzer.fftSize).map { amplitude * Float(sin(2 * Double.pi * hz * Double($0) / rate)) }
}

private func bands(_ samples: [Float], count: Int = 19, rate: Double = 44100) -> [Float] {
    samples.withUnsafeBufferPointer { SpectrumAnalyzer().bands(samples: $0, sampleRate: rate, count: count) }
}

private func bandIndex(containing hz: Double, count: Int = 19) -> Int {
    let edges = SpectrumAnalyzer.bandEdges(count: count, sampleRate: 44100)
    return edges.indices.dropLast().first { hz >= edges[$0] && hz < edges[$0 + 1] }!
}

@Test func silenceGivesAllZeros() {
    let out = bands([Float](repeating: 0, count: SpectrumAnalyzer.fftSize))
    #expect(out.count == 19)
    #expect(out.allSatisfy { $0 == 0 })
}

@Test func bandEdgesAreLogSpacedFromFiftyHertzToSixteenKilohertz() {
    let edges = SpectrumAnalyzer.bandEdges(count: 19, sampleRate: 44100)
    #expect(edges.count == 20)
    #expect(abs(edges[0] - 50) < 0.01 && abs(edges[19] - 16000) < 0.01)
    let ratios = zip(edges.dropFirst(), edges).map { $0 / $1 }
    #expect(ratios.allSatisfy { abs($0 - ratios[0]) < 0.0001 })
    #expect(SpectrumAnalyzer.bandEdges(count: 4, sampleRate: 8000).last! <= 4000)   // never past Nyquist
}

@Test(arguments: [1000.0, 8000.0])
func fullScaleToneLightsItsOwnBand(hz: Double) {
    let out = bands(sine(hz))
    let home = bandIndex(containing: hz)
    #expect(out.firstIndex(of: out.max()!) == home)
    #expect(out[home] >= 0.8)
    for (i, level) in out.enumerated() where abs(i - home) >= 2 {
        #expect(level < out[home] / 2, "band \(i) is \(level)")
    }
}

@Test func lowToneLightsTheLowEndOnly() {
    // Bands down here are narrower than the analyzer can separate, so neighbors share the energy.
    let out = bands(sine(100))
    let home = bandIndex(containing: 100)
    #expect(out[home] >= 0.8)
    #expect(abs(out.firstIndex(of: out.max()!)! - home) <= 1)
    for (i, level) in out.enumerated() where i >= bandIndex(containing: 1000) {
        #expect(level < out[home] / 2, "band \(i) is \(level)")
    }
}

@Test func quieterTonesGiveLowerBars() {
    let home = bandIndex(containing: 1000)
    let loud = bands(sine(1000))[home], soft = bands(sine(1000, amplitude: 0.05))[home]
    #expect(soft < loud - 0.3)
    #expect(soft > 0.2)
}

@Test func extremeBandCountsAndOddInputsWork() {
    #expect(bands(sine(1000), count: 1).count == 1)
    #expect(bands(sine(1000), count: 1)[0] >= 0.8)
    let many = bands(sine(1000), count: 128)
    #expect(many.count == 128 && many.allSatisfy { $0 >= 0 && $0 <= 1 })
    #expect(bands([0.5, -0.5, 0.25]).count == 19)                       // fewer samples than the FFT needs
    #expect(bands([Float](repeating: .nan, count: 2048)).allSatisfy { $0 == 0 })
    #expect(bands(sine(1000), count: 0).isEmpty)
    #expect(bands(sine(1000, rate: 96000), rate: 96000).count == 19)
}

@Test func smootherRisesAtOnceAndFallsGradually() {
    var s = BarSmoother(count: 2)
    #expect(s.isSilent)
    s.update(target: [1, 0.5], dt: 0.016)
    #expect(s.levels == [1, 0.5])
    s.update(target: [0, 0], dt: 0.1)
    #expect(abs(s.levels[0] - 0.82) < 0.001 && abs(s.levels[1] - 0.32) < 0.001)
    #expect(!s.isSilent)
    s.update(target: [0.9, 0], dt: 0.1)
    #expect(s.levels[0] == 0.9)
}

@Test func peaksHoldThenFall() {
    var s = BarSmoother(count: 1)
    s.update(target: [1], dt: 0.016)
    s.update(target: [0], dt: 0.2)
    s.update(target: [0], dt: 0.2)
    #expect(s.peaks[0] == 1)                      // 0.4 s in, still holding
    s.update(target: [0], dt: 0.2)
    #expect(abs(s.peaks[0] - 0.88) < 0.001)       // hold of 0.5 s is over; falling at 0.6 per second
    for _ in 0..<40 { s.update(target: [0], dt: 0.1) }
    #expect(s.isSilent)
    #expect(s.peaks[0] == 0 && s.levels[0] == 0)
}

@Test func smootherToleratesMismatchedInput() {
    var s = BarSmoother(count: 3)
    s.update(target: [1], dt: 0.016)
    #expect(s.levels == [1, 0, 0])
    s.update(target: [0.2, 0.2, 0.2, 0.9, .nan], dt: 0.016)
    #expect(s.levels.count == 3)
    s.update(target: [.nan, 2, -1], dt: 10)
    #expect(s.levels == [0, 1, 0])
}

@Test func levelsAreCalibratedInDecibels() {
    // A tone 20 dB below full scale, centered on an FFT bin, should read a third of the way down a 60 dB range.
    let hz = 46 * 44100.0 / Double(SpectrumAnalyzer.fftSize)
    let out = bands(sine(hz, amplitude: 0.1))
    #expect(abs(out[bandIndex(containing: hz)] - 0.667) < 0.01, "\(out[bandIndex(containing: hz)])")
}
