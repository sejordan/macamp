import Foundation
import Testing
@testable import MacampCore

final class FakeAudio: AudioPlaying {
    var onFinished: (() -> Void)?
    var volume = 1.0
    var isPlaying = false
    var currentTime = 0.0
    var duration = 100.0
    var formatInfo: AudioFormatInfo? = AudioFormatInfo(codec: "MP3", sampleRate: 44100, channels: 2, bitrate: 128_000)
    var failing: Set<String> = []
    var loaded: [String] = []

    func load(_ url: URL) throws {
        let name = url.deletingPathExtension().lastPathComponent
        if failing.contains(name) { throw CocoaError(.fileReadCorruptFile) }
        loaded.append(name)
        currentTime = 0
    }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false; currentTime = 0 }
    func seek(to seconds: Double) { currentTime = seconds }
    func monoSamples(count: Int, into: UnsafeMutableBufferPointer<Float>) -> Double? { nil }

    /// Simulates the track reaching its end.
    func finish() { isPlaying = false; onFinished?() }
}

private func make(_ names: String...) -> (PlayerController, FakeAudio) {
    let audio = FakeAudio()
    let player = PlayerController(audio: audio)
    player.add(names.map { URL(fileURLWithPath: "/music/\($0).mp3") }, playFirstNew: false, playIfIdle: false)
    return (player, audio)
}

private func currentName(_ p: PlayerController) -> String? {
    p.playlist.current?.url.deletingPathExtension().lastPathComponent
}

@Test func playStartsTheFirstTrack() {
    let (p, audio) = make("a", "b", "c")
    #expect(p.status == .stopped && p.playlist.currentIndex == nil)
    p.play()
    #expect(p.status == .playing && audio.isPlaying)
    #expect(currentName(p) == "a" && audio.loaded == ["a"])
}

@Test func playOnAnEmptyPlaylistDoesNothing() {
    let (p, audio) = make()
    p.play(); p.next(); p.previous(); p.playPause(); p.stop(); p.seek(fraction: 0.5); p.seek(by: 5)
    #expect(p.status == .stopped && audio.loaded.isEmpty)
}

@Test func naturalEndAdvancesAndEndOfListStops() {
    let (p, audio) = make("a", "b")
    p.play()
    audio.finish()
    #expect(currentName(p) == "b" && p.status == .playing && audio.isPlaying)
    audio.finish()
    #expect(p.status == .stopped && !audio.isPlaying)
    #expect(currentName(p) == "b")
    p.play()                                   // playing again restarts the current track
    #expect(audio.loaded == ["a", "b", "b"] && p.status == .playing)
}

@Test func repeatOneReplaysOnNaturalEndButNotOnManualNext() {
    let (p, audio) = make("a", "b")
    p.order.repeatMode = .one
    p.play()
    audio.finish()
    #expect(currentName(p) == "a" && p.status == .playing && audio.loaded == ["a", "a"])
    p.next()
    #expect(currentName(p) == "b")
}

@Test func pauseTogglesAndPlayResumesWithoutReloading() {
    let (p, audio) = make("a")
    p.play()
    audio.currentTime = 42
    p.pause()
    #expect(p.status == .paused && !audio.isPlaying)
    p.play()
    #expect(p.status == .playing && audio.isPlaying && audio.currentTime == 42 && audio.loaded == ["a"])
    p.pause(); p.pause()
    #expect(p.status == .playing)
    p.playPause()
    #expect(p.status == .paused)
    p.playPause()
    #expect(p.status == .playing)
}

@Test func stopKeepsTheCurrentTrackAndResetsPosition() {
    let (p, audio) = make("a", "b")
    p.playTrack(at: 1)
    audio.currentTime = 30
    p.stop()
    #expect(p.status == .stopped && currentName(p) == "b" && p.elapsed == 0)
}

@Test func unplayableTracksAreMarkedAndSkipped() {
    let (p, audio) = make("a", "bad", "c")
    audio.failing = ["bad"]
    p.play()
    audio.finish()
    #expect(currentName(p) == "c" && p.status == .playing)
    #expect(p.playlist.tracks[1].unplayable)
    #expect(!p.playlist.tracks[0].unplayable && !p.playlist.tracks[2].unplayable)
}

@Test func whenNothingIsPlayableItStopsAfterOnePass() {
    let (p, audio) = make("x", "y", "z")
    audio.failing = ["x", "y", "z"]
    p.order.repeatMode = .all
    p.play()
    #expect(p.status == .stopped && audio.loaded.isEmpty)
    #expect(p.playlist.tracks.filter(\.unplayable).count == 3)
    p.order.shuffle = true
    p.play()
    #expect(p.status == .stopped)
}

@Test func aTrackThatWorksAgainLosesItsUnplayableMark() {
    let (p, audio) = make("a")
    audio.failing = ["a"]
    p.play()
    #expect(p.playlist.tracks[0].unplayable)
    audio.failing = []
    p.playTrack(at: 0)
    #expect(!p.playlist.tracks[0].unplayable && p.status == .playing)
}

