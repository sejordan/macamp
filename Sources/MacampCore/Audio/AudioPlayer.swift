import AVFoundation
import Foundation

/// Plays one file at a time through AVAudioEngine.
///
/// The file is decoded in small chunks that are queued a little ahead of the
/// playhead, so memory use does not depend on file length. The chunks are kept
/// until they have been heard, which lets `monoSamples` hand the visualizer
/// exactly what is coming out of the speakers without an audio tap.
public final class AudioPlayer: AudioPlaying {
    static let chunkFrames: AVAudioFrameCount = 8192
    static let chunksAhead = 4
    /// Samples kept behind the playhead for the visualizer.
    static let historyFrames: AVAudioFramePosition = 4096

    public var onFinished: (() -> Void)?

    private let callbackQueue: DispatchQueue
    /// Guards every property below. Public methods hop onto it; audio callbacks post to it.
    private let queue = DispatchQueue(label: "macamp.audio")
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var attached = false
    private var connectedFormat: AVAudioFormat?
    private var observer: NSObjectProtocol?

    private var file: AVAudioFile?
    private var info: AudioFormatInfo?
    private var sampleRate = 44100.0
    private var length: AVAudioFramePosition = 0

    /// Bumped whenever queued audio is thrown away, so late callbacks can be recognized and ignored.
    private var generation = 0
    /// The file frame that the node's own clock counts from.
    private var baseFrame: AVAudioFramePosition = 0
    private var readFrame: AVAudioFramePosition = 0
    private var pending = 0
    private var playing = false
    private var heldFrame: AVAudioFramePosition = 0
    /// A known (file frame, clock time) pair. Between refreshes the position is worked out from the
    /// clock, because asking the player node takes a lock that can stall the caller for milliseconds.
    private var anchor: (frame: AVAudioFramePosition, time: UInt64)?
    private var latencyFrames: AVAudioFramePosition = 0
    private var chunks: [(start: AVAudioFramePosition, buffer: AVAudioPCMBuffer)] = []
    private var storedVolume = 1.0

