import Foundation
import Testing
@testable import MacampCore

@Test(arguments: [("tagged.mp3", "Tagged Title", "Tagged Artist"), ("tagged.flac", "Flac Title", "Flac Artist"),
                  ("tagged.m4a", "M4A Title", "M4A Artist")])
func tagsAreReadFromEachTaggedFormat(name: String, title: String, artist: String) throws {
    guard TestAudio.has(name) else { return }       // tagged files need lame or ffmpeg to generate
    let info = try #require(TrackMetadata.read(TestAudio.file(name)))
    #expect(info.title == title && info.artist == artist)
    #expect(abs((info.duration ?? 0) - 1.0) < 0.1)
}

@Test func albumIsReadWhenPresent() throws {
    guard TestAudio.has("tagged.mp3") else { return }
    let info = try #require(TrackMetadata.read(TestAudio.file("tagged.mp3")))
    #expect(info.album == "Tagged Album")
}

@Test func untaggedFilesGiveNoTagsButADuration() throws {
    let info = try #require(TrackMetadata.read(TestAudio.file("tone.wav")))
    #expect(info.title == nil && info.artist == nil && info.album == nil)
    #expect(abs((info.duration ?? 0) - 1.0) < 0.05)
}

@Test func unreadableFilesGiveNil() {
    #expect(TrackMetadata.read(TestAudio.file("fake.mp3")) == nil)
    #expect(TrackMetadata.read(TestAudio.file("empty.wav")) == nil)
    #expect(TrackMetadata.read(TestAudio.file("missing.flac")) == nil)
}
