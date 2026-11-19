import AppKit
import Testing
@testable import macamp
@testable import MacampCore

final class StubAudio: AudioPlaying {
    var onFinished: (() -> Void)?
    var volume = 1.0
    var isPlaying = false
    var currentTime = 0.0
    var duration = 100.0
    var formatInfo: AudioFormatInfo?
    var loaded: [String] = []
    func load(_ url: URL) throws { loaded.append(url.deletingPathExtension().lastPathComponent); currentTime = 0 }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false; currentTime = 0 }
    func seek(to seconds: Double) { currentTime = seconds }
    func monoSamples(count: Int, into: UnsafeMutableBufferPointer<Float>) -> Double? { nil }
}

/// A skin with one of everything at known positions, in a 300 by 300 window.
private let testSkin = ##"""
{"format": 1, "name": "T", "window": {"size": [300, 300], "titleBar": "none"},
 "elements": [
  {"type": "button", "frame": [10, 10, 30, 20], "action": "play"},
  {"type": "button", "frame": [50, 10, 30, 20], "action": "next"},
  {"type": "button", "frame": [90, 10, 30, 20], "action": "shuffle"},
  {"type": "text", "frame": [130, 10, 60, 20], "text": "{time}", "action": "toggleTime"},
  {"type": "visualizer", "frame": [200, 10, 90, 20]},
  {"type": "slider", "frame": [10, 40, 100, 10], "binds": "seek"},
  {"type": "slider", "frame": [150, 40, 100, 10], "binds": "volume"},
  {"type": "rect", "frame": [0, 60, 300, 30], "fill": "#222222"},
  {"type": "playlist", "frame": [0, 100, 300, 200], "rowHeight": 20}
 ]}