    public init(callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                          queue: nil) { [weak self] _ in
            self?.queue.async { self?.outputChanged() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if attached { node.stop() }
        engine.stop()
    }

    // MARK: AudioPlaying

    public var volume: Double {
        get { queue.sync { storedVolume } }
        set {
            let v = newValue.isFinite ? min(1, max(0, newValue)) : 0
            queue.sync {
                storedVolume = v
                if connectedFormat != nil { engine.mainMixerNode.outputVolume = Float(v) }
            }
        }
    }

    public var isPlaying: Bool { queue.sync { playing } }
    public var currentTime: Double { queue.sync { Double(currentFrame()) / sampleRate } }
    public var duration: Double { queue.sync { file == nil ? 0 : Double(length) / sampleRate } }
    public var formatInfo: AudioFormatInfo? { queue.sync { info } }

    public func load(_ url: URL) throws {
        let newFile = try AVAudioFile(forReading: url)
        guard newFile.length > 0, newFile.processingFormat.sampleRate > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let newInfo = Self.describe(newFile, url: url)
        queue.sync {
            discardQueued()
            playing = false
            file = newFile
            info = newInfo
            length = newFile.length
            sampleRate = newFile.processingFormat.sampleRate
            moveTo(0)
            connect(newFile.processingFormat)
        }
    }

    public func play() {
        queue.sync {
            guard file != nil, !playing else { return }
            guard startEngine() else { return }
            if pending == 0 {
                if readFrame >= length { moveTo(0) }
                fill()
            }
            node.play()
            playing = true
        }
    }

    public func pause() {
        queue.sync {
            guard playing else { return }
            heldFrame = currentFrame()
            playing = false
            anchor = nil
            node.pause()
            engine.pause()
        }
    }

    public func stop() {
        queue.sync {
            discardQueued()
            playing = false
            if engine.isRunning { engine.pause() }
            moveTo(0)
        }
    }

    public func seek(to seconds: Double) {
        queue.sync {
            guard file != nil else { return }
            let target = seconds.isFinite ? AVAudioFramePosition((max(0, seconds) * sampleRate).rounded()) : 0
            discardQueued()
            moveTo(min(target, length))
            guard playing else { return }
            fill()
            if pending == 0 { finish() } else { node.play() }
        }
    }

    public func monoSamples(count: Int, into out: UnsafeMutableBufferPointer<Float>) -> Double? {
        queue.sync {
            guard playing, file != nil, count > 0, out.count >= count else { return nil }
            for i in 0..<count { out[i] = 0 }
            let end = currentFrame() - latencyFrames
            let begin = end - AVAudioFramePosition(count)
            for chunk in chunks {
                let chunkEnd = chunk.start + AVAudioFramePosition(chunk.buffer.frameLength)
                let from = max(begin, chunk.start), to = min(end, chunkEnd)
                guard from < to, let channels = chunk.buffer.floatChannelData else { continue }
                let channelCount = Int(chunk.buffer.format.channelCount)
                let scale = 1 / Float(channelCount)
                let source = Int(from - chunk.start), target = Int(from - begin), n = Int(to - from)
                for channel in 0..<channelCount {
                    let data = channels[channel]
                    for i in 0..<n { out[target + i] += data[source + i] * scale }
                }
            }
            return sampleRate
        }
    }

    // MARK: Internals (all run on `queue`)

    private func connect(_ format: AVAudioFormat) {
        if !attached {
            engine.attach(node)
            attached = true
        }
        guard connectedFormat != format else { return }
        if connectedFormat != nil { engine.disconnectNodeOutput(node) }
        engine.connect(node, to: engine.mainMixerNode, format: format)
        connectedFormat = format
        engine.mainMixerNode.outputVolume = Float(storedVolume)
    }

    private func startEngine() -> Bool {
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        let latency = engine.outputNode.presentationLatency
        latencyFrames = latency.isFinite ? AVAudioFramePosition(min(1, max(0, latency)) * sampleRate) : 0
        return true
    }

    /// Throws away queued audio and makes any callbacks still in flight harmless.
    private func discardQueued() {
        generation += 1
        if attached { node.stop() }
        pending = 0
        chunks.removeAll()
        anchor = nil
    }

    private func moveTo(_ frame: AVAudioFramePosition) {
        baseFrame = frame
        readFrame = frame
        heldFrame = frame
        file?.framePosition = frame
    }

    private func currentFrame() -> AVAudioFramePosition {
        guard playing else { return heldFrame }
        if anchor == nil { refreshAnchor() }
        guard let anchor else { return heldFrame }
        let now = mach_absolute_time()
        let seconds = now >= anchor.time ? AVAudioTime.seconds(forHostTime: now - anchor.time) : 0
        heldFrame = min(length, max(baseFrame, anchor.frame + AVAudioFramePosition(seconds * sampleRate)))
        return heldFrame
    }

    /// Asks the player node where it really is and remembers the answer against the clock.
    private func refreshAnchor() {
        guard playing, let renderTime = node.lastRenderTime, renderTime.isSampleTimeValid, renderTime.isHostTimeValid,
              let time = node.playerTime(forNodeTime: renderTime), time.sampleRate > 0 else { return }
        let played = AVAudioFramePosition(Double(time.sampleTime) * sampleRate / time.sampleRate)
        anchor = (baseFrame + played, renderTime.hostTime)
    }

    private func fill() {
        guard let file else { return }
        while pending < Self.chunksAhead, readFrame < length {
            let wanted = AVAudioFrameCount(min(AVAudioFramePosition(Self.chunkFrames), length - readFrame))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: wanted) else { break }
            do { try file.read(into: buffer, frameCount: wanted) } catch { buffer.frameLength = 0 }
            guard buffer.frameLength > 0 else {
                // Nothing more can be decoded; treat this as the end of the file.
                length = readFrame
                break
            }
            chunks.append((start: readFrame, buffer: buffer))
            readFrame += AVAudioFramePosition(buffer.frameLength)
            pending += 1
            let scheduledIn = generation
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.queue.async { self?.chunkPlayed(scheduledIn) }
            }
        }
    }

    private func chunkPlayed(_ scheduledIn: Int) {
        guard scheduledIn == generation else { return }
        pending -= 1
        refreshAnchor()
        let keepFrom = currentFrame() - latencyFrames - Self.historyFrames
        chunks.removeAll { $0.start + AVAudioFramePosition($0.buffer.frameLength) < keepFrom }
        fill()
        if pending == 0 { finish() }
    }

    private func finish() {
        discardQueued()
        playing = false
        heldFrame = length
        baseFrame = length
        callbackQueue.async { [weak self] in self?.onFinished?() }
    }

    /// The output device changed (headphones unplugged, for example). Carry on from the same place.
    private func outputChanged() {
        guard let file else { return }
        let wasPlaying = playing
        let frame = heldFrame
        discardQueued()
        if connectedFormat != nil { engine.disconnectNodeOutput(node) }
        connectedFormat = nil
        connect(file.processingFormat)
        moveTo(frame)
        guard wasPlaying else { return }
        guard startEngine() else {
            playing = false
            return
        }
        fill()
        if pending == 0 { finish() } else { node.play() }
    }

    private static func describe(_ file: AVAudioFile, url: URL) -> AudioFormatInfo {
        let format = file.fileFormat
        let ext = url.pathExtension.lowercased()
        let codec: String
        switch format.streamDescription.pointee.mFormatID {
        case kAudioFormatLinearPCM:
            switch ext {
            case "wav", "wave": codec = "WAV"
            case "aif", "aiff", "aifc": codec = "AIFF"
            case "caf": codec = "CAF"
            default: codec = "PCM"
            }
        case kAudioFormatMPEGLayer3: codec = "MP3"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD: codec = "AAC"
        case kAudioFormatAppleLossless: codec = "ALAC"
        case kAudioFormatFLAC: codec = "FLAC"
        default: codec = ext.isEmpty ? "?" : ext.uppercased()
        }
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let bitrate = seconds > 0 && bytes > 0 ? Double(bytes) * 8 / seconds : nil
        return AudioFormatInfo(codec: codec, sampleRate: format.sampleRate,
                               channels: Int(format.channelCount), bitrate: bitrate)
    }
}
