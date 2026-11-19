import AppKit
import Testing
@testable import macamp
@testable import MacampCore

private func tempSkin(name: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-skins-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("skin.json")
    try write(name: name, to: url)
    return url
}

private func write(name: String, to url: URL) throws {
    let text = #"{"format": 1, "name": "\#(name)", "window": {"size": [300, 200]}, "elements": [{"type": "playlist", "frame": [0, 0, 300, 200]}]}"#
    try Data(text.utf8).write(to: url, options: .atomic)
}

@MainActor private func wait(upTo seconds: Double, until condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
}

@MainActor @Test func skinFileEditsAreReloaded() async throws {
    _ = NSApplication.shared
    let url = try tempSkin(name: "One")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let manager = SkinManager(saved: "Phosphor")
    manager.open(file: url)
    #expect(manager.current.name == "One")
    try write(name: "Two", to: url)                 // an atomic save replaces the file
    try await wait(upTo: 3) { manager.current.name == "Two" }
    #expect(manager.current.name == "Two")
    try write(name: "Three", to: url)               // and the replacement is still being watched
    try await wait(upTo: 3) { manager.current.name == "Three" }
    #expect(manager.current.name == "Three")
}

@MainActor @Test func aSkinFileThatComesBackAfterBeingDeletedIsPickedUpAgain() async throws {
    _ = NSApplication.shared
    let url = try tempSkin(name: "One")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let manager = SkinManager(saved: "Phosphor")
    manager.open(file: url)
    try FileManager.default.removeItem(at: url)
    // Longer than the old watcher was willing to wait, when asked for; a short absence otherwise.
    let away = ProcessInfo.processInfo.environment["MACAMP_SLOW_TESTS"] != nil ? 11.5 : 1.2
    try await Task.sleep(for: .milliseconds(Int(away * 1000)))
    #expect(manager.current.name == "One")          // the last good skin stays up meanwhile
    #expect(manager.currentError != nil)
    try write(name: "Back", to: url)
    try await wait(upTo: 3) { manager.current.name == "Back" }
    #expect(manager.current.name == "Back" && manager.currentError == nil)
    try write(name: "Again", to: url)
    try await wait(upTo: 3) { manager.current.name == "Again" }
    #expect(manager.current.name == "Again")
}

@MainActor @Test func aSkinFileThatNeverLoadedIsNotRemembered() throws {
    _ = NSApplication.shared
    let url = try tempSkin(name: "Fine")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let manager = SkinManager(saved: "Rack Unit")
    #expect(manager.savedIdentifier == "Rack Unit")
    let junk = url.deletingLastPathComponent().appendingPathComponent("package.json")
    try Data(#"{"name": "not a skin"}"#.utf8).write(to: junk)
    manager.open(file: junk)
    #expect(manager.current.name == "Rack Unit")    // still on screen
    #expect(manager.currentError != nil)            // and the problem is reported
    #expect(manager.savedIdentifier == "Rack Unit") // but next launch comes back as Rack Unit
    manager.open(file: url)
    #expect(manager.savedIdentifier == url.standardizedFileURL.path)
}

@MainActor @Test func aRememberedSkinFileThatIsGoneFallsBackQuietly() {
    _ = NSApplication.shared
    let manager = SkinManager(saved: "/nonexistent/folder/skin.json")
    #expect(manager.current.name == BuiltinSkins.defaultName)
    #expect(manager.currentError == nil)
    #expect(manager.savedIdentifier == BuiltinSkins.defaultName)
}

@MainActor @Test func aSkinFileNamedOnTheCommandLineIsKeptEvenWhenBroken() throws {
    _ = NSApplication.shared
    let url = try tempSkin(name: "x")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try Data("{".utf8).write(to: url)
    let manager = SkinManager(saved: "Phosphor", requested: url.path)
    #expect(manager.currentError != nil)            // the author asked for this file, so say what is wrong with it
    #expect(manager.source == .file(url.standardizedFileURL))
}

@MainActor @Test func menuShortcutsDoNotStealPlainKeys() throws {
    _ = NSApplication.shared
    let menu = MainMenu.build(delegate: AppDelegate(options: CLI.LaunchOptions()))
    var plain: [String] = []
    func walk(_ menu: NSMenu) {
        for item in menu.items {
            if !item.keyEquivalent.isEmpty, item.keyEquivalentModifierMask.intersection([.command, .control, .option]).isEmpty {
                plain.append(item.title)
            }
            if let sub = item.submenu { walk(sub) }
        }
    }
    walk(menu)
    // A shortcut with no modifier fires even while typing in a dialog's text field.
    #expect(plain.isEmpty, "menu items with a bare-key shortcut: \(plain)")
}

@MainActor @Test func minimizeGoesThroughTheAppSoChromelessWindowsCanMinimize() throws {
    _ = NSApplication.shared
    let menu = MainMenu.build(delegate: AppDelegate(options: CLI.LaunchOptions()))
    let window = try #require(menu.items.first { $0.title == "Window" }?.submenu)
    let minimize = try #require(window.items.first { $0.title == "Minimize" })
    #expect(minimize.action == #selector(AppDelegate.minimizeWindow(_:)))
}
