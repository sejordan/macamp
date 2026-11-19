import Foundation
import Testing
@testable import MacampCore

private func scratch() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-welcome-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Test func theWelcomeTrackIsCopiedIntoTheSupportFolder() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let bundled = root.appendingPathComponent("bundle/macamp.mp3")
    try FileManager.default.createDirectory(at: bundled.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("audio".utf8).write(to: bundled)
    let support = root.appendingPathComponent("support/nested")       // does not exist yet

    let installed = try #require(WelcomeTrack.install(from: bundled, into: support))
    #expect(installed.deletingLastPathComponent().standardizedFileURL == support.standardizedFileURL)
    #expect(installed.lastPathComponent == "macamp.mp3")
    #expect(try Data(contentsOf: installed) == Data("audio".utf8))
}

@Test func anExistingCopyIsReusedNotOverwritten() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let bundled = root.appendingPathComponent("macamp.mp3")
    try Data("new".utf8).write(to: bundled)
    let support = root.appendingPathComponent("support")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    try Data("already here".utf8).write(to: support.appendingPathComponent("macamp.mp3"))

    let installed = try #require(WelcomeTrack.install(from: bundled, into: support))
    #expect(try Data(contentsOf: installed) == Data("already here".utf8))
}

@Test func noBundledTrackMeansNoWelcomeTrack() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(WelcomeTrack.install(from: nil, into: root) == nil)
    #expect(WelcomeTrack.install(from: root.appendingPathComponent("missing.mp3"), into: root) == nil)
    #expect((try FileManager.default.contentsOfDirectory(atPath: root.path)).isEmpty)
}

@Test func aSupportFolderThatCannotBeCreatedGivesNil() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let bundled = root.appendingPathComponent("macamp.mp3")
    try Data("audio".utf8).write(to: bundled)
    let blocker = root.appendingPathComponent("file-not-folder")
    try Data().write(to: blocker)
    #expect(WelcomeTrack.install(from: bundled, into: blocker.appendingPathComponent("support")) == nil)
}
