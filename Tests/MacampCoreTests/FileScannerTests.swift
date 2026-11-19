import Foundation
import Testing
@testable import MacampCore

private func makeTree() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-scan-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("Album B/Disc 2"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("Album A"), withIntermediateDirectories: true)
    for path in ["Album A/10 a.mp3", "Album A/2 b.MP3", "Album A/cover.jpg", "Album A/.hidden.mp3",
                 "Album B/1.flac", "Album B/Disc 2/1.m4a", "Album B/notes.txt", "z.wav", "skin.json"] {
        fm.createFile(atPath: root.appendingPathComponent(path).path, contents: Data())
    }
    return root
}

@Test func foldersAreScannedRecursivelyInNaturalOrder() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let found = FileScanner.expand([root]).map { $0.path.components(separatedBy: root.lastPathComponent + "/").last! }
    #expect(found == ["Album A/2 b.MP3", "Album A/10 a.mp3", "Album B/1.flac", "Album B/Disc 2/1.m4a", "z.wav"])
}

@Test func givenOrderIsKeptAndNonAudioAndMissingFilesAreDropped() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let picked = [root.appendingPathComponent("z.wav"), root.appendingPathComponent("Album A/cover.jpg"),
                  root.appendingPathComponent("gone.mp3"), root.appendingPathComponent("Album B/1.flac")]
    #expect(FileScanner.expand(picked).map(\.lastPathComponent) == ["z.wav", "1.flac"])
    #expect(FileScanner.expand([]).isEmpty)
}

@Test func skinFilesAreRecognizedByExtension() {
    #expect(FileScanner.isSkinFile(URL(fileURLWithPath: "/x/My Skin.JSON")))
    #expect(!FileScanner.isSkinFile(URL(fileURLWithPath: "/x/song.mp3")))
    #expect(FileScanner.audioExtensions.isSuperset(of: ["mp3", "m4a", "flac", "wav", "aiff", "aif", "caf", "aac"]))
}
