import CoreGraphics
import Foundation
import Testing
@testable import MacampCore

/// A rendered picture whose pixels can be read back, addressed in points from the top-left.
struct Bitmap {
    let image: CGImage
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        self.image = image
        let data = image.dataProvider!.data! as Data
        bytes = [UInt8](data)
    }

    /// Premultiplied RGBA.
    func pixel(_ x: Int, _ y: Int) -> [Int] {
        let offset = y * image.bytesPerRow + x * 4
        return bytes[offset..<offset + 4].map(Int.init)
    }

    func matches(_ x: Int, _ y: Int, _ hex: String, tolerance: Int = 3) -> Bool {
        let c = RGBA(hex: hex)!
        let want = [c.r, c.g, c.b, c.a].map { Int(($0 * 255).rounded()) }
        return zip(pixel(x, y), want).allSatisfy { abs($0 - $1) <= tolerance }
    }
}

private let blackWindow = ##"{"size": [300, 200], "background": "#000000", "titleBar": "none"}"##

private func makeSkin(_ elements: [String], window: String = blackWindow) throws -> Skin {
    let result = parse(skinJSON(window: window, elements: elements))
    return try #require(result.skin, "\(result.errors)")
}

private func render(_ elements: [String], window: String = blackWindow,
                    state: RenderState = .sample(playing: true), height: CGFloat? = nil) throws -> Bitmap {
    let image = try #require(PNGRenderer.render(skin: try makeSkin(elements, window: window), state: state,
                                                height: height, scale: 1))
    return Bitmap(image)
}

