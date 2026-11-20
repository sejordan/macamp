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

// MARK: Command-line control

@MainActor private func router() -> (ControlRouter, PlayerController, SkinManager) {
    _ = NSApplication.shared
    let controller = PlayerController(audio: StubAudio())
    controller.add([URL(fileURLWithPath: "/music/a.mp3"), URL(fileURLWithPath: "/music/b.mp3")], playFirstNew: false, playIfIdle: false)
    let skins = SkinManager(saved: "Phosphor")
    return (ControlRouter(controller: controller, skins: skins), controller, skins)
}

@MainActor @Test func controlRequestsReachThePlayerAndReportTheSkin() {
    let (router, controller, _) = router()
    let reply = router.handle(ControlRequest(command: "jump", arguments: ["2"]))
    #expect(reply.ok && reply.status?.index == 2 && reply.status?.state == "playing")
    #expect(reply.status?.skin == "Phosphor")
    #expect(controller.playlist.currentIndex == 1)
    #expect(router.handle(ControlRequest(command: "status")).status?.skin == "Phosphor")
}

@MainActor @Test func theSkinCommandTakesBuiltinNamesAndFiles() throws {
    let (router, _, skins) = router()
    var reply = router.handle(ControlRequest(command: "skin", arguments: ["rack unit"]))
    #expect(reply.ok && reply.status?.skin == "Rack Unit")

    let file = try tempSkin(name: "Mine")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    reply = router.handle(ControlRequest(command: "skin", arguments: [file.path]))
    #expect(reply.ok && reply.status?.skin == "Mine")

    try Data("{".utf8).write(to: file)
    reply = router.handle(ControlRequest(command: "skin", arguments: [file.path]))
    #expect(!reply.ok && reply.error?.contains("not valid JSON") == true)
    #expect(reply.status?.skin == "Mine")                    // the last good skin is still showing
    #expect(skins.current.name == "Mine")

    reply = router.handle(ControlRequest(command: "skin", arguments: ["No Such Skin"]))
    #expect(!reply.ok && reply.error?.contains("Phosphor") == true)
    #expect(!router.handle(ControlRequest(command: "skin")).ok)
}

@MainActor @Test func quitRepliesAndThenAsksTheAppToQuit() {
    let (router, _, _) = router()
    var quits = 0
    router.onQuit = { quits += 1 }
    #expect(router.handle(ControlRequest(command: "quit")).ok)
    #expect(quits == 1)
    #expect(!router.handle(ControlRequest(command: "quit", arguments: ["now"])).ok)
    #expect(quits == 1)
}

@MainActor @Test func addingFilesAsksForTheirTagsToBeRead() throws {
    let (router, _, _) = router()
    var notified = 0
    router.onFilesAdded = { notified += 1 }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-router-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    FileManager.default.createFile(atPath: folder.appendingPathComponent("x.mp3").path, contents: Data())
    #expect(router.handle(ControlRequest(command: "add", arguments: [folder.path])).ok)
    #expect(notified == 1)
    #expect(!router.handle(ControlRequest(command: "add", arguments: ["/no/such"])).ok)
    #expect(notified == 1)
    _ = router.handle(ControlRequest(command: "next"))
    #expect(notified == 1)
}

@Test func theCommandLineRecognizesControlCommands() throws {
    var parsed = try #require(CLI.parseControl(["status"]))
    #expect(parsed.request == ControlRequest(command: "status") && !parsed.json && parsed.stateFile == nil)

    parsed = try #require(CLI.parseControl(["--json", "seek", "+10"]))
    #expect(parsed.request == ControlRequest(command: "seek", arguments: ["+10"]) && parsed.json)

    parsed = try #require(CLI.parseControl(["volume", "-5", "--json"]))          // a leading minus is a value, not a flag
    #expect(parsed.request == ControlRequest(command: "volume", arguments: ["-5"]) && parsed.json)

    parsed = try #require(CLI.parseControl(["--state", "/tmp/x/state.json", "next"]))
    #expect(parsed.stateFile?.path == "/tmp/x/state.json" && parsed.request.command == "next")

    #expect(CLI.parseControl(["song.mp3"]) == nil)                               // a file to open, not a command
    #expect(CLI.parseControl(["--skin", "x.json"]) == nil)
    #expect(CLI.parseControl([]) == nil)
}

@Test func relativePathsAreMadeAbsoluteBeforeTheyAreSent() throws {
    let here = FileManager.default.currentDirectoryPath
    var parsed = try #require(CLI.parseControl(["play", "music/a.mp3", "/abs/b.mp3", "~/c.mp3"]))
    #expect(parsed.request.arguments == ["\(here)/music/a.mp3", "/abs/b.mp3", NSHomeDirectory() + "/c.mp3"])
    parsed = try #require(CLI.parseControl(["skin", "Rack Unit"]))               // a skin name is left alone
    #expect(parsed.request.arguments == ["Rack Unit"])
    parsed = try #require(CLI.parseControl(["seek", "1:30"]))                    // and so is anything that is not a path
    #expect(parsed.request.arguments == ["1:30"])
}
