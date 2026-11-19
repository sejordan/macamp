import Foundation
import Testing
@testable import MacampCore

@Test func builtinNamesAndLookup() {
    #expect(BuiltinSkins.names == ["Phosphor", "Rack Unit", "Native Mini"])
    #expect(BuiltinSkins.defaultName == "Phosphor")
    #expect(BuiltinSkins.data(named: "Rack Unit") != nil)
    #expect(BuiltinSkins.data(named: "rackunit") != nil)
    #expect(BuiltinSkins.data(named: "Nope") == nil)
}

@Test(arguments: BuiltinSkins.names, [false, true])
func builtinSkinIsCleanAndRenders(name: String, dark: Bool) throws {
    let data = try #require(BuiltinSkins.data(named: name))
    let result = SkinParser.parse(data: data, dark: dark)
    #expect(result.issues.isEmpty, "\(name): \(result.issues)")
    let skin = try #require(result.skin)
    #expect(skin.name == name)
    for playing in [false, true] {
        var state = RenderState.sample(playing: playing)
        state.drawWindowButtons = true
        #expect(PNGRenderer.render(skin: skin, state: state, height: nil, scale: 2) != nil)
    }
    #expect(PNGRenderer.render(skin: skin, state: .sample(playing: true), height: 600, scale: 1) != nil)
}

@Test func nativeMiniFollowsAppearanceAndOthersDoNot() throws {
    func follows(_ name: String) throws -> Bool {
        let data = try #require(BuiltinSkins.data(named: name))
        return try #require(SkinParser.parse(data: data).skin).followsAppearance
    }
    #expect(try follows("Native Mini"))
    #expect(try !follows("Phosphor"))
    #expect(try !follows("Rack Unit"))
}

@Test func builtinSkinsCoverEveryTransportAction() throws {
    for name in BuiltinSkins.names {
        let data = try #require(BuiltinSkins.data(named: name))
        let skin = try #require(SkinParser.parse(data: data).skin)
        let actions = Set(skin.elements.compactMap { element -> ButtonAction? in
            if case .button(let b) = element.kind { return b.action } else { return nil }
        })
        #expect(actions.contains(.previous) && actions.contains(.next), "\(name)")
        #expect(actions.contains(.play) || actions.contains(.playPause), "\(name)")
        #expect(actions.contains(.shuffle) && actions.contains(.repeat), "\(name)")
        let sliders = Set(skin.elements.compactMap { element -> SliderBinding? in
            if case .slider(let s) = element.kind { return s.binds } else { return nil }
        })
        #expect(sliders == [.seek, .volume], "\(name)")
        if skin.window.titleBar == .none {
            #expect(actions.contains(.close) && actions.contains(.minimize), "\(name) has no system buttons")
        }
    }
}

@Test func guideDocumentsEveryFieldTokenActionAndType() {
    let guide = BuiltinSkins.guide
    for (kind, fields) in SkinParser.knownFields {
        for field in fields {
            #expect(guide.contains("`\(field)`"), "guide does not mention `\(field)` (\(kind))")
        }
    }
    for token in TextTemplate.tokenNames { #expect(guide.contains("`{\(token)}`"), "guide lacks {\(token)}") }
    for action in ButtonAction.allCases { #expect(guide.contains("`\(action.rawValue)`"), "guide lacks \(action.rawValue)") }
    for type in SkinParser.elementTypes { #expect(guide.contains("`\(type)`"), "guide lacks \(type)") }
}

@Test func schemaIsValidJSONAndNamesEveryField() throws {
    let schema = BuiltinSkins.schema
    _ = try JSONSerialization.jsonObject(with: Data(schema.utf8))
    for fields in SkinParser.knownFields.values {
        for field in fields { #expect(schema.contains("\"\(field)\""), "schema lacks \(field)") }
    }
}
