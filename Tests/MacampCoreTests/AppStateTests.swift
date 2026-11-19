import Foundation
import Testing
@testable import MacampCore

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("macamp-state-\(UUID().uuidString)/state.json")
}

@Test func defaultsAreSensible() {
    let s = AppState.default
    #expect(s.tracks.isEmpty && s.currentID == nil)
    #expect(s.volume == 0.8)
    #expect(s.skin == "Phosphor")
    #expect(s.shuffle == false && s.repeatMode == .off)
    #expect(s.showRemaining == false && s.scopeMode == false)
    #expect(AppState.defaultURL.path.hasSuffix("Library/Application Support/macamp/state.json"))
}

@Test func stateRoundTripsThroughAFile() throws {
    var s = AppState.default
    var track = Track(url: URL(fileURLWithPath: "/music/夜 song.flac"))
    track.title = "Song"; track.artist = "Artist"; track.duration = 12.5; track.metadataLoaded = true
    s.tracks = [track, Track(url: URL(fileURLWithPath: "/music/b.mp3"))]
    s.currentID = track.id
    s.volume = 0.33; s.shuffle = true; s.repeatMode = .one
    s.skin = "/Users/me/skins/mine.json"
    s.windowOrigin = [120, 340]; s.windowHeight = 420
    s.showRemaining = true; s.scopeMode = true
    let url = tempFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try s.save(to: url)                      // creates the folder
    #expect(AppState.load(from: url) == s)
    try s.save(to: url)                      // overwrites
    #expect(AppState.load(from: url) == s)
}

@Test func missingOrCorruptFilesGiveDefaults() throws {
    let url = tempFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    #expect(AppState.load(from: url) == .default)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    for junk in ["", "{", "[1,2,3]", "{\"volume\": \"loud\"}"] {
        try Data(junk.utf8).write(to: url)
        #expect(AppState.load(from: url) == .default, "\(junk)")
    }
}

@Test func olderFilesMissingNewerKeysStillLoad() throws {
    let url = tempFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"volume": 0.5, "skin": "Rack Unit", "futureKey": true}"#.utf8).write(to: url)
    let s = AppState.load(from: url)
    #expect(s.volume == 0.5 && s.skin == "Rack Unit")
    #expect(s.tracks.isEmpty && s.repeatMode == .off && s.windowOrigin == nil)
}

@Test func outOfRangeValuesAreClamped() throws {
    let url = tempFile()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"volume": 7, "windowOrigin": [1], "windowHeight": -3}"#.utf8).write(to: url)
    let s = AppState.load(from: url)
    #expect(s.volume == 1)
    #expect(s.windowOrigin == nil && s.windowHeight == nil)
}
