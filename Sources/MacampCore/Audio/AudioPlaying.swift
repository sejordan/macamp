import Foundation

/// Details of the file being played, for skins that show them.
public struct AudioFormatInfo: Equatable {
    public var codec: String
    public var sampleRate: Double
    public var channels: Int
    /// Bits per second, averaged over the file.
    public var bitrate: Double?

    public init(codec: String, sampleRate: Double, channels: Int, bitrate: Double?) {
        self.codec = codec; self.sampleRate = sampleRate; self.channels = channels; self.bitrate = bitrate
    }
}

/// What the player controller needs from an audio engine. Tests substitute a fake.
public protocol AudioPlaying: AnyObject {
    /// Called when a track plays through to its end by itself.
    var onFinished: (() -> Void)? { get set }
    /// 0 to 1.
    var volume: Double { get set }
    var isPlaying: Bool { get }
    /// Seconds.
    var currentTime: Double { get }
    var duration: Double { get }
    var formatInfo: AudioFormatInfo? { get }
    /// Opens a file, replacing the current one. Throws if it cannot be played, leaving the current one in place.
    func load(_ url: URL) throws
    func play()
    func pause()
    /// Stops and returns to the start of the file.
    func stop()
    func seek(to seconds: Double)
    /// Copies the `count` samples just played, mixed to mono, into `into`.
    /// Returns their sample rate, or nil when nothing is playing.
    func monoSamples(count: Int, into: UnsafeMutableBufferPointer<Float>) -> Double?
}
