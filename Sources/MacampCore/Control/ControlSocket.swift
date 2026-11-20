import Foundation

public enum ControlError: Error, Equatable {
    /// Nothing is listening at the socket path.
    case notRunning
    /// Another player is already listening at the socket path.
    case alreadyRunning
    /// Socket paths are limited to about 100 bytes by the system.
    case pathTooLong
    case timedOut
    case failed(String)
}

private func socketAddress(_ path: URL) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard bytes.count < capacity else { throw ControlError.pathTooLong }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.copyBytes(from: bytes)
        buffer[bytes.count] = 0
    }
    return address
}

private func withSockaddr<T>(_ address: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    var copy = address
    return withUnsafePointer(to: &copy) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}

/// A new socket on which writing to a vanished peer returns an error instead of raising SIGPIPE,
/// which by default kills the whole process.
///
/// The option has to be set here, at creation. macOS refuses to set options on a socket whose
/// peer has already closed, so setting it later can silently fail on exactly the connections
/// that need it. Sockets accepted from a listening socket inherit it.
private func makeSocket() -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }
    var on: Int32 = 1
    guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
        close(fd)
        return -1
    }
    return fd
}

/// True when a write to `fd` cannot raise SIGPIPE.
private func isProtectedFromSigpipe(_ fd: Int32) -> Bool {
    var value: Int32 = 0
    var length = socklen_t(MemoryLayout<Int32>.size)
    return getsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, &length) == 0 && value != 0
}

private func setTimeouts(_ fd: Int32, seconds: TimeInterval) {
    var time = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
}

/// Reads until a newline, the end of the stream, or `limit` bytes. Returns nil if the read timed out with nothing useful.
private func readMessage(_ fd: Int32, limit: Int = 4 << 20, untilNewline: Bool) -> (data: Data, timedOut: Bool) {
    var data = Data()
    var chunk = [UInt8](repeating: 0, count: 16 * 1024)
    while data.count < limit {
        let n = read(fd, &chunk, chunk.count)
        if n > 0 {
            data.append(contentsOf: chunk[0..<n])
            if untilNewline, chunk[0..<n].contains(0x0A) { break }
        } else if n == 0 {
            break
        } else if errno == EINTR {
            continue
        } else {
            return (data, errno == EAGAIN || errno == EWOULDBLOCK)
        }
    }
    return (data, false)
}

private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    var sent = 0
    return data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
        while sent < buffer.count {
            let n = write(fd, buffer.baseAddress! + sent, buffer.count - sent)
            if n > 0 { sent += n } else if errno != EINTR { return false }
        }
        return true
    }
}

/// Listens on a socket file for control requests and answers each with one reply.
/// It does nothing, and costs nothing, until a request arrives.
public final class ControlServer {
    /// How long a connected client may take to send its request.
    public var readTimeout: TimeInterval = 5

    private let path: URL
    private let handlerQueue: DispatchQueue
    private let handler: (ControlRequest) -> ControlReply
    private let acceptQueue = DispatchQueue(label: "macamp.control.accept")
    private let workQueue = DispatchQueue(label: "macamp.control.work", attributes: .concurrent)
    private var source: DispatchSourceRead?
    private var ownsSocket = false

    /// `handler` is called on `handlerQueue`, one request at a time per connection.
    public init(path: URL, handlerQueue: DispatchQueue, handler: @escaping (ControlRequest) -> ControlReply) {
        self.path = path
        self.handlerQueue = handlerQueue
        self.handler = handler
    }

    deinit { stop() }

