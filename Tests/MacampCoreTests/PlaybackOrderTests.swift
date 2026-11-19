import Foundation
import Testing
@testable import MacampCore

private let ids = (0..<5).map { _ in UUID() }

@Test func inOrderNextAndEndOfList() {
    var o = PlaybackOrder()
    #expect(o.next(in: ids, current: nil, auto: false) == ids[0])
    #expect(o.next(in: ids, current: ids[0], auto: true) == ids[1])
    #expect(o.next(in: ids, current: ids[4], auto: true) == nil)
    #expect(o.next(in: ids, current: ids[4], auto: false) == nil)
    #expect(o.next(in: [], current: nil, auto: false) == nil)
    #expect(o.next(in: ids, current: UUID(), auto: true) == ids[0])   // current no longer in the list
}

@Test func repeatAllWrapsAround() {
    var o = PlaybackOrder()
    o.repeatMode = .all
    #expect(o.next(in: ids, current: ids[4], auto: true) == ids[0])
    #expect(o.previous(in: ids, current: ids[0]) == ids[4])
}

@Test func repeatOneReplaysOnlyOnNaturalEnd() {
    var o = PlaybackOrder()
    o.repeatMode = .one
    #expect(o.next(in: ids, current: ids[2], auto: true) == ids[2])
    #expect(o.next(in: ids, current: ids[2], auto: false) == ids[3])
    #expect(o.next(in: ids, current: ids[4], auto: false) == ids[0])
}

@Test func previousInOrder() {
    var o = PlaybackOrder()
    #expect(o.previous(in: ids, current: ids[2]) == ids[1])
    #expect(o.previous(in: ids, current: ids[0]) == ids[0])
    #expect(o.previous(in: ids, current: nil) == ids[0])
    #expect(o.previous(in: [], current: nil) == nil)
}

@Test func shuffleVisitsEveryTrackOnceThenStops() {
    let many = (0..<50).map { _ in UUID() }
    var o = PlaybackOrder()
    o.shuffle = true
    var seen: [UUID] = []
    var current: UUID?
    while let next = o.next(in: many, current: current, auto: true) {
        o.noteStarted(next)
        seen.append(next)
        current = next
        if seen.count > 60 { break }
    }
    #expect(seen.count == 50)
    #expect(Set(seen) == Set(many))
}

@Test func shuffleWithRepeatAllStartsANewRoundWithADifferentTrack() {
    let many = (0..<50).map { _ in UUID() }
    var o = PlaybackOrder()
    o.shuffle = true
    o.repeatMode = .all
    var seen: [UUID] = []
    var current: UUID?
    for _ in 0..<150 {
        let next = o.next(in: many, current: current, auto: true)!
        #expect(next != current)
        o.noteStarted(next)
        seen.append(next)
        current = next
    }
    #expect(Set(seen[0..<50]).count == 50)
    #expect(Set(seen[50..<100]).count == 50)
    #expect(Set(seen[100..<150]).count == 50)
}

@Test func shuffleSurvivesTracksRemovedMidRound() {
    var list = (0..<6).map { _ in UUID() }
    var o = PlaybackOrder()
    o.shuffle = true
    let first = o.next(in: list, current: nil, auto: true)!
    o.noteStarted(first)
    list.removeAll { $0 != first }
    list.append(contentsOf: [UUID(), UUID()])
    var seen: Set<UUID> = [first]
    var current = first
    while let next = o.next(in: list, current: current, auto: true) {
        #expect(list.contains(next))
        o.noteStarted(next)
        seen.insert(next)
        current = next
        if seen.count > 10 { break }
    }
    #expect(seen == Set(list))
}

@Test func shufflePreviousWalksBackThroughHistory() {
    var o = PlaybackOrder()
    o.shuffle = true
    var played: [UUID] = []
    var current: UUID?
    for _ in 0..<4 {
        let next = o.next(in: ids, current: current, auto: true)!
        o.noteStarted(next); played.append(next); current = next
    }
    let back1 = o.previous(in: ids, current: played[3])
    #expect(back1 == played[2])
    o.noteStarted(back1!)
    #expect(o.previous(in: ids, current: back1) == played[1])
}

@Test func shuffleWithOneTrack() {
    let one = [UUID()]
    var o = PlaybackOrder()
    o.shuffle = true
    #expect(o.next(in: one, current: nil, auto: true) == one[0])
    o.noteStarted(one[0])
    #expect(o.next(in: one, current: one[0], auto: true) == nil)
    o.repeatMode = .all
    #expect(o.next(in: one, current: one[0], auto: true) == one[0])
}
