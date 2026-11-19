import Foundation
import Testing
@testable import MacampCore

func urls(_ names: String...) -> [URL] { names.map { URL(fileURLWithPath: "/music/\($0).mp3") } }

private func names(_ p: Playlist) -> [String] { p.tracks.map { $0.url.deletingPathExtension().lastPathComponent } }

@Test func appendReturnsTheNewRange() {
    let p = Playlist()
    #expect(p.append(urls("a", "b")) == 0..<2)
    #expect(p.append(urls("c")) == 2..<3)
    #expect(names(p) == ["a", "b", "c"])
    #expect(p.currentIndex == nil)
    #expect(Set(p.tracks.map(\.id)).count == 3)
}

@Test func removingBeforeAtAndAfterTheCurrentTrack() {
    let p = Playlist()
    p.append(urls("a", "b", "c", "d"))
    p.currentID = p.tracks[2].id
    p.remove(at: [0])
    #expect(names(p) == ["b", "c", "d"])
    #expect(p.currentIndex == 1)
    p.remove(at: [2])
    #expect(p.currentIndex == 1)
    p.remove(at: [1])
    #expect(names(p) == ["b"])
    #expect(p.currentID == nil)
    #expect(p.currentIndex == nil)
    p.remove(at: [5, 9])          // out of range is ignored
    #expect(names(p) == ["b"])
}

@Test func moveKeepsTheCurrentTrackAndReportsNewPositions() {
    let p = Playlist()
    p.append(urls("a", "b", "c", "d", "e"))
    p.currentID = p.tracks[1].id
    #expect(p.move(from: [0, 1], to: 4) == IndexSet(2...3))
    #expect(names(p) == ["c", "d", "a", "b", "e"])
    #expect(p.currentIndex == 3)
    #expect(p.move(from: [4], to: 0) == IndexSet(integer: 0))
    #expect(names(p) == ["e", "c", "d", "a", "b"])
    #expect(p.move(from: [1], to: 99) == IndexSet(integer: 4))
    #expect(names(p) == ["e", "d", "a", "b", "c"])
    #expect(p.move(from: [2], to: 2) == IndexSet(integer: 2))   // dropping in place changes nothing
    #expect(names(p) == ["e", "d", "a", "b", "c"])
}

@Test func clearUpdateAndReplace() {
    let p = Playlist()
    p.append(urls("a", "b"))
    let id = p.tracks[1].id
    p.update(id: id) { $0.title = "Bee"; $0.unplayable = true }
    #expect(p.tracks[1].title == "Bee" && p.tracks[1].unplayable)
    p.update(id: UUID()) { $0.title = "nobody" }   // unknown id is ignored
    p.currentID = id
    p.clear()
    #expect(p.tracks.isEmpty && p.currentID == nil)
    let saved = [Track(url: urls("x")[0]), Track(url: urls("y")[0])]
    p.replaceAll(saved, currentID: saved[1].id)
    #expect(p.currentIndex == 1)
    p.replaceAll(saved, currentID: UUID())         // a current id that is not in the list is dropped
    #expect(p.currentID == nil)
}
