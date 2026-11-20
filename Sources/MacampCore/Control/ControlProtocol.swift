import Foundation

/// One command sent to a running player, as `macamp <command> [arguments…]`.
public struct ControlRequest: Codable, Equatable {
    public var command: String
    public var arguments: [String]

    public init(command: String, arguments: [String] = []) {
        self.command = command
        self.arguments = arguments
    }

    public func encoded() throws -> Data { try JSONEncoder.control.encode(self) }
    public static func decode(_ data: Data) throws -> ControlRequest { try JSONDecoder().decode(ControlRequest.self, from: data) }
}

public struct TrackStatus: Codable, Equatable {
    /// Position in the playlist, starting at 1.
    public var index: Int
    public var file: String
    public var title: String?
    public var artist: String?
    public var album: String?
    public var duration: Double?
    public var unplayable: Bool
}

public struct PlayerStatus: Codable, Equatable {
    public var running = true
    /// "playing", "paused" or "stopped".
    public var state = "stopped"
    /// The current track's position in the playlist, starting at 1.
    public var index: Int?
    public var count = 0
    public var track: TrackStatus?
    public var elapsed = 0.0
    public var duration = 0.0
    /// 0 to 100.
    public var volume = 100
    public var shuffle = false
    /// "off", "all" or "one".
    public var repeatMode = "off"
    public var skin: String?
    public var version = Macamp.version

    enum CodingKeys: String, CodingKey {
        case running, state, index, count, track, elapsed, duration, volume, shuffle
        case repeatMode = "repeat"
        case skin, version
    }
}

/// What the player sends back. `status` is included whenever the player is running, even on an error.
public struct ControlReply: Codable, Equatable {
    public var ok: Bool
    public var error: String?
    public var status: PlayerStatus?
    public var playlist: [TrackStatus]?

    public init(ok: Bool, error: String? = nil, status: PlayerStatus? = nil, playlist: [TrackStatus]? = nil) {
        self.ok = ok; self.error = error; self.status = status; self.playlist = playlist
    }

    /// What a status request gets when no player is running.
    public static var notRunning: ControlReply {
        var status = PlayerStatus()
        status.running = false
        return ControlReply(ok: true, status: status)
    }

    /// One line of JSON.
    public func encoded() throws -> Data { try JSONEncoder.control.encode(self) }
    public static func decode(_ data: Data) throws -> ControlReply { try JSONDecoder().decode(ControlReply.self, from: data) }

    /// A short description for people. Agents should ask for JSON instead.
    public var summary: String {
        if let error { return error }
        guard let status else { return ok ? "ok" : "failed" }
        guard status.running else { return "macamp is not running" }
        if let playlist {
            if playlist.isEmpty { return "the playlist is empty" }
            return playlist.map { track in
                let marker = track.index == status.index ? ">" : " "
                let length = track.duration.map { "  " + formatTime($0, pad: false) } ?? ""
                return "\(marker) \(track.index). \(Self.name(track))\(length)\(track.unplayable ? "  (unplayable)" : "")"
            }.joined(separator: "\n")
        }
        var parts = [status.state]
        if let index = status.index, let track = status.track {
            parts.append("\(index)/\(status.count)")
            parts.append(Self.name(track))
            parts.append("\(formatTime(status.elapsed, pad: false)) / \(formatTime(status.duration, pad: false))")
        } else {
            parts.append(status.count == 1 ? "1 track" : "\(status.count) tracks")
        }
        parts.append("volume \(status.volume)")
        if status.shuffle { parts.append("shuffle") }
        if status.repeatMode != "off" { parts.append("repeat \(status.repeatMode)") }
        return parts.joined(separator: "  ")
    }

    private static func name(_ track: TrackStatus) -> String {
        var values = TemplateValues()
        values.title = track.title
        values.artist = track.artist
        values.fileName = (track.file as NSString).lastPathComponent
        return TextTemplate("{display}").render(values)
    }
}

extension JSONEncoder {
    static var control: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// The command words the command line accepts.
public enum ControlCommand {
    /// Handled by `PlayerCommands`.
    public static let playerCommands = [
        "status", "playlist", "play", "pause", "toggle", "stop", "next", "previous", "prev",
        "seek", "volume", "jump", "add", "remove", "clear", "shuffle", "repeat",
    ]
    /// Handled by the app, because they concern its window or its lifetime.
    public static let appCommands = ["skin", "quit"]
    public static var all: [String] { playerCommands + appCommands }
    /// Commands whose arguments are file paths, which the sender must make absolute.
    public static let pathCommands: Set<String> = ["play", "add", "skin"]
    /// Commands that make sense to send to a player that has to be started first.
    public static let startsPlayer: Set<String> = ["play", "add", "toggle", "next", "previous", "prev", "jump", "skin",
                                                   "volume", "shuffle", "repeat", "clear", "remove", "seek", "pause", "stop", "playlist"]
}
