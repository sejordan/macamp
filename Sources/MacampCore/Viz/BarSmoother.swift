import Foundation

/// Gives bars their motion: they jump up with the music and fall back at a steady rate,
/// with peak markers that hang for a moment before dropping.
public struct BarSmoother {
    static let fallPerSecond: Float = 1.8
    static let peakHold = 0.5
    static let peakFallPerSecond: Float = 0.6

    public private(set) var levels: [Float]
    public private(set) var peaks: [Float]
    private var holds: [Double]

    public init(count: Int) {
        let n = max(0, count)
        levels = [Float](repeating: 0, count: n)
        peaks = [Float](repeating: 0, count: n)
        holds = [Double](repeating: 0, count: n)
    }

    public var isSilent: Bool {
        !levels.contains { $0 > 0.001 } && !peaks.contains { $0 > 0.001 }
    }

    public mutating func update(target: [Float], dt: Double) {
        let step = Float(max(0, dt))
        for i in levels.indices {
            let raw = i < target.count ? target[i] : 0
            let wanted = raw.isFinite ? min(1, max(0, raw)) : 0
            levels[i] = wanted >= levels[i] ? wanted : max(wanted, levels[i] - Self.fallPerSecond * step)
            if levels[i] >= peaks[i] {
                peaks[i] = levels[i]
                holds[i] = Self.peakHold
            } else {
                holds[i] -= max(0, dt)
                if holds[i] < 0 { peaks[i] = max(levels[i], peaks[i] - Self.peakFallPerSecond * step) }
            }
        }
    }
}
