import Foundation

/// Carries out control commands against a player. Use it from the main thread.
public enum PlayerCommands {
    private struct Failure: Error { let message: String }

    public static func run(_ request: ControlRequest, on player: PlayerController) -> ControlReply {
        var reply = ControlReply(ok: true)
        do {
            try perform(request.command, request.arguments, on: player, reply: &reply)
        } catch let failure as Failure {
            reply = ControlReply(ok: false, error: failure.message)
        } catch {
            reply = ControlReply(ok: false, error: error.localizedDescription)
        }
        reply.status = status(of: player)
        return reply
    }

    public static func status(of player: PlayerController) -> PlayerStatus {
        var s = PlayerStatus()
        switch player.status {
        case .playing: s.state = "playing"
        case .paused: s.state = "paused"
        case .stopped: s.state = "stopped"
        }
        s.count = player.playlist.count
        s.elapsed = player.elapsed
        s.duration = player.duration
        s.volume = Int((player.volume * 100).rounded())
        s.shuffle = player.order.shuffle
        s.repeatMode = player.order.repeatMode.rawValue
        if let index = player.playlist.currentIndex {
            s.index = index + 1
            s.track = describe(player.playlist.tracks[index], at: index)
        }
        return s
    }

    private static func describe(_ track: Track, at index: Int) -> TrackStatus {
        TrackStatus(index: index + 1, file: track.url.path, title: track.title, artist: track.artist,
                    album: track.album, duration: track.duration, unplayable: track.unplayable)
    }

    private static func perform(_ command: String, _ args: [String], on player: PlayerController,
                                reply: inout ControlReply) throws {
        func noArguments() throws {
            if !args.isEmpty { throw Failure(message: "'\(command)' takes no arguments") }
        }
        func oneArgument(_ what: String) throws -> String {
            guard args.count == 1 else { throw Failure(message: "'\(command)' needs \(what)") }
            return args[0]
        }

        switch command {
        case "status":
            try noArguments()
        case "playlist":
            try noArguments()
            reply.playlist = player.playlist.tracks.enumerated().map { describe($1, at: $0) }
        case "play":
            if args.isEmpty {
                player.play()
            } else {
                player.add(try audioFiles(args), playFirstNew: true, playIfIdle: true)
            }
        case "add":
            if args.isEmpty { throw Failure(message: "'add' needs at least one file or folder") }
            player.add(try audioFiles(args), playFirstNew: false, playIfIdle: false)
        case "pause":
            try noArguments()
            if player.status == .playing { player.pause() }
        case "toggle":
            try noArguments()
            player.playPause()
        case "stop":
            try noArguments()
            player.stop()
        case "next":
            try noArguments()
            player.next()
        case "previous", "prev":
            try noArguments()
            player.previous()
        case "seek":
            try seek(try oneArgument("a position such as 90, 1:30, +10, -10 or 50%"), on: player)
        case "volume":
            guard !args.isEmpty else { return }
            let text = try oneArgument("a level from 0 to 100, or a change such as +5 or -5")
            let current = (player.volume * 100).rounded()
            let level: Double
            if text.hasPrefix("+") || text.hasPrefix("-") {
                guard let change = Double(text.dropFirst()), change.isFinite else {
                    throw Failure(message: "'\(text)' is not a volume change; use something like +5 or -5")
                }
                level = current + (text.hasPrefix("-") ? -change : change)
            } else {
                guard let value = Double(text), value >= 0, value <= 100 else {
                    throw Failure(message: "'\(text)' is not a volume; use 0 to 100, or a change such as +5")
                }
                level = value
            }
            player.volume = min(100, max(0, level)) / 100
        case "jump":
            let count = player.playlist.count
            let range = count == 0 ? "the playlist is empty" : "use 1 to \(count)"
            guard args.count == 1, let n = Int(args[0]), n >= 1, n <= count else {
                throw Failure(message: "'jump' needs a track number; \(range)")
            }
            player.playTrack(at: n - 1)
        case "remove":
            let count = player.playlist.count
            guard !args.isEmpty else { throw Failure(message: "'remove' needs one or more track numbers") }
            var rows = IndexSet()
            for text in args {
                guard let n = Int(text), n >= 1, n <= count else {
                    throw Failure(message: "'\(text)' is not a track number; \(count == 0 ? "the playlist is empty" : "use 1 to \(count)")")
                }
                rows.insert(n - 1)
            }
            player.remove(at: rows)
        case "clear":
            try noArguments()
            player.clear()
        case "shuffle":
            var order = player.order
            switch args.first ?? "toggle" {
            case "on": order.shuffle = true
            case "off": order.shuffle = false
            case "toggle": order.shuffle.toggle()
            default: throw Failure(message: "'shuffle' takes on, off or toggle")
            }
            if args.count > 1 { throw Failure(message: "'shuffle' takes on, off or toggle") }
            player.order = order
        case "repeat":
            var order = player.order
            if let text = args.first {
                guard args.count == 1, let mode = RepeatMode(rawValue: text) else {
                    throw Failure(message: "'repeat' takes off, all or one")
                }
                order.repeatMode = mode
            } else {
                order.repeatMode = order.repeatMode.next
            }
            player.order = order
        default:
            throw Failure(message: "unknown command '\(command)'; commands are \(ControlCommand.all.joined(separator: ", "))")
        }
    }

    private static func audioFiles(_ paths: [String]) throws -> [URL] {
        let files = FileScanner.expand(paths.map { URL(fileURLWithPath: $0) })
        if files.isEmpty { throw Failure(message: "no audio files found in: \(paths.joined(separator: ", "))") }
        return files
    }

    /// Seconds from "90", "1:30" or "1:02:03".
    private static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part), value.isFinite, value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }

    private static func seek(_ text: String, on player: PlayerController) throws {
        guard player.hasLoadedTrack else { throw Failure(message: "nothing is loaded; play a track before seeking") }
        let bad = Failure(message: "'\(text)' is not a position; use seconds (90), a time (1:30), an offset (+10, -10) or a percentage (50%)")
        if text.hasSuffix("%") {
            guard let percent = Double(text.dropLast()), percent >= 0, percent <= 100 else { throw bad }
            player.seek(fraction: percent / 100)
        } else if text.hasPrefix("+") || text.hasPrefix("-") {
            guard let amount = seconds(String(text.dropFirst())) else { throw bad }
            player.seek(by: text.hasPrefix("-") ? -amount : amount)
        } else {
            guard let position = seconds(text) else { throw bad }
            let duration = player.duration
            player.seek(fraction: duration > 0 ? min(1, position / duration) : 0)
        }
    }
}
