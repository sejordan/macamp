import Foundation
import Testing
@testable import MacampCore

private func rig(_ names: String...) -> (PlayerController, FakeAudio) {
    let audio = FakeAudio()
    let player = PlayerController(audio: audio)
    player.add(names.map { URL(fileURLWithPath: "/music/\($0).mp3") }, playFirstNew: false, playIfIdle: false)
    return (player, audio)
}

@discardableResult
private func run(_ p: PlayerController, _ command: String, _ arguments: String...) -> ControlReply {
    PlayerCommands.run(ControlRequest(command: command, arguments: arguments), on: p)
}

/// A folder holding real (empty) audio files, since adding goes through the file scanner.
private func musicFolder(_ names: [String]) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-cmd-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in names { FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data()) }
    return folder
}

@Test func statusDescribesThePlayer() {
    let (p, audio) = rig("a", "b")
    p.playlist.update(id: p.playlist.tracks[1].id) { $0.title = "Bee"; $0.artist = "Hive"; $0.duration = 100 }
    var reply = run(p, "status")
    #expect(reply.ok && reply.error == nil)
    var s = reply.status!
    #expect(s.running && s.state == "stopped" && s.index == nil && s.count == 2 && s.track == nil)
    #expect(s.volume == 100 && s.shuffle == false && s.repeatMode == "off" && s.version == Macamp.version)

    p.playTrack(at: 1)
    audio.currentTime = 12.5
    p.volume = 0.4
    reply = run(p, "status")
    s = reply.status!
    #expect(s.state == "playing" && s.index == 2 && s.elapsed == 12.5 && s.duration == 100 && s.volume == 40)
    #expect(s.track == TrackStatus(index: 2, file: "/music/b.mp3", title: "Bee", artist: "Hive", album: nil,
                                   duration: 100, unplayable: false))
    #expect(reply.playlist == nil)
}

@Test func playlistListsEveryTrackWithOneBasedIndexes() {
    let (p, _) = rig("a", "b", "c")
    let reply = run(p, "playlist")
    #expect(reply.ok)
    #expect(reply.playlist?.map(\.index) == [1, 2, 3])
    #expect(reply.playlist?.map(\.file) == ["/music/a.mp3", "/music/b.mp3", "/music/c.mp3"])
}

@Test func transportCommands() {
    let (p, audio) = rig("a", "b", "c")
    #expect(run(p, "play").status?.state == "playing")
    #expect(run(p, "pause").status?.state == "paused")
    #expect(run(p, "pause").status?.state == "paused")        // pause is not a toggle from the command line
    #expect(run(p, "play").status?.state == "playing")
    #expect(audio.loaded == ["a"])                             // resumed, not reloaded
    #expect(run(p, "toggle").status?.state == "paused")
    #expect(run(p, "toggle").status?.state == "playing")
    #expect(run(p, "next").status?.index == 2)
    #expect(run(p, "previous").status?.index == 1)
    #expect(run(p, "prev").status?.index == 1)
    #expect(run(p, "stop").status?.state == "stopped")
    #expect(run(p, "pause").status?.state == "stopped")        // nothing to pause; not an error
}

@Test func jumpPlaysATrackByNumber() {
    let (p, _) = rig("a", "b", "c")
    #expect(run(p, "jump", "3").status?.index == 3)
    #expect(p.status == .playing)
    for bad in ["0", "4", "-1", "two", "1.5"] {
        let reply = run(p, "jump", bad)
        #expect(!reply.ok && reply.error?.contains("1 to 3") == true, "\(bad): \(reply.error ?? "")")
    }
    #expect(!run(p, "jump").ok)
    #expect(run(p, "status").status?.index == 3)               // failed jumps change nothing
}