@Test func backgroundFillsTheWindow() throws {
    let b = try render([], window: ##"{"size": [300, 200], "background": "#123456", "titleBar": "none"}"##)
    #expect(b.image.width == 300 && b.image.height == 200)
    #expect(b.matches(5, 5, "#123456"))
    #expect(b.matches(295, 195, "#123456"))
}

@Test func gradientBackgroundRunsTopToBottomAtNinetyDegrees() throws {
    let b = try render([], window: ##"{"size": [300, 200], "titleBar": "none", "background": {"gradient": ["#ff0000", "#0000ff"], "angle": 90}}"##)
    #expect(b.pixel(150, 1)[0] > 240 && b.pixel(150, 1)[2] < 15)
    #expect(b.pixel(150, 198)[2] > 240 && b.pixel(150, 198)[0] < 15)
    let sideways = try render([], window: ##"{"size": [300, 200], "titleBar": "none", "background": {"gradient": ["#ff0000", "#0000ff"], "angle": 0}}"##)
    #expect(sideways.pixel(1, 100)[0] > 240 && sideways.pixel(298, 100)[2] > 240)
}

@Test func rectFillsItsFrameAndNothingElse() throws {
    let b = try render([##"{"type": "rect", "frame": [50, 40, 100, 60], "fill": "#ff0000"}"##])
    #expect(b.matches(51, 41, "#ff0000"))
    #expect(b.matches(148, 98, "#ff0000"))
    #expect(b.matches(48, 60, "#000000"))
    #expect(b.matches(152, 60, "#000000"))
    #expect(b.matches(100, 38, "#000000"))
    #expect(b.matches(100, 102, "#000000"))
}

@Test func laterElementsDrawOnTop() throws {
    let b = try render([
        ##"{"type": "rect", "frame": [50, 40, 100, 60], "fill": "#ff0000"}"##,
        ##"{"type": "rect", "frame": [100, 40, 100, 60], "fill": "#00ff00"}"##,
    ])
    #expect(b.matches(75, 70, "#ff0000"))
    #expect(b.matches(125, 70, "#00ff00"))
}

@Test func roundedCornersLeaveTheCornerPixelUnpainted() throws {
    let b = try render([##"{"type": "rect", "frame": [50, 40, 100, 60], "fill": "#ff0000", "cornerRadius": 20}"##])
    #expect(b.matches(51, 41, "#000000"))
    #expect(b.matches(100, 70, "#ff0000"))
}

@Test func bevelLightensTopEdgeAndDarkensBottomEdge() throws {
    let b = try render([##"{"type": "rect", "frame": [50, 40, 100, 60], "fill": "#808080", "bevel": {"light": "#ffffff", "dark": "#000000", "width": 2}}"##])
    #expect(b.matches(100, 40, "#ffffff"))
    #expect(b.matches(100, 99, "#000000"))
    #expect(b.matches(100, 70, "#808080"))
}

@Test func seekSliderProgressEndsAtTheSeekFraction() throws {
    var state = RenderState.sample(playing: true)
    state.seekFraction = 0.25
    let b = try render([##"{"type": "slider", "frame": [50, 100, 200, 10], "binds": "seek", "track": {"fill": "#222222"}, "progress": {"fill": "#00ff00"}}"##], state: state)
    #expect(b.matches(60, 105, "#00ff00"))
    #expect(b.matches(97, 105, "#00ff00"))
    #expect(b.matches(103, 105, "#222222"))
    #expect(b.matches(240, 105, "#222222"))
}

@Test func volumeSliderUsesVolumeAndDragOverridesIt() throws {
    var state = RenderState.sample(playing: true)
    state.volume = 1
    let json = ##"{"type": "slider", "frame": [50, 100, 200, 10], "binds": "volume", "track": {"fill": "#222222"}, "progress": {"fill": "#00ff00"}}"##
    #expect(try render([json], state: state).matches(245, 105, "#00ff00"))
    state.dragSlider = (element: 0, value: 0.1)
    #expect(try render([json], state: state).matches(245, 105, "#222222"))
}

@Test func textDrawsInsideItsFrameOnly() throws {
    var state = RenderState.sample(playing: true)
    state.values.title = String(repeating: "W", count: 400)
    let b = try render([##"{"type": "text", "frame": [100, 80, 60, 20], "text": "{title}", "color": "#ffffff", "font": {"size": 14}}"##], state: state)
    var painted = 0
    for x in 100..<160 { for y in 80..<100 where b.pixel(x, y)[0] > 100 { painted += 1 } }
    #expect(painted > 20)
    for y in 70..<110 {
        #expect(b.matches(98, y, "#000000"))
        #expect(b.matches(162, y, "#000000"))
    }
    for x in 90..<170 {
        #expect(b.matches(x, 78, "#000000"))
        #expect(b.matches(x, 101, "#000000"))
    }
}

@Test func textAlignmentMovesTheInk() throws {
    func inkCenter(_ align: String) throws -> Double {
        let b = try render([##"{"type": "text", "frame": [50, 80, 200, 20], "text": "WW", "color": "#ffffff", "align": "\##(align)"}"##])
        var sum = 0.0, n = 0.0
        for x in 50..<250 { for y in 80..<100 where b.pixel(x, y)[0] > 100 { sum += Double(x); n += 1 } }
        return n == 0 ? -1 : sum / n
    }
    let left = try inkCenter("left"), center = try inkCenter("center"), right = try inkCenter("right")
    #expect(left > 50 && left < 80)
    #expect(abs(center - 150) < 6)
    #expect(right > 220 && right < 250)
}

@Test func nonLatinAndEmptyTextRenderWithoutTrouble() throws {
    var state = RenderState.sample(playing: true)
    state.values.title = "夜のフェリー 🎧 مرحبا"
    _ = try render([##"{"type": "text", "frame": [10, 10, 200, 20], "text": "{title}", "overflow": "scroll"}"##], state: state)
    state.values.title = ""
    _ = try render([##"{"type": "text", "frame": [10, 10, 200, 20], "text": "{title}", "overflow": "ellipsis"}"##], state: state)
}

@Test func barsAtFullLevelReachTheTopAndZeroLeavesItEmpty() throws {
    let json = ##"{"type": "visualizer", "frame": [50, 50, 100, 40], "bars": 4, "gap": 4, "colors": ["#00ff00"]}"##
    var state = RenderState.sample(playing: true)
    state.scopeMode = false
    state.bars = [1, 1, 1, 1]; state.peaks = [1, 1, 1, 1]
    let full = try render([json], state: state)
    #expect(full.matches(55, 51, "#00ff00"))
    #expect(full.matches(55, 88, "#00ff00"))
    #expect(full.matches(55, 48, "#000000"))
    state.bars = [0, 0, 0, 0]; state.peaks = [0, 0, 0, 0]
    let empty = try render([json], state: state)
    for x in stride(from: 50, to: 150, by: 3) { for y in stride(from: 50, to: 90, by: 3) {
        #expect(empty.matches(x, y, "#000000"))
    } }
}

@Test func halfLevelBarStopsHalfway() throws {
    var state = RenderState.sample(playing: true)
    state.scopeMode = false
    state.bars = [0.5]; state.peaks = [0.5]
    let b = try render([##"{"type": "visualizer", "frame": [50, 50, 100, 40], "bars": 1, "colors": ["#00ff00"]}"##], state: state)
    #expect(b.matches(100, 85, "#00ff00"))
    #expect(b.matches(100, 72, "#00ff00"))
    #expect(b.matches(100, 66, "#000000"))
}

@Test func barColorsRunBottomToTop() throws {
    var state = RenderState.sample(playing: true)
    state.scopeMode = false
    state.bars = [1]; state.peaks = [1]
    let b = try render([##"{"type": "visualizer", "frame": [50, 50, 100, 40], "bars": 1, "segment": 2, "colors": ["#00ff00", "#ff0000"]}"##], state: state)
    #expect(b.matches(100, 88, "#00ff00"))
    #expect(b.matches(100, 50, "#ff0000"))
}

@Test func scopeModeDrawsALineThroughTheMiddle() throws {
    var state = RenderState.sample(playing: true)
    state.scopeMode = true
    state.scope = [Float](repeating: 0, count: 64)
    let b = try render([##"{"type": "visualizer", "frame": [50, 50, 100, 40], "scopeColor": "#00ff00", "scopeWidth": 2}"##], state: state)
    #expect(b.pixel(100, 70)[1] > 200)
    #expect(b.matches(100, 55, "#000000"))
}

@Test func currentPlaylistRowShowsItsBackground() throws {
    var state = RenderState.sample(playing: true)
    state.currentRow = 2
    state.selection = []
    let b = try render([##"{"type": "playlist", "frame": [0, 100, 300, 100], "rowHeight": 20, "currentBackground": "#003300", "color": "#ffffff", "padding": 20}"##], state: state)
    #expect(b.matches(5, 150, "#003300"))
    #expect(b.matches(5, 130, "#000000"))
    #expect(b.matches(5, 170, "#000000"))
}

@Test func playlistScrollShiftsRowsAndSelectionShows() throws {
    var state = RenderState.sample(playing: true)
    state.currentRow = nil
    state.selection = [1]
    state.playlistScroll = 20
    let b = try render([##"{"type": "playlist", "frame": [0, 100, 300, 100], "rowHeight": 20, "selectedBackground": "#000080", "padding": 20}"##], state: state)
    #expect(b.matches(5, 110, "#000080"))
    #expect(b.matches(5, 130, "#000000"))
}

@Test func playlistNeverDrawsOutsideItsFrame() throws {
    var state = RenderState.sample(playing: true)
    state.rowCount = 1000
    state.currentRow = 0
    state.playlistScroll = 10
    let b = try render([##"{"type": "playlist", "frame": [0, 100, 300, 60], "rowHeight": 20, "currentBackground": "#003300", "background": "#111111"}"##], state: state)
    #expect(b.matches(5, 98, "#000000"))
    #expect(b.matches(5, 162, "#000000"))
    #expect(b.matches(5, 105, "#003300"))
}

@Test func buttonUsesOnStyleWhenItsStateIsActive() throws {
    let json = ##"{"type": "button", "frame": [50, 50, 40, 30], "action": "shuffle", "icon": "none", "style": {"fill": "#222222"}, "on": {"fill": "#00aa00"}, "pressed": {"fill": "#ffffff"}, "hover": {"fill": "#444444"}}"##
    var state = RenderState.sample(playing: true)
    state.shuffle = false
    #expect(try render([json], state: state).matches(55, 55, "#222222"))
    state.hoverElement = 0
    #expect(try render([json], state: state).matches(55, 55, "#444444"))
    state.shuffle = true
    #expect(try render([json], state: state).matches(55, 55, "#00aa00"))
    state.pressedElement = 0
    #expect(try render([json], state: state).matches(55, 55, "#ffffff"))
}

@Test func buttonIconIsDrawnInItsColor() throws {
    let b = try render([##"{"type": "button", "frame": [50, 50, 40, 40], "action": "stop", "iconSize": 32, "style": {"color": "#ff00ff"}}"##])
    #expect(b.matches(70, 70, "#ff00ff"))
    #expect(b.matches(52, 52, "#000000"))
}

@Test func everyActionHasAnIcon() {
    for action in ButtonAction.allCases {
        #expect(Icons.path(for: action.rawValue) != nil, "no icon for \(action.rawValue)")
    }
    #expect(Icons.path(for: "banana") == nil)
}

@Test func errorBannerCoversTheBottomStrip() throws {
    var state = RenderState.sample(playing: true)
    let plain = try render([], state: state)
    state.errorBanner = "elements[3].frame: expected 4 numbers, got 3"
    let withBanner = try render([], state: state)
    #expect(plain.matches(2, 197, "#000000"))
    #expect(withBanner.pixel(2, 197) != plain.pixel(2, 197))
    #expect(withBanner.matches(2, 100, "#000000"))
}

@Test func dirtyRectLimitsWhatIsRepainted() throws {
    let skin = try makeSkin([
        ##"{"type": "rect", "frame": [0, 0, 100, 100], "fill": "#ff0000"}"##,
        ##"{"type": "rect", "frame": [150, 0, 100, 100], "fill": "#00ff00"}"##,
    ])
    let ctx = try #require(PNGRenderer.makeContext(width: 300, height: 200, scale: 1))
    ctx.setFillColor(RGBA(hex: "#0000ff")!.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
    SkinRenderer(skin: skin, windowHeight: 200).draw(in: ctx, state: .sample(playing: true),
                                                     dirty: CGRect(x: 150, y: 0, width: 100, height: 100))
    let b = Bitmap(try #require(ctx.makeImage()))
    #expect(b.matches(200, 50, "#00ff00"))   // inside the dirty rect: repainted
    #expect(b.matches(50, 50, "#0000ff"))    // first rect lies outside: marker survives
    #expect(b.matches(200, 150, "#0000ff"))  // background outside the dirty rect: untouched
}

@Test func windowShapeIsClippedForChromelessSkins() throws {
    let b = try render([], window: ##"{"size": [300, 200], "background": "#ffffff", "titleBar": "none", "cornerRadius": 20}"##)
    #expect(b.pixel(1, 1)[3] == 0)
    #expect(b.matches(150, 100, "#ffffff"))
}

@Test func previewDrawsWindowButtonsOnlyWhenAsked() throws {
    let window = ##"{"size": [300, 200], "background": "#000000"}"##
    var state = RenderState.sample(playing: true)
    state.drawWindowButtons = true
    let with = try render([], window: window, state: state)
    #expect(with.pixel(14, 14)[0] > 200)        // red close button likeness
    #expect(with.pixel(1, 1)[3] == 0)           // system corner radius in the preview
    state.drawWindowButtons = false
    #expect(try render([], window: window, state: state).matches(14, 14, "#000000"))
}

@Test func resizedHeightStretchesAnchoredElements() throws {
    let b = try render([##"{"type": "rect", "frame": [0, 180, 300, 20], "fill": "#ff0000", "anchor": "bottom"}"##],
                       window: ##"{"size": [300, 200], "background": "#000000", "titleBar": "none", "resize": "vertical"}"##,
                       height: 300)
    #expect(b.image.height == 300)
    #expect(b.matches(150, 290, "#ff0000"))
    #expect(b.matches(150, 190, "#000000"))
}

@Test func renderedTextAndMarqueeDetection() throws {
    let skin = try makeSkin([
        #"{"type": "text", "frame": [0, 0, 40, 20], "text": "{title}", "overflow": "scroll"}"#,
        #"{"type": "text", "frame": [0, 30, 290, 20], "text": "{index}", "overflow": "scroll"}"#,
        #"{"type": "text", "frame": [0, 60, 40, 20], "text": "{title}"}"#,
        #"{"type": "rect", "frame": [0, 90, 40, 20]}"#,
        #"{"type": "visualizer", "frame": [0, 120, 40, 20], "bars": 7}"#,
    ])
    let r = SkinRenderer(skin: skin, windowHeight: 200)
    let state = RenderState.sample(playing: true)
    #expect(r.renderedText(element: 0, state: state) == "Low Tide Radio")
    #expect(r.renderedText(element: 3, state: state) == nil)
    #expect(r.needsMarquee(element: 0, state: state))
    #expect(!r.needsMarquee(element: 1, state: state))
    #expect(!r.needsMarquee(element: 2, state: state))
    #expect(r.barCount(element: 4) == 7)
    #expect(r.barCount(element: 0) == 0)
}

@Test func scaleTwoDoublesThePixelSize() throws {
    let image = try #require(PNGRenderer.render(skin: try makeSkin([]), state: .sample(playing: false), height: nil, scale: 2))
    #expect(image.width == 600 && image.height == 400)
}

@Test func pngFileIsWritten() throws {
    let image = try #require(PNGRenderer.render(skin: try makeSkin([]), state: .sample(playing: false), height: nil, scale: 1))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-test-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try PNGRenderer.write(image, to: url)
    let data = try Data(contentsOf: url)
    #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
}

@Test func absurdBitmapSizesAreRefusedWithoutCrashing() {
    #expect(PNGRenderer.makeContext(width: 1e300, height: 10, scale: 2) == nil)
    #expect(PNGRenderer.makeContext(width: 10, height: .infinity, scale: 1) == nil)
    #expect(PNGRenderer.makeContext(width: .nan, height: 10, scale: 1) == nil)
    #expect(PNGRenderer.makeContext(width: 0, height: 10, scale: 1) == nil)
    #expect(PNGRenderer.makeContext(width: 10, height: 10, scale: 2) != nil)
}
