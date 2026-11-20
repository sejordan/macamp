import Foundation

/// The player's behavior: what happens on play, next, the end of a track, and
/// edits to the playlist. It has no user interface and no audio code of its own.
/// Use it from the main thread.
public final class PlayerController {
    public enum Status: Equatable { case stopped, playing, paused }
    /// `previous` restarts the track when more than this many seconds have played.
    static let restartThreshold = 3.0

    public let playlist: Playlist
    public private(set) var status = Status.stopped
    /// Shuffle and repeat settings. Setting this announces a change.
    public var order: PlaybackOrder {
        get { ordering }
        set {
            ordering = newValue
            onChange?()
        }
    }
    /// Called after anything a user interface might show has changed.
    public var onChange: (() -> Void)?

    private let audio: AudioPlaying
    /// Backing store for `order`, so the controller's own bookkeeping does not announce changes.
    private var ordering = PlaybackOrder()
    /// The track whose file the audio engine currently has open.
    private var loadedID: UUID?

    public init(audio: AudioPlaying, playlist: Playlist = Playlist()) {
        self.audio = audio
        self.playlist = playlist
        audio.onFinished = { [weak self] in self?.trackEnded() }
    }

    public var volume: Double {
        get { audio.volume }
        set {
            audio.volume = newValue
            onChange?()
        }
    }

    /// True when the audio engine has a track open, so seeking means something.
    public var hasLoadedTrack: Bool { loadedID != nil }

    public var elapsed: Double { loadedID == nil ? 0 : audio.currentTime }

    public var duration: Double {
        if loadedID != nil { return audio.duration }
        return playlist.current?.duration ?? 0
    }

    public var formatInfo: AudioFormatInfo? { loadedID == nil ? nil : audio.formatInfo }

    public func monoSamples(count: Int, into buffer: UnsafeMutableBufferPointer<Float>) -> Double? {
        audio.monoSamples(count: count, into: buffer)
    }

    public var templateValues: TemplateValues { templateValues(elapsed: elapsed, duration: duration) }

    /// The same, for callers that already asked the audio engine for the position this frame.
    /// Asking is not free, and a view may need the values several times per frame.
    public func templateValues(elapsed: Double, duration length: Double) -> TemplateValues {
        var v = TemplateValues()
        v.count = playlist.count
        switch status {
        case .playing: v.state = "playing"
        case .paused: v.state = "paused"
        case .stopped: v.state = "stopped"
        }
        guard let index = playlist.currentIndex else { return v }
        let track = playlist.tracks[index]
        v.title = track.title; v.artist = track.artist; v.album = track.album
        v.fileName = track.fileName
        v.index = index + 1
        v.elapsed = elapsed
        v.duration = length > 0 ? length : track.duration
        if let info = formatInfo {
            v.codec = info.codec; v.sampleRate = info.sampleRate
            v.bitrate = info.bitrate; v.channels = info.channels
        }
        return v
    }

    // MARK: Transport

    public func play() {
        switch status {
        case .playing: return
        case .paused:
            audio.play()
            status = .playing
            onChange?()
        case .stopped:
            if let current = playlist.currentID {
                start(current)
            } else if let first = ordering.next(in: playlist.ids, current: nil, auto: false) {
                start(first)
            }
        }
    }

    /// Pauses; pressing pause again resumes.
    public func pause() {
        switch status {
        case .playing:
            audio.pause()
            status = .paused
            onChange?()
        case .paused: play()
        case .stopped: return
        }
    }

    public func playPause() {
        if status == .playing { pause() } else { play() }
    }

    public func stop() {
        guard status != .stopped || loadedID != nil else { return }
        audio.stop()
        status = .stopped
        onChange?()
    }

    public func next() {
        guard let id = ordering.next(in: playlist.ids, current: playlist.currentID, auto: false) else { return }
        start(id)
    }