@Test func seekAcceptsSecondsClockTimesOffsetsAndPercentages() {
    let (p, audio) = rig("a")
    run(p, "play")                                             // FakeAudio tracks are 100 seconds long
    #expect(run(p, "seek", "30").status?.elapsed == 30)
    #expect(run(p, "seek", "+15").status?.elapsed == 45)
    #expect(run(p, "seek", "-40").status?.elapsed == 5)
    #expect(run(p, "seek", "-40").status?.elapsed == 0)
    #expect(run(p, "seek", "1:05").status?.elapsed == 65)
    #expect(run(p, "seek", "50%").status?.elapsed == 50)
    #expect(run(p, "seek", "999").status!.elapsed <= 100)
    audio.currentTime = 20
    for bad in ["soon", "", "10:99:xx", "150%", "-", "+"] {
        let reply = run(p, "seek", bad)
        #expect(!reply.ok, "\(bad) was accepted")
        #expect(audio.currentTime == 20)
    }
    #expect(!run(p, "seek").ok)
}

@Test func seekWithNothingLoadedIsAnError() {
    let (p, _) = rig("a")
    let reply = run(p, "seek", "10")
    #expect(!reply.ok && reply.error?.contains("nothing is loaded") == true)
}

@Test func volumeIsSetOnAScaleOfZeroToOneHundred() {
    let (p, audio) = rig("a")
    #expect(run(p, "volume", "35").status?.volume == 35)
    #expect(abs(audio.volume - 0.35) < 0.001)
    #expect(run(p, "volume", "+10").status?.volume == 45)
    #expect(run(p, "volume", "-50").status?.volume == 0)
    #expect(run(p, "volume", "+250").status?.volume == 100)
    #expect(run(p, "volume").status?.volume == 100)            // no argument just reports
    for bad in ["loud", "101", "-", "50%x"] {
        #expect(!run(p, "volume", bad).ok, "\(bad) was accepted")
    }
    #expect(run(p, "status").status?.volume == 100)
}

@Test func shuffleAndRepeat() {
    let (p, _) = rig("a")
    #expect(run(p, "shuffle", "on").status?.shuffle == true)
    #expect(run(p, "shuffle", "on").status?.shuffle == true)
    #expect(run(p, "shuffle", "off").status?.shuffle == false)
    #expect(run(p, "shuffle").status?.shuffle == true)          // no argument toggles
    #expect(run(p, "shuffle", "toggle").status?.shuffle == false)
    #expect(!run(p, "shuffle", "maybe").ok)
    #expect(run(p, "repeat", "all").status?.repeatMode == "all")
    #expect(run(p, "repeat", "one").status?.repeatMode == "one")
    #expect(run(p, "repeat", "off").status?.repeatMode == "off")
    #expect(run(p, "repeat").status?.repeatMode == "all")       // no argument steps off, all, one
    #expect(!run(p, "repeat", "twice").ok)
}

@Test func addAppendsWithoutInterruptingAndPlayStartsTheFirstNewTrack() throws {
    let folder = try musicFolder(["2 two.mp3", "10 ten.mp3", "notes.txt"])
    defer { try? FileManager.default.removeItem(at: folder) }
    let (p, _) = rig("a")
    run(p, "play")

    var reply = run(p, "add", folder.path)
    #expect(reply.ok && reply.status?.count == 3 && reply.status?.index == 1)       // still on the first track
    #expect(p.playlist.tracks.map(\.fileName) == ["a.mp3", "2 two.mp3", "10 ten.mp3"])

    reply = run(p, "play", folder.appendingPathComponent("10 ten.mp3").path)
    #expect(reply.ok && reply.status?.count == 4 && reply.status?.index == 4 && reply.status?.state == "playing")

    for command in ["add", "play"] {
        let none = run(p, command, folder.appendingPathComponent("notes.txt").path, "/no/such/place")
        #expect(!none.ok && none.error?.contains("no audio files") == true)
    }
    #expect(!run(p, "add").ok)
    #expect(p.playlist.count == 4)
}

