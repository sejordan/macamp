import CoreGraphics
import Foundation
import Testing
@testable import MacampCore

private func layout(_ elements: [String], window: String = #"{"size": [300, 200], "resize": "vertical"}"#,
                    height: CGFloat = 200) throws -> SkinLayout {
    let result = parse(skinJSON(window: window, elements: elements))
    let skin = try #require(result.skin, "\(result.errors)")
    return SkinLayout(skin: skin, windowHeight: height)
}

@Test func anchorsMoveAndStretchWithWindowHeight() throws {
    let l = try layout([
        #"{"type": "rect", "frame": [0, 0, 300, 50]}"#,
        #"{"type": "rect", "frame": [0, 180, 300, 20], "anchor": "bottom"}"#,
        #"{"type": "playlist", "frame": [0, 50, 300, 130], "anchor": "stretch"}"#,
    ], height: 260)
    #expect(l.frames[0] == CGRect(x: 0, y: 0, width: 300, height: 50))
    #expect(l.frames[1] == CGRect(x: 0, y: 240, width: 300, height: 20))
    #expect(l.frames[2] == CGRect(x: 0, y: 50, width: 300, height: 190))
}

@Test func framesAreUnchangedAtTheSkinsOwnHeight() throws {
    let l = try layout([#"{"type": "playlist", "frame": [0, 50, 300, 130], "anchor": "stretch"}"#])
    #expect(l.frames[0] == CGRect(x: 0, y: 50, width: 300, height: 130))
}

@Test func stretchNeverCollapsesBelowOnePoint() throws {
    let l = try layout([#"{"type": "playlist", "frame": [0, 50, 300, 20], "anchor": "stretch"}"#],
                       window: #"{"size": [300, 200], "resize": "vertical", "minHeight": 100}"#, height: 100)
    #expect(l.frames[0].height == 1)
}

@Test func hitTestingReturnsTopmostInteractiveElement() throws {
    let l = try layout([
        #"{"type": "button", "frame": [10, 10, 40, 40], "action": "play"}"#,
        #"{"type": "button", "frame": [30, 30, 40, 40], "action": "stop"}"#,
        #"{"type": "rect", "frame": [0, 0, 300, 200]}"#,
        #"{"type": "text", "frame": [100, 0, 50, 20], "text": "plain"}"#,
        #"{"type": "text", "frame": [200, 0, 50, 20], "text": "{time}", "action": "toggleTime"}"#,
        #"{"type": "visualizer", "frame": [100, 100, 50, 20]}"#,
    ])
    #expect(l.interactiveElement(at: CGPoint(x: 15, y: 15)) == 0)
    #expect(l.interactiveElement(at: CGPoint(x: 40, y: 40)) == 1)   // overlap: later wins
    #expect(l.interactiveElement(at: CGPoint(x: 150, y: 150)) == nil) // decoration only
    #expect(l.interactiveElement(at: CGPoint(x: 110, y: 10)) == nil)  // text without action
    #expect(l.interactiveElement(at: CGPoint(x: 210, y: 10)) == 4)
    #expect(l.interactiveElement(at: CGPoint(x: 110, y: 110)) == 5)
    #expect(l.interactiveElement(at: CGPoint(x: -5, y: -5)) == nil)
}

@Test func horizontalSliderValueAccountsForThumbAndClamps() throws {
    let l = try layout([
        #"{"type": "slider", "frame": [100, 10, 110, 10], "binds": "seek", "thumb": {"size": [10, 10]}}"#,
        #"{"type": "slider", "frame": [100, 40, 100, 4], "binds": "seek"}"#,
    ])
    #expect(l.sliderValue(element: 0, at: CGPoint(x: 105, y: 15)) == 0)
    #expect(l.sliderValue(element: 0, at: CGPoint(x: 155, y: 15)) == 0.5)
    #expect(l.sliderValue(element: 0, at: CGPoint(x: 205, y: 15)) == 1)
    #expect(l.sliderValue(element: 0, at: CGPoint(x: 0, y: 15)) == 0)
    #expect(l.sliderValue(element: 0, at: CGPoint(x: 999, y: 15)) == 1)
    #expect(l.sliderValue(element: 1, at: CGPoint(x: 125, y: 42)) == 0.25)   // no thumb: full width
}

@Test func verticalSliderRunsBottomToTop() throws {
    let l = try layout([#"{"type": "slider", "frame": [10, 20, 10, 100], "binds": "volume"}"#])
    #expect(l.sliderValue(element: 0, at: CGPoint(x: 15, y: 120)) == 0)
    #expect(l.sliderValue(element: 0, at: CGPoint(x: 15, y: 20)) == 1)
    #expect(l.sliderValue(element: 0, at: CGPoint(x: 15, y: 95)) == 0.25)
    #expect(l.sliderValue(element: 0, at: CGPoint(x: 15, y: 500)) == 0)
}

@Test func sliderGeometryPlacesProgressAndThumb() throws {
    let l = try layout([
        #"{"type": "slider", "frame": [100, 10, 110, 10], "binds": "seek", "track": {"thickness": 4}, "thumb": {"size": [10, 10]}}"#,
    ])
    let g = l.sliderGeometry(element: 0, value: 0.5)
    #expect(g.track == CGRect(x: 100, y: 13, width: 110, height: 4))
    #expect(g.thumb == CGRect(x: 150, y: 10, width: 10, height: 10))
    #expect(g.progress == CGRect(x: 100, y: 13, width: 55, height: 4))
}

@Test func playlistRowLookupHonorsScroll() throws {
    let l = try layout([#"{"type": "playlist", "frame": [0, 100, 300, 100], "rowHeight": 20}"#])
    #expect(l.playlistRow(element: 0, at: CGPoint(x: 10, y: 105), scroll: 0, count: 50) == 0)
    #expect(l.playlistRow(element: 0, at: CGPoint(x: 10, y: 145), scroll: 0, count: 50) == 2)
    #expect(l.playlistRow(element: 0, at: CGPoint(x: 10, y: 145), scroll: 30, count: 50) == 3)
    #expect(l.playlistRow(element: 0, at: CGPoint(x: 10, y: 145), scroll: 0, count: 2) == nil)
    #expect(l.playlistRow(element: 0, at: CGPoint(x: 10, y: 50), scroll: 0, count: 50) == nil)
    #expect(l.maxPlaylistScroll(element: 0, count: 50) == 900)
    #expect(l.maxPlaylistScroll(element: 0, count: 3) == 0)
}

@Test func insertionIndexSwitchesAtRowMidpoints() throws {
    let l = try layout([#"{"type": "playlist", "frame": [0, 100, 300, 100], "rowHeight": 20}"#])
    #expect(l.playlistInsertionIndex(element: 0, at: CGPoint(x: 10, y: 109), scroll: 0, count: 5) == 0)
    #expect(l.playlistInsertionIndex(element: 0, at: CGPoint(x: 10, y: 111), scroll: 0, count: 5) == 1)
    #expect(l.playlistInsertionIndex(element: 0, at: CGPoint(x: 10, y: 199), scroll: 0, count: 5) == 5)
    #expect(l.playlistInsertionIndex(element: 0, at: CGPoint(x: 10, y: 199), scroll: 0, count: 2) == 2)
    #expect(l.playlistInsertionIndex(element: 0, at: CGPoint(x: 10, y: 0), scroll: 0, count: 5) == 0)
}

@Test func sliderRepaintKeyChangesAsTheValueMovesInEitherOrientation() throws {
    let l = try layout([
        #"{"type": "slider", "frame": [10, 10, 100, 10], "binds": "seek"}"#,
        #"{"type": "slider", "frame": [10, 40, 10, 100], "binds": "seek"}"#,
    ])
    for element in 0...1 {
        #expect(l.sliderRepaintKey(element: element, value: 0.2) != l.sliderRepaintKey(element: element, value: 0.6))
        #expect(l.sliderRepaintKey(element: element, value: 0.5) == l.sliderRepaintKey(element: element, value: 0.5001))
    }
}