    public func start() throws {
        let address = try socketAddress(path)
        if FileManager.default.fileExists(atPath: path.path) {
            // Either another player is running, or one crashed and left its socket file behind.
            if ControlClient.isRunning(at: path) { throw ControlError.alreadyRunning }
            unlink(path.path)
        }
        try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fd = makeSocket()
        guard fd >= 0 else { throw ControlError.failed("could not create a socket") }
        // Make the socket file private to this user before listening. Nothing can connect until
        // listen() is called, so there is no moment when another user could reach it. (Changing the
        // process's umask around bind() would also work, but that briefly alters every file any
        // other thread creates.)
        guard withSockaddr(address, { bind(fd, $0, $1) }) == 0 else {
            close(fd)
            throw ControlError.failed("could not create the control socket at \(path.path)")
        }
        guard chmod(path.path, 0o600) == 0, listen(fd, 64) == 0 else {
            close(fd)
            unlink(path.path)
            throw ControlError.failed("could not listen at \(path.path)")
        }
        ownsSocket = true

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            let client = accept(fd, nil, nil)
            guard client >= 0, let self else { return }
            let timeout = self.readTimeout
            self.workQueue.async { self.serve(client, timeout: timeout) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        if ownsSocket {
            unlink(path.path)
            ownsSocket = false
        }
    }

    /// Stops listening without removing the socket file, the way a crash would. For tests.
    func abandonForTesting() {
        source?.cancel()
        source = nil
        ownsSocket = false
        acceptQueue.sync {}                                 // let the cancellation close the descriptor
        Thread.sleep(forTimeInterval: 0.05)
    }

    private func serve(_ client: Int32, timeout: TimeInterval) {
        defer { close(client) }
        setTimeouts(client, seconds: timeout)
        let (data, _) = readMessage(client, untilNewline: true)
        let line = data.prefix { $0 != 0x0A }
        guard !line.isEmpty else { return }                 // a probe, or a client that sent nothing
        let reply: ControlReply
        if let request = try? ControlRequest.decode(Data(line)) {
            reply = handlerQueue.sync { handler(request) }
        } else {
            reply = ControlReply(ok: false, error: "the request could not be understood")
        }
        guard var out = try? reply.encoded() else { return }
        out.append(0x0A)
        // The client may be gone by now. Only write if that cannot hurt this process.
        guard isProtectedFromSigpipe(client) else { return }
        _ = writeAll(client, out)
    }
}

public enum ControlClient {
    private static func connected(to path: URL) throws -> Int32 {
        let address = try socketAddress(path)
        let fd = makeSocket()
        guard fd >= 0 else { throw ControlError.failed("could not create a socket") }
        guard withSockaddr(address, { connect(fd, $0, $1) }) == 0 else {
            close(fd)
            throw ControlError.notRunning
        }
        return fd
    }

    /// Sends bytes and closes at once, without waiting for a reply. For tests of how the server copes.
    static func sendAndHangUp(_ data: Data, to path: URL) throws {
        let fd = try connected(to: path)
        _ = writeAll(fd, data)
        close(fd)
    }

    /// True when a player is listening at `path`.
    public static func isRunning(at path: URL) -> Bool {
        guard let fd = try? connected(to: path) else { return false }
        close(fd)
        return true
    }

    /// Sends raw bytes and returns whatever comes back.
    public static func exchange(_ data: Data, with path: URL, timeout: TimeInterval) throws -> Data {
        let fd = try connected(to: path)
        defer { close(fd) }
        setTimeouts(fd, seconds: timeout)
        guard writeAll(fd, data) else { throw ControlError.failed("could not send the request") }
        shutdown(fd, SHUT_WR)
        let (reply, timedOut) = readMessage(fd, untilNewline: false)
        if timedOut, reply.isEmpty { throw ControlError.timedOut }
        return reply
    }

    public static func send(_ request: ControlRequest, to path: URL, timeout: TimeInterval = 10) throws -> ControlReply {
        var data = try request.encoded()
        data.append(0x0A)
        let reply = try exchange(data, with: path, timeout: timeout)
        guard !reply.isEmpty else { throw ControlError.failed("the player closed the connection without answering") }
        do { return try ControlReply.decode(reply.prefix { $0 != 0x0A }) } catch {
            throw ControlError.failed("the player's reply could not be understood")
        }
    }
}