@Test func removingThePlayingTrackStopsPlayback() {
    let (p, audio) = make("a", "b", "c")
    p.playTrack(at: 1)
    p.remove(at: [0])
    #expect(p.status == .playing && currentName(p) == "b")
    p.remove(at: [0])
    #expect(p.status == .stopped && !audio.isPlaying && p.playlist.currentID == nil)
    p.play()
    #expect(currentName(p) == "c")
}

@Test func movingThePlayingTrackKeepsItCurrent() {
    let (p, audio) = make("a", "b", "c")
    p.playTrack(at: 0)
    #expect(p.move(from: [0], to: 3) == IndexSet(integer: 2))
    #expect(p.playlist.currentIndex == 2 && p.status == .playing && audio.loaded == ["a"])
}

@Test func clearStopsPlayback() {
    let (p, audio) = make("a", "b")
    p.play()
    p.clear()
    #expect(p.status == .stopped && !audio.isPlaying && p.playlist.tracks.isEmpty)
    #expect(p.elapsed == 0 && p.duration == 0)
}

@Test func addHonorsPlayFirstNewAndPlayIfIdle() {
    let (p, audio) = make("a")
    p.add([URL(fileURLWithPath: "/music/b.mp3")], playFirstNew: false, playIfIdle: true)
    #expect(currentName(p) == "b" && p.status == .playing)         // idle, so it starts
    p.add([URL(fileURLWithPath: "/music/c.mp3")], playFirstNew: false, playIfIdle: true)
    #expect(currentName(p) == "b")                                  // already playing, so it does not interrupt
    p.add([URL(fileURLWithPath: "/music/d.mp3"), URL(fileURLWithPath: "/music/e.mp3")], playFirstNew: true, playIfIdle: false)
    #expect(currentName(p) == "d" && audio.loaded == ["b", "d"])
    p.add([], playFirstNew: true, playIfIdle: true)
    #expect(currentName(p) == "d")
}

@Test func previousRestartsAfterThreeSecondsOtherwiseGoesBack() {
    let (p, audio) = make("a", "b")
    p.playTrack(at: 1)
    audio.currentTime = 10
    p.previous()
    #expect(currentName(p) == "b" && audio.currentTime == 0 && audio.loaded == ["b"])
    audio.currentTime = 2
    p.previous()
    #expect(currentName(p) == "a")
}

@Test func seekingByFractionAndBySeconds() {
    let (p, audio) = make("a")
    p.play()
    p.seek(fraction: 0.25)
    #expect(audio.currentTime == 25)
    p.seek(by: 10)
    #expect(audio.currentTime == 35)
    p.seek(by: -100)
    #expect(audio.currentTime == 0)
    p.seek(by: 1000)
    #expect(audio.currentTime <= 100)
    p.seek(fraction: .nan)
    #expect(audio.currentTime.isFinite)
}

@Test func templateValuesDescribeTheCurrentTrack() {
    let (p, audio) = make("a", "b")
    p.playlist.update(id: p.playlist.tracks[1].id) { $0.title = "Bee"; $0.artist = "Hive" }
    #expect(p.templateValues.state == "stopped" && p.templateValues.index == nil && p.templateValues.count == 2)
    p.playTrack(at: 1)
    audio.currentTime = 7
    let v = p.templateValues
    #expect(v.title == "Bee" && v.artist == "Hive" && v.fileName == "b.mp3")
    #expect(v.index == 2 && v.count == 2 && v.elapsed == 7 && v.duration == 100)
    #expect(v.codec == "MP3" && v.sampleRate == 44100 && v.channels == 2 && v.state == "playing")
    p.pause()
    #expect(p.templateValues.state == "paused")
}

@Test func changesAreAnnounced() {
    let (p, audio) = make("a", "b")
    var changes = 0
    p.onChange = { changes += 1 }
    p.play();            #expect(changes == 1)
    audio.finish();      #expect(changes == 2)
    p.pause();           #expect(changes == 3)
    p.volume = 0.4;      #expect(changes == 4 && audio.volume == 0.4)
    p.order.shuffle = true; #expect(changes == 5)
    p.remove(at: [0]);   #expect(changes == 6)
}

@Test func playTrackOutOfRangeIsIgnored() {
    let (p, _) = make("a")
    p.playTrack(at: 5); p.playTrack(at: -1)
    #expect(p.status == .stopped)
}

@Test func shuffleWithRepeatAllFindsThePlayableTrackAmongBadOnes() {
    for _ in 0..<60 {
        let (p, audio) = make("bad1", "bad2", "good")
        audio.failing = ["bad1", "bad2"]
        var order = PlaybackOrder()
        order.shuffle = true
        order.repeatMode = .all
        p.order = order
        p.playTrack(at: 2)
        audio.finish()                 // the good track ends; every other track is bad
        #expect(p.status == .playing && currentName(p) == "good")
        if p.status != .playing { break }
    }
}