@Test func removeAndClear() {
    let (p, _) = rig("a", "b", "c", "d")
    p.playTrack(at: 1)
    var reply = run(p, "remove", "4", "1")
    #expect(reply.ok && reply.status?.count == 2 && reply.status?.index == 1 && reply.status?.state == "playing")
    #expect(!run(p, "remove", "3").ok)
    #expect(!run(p, "remove", "x").ok)
    #expect(!run(p, "remove").ok)
    #expect(p.playlist.count == 2)
    reply = run(p, "clear")
    #expect(reply.ok && reply.status?.count == 0 && reply.status?.state == "stopped")
}

@Test func unknownCommandsAndExtraArgumentsAreErrors() {
    let (p, _) = rig("a")
    let reply = run(p, "explode")
    #expect(!reply.ok && reply.error?.contains("unknown command") == true)
    #expect(reply.status != nil)                               // the state still comes back, so a caller can recover
    #expect(!run(p, "next", "now").ok)
    #expect(!run(p, "status", "please").ok)
}

@Test func everyAdvertisedCommandIsHandled() {
    let (p, _) = rig("a")
    for name in ControlCommand.playerCommands {
        let reply = run(p, name)
        #expect(reply.error?.contains("unknown command") != true, "\(name) is advertised but not handled")
    }
}

@Test func repliesRoundTripThroughJSONWithStableFieldNames() throws {
    let (p, _) = rig("a")
    p.playTrack(at: 0)
    let reply = run(p, "playlist")
    let data = try reply.encoded()
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("\n"))
    for key in ["\"ok\"", "\"status\"", "\"playlist\"", "\"state\"", "\"repeat\"", "\"elapsed\"", "\"volume\"", "\"file\""] {
        #expect(text.contains(key), "missing \(key) in \(text)")
    }
    #expect(try ControlReply.decode(data) == reply)
    let request = ControlRequest(command: "seek", arguments: ["+10"])
    #expect(try ControlRequest.decode(try request.encoded()) == request)
}

@Test func summariesReadWellForPeople() {
    let (p, audio) = rig("a", "b")
    p.playlist.update(id: p.playlist.tracks[0].id) { $0.title = "Low Tide Radio"; $0.artist = "Night Ferry" }
    p.playTrack(at: 0)
    audio.currentTime = 84
    p.volume = 0.8
    #expect(run(p, "status").summary == "playing  1/2  Night Ferry - Low Tide Radio  1:24 / 1:40  volume 80")
    let list = run(p, "playlist").summary
    #expect(list.contains("> 1. Night Ferry - Low Tide Radio"))
    #expect(list.contains("  2. b"))
    #expect(run(p, "explode").summary.contains("unknown command"))
    #expect(ControlReply.notRunning.summary == "macamp is not running")
}

@Test func theControlGuideCoversEveryCommandReplyFieldAndExitStatus() throws {
    let guide = ControlCommand.guide
    for command in ControlCommand.all {
        #expect(guide.contains("`\(command)"), "the guide does not mention the command \(command)")
    }
    // Every key an agent can see in a reply must be explained.
    let (p, _) = rig("a")
    p.playlist.update(id: p.playlist.tracks[0].id) { $0.title = "T"; $0.artist = "A"; $0.album = "L"; $0.duration = 1 }
    p.playTrack(at: 0)
    var reply = run(p, "playlist")
    reply.error = "example"
    reply.status?.skin = "Phosphor"
    var keys: Set<String> = []
    func collect(_ value: Any) {
        if let dict = value as? [String: Any] { for (k, v) in dict { keys.insert(k); collect(v) } }
        if let list = value as? [Any] { list.forEach(collect) }
    }
    collect(try JSONSerialization.jsonObject(with: try reply.encoded()))
    #expect(keys.count >= 20)
    for key in keys.sorted() {
        #expect(guide.contains("`\(key)`"), "the guide does not explain the reply field \(key)")
    }
    for status in ["| 0 |", "| 1 |", "| 2 |", "| 3 |"] {
        #expect(guide.contains(status), "the guide does not list exit status \(status)")
    }
    #expect(guide.contains("--json"))
}