"""##

@MainActor
private final class Rig {
    let audio = StubAudio()
    let controller: PlayerController
    let view: SkinView
    let window: NSWindow
    var actions: [ButtonAction] = []
    var dropped: [[URL]] = []

    init(tracks: Int = 6) {
        _ = NSApplication.shared
        controller = PlayerController(audio: audio)
        let skin = SkinParser.parse(data: Data(testSkin.utf8)).skin!
        view = SkinView(controller: controller, skin: skin, height: 300)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless],
                          backing: .buffered, defer: true)
        window.contentView = view
        view.onAction = { [unowned self] in self.actions.append($0) }
        view.onDrop = { [unowned self] in self.dropped.append($0) }
        controller.onChange = { [unowned self] in self.view.controllerChanged() }
        let urls = (0..<tracks).map { URL(fileURLWithPath: "/music/t\($0).mp3") }
        controller.add(urls, playFirstNew: false, playIfIdle: false)
    }

    /// `x` and `y` are in skin coordinates, from the top-left.
    func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, clicks: Int = 1,
               flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 300 - y), modifierFlags: flags, timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    func click(_ x: CGFloat, _ y: CGFloat, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) {
        view.mouseDown(with: mouse(.leftMouseDown, x, y, clicks: clicks, flags: flags))
        view.mouseUp(with: mouse(.leftMouseUp, x, y, clicks: clicks, flags: flags))
    }

    func drag(from a: CGPoint, to b: CGPoint, steps: Int = 4) {
        view.mouseDown(with: mouse(.leftMouseDown, a.x, a.y))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            view.mouseDragged(with: mouse(.leftMouseDragged, a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
        }
        view.mouseUp(with: mouse(.leftMouseUp, b.x, b.y))
    }

    func key(_ code: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = []) {
        view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                            windowNumber: window.windowNumber, context: nil, characters: characters,
                                            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
    }

    var names: [String] { controller.playlist.tracks.map { $0.url.deletingPathExtension().lastPathComponent } }
}

@MainActor @Test func clickingAButtonRunsItsAction() {
    let rig = Rig()
    rig.click(20, 20)
    rig.click(60, 20)
    #expect(rig.actions == [.play, .next])
}

@MainActor @Test func releasingOutsideAButtonCancelsTheClick() {
    let rig = Rig()
    rig.view.mouseDown(with: rig.mouse(.leftMouseDown, 20, 20))
    rig.view.mouseUp(with: rig.mouse(.leftMouseUp, 200, 200))
    rig.view.mouseDown(with: rig.mouse(.leftMouseDown, 20, 20))
    rig.view.mouseDragged(with: rig.mouse(.leftMouseDragged, 200, 80))
    rig.view.mouseDragged(with: rig.mouse(.leftMouseDragged, 20, 20))
    rig.view.mouseUp(with: rig.mouse(.leftMouseUp, 20, 20))
    #expect(rig.actions.isEmpty)
}

@MainActor @Test func clickableTextAndVisualizerRunTheirActions() {
    let rig = Rig()
    rig.click(150, 20)
    rig.click(240, 20)
    #expect(rig.actions == [.toggleTime, .toggleVisualizer])
}

@MainActor @Test func clickingDecorationOrEmptySpaceDoesNothing() {
    let rig = Rig()
    rig.click(150, 75)      // the rect
    rig.click(280, 45)      // empty space
    #expect(rig.actions.isEmpty && rig.view.selection.isEmpty)
}

@MainActor @Test func draggingTheVolumeSliderChangesVolumeLive() {
    let rig = Rig()
    rig.view.mouseDown(with: rig.mouse(.leftMouseDown, 200, 45))
    #expect(abs(rig.controller.volume - 0.5) < 0.01)
    rig.view.mouseDragged(with: rig.mouse(.leftMouseDragged, 175, 45))
    #expect(abs(rig.controller.volume - 0.25) < 0.01)
    rig.view.mouseDragged(with: rig.mouse(.leftMouseDragged, 999, 45))
    #expect(rig.controller.volume == 1)
    rig.view.mouseUp(with: rig.mouse(.leftMouseUp, 999, 45))
    #expect(rig.controller.volume == 1)
}

@MainActor @Test func seekAppliesOnlyWhenTheMouseIsReleased() {
    let rig = Rig()
    rig.controller.play()
    rig.view.mouseDown(with: rig.mouse(.leftMouseDown, 20, 45))
    rig.view.mouseDragged(with: rig.mouse(.leftMouseDragged, 60, 45))
    #expect(rig.audio.currentTime == 0)
    rig.view.mouseUp(with: rig.mouse(.leftMouseUp, 60, 45))
    #expect(abs(rig.audio.currentTime - 50) < 0.5)
}

@MainActor @Test func playlistClickSelectsAndDoubleClickPlays() {
    let rig = Rig()
    rig.click(50, 150)                       // row 2
    #expect(rig.view.selection == [2])
    #expect(rig.controller.status == .stopped)
    rig.click(50, 130, clicks: 2)            // row 1
    #expect(rig.controller.status == .playing && rig.controller.playlist.currentIndex == 1)
    rig.click(50, 290)                       // below the last row
    #expect(rig.view.selection.isEmpty)
}

@MainActor @Test func shiftAndCommandClickExtendTheSelection() {
    let rig = Rig()
    rig.click(50, 110)
    rig.click(50, 170, flags: .shift)
    #expect(rig.view.selection == IndexSet(0...3))
    rig.click(50, 130, flags: .command)
    #expect(rig.view.selection == [0, 2, 3])
    rig.click(50, 210, flags: .command)
    #expect(rig.view.selection == [0, 2, 3, 5])
    rig.click(50, 150)                       // plain click on a selected row collapses to it
    #expect(rig.view.selection == [2])
}

@MainActor @Test func draggingARowReordersThePlaylistAndKeepsItSelected() {
    let rig = Rig()
    rig.controller.playTrack(at: 0)
    rig.drag(from: CGPoint(x: 50, y: 110), to: CGPoint(x: 50, y: 172))    // row 0 to between rows 3 and 4
    #expect(rig.names == ["t1", "t2", "t3", "t0", "t4", "t5"])
    #expect(rig.view.selection == [3])
    #expect(rig.controller.playlist.currentIndex == 3)
}

@MainActor @Test func draggingSeveralSelectedRowsMovesThemTogether() {
    let rig = Rig()
    rig.click(50, 110)
    rig.click(50, 130, flags: .shift)
    rig.drag(from: CGPoint(x: 50, y: 130), to: CGPoint(x: 50, y: 219))    // rows 0-1 to the end
    #expect(rig.names == ["t2", "t3", "t4", "t5", "t0", "t1"])
    #expect(rig.view.selection == [4, 5])
}

@MainActor @Test func aTinyMouseWobbleIsAClickNotADrag() {
    let rig = Rig()
    rig.drag(from: CGPoint(x: 50, y: 150), to: CGPoint(x: 51, y: 151))
    #expect(rig.names == ["t0", "t1", "t2", "t3", "t4", "t5"])
    #expect(rig.view.selection == [2])
}

@MainActor @Test func keyboardTransportAndSeekAndVolume() {
    let rig = Rig()
    rig.key(49, " ")
    rig.key(6, "z"); rig.key(7, "x"); rig.key(8, "c"); rig.key(9, "v"); rig.key(11, "b")
    #expect(rig.actions == [.playPause, .previous, .play, .pause, .stop, .next])
    rig.controller.play()
    rig.key(124)
    #expect(rig.audio.currentTime == 5)
    rig.key(123)
    #expect(rig.audio.currentTime == 0)
    rig.controller.volume = 0.5
    rig.key(126)
    #expect(abs(rig.controller.volume - 0.55) < 0.001)
    rig.key(125); rig.key(125)
    #expect(abs(rig.controller.volume - 0.45) < 0.001)
}

@MainActor @Test func returnPlaysAndDeleteRemovesTheSelection() {
    let rig = Rig()
    rig.click(50, 170)
    rig.key(36, "\r")
    #expect(rig.controller.playlist.currentIndex == 3 && rig.controller.status == .playing)
    rig.click(50, 110)
    rig.click(50, 130, flags: .shift)
    rig.key(51)
    #expect(rig.names == ["t2", "t3", "t4", "t5"])
    #expect(rig.view.selection.isEmpty)
    #expect(rig.controller.playlist.currentIndex == 1)
    rig.key(51)                              // nothing selected: nothing happens
    #expect(rig.names.count == 4)
}

@MainActor @Test func selectAllThenDeleteEmptiesThePlaylistAndStops() {
    let rig = Rig()
    rig.controller.play()
    rig.view.selectAllRows()
    #expect(rig.view.selection == IndexSet(0...5))
    rig.view.removeSelectedRows()
    #expect(rig.names.isEmpty && rig.controller.status == .stopped)
}

@MainActor @Test func keysWithCommandHeldAreLeftForTheMenus() {
    let rig = Rig()
    rig.key(49, " ", flags: .command)
    rig.key(6, "z", flags: .command)
    #expect(rig.actions.isEmpty)
}

@MainActor @Test func selectionShrinksWhenThePlaylistDoes() {
    let rig = Rig()
    rig.view.selectAllRows()
    rig.controller.remove(at: [4, 5])
    #expect(rig.view.selection == IndexSet(0...3))
    rig.controller.clear()
    #expect(rig.view.selection.isEmpty)
}

@MainActor @Test func theViewDrawsAndSnapshotsWithoutAWindowOnScreen() {
    let rig = Rig(tracks: 1000)
    rig.controller.playTrack(at: 999)        // scrolls the current row into view
    let png = rig.view.snapshotPNG()
    #expect((png?.count ?? 0) > 1000)
    rig.view.errorBanner = "elements[0].frame: expected 4 numbers, got 3"
    rig.view.scopeMode = true
    #expect(rig.view.snapshotPNG() != nil)
    rig.view.setFrameSize(NSSize(width: 300, height: 500))
    #expect(rig.view.snapshotPNG() != nil)
}

@MainActor @Test func applyingAnotherSkinKeepsWorking() {
    let rig = Rig()
    rig.click(50, 150)
    let phosphor = SkinParser.parse(data: BuiltinSkins.data(named: "Phosphor")!).skin!
    rig.view.apply(skin: phosphor)
    rig.view.setFrameSize(NSSize(width: 380, height: 316))
    #expect(rig.view.snapshotPNG() != nil)
    rig.actions = []
    rig.view.mouseDown(with: rig.mouse(.leftMouseDown, 58, 300 - (316 - 139)))   // Phosphor's play button
    #expect(rig.actions.isEmpty)             // press alone does nothing
}
