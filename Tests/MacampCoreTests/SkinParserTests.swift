import CoreGraphics
import Foundation
import Testing
@testable import MacampCore

/// Builds a skin document from a window object and element objects, both as JSON text.
func skinJSON(window: String = #"{"size": [300, 200]}"#,
              extra: String = "",
              elements: [String] = [#"{"type": "playlist", "frame": [0, 100, 300, 100]}"#]) -> Data {
    let body = """
    {"format": 1, "name": "Test", "window": \(window)\(extra.isEmpty ? "" : ", " + extra),
     "elements": [\(elements.joined(separator: ","))]}
    """
    return Data(body.utf8)
}

func parse(_ data: Data, dark: Bool = false) -> SkinParseResult { SkinParser.parse(data: data, dark: dark) }

/// Parses a skin holding one element (plus a playlist so the "no way to play" warning stays quiet).
func parseElement(_ json: String, extra: String = "") -> SkinParseResult {
    parse(skinJSON(extra: extra, elements: [json, #"{"type": "playlist", "frame": [0, 100, 300, 100]}"#]))
}

private func expectOneError(_ result: SkinParseResult, at path: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(result.skin == nil, sourceLocation: sourceLocation)
    #expect(result.errors.map(\.path) == [path], "errors: \(result.errors)", sourceLocation: sourceLocation)
}

@Test func minimalSkinParsesWithDefaults() throws {
    let result = parse(skinJSON())
    #expect(result.issues.isEmpty, "\(result.issues)")
    let skin = try #require(result.skin)
    #expect(skin.name == "Test")
    #expect(skin.window.size == CGSize(width: 300, height: 200))
    #expect(skin.window.titleBar == .system)
    #expect(skin.window.resize == .none)
    #expect(skin.window.minHeight == 200)
    #expect(skin.followsAppearance == false)
    #expect(skin.elements.count == 1)
    #expect(skin.elements[0].frame == CGRect(x: 0, y: 100, width: 300, height: 100))
    #expect(skin.elements[0].anchor == .top)
}

@Test func windowFieldsParse() throws {
    let window = """
    {"size": [380, 300], "cornerRadius": 4, "background": "#102030",
     "border": {"color": "#000", "width": 2}, "titleBar": "none",
     "resize": "vertical", "minHeight": 220, "maxHeight": 900}
    """
    let skin = try #require(parse(skinJSON(window: window)).skin)
    #expect(skin.window.cornerRadius == 4)
    #expect(skin.window.background == .solid(RGBA(hex: "#102030")!))
    #expect(skin.window.border == Border(color: RGBA(0, 0, 0), width: 2))
    #expect(skin.window.titleBar == TitleBar.none)
    #expect(skin.window.resize == .vertical)
    #expect(skin.window.minHeight == 220)
    #expect(skin.window.maxHeight == 900)
}

@Test func colorsParseInAllForms() {
    #expect(RGBA(hex: "#fff") == RGBA(1, 1, 1))
    #expect(RGBA(hex: "#ff0000") == RGBA(1, 0, 0))
    #expect(RGBA(hex: "#00ff0080")?.a == 128.0 / 255)
    #expect(RGBA(hex: "ff0000") == nil)
    #expect(RGBA(hex: "#ff00") == nil)
    #expect(RGBA(hex: "#gggggg") == nil)
}

@Test func rectElementParses() throws {
    let result = parseElement("""
    {"type": "rect", "frame": [1, 2, 30, 40], "anchor": "stretch",
     "fill": {"gradient": ["#000000", "#ffffff"], "angle": 0},
     "border": {"color": "#ff0000", "width": 1.5}, "cornerRadius": 3,
     "bevel": {"light": "#ffffff", "dark": "#000000", "width": 2}}
    """)
    #expect(result.issues.isEmpty, "\(result.issues)")
    let element = try #require(result.skin?.elements.first)
    #expect(element.anchor == .stretch)
    guard case .rect(let rect) = element.kind else { Issue.record("not a rect"); return }
    #expect(rect.box.fill == .gradient(stops: [RGBA(0, 0, 0), RGBA(1, 1, 1)], angle: 0))
    #expect(rect.box.border == Border(color: RGBA(1, 0, 0), width: 1.5))
    #expect(rect.box.cornerRadius == 3)
    #expect(rect.box.bevel == Bevel(light: RGBA(1, 1, 1), dark: RGBA(0, 0, 0), width: 2))
}

@Test func textElementParses() throws {
    let result = parseElement("""
    {"type": "text", "frame": [0, 0, 100, 20], "text": "{time:pad}",
     "font": {"family": "system", "size": 30, "weight": "light"}, "color": "#7dff6e",
     "glow": {"radius": 8, "color": "#00ff00"}, "align": "right", "overflow": "scroll",
     "action": "toggleTime"}
    """)
    #expect(result.issues.isEmpty, "\(result.issues)")
    guard case .text(let text) = result.skin?.elements.first?.kind else { Issue.record("not text"); return }
    #expect(text.template == TextTemplate("{time:pad}"))
    #expect(text.font == FontSpec(family: "system", size: 30, weight: "light"))
    #expect(text.color == RGBA(hex: "#7dff6e"))
    #expect(text.glow == Glow(color: RGBA(0, 1, 0), radius: 8))
    #expect(text.align == .right)
    #expect(text.overflow == .scroll)
    #expect(text.action == .toggleTime)
}

@Test func glowAcceptsABareRadius() throws {
    let result = parseElement(#"{"type": "text", "frame": [0, 0, 100, 20], "text": "x", "glow": 6}"#)
    guard case .text(let text) = result.skin?.elements.first?.kind else { Issue.record("not text"); return }
    #expect(text.glow == Glow(color: nil, radius: 6))
}

@Test func visualizerElementParses() throws {
    let result = parseElement("""
    {"type": "visualizer", "frame": [0, 0, 100, 30], "bars": 24, "gap": 1,
     "colors": ["#00ff00", "#ffff00", "#ff0000"], "segment": 2, "peaks": true,
     "peakColor": "#ffffff", "cornerRadius": 1, "glow": 4, "scopeColor": "#0000ff",
     "scopeWidth": 2, "background": "#000000"}
    """)
    #expect(result.issues.isEmpty, "\(result.issues)")
    guard case .visualizer(let viz) = result.skin?.elements.first?.kind else { Issue.record("not viz"); return }
    #expect(viz.bars == 24)
    #expect(viz.gap == 1)
    #expect(viz.colors == [RGBA(0, 1, 0), RGBA(1, 1, 0), RGBA(1, 0, 0)])
    #expect(viz.segment == 2)
    #expect(viz.peaks)
    #expect(viz.peakColor == RGBA(1, 1, 1))
    #expect(viz.cornerRadius == 1)
    #expect(viz.glow == Glow(color: nil, radius: 4))
    #expect(viz.scopeColor == RGBA(0, 0, 1))
    #expect(viz.scopeWidth == 2)
    #expect(viz.background == .solid(RGBA(0, 0, 0)))
}

@Test func sliderElementParses() throws {
    let result = parseElement("""
    {"type": "slider", "frame": [0, 0, 100, 12], "binds": "volume",
     "track": {"fill": "#222222", "cornerRadius": 2, "thickness": 4},
     "progress": {"fill": "#00ff00"},
     "thumb": {"fill": "#ffffff", "size": [10, 12], "cornerRadius": 5}}
    """)
    #expect(result.issues.isEmpty, "\(result.issues)")
    guard case .slider(let slider) = result.skin?.elements.first?.kind else { Issue.record("not slider"); return }
    #expect(slider.binds == .volume)
    #expect(slider.track.fill == .solid(RGBA(hex: "#222222")!))
    #expect(slider.track.cornerRadius == 2)
    #expect(slider.trackThickness == 4)
    #expect(slider.progress?.fill == .solid(RGBA(0, 1, 0)))
    #expect(slider.thumb?.fill == .solid(RGBA(1, 1, 1)))
    #expect(slider.thumb?.cornerRadius == 5)
    #expect(slider.thumbSize == CGSize(width: 10, height: 12))
}

@Test func buttonStatesInheritFromStyle() throws {
    let result = parseElement("""
    {"type": "button", "frame": [0, 0, 34, 24], "action": "play", "iconSize": 12,
     "style": {"fill": "#333333", "cornerRadius": 5, "color": "#cccccc",
               "border": {"color": "#444444", "width": 1}},
     "hover": {"fill": "#444444"},
     "pressed": {"color": "#ffffff"},
     "on": {"color": "#00ff00", "glow": 5}}
    """)
    #expect(result.issues.isEmpty, "\(result.issues)")
    guard case .button(let button) = result.skin?.elements.first?.kind else { Issue.record("not button"); return }
    #expect(button.action == .play)
    #expect(button.icon == "play")
    #expect(button.iconSize == 12)
    #expect(button.normal.box.fill == .solid(RGBA(hex: "#333333")!))
    #expect(button.normal.color == RGBA(hex: "#cccccc"))
    #expect(button.hover.box.fill == .solid(RGBA(hex: "#444444")!))
    #expect(button.hover.box.cornerRadius == 5)
    #expect(button.hover.color == RGBA(hex: "#cccccc"))
    #expect(button.pressed.color == RGBA(1, 1, 1))
    #expect(button.pressed.box.fill == .solid(RGBA(hex: "#333333")!))
    #expect(button.on.color == RGBA(0, 1, 0))
    #expect(button.on.glow == Glow(color: nil, radius: 5))
    #expect(button.on.box.border == Border(color: RGBA(hex: "#444444")!, width: 1))
}

@Test func buttonIconAndLabelOptions() throws {
    let result = parseElement("""
    {"type": "button", "frame": [0, 0, 34, 24], "action": "shuffle", "icon": "none", "label": "SHUF",
     "font": {"size": 9}}
    """)
    #expect(result.issues.isEmpty, "\(result.issues)")
    guard case .button(let button) = result.skin?.elements.first?.kind else { Issue.record("not button"); return }
    #expect(button.icon == nil)
    #expect(button.label == "SHUF")
    #expect(button.font.size == 9)
    #expect(button.font.family == "systemMono")
}

@Test func playlistElementParses() throws {
    let result = parse(skinJSON(elements: ["""
    {"type": "playlist", "frame": [0, 100, 300, 100], "rowHeight": 20,
     "font": {"family": "system", "size": 12}, "text": "{title}", "detail": "{duration}",
     "color": "#aaaaaa", "detailColor": "#888888", "currentColor": "#00ff00",
     "currentBackground": "#001100", "selectedColor": "#ffffff", "selectedBackground": "#333333",
     "unplayableColor": "#550000", "background": "#000000", "padding": 12,
     "rowCornerRadius": 6, "rowInset": 4}
    """]))
    #expect(result.issues.isEmpty, "\(result.issues)")
    guard case .playlist(let list) = result.skin?.elements.first?.kind else { Issue.record("not playlist"); return }
    #expect(list.rowHeight == 20)
    #expect(list.font.family == "system")
    #expect(list.text == TextTemplate("{title}"))
    #expect(list.detail == TextTemplate("{duration}"))
    #expect(list.color == RGBA(hex: "#aaaaaa"))
    #expect(list.detailColor == RGBA(hex: "#888888"))
    #expect(list.currentColor == RGBA(0, 1, 0))
    #expect(list.currentBackground == .solid(RGBA(hex: "#001100")!))
    #expect(list.selectedColor == RGBA(1, 1, 1))
    #expect(list.selectedBackground == .solid(RGBA(hex: "#333333")!))
    #expect(list.unplayableColor == RGBA(hex: "#550000"))
    #expect(list.background == .solid(RGBA(0, 0, 0)))
    #expect(list.padding == 12)
    #expect(list.rowCornerRadius == 6)
    #expect(list.rowInset == 4)
}

@Test func paletteReferencesResolveAndDarkOverrides() throws {
    let extra = ##""palette": {"fg": "#111111", "bg": "#eeeeee"}, "paletteDark": {"fg": "#f0f0f0"}"##
    let element = #"{"type": "rect", "frame": [0, 0, 10, 10], "fill": "$fg", "border": {"color": "$bg", "width": 1}}"#
    let light = try #require(parseElement(element, extra: extra).skin)
    let dark = try #require(parse(skinJSON(extra: extra, elements: [element,
        #"{"type": "playlist", "frame": [0, 100, 300, 100]}"#]), dark: true).skin)
    guard case .rect(let l) = light.elements[0].kind, case .rect(let d) = dark.elements[0].kind else {
        Issue.record("not rects"); return
    }
    #expect(l.box.fill == .solid(RGBA(hex: "#111111")!))
    #expect(d.box.fill == .solid(RGBA(hex: "#f0f0f0")!))
    #expect(d.box.border?.color == RGBA(hex: "#eeeeee"))
    #expect(light.followsAppearance)
}

@Test func unknownPaletteNameIsALocatedError() {
    expectOneError(parseElement(#"{"type": "rect", "frame": [0, 0, 10, 10], "fill": "$nope"}"#),
                   at: "elements[0].fill")
}

// MARK: Limits and bad values

@Test func eachLimitYieldsOneLocatedError() {
    expectOneError(parse(skinJSON(window: #"{"size": [79, 200]}"#)), at: "window.size")
    expectOneError(parse(skinJSON(window: #"{"size": [300, 100000]}"#)), at: "window.size")
    expectOneError(parseElement(#"{"type": "rect", "frame": [0, 0, 0, 10]}"#), at: "elements[0].frame")
    expectOneError(parseElement(#"{"type": "rect", "frame": [0, 0, 10, -5]}"#), at: "elements[0].frame")
    expectOneError(parseElement(#"{"type": "rect", "frame": [0, 0, 10]}"#), at: "elements[0].frame")
    expectOneError(parseElement(#"{"type": "visualizer", "frame": [0, 0, 10, 10], "bars": 0}"#), at: "elements[0].bars")
    expectOneError(parseElement(#"{"type": "visualizer", "frame": [0, 0, 10, 10], "bars": 129}"#), at: "elements[0].bars")
    expectOneError(parseElement(#"{"type": "text", "frame": [0, 0, 10, 10], "text": "x", "font": {"size": 3}}"#),
                   at: "elements[0].font.size")
    expectOneError(parseElement(#"{"type": "text", "frame": [0, 0, 10, 10], "text": "x", "font": {"size": 201}}"#),
                   at: "elements[0].font.size")
    expectOneError(parse(skinJSON(elements: [#"{"type": "playlist", "frame": [0, 0, 10, 10], "rowHeight": 7}"#])),
                   at: "elements[0].rowHeight")
    expectOneError(parseElement(##"{"type": "rect", "frame": [0, 0, 10, 10], "fill": {"gradient": ["#000"]}}"##),
                   at: "elements[0].fill")
}

@Test func frameErrorMessageSaysWhatWasExpected() {
    let result = parseElement(#"{"type": "rect", "frame": [0, 0, 10]}"#)
    #expect(result.errors.first?.description == "elements[0].frame: expected 4 numbers, got 3")
}

@Test func wrongTypesAreLocatedErrors() {
    expectOneError(parse(skinJSON(window: #"{"size": "big"}"#)), at: "window.size")
    expectOneError(parseElement(#"{"type": "rect", "frame": [0, 0, 10, 10], "cornerRadius": "round"}"#),
                   at: "elements[0].cornerRadius")
    expectOneError(parseElement(#"{"type": "rect", "frame": [0, 0, 10, 10], "cornerRadius": true}"#),
                   at: "elements[0].cornerRadius")
    expectOneError(parseElement(#"{"type": "visualizer", "frame": [0, 0, 10, 10], "peaks": 1}"#),
                   at: "elements[0].peaks")
    expectOneError(parseElement(#"{"type": "visualizer", "frame": [0, 0, 10, 10], "bars": 4.5}"#),
                   at: "elements[0].bars")
    expectOneError(parseElement(#"{"type": "rect", "frame": [0, 0, 10, 10], "fill": "red"}"#),
                   at: "elements[0].fill")
    expectOneError(parseElement(#"{"type": "rect", "frame": [0, 0, 10, 10], "anchor": "middle"}"#),
                   at: "elements[0].anchor")
    expectOneError(parseElement(#"{"type": "button", "frame": [0, 0, 10, 10], "action": "explode"}"#),
                   at: "elements[0].action")
    expectOneError(parseElement(#"{"type": "button", "frame": [0, 0, 10, 10]}"#), at: "elements[0].action")
    expectOneError(parseElement(#"{"type": "slider", "frame": [0, 0, 10, 10]}"#), at: "elements[0].binds")
    expectOneError(parseElement(#"{"type": "text", "frame": [0, 0, 10, 10]}"#), at: "elements[0].text")
    expectOneError(parseElement(#"{"type": "sparkle", "frame": [0, 0, 10, 10]}"#), at: "elements[0].type")
    expectOneError(parseElement(#"{"frame": [0, 0, 10, 10]}"#), at: "elements[0].type")
    expectOneError(parseElement(#""just a string""#), at: "elements[0]")
    expectOneError(parseElement(#"{"type": "text", "frame": [0, 0, 10, 10], "text": "x", "font": {"weight": "heavy"}}"#),
                   at: "elements[0].font.weight")
    expectOneError(parseElement(#"{"type": "button", "frame": [0, 0, 10, 10], "action": "play", "icon": "banana"}"#),
                   at: "elements[0].icon")
}

@Test func missingTopLevelFieldsAreErrors() {
    expectOneError(parse(Data(#"{"name": "x", "window": {"size": [300, 200]}, "elements": []}"#.utf8)), at: "format")
    expectOneError(parse(Data(#"{"format": 2, "name": "x", "window": {"size": [300, 200]}, "elements": []}"#.utf8)), at: "format")
    expectOneError(parse(Data(#"{"format": 1, "name": "x", "elements": []}"#.utf8)), at: "window")
    expectOneError(parse(Data(#"{"format": 1, "name": "x", "window": {"size": [300, 200]}}"#.utf8)), at: "elements")
    expectOneError(parse(Data(#"{"format": 1, "name": "x", "window": {}, "elements": []}"#.utf8)), at: "window.size")
}

@Test func heightLimitsMustBracketTheHeight() {
    expectOneError(parse(skinJSON(window: #"{"size": [300, 200], "minHeight": 250}"#)), at: "window.minHeight")
    expectOneError(parse(skinJSON(window: #"{"size": [300, 200], "maxHeight": 150}"#)), at: "window.maxHeight")
}

@Test func emptyTruncatedAndNonObjectInputFailAtRoot() {
    for text in ["", "{", "[1, 2]", "null", #"{"format": 1, "name": "x", "window": {"size": [300, 2"#] {
        expectOneError(parse(Data(text.utf8)), at: "$")
    }
}

@Test func tooManyElementsIsOneErrorAndReturnsQuickly() {
    let one = #"{"type": "rect", "frame": [0, 0, 10, 10]}"#
    let start = Date()
    expectOneError(parse(skinJSON(elements: Array(repeating: one, count: 501))), at: "elements")
    #expect(Date().timeIntervalSince(start) < 1)
    let many = parse(skinJSON(elements: Array(repeating: one, count: 499)
                              + [#"{"type": "playlist", "frame": [0, 0, 10, 10]}"#]))
    #expect(many.skin?.elements.count == 500)
}

@Test func severalErrorsAreAllReported() {
    let result = parse(skinJSON(elements: [
        #"{"type": "rect", "frame": [0, 0, 0, 10]}"#,
        #"{"type": "rect", "frame": [0, 0, 10, 10], "fill": "nope"}"#,
    ]))
    #expect(result.skin == nil)
    #expect(result.errors.map(\.path) == ["elements[0].frame", "elements[1].fill"])
}

// MARK: Warnings

@Test func unknownFieldWarnsWithSuggestionAndStillLoads() {
    let result = parseElement(##"{"type": "rect", "frame": [0, 0, 10, 10], "colour": "#fff", "cornerRadios": 2}"##)
    #expect(result.skin != nil)
    #expect(result.errors.isEmpty)
    #expect(result.warnings.map(\.path).sorted() == ["elements[0].colour", "elements[0].cornerRadios"])
    #expect(result.warnings.contains { $0.message.contains("cornerRadius") })
}

@Test func unknownTopLevelAndWindowFieldsWarn() {
    let result = parse(skinJSON(window: #"{"size": [300, 200], "shadow": true}"#, extra: #""version": 3"#))
    #expect(result.skin != nil)
    #expect(result.warnings.map(\.path).sorted() == ["version", "window.shadow"])
}

@Test func elementOutsideWindowWarns() {
    let result = parseElement(#"{"type": "rect", "frame": [400, 0, 10, 10]}"#)
    #expect(result.skin != nil)
    #expect(result.warnings.map(\.path) == ["elements[0].frame"])
}

@Test func missingFontFamilyWarns() {
    let result = parseElement(#"{"type": "text", "frame": [0, 0, 50, 10], "text": "x", "font": {"family": "No Such Font 123"}}"#)
    #expect(result.skin != nil)
    #expect(result.warnings.map(\.path) == ["elements[0].font.family"])
    let fine = parseElement(#"{"type": "text", "frame": [0, 0, 50, 10], "text": "x", "font": {"family": "Menlo"}}"#)
    #expect(fine.warnings.isEmpty, "\(fine.warnings)")
}

@Test func cornerRadiusWithSystemTitleBarWarns() {
    let result = parse(skinJSON(window: #"{"size": [300, 200], "cornerRadius": 6}"#))
    #expect(result.warnings.map(\.path) == ["window.cornerRadius"])
    let fine = parse(skinJSON(window: #"{"size": [300, 200], "cornerRadius": 6, "titleBar": "none"}"#))
    #expect(fine.warnings.isEmpty, "\(fine.warnings)")
}

@Test func skinWithNoWayToPlayWarns() {
    let result = parse(skinJSON(elements: [#"{"type": "rect", "frame": [0, 0, 10, 10]}"#]))
    #expect(result.skin != nil)
    #expect(result.warnings.map(\.path) == ["elements"])
    let withButton = parse(skinJSON(elements: [#"{"type": "button", "frame": [0, 0, 10, 10], "action": "playPause"}"#]))
    #expect(withButton.warnings.isEmpty, "\(withButton.warnings)")
}

@Test func unknownTemplateTokenWarns() {
    let result = parseElement(#"{"type": "text", "frame": [0, 0, 50, 10], "text": "{titel}"}"#)
    #expect(result.skin != nil)
    #expect(result.warnings.map(\.path) == ["elements[0].text"])
    #expect(result.warnings.first?.message.contains("titel") == true)
}

@Test func elementFramesMustStayWithinSaneBounds() {
    expectOneError(parseElement(#"{"type": "rect", "frame": [0, 0, 100, 1e300]}"#), at: "elements[0].frame")
    expectOneError(parseElement(#"{"type": "rect", "frame": [0, 0, 10001, 10]}"#), at: "elements[0].frame")
    expectOneError(parseElement(#"{"type": "rect", "frame": [1e9, 0, 10, 10]}"#), at: "elements[0].frame")
    expectOneError(parseElement(#"{"type": "rect", "frame": [0, -10001, 10, 10]}"#), at: "elements[0].frame")
    expectOneError(parse(skinJSON(elements: [#"{"type": "playlist", "frame": [0, 0, 100, 1e300]}"#])), at: "elements[0].frame")
    expectOneError(parseElement(#"{"type": "slider", "frame": [0, 0, 100, 10], "binds": "seek", "thumb": {"size": [1e12, 10]}}"#),
                   at: "elements[0].thumb.size")
    #expect(parseElement(#"{"type": "rect", "frame": [-50, -50, 10000, 10000]}"#).skin != nil)
}