    public func previous() {
        guard playlist.count > 0 else { return }
        if loadedID != nil, elapsed > Self.restartThreshold {
            audio.seek(to: 0)
            onChange?()
            return
        }
        guard let id = ordering.previous(in: playlist.ids, current: playlist.currentID) else { return }
        start(id)
    }

    public func playTrack(at index: Int) {
        guard playlist.tracks.indices.contains(index) else { return }
        start(playlist.tracks[index].id)
    }

    public func seek(fraction: Double) {
        guard loadedID != nil, fraction.isFinite else { return }
        audio.seek(to: min(1, max(0, fraction)) * audio.duration)
        onChange?()
    }

    public func seek(by seconds: Double) {
        guard loadedID != nil, seconds.isFinite else { return }
        audio.seek(to: min(audio.duration, max(0, audio.currentTime + seconds)))
        onChange?()
    }

    // MARK: Playlist edits

    /// `playFirstNew` starts the first added track no matter what; `playIfIdle` starts it only if nothing is playing.
    public func add(_ urls: [URL], playFirstNew: Bool, playIfIdle: Bool) {
        guard !urls.isEmpty else { return }
        let range = playlist.append(urls)
        if playFirstNew || (playIfIdle && status != .playing) {
            start(playlist.tracks[range.lowerBound].id)
        } else {
            onChange?()
        }
    }

    public func remove(at indexes: IndexSet) {
        playlist.remove(at: indexes)
        haltIfCurrentIsGone()
        onChange?()
    }

    @discardableResult
    public func move(from indexes: IndexSet, to destination: Int) -> IndexSet {
        let moved = playlist.move(from: indexes, to: destination)
        onChange?()
        return moved
    }

    public func clear() {
        playlist.clear()
        haltIfCurrentIsGone()
        onChange?()
    }

    /// Restores a saved playlist without starting playback.
    public func restore(tracks: [Track], currentID: UUID?) {
        audio.stop()
        loadedID = nil
        status = .stopped
        playlist.replaceAll(tracks, currentID: currentID)
        onChange?()
    }

    // MARK: Internals

    private func haltIfCurrentIsGone() {
        guard playlist.currentID == nil, loadedID != nil || status != .stopped else { return }
        audio.stop()
        loadedID = nil
        status = .stopped
    }

    /// Opens and plays one track. Returns false, marking it unplayable, if the file cannot be played.
    private func tryToPlay(_ id: UUID) -> Bool {
        guard let index = playlist.index(of: id) else { return false }
        do {
            try audio.load(playlist.tracks[index].url)
        } catch {
            playlist.update(id: id) { $0.unplayable = true }
            ordering.noteStarted(id)
            return false
        }
        let length = audio.duration
        playlist.update(id: id) {
            $0.unplayable = false
            if length > 0 { $0.duration = length }
        }
        playlist.currentID = id
        loadedID = id
        ordering.noteStarted(id)
        audio.play()
        status = .playing
        onChange?()
        return true
    }

    /// Plays `id`, or failing that the next track that can actually be opened.
    /// Each track is tried at most once, so a playlist of bad files stops instead of spinning.
    private func start(_ id: UUID) {
        var tried: Set<UUID> = []
        var candidate: UUID? = id
        var steps = 0
        while let next = candidate, tried.count < playlist.count, steps < playlist.count * 2 + 2 {
            steps += 1
            if tried.insert(next).inserted, tryToPlay(next) { return }
            candidate = ordering.next(in: playlist.ids, current: next, auto: false)
        }
        // Shuffle may keep offering tracks already tried. If the order has not said "the end",
        // go through whatever is left in playlist order so a playable track is never missed.
        if candidate != nil {
            for other in playlist.ids where !tried.contains(other) {
                if tryToPlay(other) { return }
            }
        }
        audio.stop()
        loadedID = nil
        status = .stopped
        onChange?()
    }

    private func trackEnded() {
        guard status == .playing else { return }
        if let id = ordering.next(in: playlist.ids, current: playlist.currentID, auto: true) {
            start(id)
        } else {
            audio.stop()
            status = .stopped
            onChange?()
        }
    }
}
