import Foundation
import Testing
@testable import MacampCore

/// Tone files generated once per test run by scripts/make-test-audio.sh.
enum TestAudio {
    static let directory: URL = {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-audio-\(UUID().uuidString)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repo.appendingPathComponent("scripts/make-test-audio.sh").path, out.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return out
    }()

    static func file(_ name: String) -> URL { directory.appendingPathComponent(name) }
    static func has(_ name: String) -> Bool { FileManager.default.fileExists(atPath: file(name).path) }
}

@Test(arguments: [("tone.wav", "WAV"), ("tone.aiff", "AIFF"), ("tone.caf", "CAF"), ("tone-aac.m4a", "AAC"),
                  ("tone-alac.m4a", "ALAC"), ("tone.flac", "FLAC"), ("tone.mp3", "MP3")])
func everyFormatLoadsWithItsDurationAndCodec(name: String, codec: String) throws {
    guard TestAudio.has(name) else { return }       // MP3 needs lame or ffmpeg to generate
    let player = AudioPlayer()
    try player.load(TestAudio.file(name))
    #expect(abs(player.duration - 1.0) < 0.1, "\(name): \(player.duration)")
    let info = try #require(player.formatInfo)
    #expect(info.codec == codec)
    #expect(info.sampleRate == 44100 && info.channels == 2)
    #expect((info.bitrate ?? 0) > 1000)
    #expect(player.currentTime == 0 && !player.isPlaying)
}

@Test func filesThatAreNotAudioThrow() {
    let player = AudioPlayer()
    #expect(throws: (any Error).self) { try player.load(TestAudio.file("fake.mp3")) }
    #expect(throws: (any Error).self) { try player.load(TestAudio.file("empty.wav")) }
    #expect(throws: (any Error).self) { try player.load(TestAudio.file("does-not-exist.wav")) }
    #expect(player.duration == 0 && player.formatInfo == nil)
}

@Test func aFailedLoadLeavesThePreviousFileUsable() throws {
    let player = AudioPlayer()
    try player.load(TestAudio.file("tone.wav"))
    #expect(throws: (any Error).self) { try player.load(TestAudio.file("fake.mp3")) }
    #expect(abs(player.duration - 1.0) < 0.1)
}

@Test func differentSampleRatesAndChannelCountsLoadOneAfterAnother() throws {
    let player = AudioPlayer()
    try player.load(TestAudio.file("tone.wav"))
    try player.load(TestAudio.file("mono48.wav"))
    #expect(player.formatInfo?.sampleRate == 48000 && player.formatInfo?.channels == 1)
    try player.load(TestAudio.file("tone.flac"))
    #expect(player.formatInfo?.sampleRate == 44100 && player.formatInfo?.channels == 2)
}

@Test func seekingWhileStoppedMovesThePositionAndClamps() throws {
    let player = AudioPlayer()
    try player.load(TestAudio.file("long.wav"))
    player.seek(to: 2.5)
    #expect(abs(player.currentTime - 2.5) < 0.01)
    player.seek(to: 999)
    #expect(player.currentTime <= player.duration)
    player.seek(to: -5)
    #expect(player.currentTime == 0)
    player.seek(to: .nan)
    #expect(player.currentTime == 0)
}

@Test func volumeIsClampedAndRemembered() {
    let player = AudioPlayer()
    player.volume = 0.3
    #expect(abs(player.volume - 0.3) < 0.001)
    player.volume = 5
    #expect(player.volume == 1)
    player.volume = -1
    #expect(player.volume == 0)
}

