import Foundation
import Testing
@testable import MacampCore

/// A short folder under the system temp location; socket paths have a small length limit.
private func socketFolder() throws -> URL {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mc-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func echoServer(at path: URL) -> ControlServer {
    ControlServer(path: path, handlerQueue: DispatchQueue(label: "test.handler")) { request in
        ControlReply(ok: request.command != "fail", error: request.command == "fail" ? "told to fail" : nil,
                     status: nil, playlist: request.arguments.enumerated().map {
                         TrackStatus(index: $0 + 1, file: $1, title: nil, artist: nil, album: nil, duration: nil, unplayable: false)
                     })
    }
}

@Test func aRequestReachesTheHandlerAndItsReplyComesBack() throws {
    let folder = try socketFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let path = folder.appendingPathComponent("control.sock")
    let server = echoServer(at: path)
    try server.start()
    defer { server.stop() }

    let reply = try ControlClient.send(ControlRequest(command: "play", arguments: ["/a b/ü.mp3", "second"]), to: path)
    #expect(reply.ok)
    #expect(reply.playlist?.map(\.file) == ["/a b/ü.mp3", "second"])
    let failure = try ControlClient.send(ControlRequest(command: "fail"), to: path)
    #expect(!failure.ok && failure.error == "told to fail")
    for i in 0..<20 {                                           // many requests, one after another
        #expect(try ControlClient.send(ControlRequest(command: "n", arguments: ["\(i)"]), to: path).playlist?.first?.file == "\(i)")
    }
}

@Test func theSocketIsPrivateToTheUserAndRemovedOnStop() throws {
    let folder = try socketFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let path = folder.appendingPathComponent("control.sock")
    let server = echoServer(at: path)
    try server.start()
    let mode = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
    server.stop()
    #expect(!FileManager.default.fileExists(atPath: path.path))
    #expect(throws: ControlError.notRunning) { try ControlClient.send(ControlRequest(command: "status"), to: path) }
}

@Test func noPlayerMeansNotRunning() throws {
    let folder = try socketFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let path = folder.appendingPathComponent("control.sock")
    #expect(throws: ControlError.notRunning) { try ControlClient.send(ControlRequest(command: "status"), to: path) }
    #expect(!ControlClient.isRunning(at: path))
}

@Test func aSocketFileLeftBehindByACrashIsReplaced() throws {
    let folder = try socketFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let path = folder.appendingPathComponent("control.sock")
    let crashed = echoServer(at: path)
    try crashed.start()
    crashed.abandonForTesting()                                 // stops listening but leaves the file, as a crash would
    #expect(FileManager.default.fileExists(atPath: path.path))
    #expect(throws: ControlError.notRunning) { try ControlClient.send(ControlRequest(command: "status"), to: path) }

    let server = echoServer(at: path)
    try server.start()
    defer { server.stop() }
    #expect(try ControlClient.send(ControlRequest(command: "ok"), to: path).ok)
}

@Test func aSecondPlayerDoesNotStealTheSocketOfARunningOne() throws {
    let folder = try socketFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let path = folder.appendingPathComponent("control.sock")
    let first = echoServer(at: path)
    try first.start()
    defer { first.stop() }
    let second = ControlServer(path: path, handlerQueue: DispatchQueue(label: "test.second")) { _ in
        ControlReply(ok: false, error: "the wrong player answered")
    }
    #expect(throws: ControlError.alreadyRunning) { try second.start() }
    #expect(try ControlClient.send(ControlRequest(command: "ok"), to: path).ok)
    second.stop()                                               // must not remove the first player's socket
    #expect(try ControlClient.send(ControlRequest(command: "ok"), to: path).ok)
}

@Test func garbageAndSilenceFromAClientDoNotBreakTheServer() throws {
    let folder = try socketFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let path = folder.appendingPathComponent("control.sock")
    let server = echoServer(at: path)
    server.readTimeout = 0.3
    try server.start()
    defer { server.stop() }

    let junk = try ControlClient.exchange(Data("this is not json\n".utf8), with: path, timeout: 2)
    let reply = try ControlReply.decode(junk)
    #expect(!reply.ok && reply.error?.contains("could not be understood") == true)

    let silent = try ControlClient.exchange(Data(), with: path, timeout: 2)     // connects, sends nothing
    #expect(silent.isEmpty || (try? ControlReply.decode(silent))?.ok == false)

    #expect(try ControlClient.send(ControlRequest(command: "still-alive"), to: path).ok)
}

@Test func aPathTooLongForASocketIsReportedNotTruncated() throws {
    let long = URL(fileURLWithPath: "/tmp/" + String(repeating: "x", count: 120) + "/control.sock")
    #expect(throws: ControlError.pathTooLong) { try ControlServer(path: long, handlerQueue: .main) { _ in .notRunning }.start() }
    #expect(throws: ControlError.pathTooLong) { try ControlClient.send(ControlRequest(command: "status"), to: long) }
}

@Test func aHandlerThatNeverAnswersTimesOutForTheClient() throws {
    let folder = try socketFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let path = folder.appendingPathComponent("control.sock")
    let gate = DispatchSemaphore(value: 0)
    let server = ControlServer(path: path, handlerQueue: DispatchQueue(label: "test.stuck")) { _ in
        gate.wait()
        return ControlReply(ok: true)
    }
    try server.start()
    defer { gate.signal(); server.stop() }
    #expect(throws: ControlError.timedOut) {
        try ControlClient.send(ControlRequest(command: "status"), to: path, timeout: 0.4)
    }
}

/// Starting a server once changed a process-wide setting for an instant, which made files
/// created at that moment by any other thread unusable.
@Test func startingServersDoesNotDisturbFilesCreatedElsewhereInTheProcess() throws {
    let folder = try socketFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        for i in 0..<150 {
            let server = echoServer(at: folder.appendingPathComponent("s\(i % 4).sock"))
            try? server.start()
            server.stop()
        }
        done.signal()
    }
    var unusable = 0
    for i in 0..<600 {
        let sub = folder.appendingPathComponent("d\(i)")
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        if !FileManager.default.createFile(atPath: sub.appendingPathComponent("f").path, contents: Data("x".utf8)) { unusable += 1 }
    }
    done.wait()
    #expect(unusable == 0, "\(unusable) folders created during server starts could not be written to")
}

/// A command that is interrupted (Ctrl-C, a timeout, a killed agent) can send its request and
/// vanish before the player reads it. The player's reply then goes to a closed connection.
/// That must be a non-event, not a signal that kills the player.
@Test func aClientThatHangsUpBeforeTheReplyDoesNotKillTheServer() throws {
    let folder = try socketFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let path = folder.appendingPathComponent("control.sock")
    let server = echoServer(at: path)
    try server.start()
    defer { server.stop() }

    var request = try ControlRequest(command: "status").encoded()
    request.append(0x0A)
    var delivered = 0
    for _ in 0..<200 {
        // Hanging up this fast can outrun the server's queue of waiting connections; when it is
        // full the connection is refused, so give the server a moment and try again.
        for _ in 0..<200 {
            do {
                try ControlClient.sendAndHangUp(request, to: path)
                delivered += 1
                break
            } catch ControlError.notRunning {
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
    }
    #expect(delivered == 200)
    Thread.sleep(forTimeInterval: 0.3)                         // let the server work through them
    #expect(try ControlClient.send(ControlRequest(command: "still-alive"), to: path).ok)
}
