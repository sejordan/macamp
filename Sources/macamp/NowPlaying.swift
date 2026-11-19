import Foundation
import MacampCore
import MediaPlayer

/// Connects the player to the keyboard media keys, headphone buttons and the
/// system's Now Playing panel.
final class NowPlaying {
    private let controller: PlayerController
    private var lastSignature = ""

    init(controller: PlayerController) {
        self.controller = controller
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.run { $0.play() } ?? .commandFailed }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.run { if $0.status == .playing { $0.pause() } } ?? .commandFailed
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.run { $0.playPause() } ?? .commandFailed }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.run { $0.next() } ?? .commandFailed }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.run { $0.previous() } ?? .commandFailed }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self?.run {
                let duration = $0.duration
                if duration > 0 { $0.seek(fraction: event.positionTime / duration) }
            } ?? .commandFailed
        }
        update()
    }

    private func run(_ body: (PlayerController) -> Void) -> MPRemoteCommandHandlerStatus {
        body(controller)
        return .success
    }

    /// What the system has been told, for the diagnostic status file.
    var published: [String: Any] {
        let center = MPNowPlayingInfoCenter.default()
        let states: [MPNowPlayingPlaybackState: String] = [.playing: "playing", .paused: "paused", .stopped: "stopped"]
        return ["title": center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String ?? "",
                "artist": center.nowPlayingInfo?[MPMediaItemPropertyArtist] as? String ?? "",
                "state": states[center.playbackState] ?? "unknown"]
    }

    /// Publishes the current track and position. Call after any player change.
    func update() {
        let center = MPNowPlayingInfoCenter.default()
        let values = controller.templateValues
        guard values.index != nil else {
            if !lastSignature.isEmpty {
                center.nowPlayingInfo = nil
                center.playbackState = .stopped
                lastSignature = ""
            }
            return
        }
        let elapsed = controller.elapsed
        let title = TextTemplate("{title}").render(values)
        // Position is only republished when something other than the passage of time changed it.
        let signature = "\(title)|\(values.artist ?? "")|\(values.state)|\(Int(controller.duration))|\(Int(elapsed / 2))"
        guard signature != lastSignature else { return }
        lastSignature = signature
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: controller.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: controller.status == .playing ? 1.0 : 0.0,
        ]
        if let artist = values.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = values.album { info[MPMediaItemPropertyAlbumTitle] = album }
        center.nowPlayingInfo = info
        switch controller.status {
        case .playing: center.playbackState = .playing
        case .paused: center.playbackState = .paused
        case .stopped: center.playbackState = .stopped
        }
    }
}