/// Plays through the real audio engine with the volume at zero, so nothing is heard.
@Test func playbackAdvancesSuppliesSamplesAndReportsTheEnd() async throws {
    let queue = DispatchQueue(label: "test.callbacks")
    let player = AudioPlayer(callbackQueue: queue)
    player.volume = 0
    try player.load(TestAudio.file("tone.wav"))
    let finished = LockedFlag()
    player.onFinished = { finished.set() }
    player.play()
    #expect(player.isPlaying)

    try await Task.sleep(for: .milliseconds(450))
    let midway = player.currentTime
    #expect(midway > 0.15 && midway < 0.9, "\(midway)")
    var samples = [Float](repeating: 0, count: 1024)
    let rate = samples.withUnsafeMutableBufferPointer { player.monoSamples(count: 1024, into: $0) }
    #expect(rate == 44100)
    #expect(samples.contains { abs($0) > 0.05 }, "visualizer samples are silent while a tone plays")

    for _ in 0..<40 where !finished.isSet { try await Task.sleep(for: .milliseconds(100)) }
    #expect(finished.isSet, "onFinished was not called within 4 seconds of a 1 second file")
    #expect(!player.isPlaying)
}

@Test func pauseHoldsThePositionAndSeekWhilePlayingJumps() async throws {
    let player = AudioPlayer(callbackQueue: DispatchQueue(label: "test.callbacks2"))
    player.volume = 0
    try player.load(TestAudio.file("long.wav"))
    player.play()
    try await Task.sleep(for: .milliseconds(300))
    player.pause()
    let held = player.currentTime
    #expect(held > 0.1 && !player.isPlaying)
    try await Task.sleep(for: .milliseconds(250))
    #expect(player.currentTime == held)
    player.play()
    player.seek(to: 4)
    try await Task.sleep(for: .milliseconds(300))
    let after = player.currentTime
    #expect(after > 4.05 && after < 5, "\(after)")
    player.stop()
    #expect(player.currentTime == 0 && !player.isPlaying)
    var samples = [Float](repeating: 0, count: 64)
    #expect(samples.withUnsafeMutableBufferPointer { player.monoSamples(count: 64, into: $0) } == nil)
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

// MARK: Damaged files

/// A copy of a fixture cut off after `bytes` bytes.
private func truncated(_ name: String, bytes: Int) throws -> URL {
    let source = TestAudio.file(name)
    let data = try Data(contentsOf: source).prefix(bytes)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("macamp-cut-\(UUID().uuidString).\(source.pathExtension)")
    try Data(data).write(to: url)
    return url
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@Test func aFileWithAHeaderButNoAudioIsRejected() throws {
    let url = try truncated("long.flac", bytes: 120)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: (any Error).self) { try AudioPlayer().load(url) }
}

@Test func playingPastTheEndOfATruncatedFileEndsInsteadOfHanging() async throws {
    let size = try Data(contentsOf: TestAudio.file("long.flac")).count
    let url = try truncated("long.flac", bytes: size / 2)
    defer { try? FileManager.default.removeItem(at: url) }
    let player = AudioPlayer(callbackQueue: DispatchQueue(label: "test.callbacks3"))
    player.volume = 0
    try player.load(url)
    let finished = LockedFlag()
    player.onFinished = { finished.set() }
    player.seek(to: 5.5)               // the header claims 6 seconds; the audio stops near 3
    player.play()
    for _ in 0..<25 where !finished.isSet { try await Task.sleep(for: .milliseconds(100)) }
    #expect(finished.isSet, "the player is stuck on a position with no audio behind it")
    #expect(!player.isPlaying)
}

@Test func anEndReportedLateForAnEarlierFileIsDropped() async throws {
    let callbacks = DispatchQueue(label: "test.held")
    let player = AudioPlayer(callbackQueue: callbacks)
    player.volume = 0
    let reports = LockedCounter()
    player.onFinished = { reports.increment() }
    try player.load(TestAudio.file("tone.wav"))
    player.play()
    let gate = DispatchSemaphore(value: 0)
    callbacks.async { gate.wait() }    // hold the queue that end-of-track reports arrive on
    player.seek(to: 999)               // ends the first file; its report is now waiting behind the gate
    try await Task.sleep(for: .milliseconds(150))
    try player.load(TestAudio.file("long.wav"))
    player.play()
    gate.signal()
    try await Task.sleep(for: .milliseconds(300))
    #expect(reports.value == 0, "the first file's end was reported against the second file")
    #expect(player.isPlaying)
    player.stop()
}
