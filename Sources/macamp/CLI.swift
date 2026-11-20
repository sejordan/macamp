import Foundation
import MacampCore

/// Command-line modes. They exist mainly so a skin author who cannot see the
/// screen (an AI assistant, for instance) can validate and preview a skin.
enum CLI {
    struct LaunchOptions {
        var skinPath: String?
        var files: [URL] = []
        /// Diagnostics: keep saved state somewhere other than the usual place.
        var stateFile: URL?
        /// Diagnostics: write a picture of the live window here, then quit.
        var snapshotFile: URL?
        var snapshotDelay = 2.0
        /// Started by a control command: come up without taking focus from what the user is doing.
        var background = false
    }

    struct ControlInvocation {
        var request: ControlRequest
        var json = false
        var stateFile: URL?
    }

    /// Where a player keeps its control socket: beside its saved state.
    static func socketPath(stateFile: URL?) -> URL {
        (stateFile ?? AppState.defaultURL).deletingLastPathComponent().appendingPathComponent("control.sock")
    }

    static var launchOptions = LaunchOptions()

    static let usage = """
    macamp \(Macamp.version): a lightweight audio player

    Usage:
      macamp [audio files or folders…]         open the player
      macamp --skin <file.json> [audio files…] open the player with a skin file, reloading it on save
      macamp --list-skins                      list built-in skins
      macamp --copy-skin <name> <dest.json>    copy a built-in skin as a starting point
      macamp --validate-skin <file.json>       check a skin; exit status 1 if it has errors
      macamp --render-skin <file.json | name> --out <file.png>
             [--state playing|stopped] [--scale N] [--height N] [--appearance light|dark]
                                               draw a skin to a PNG without opening a window
      macamp --skin-guide                      print the skin format reference
      macamp --skin-schema                     print the JSON Schema for skins
      macamp --control-guide                   print the reference for controlling the player (for agents and scripts)
      macamp --help

    Controlling a running player (add --json to any of these for machine-readable output):
      macamp status                            what is playing, position, volume
      macamp playlist                          every track, numbered from 1
      macamp play [files or folders…]          resume; or add these and play the first of them
      macamp add <files or folders…>           add to the playlist without interrupting
      macamp pause | toggle | stop | next | previous
      macamp jump <n>                          play track n
      macamp seek <position>                   90, 1:30, +10, -10 or 50%
      macamp volume [0-100 | +n | -n]
      macamp shuffle [on|off|toggle]           macamp repeat [off|all|one]
      macamp remove <n…>                       macamp clear
      macamp skin <name | file.json>
      macamp quit
    If no player is running, these start one in the background first (except status and quit).
    macamp --control-guide prints the full reference, including the JSON reply. Agents should read it.
    Exit status: 0 on success, 1 if the command failed, 2 for bad usage, 3 if status finds no player.

    Diagnostics, usable with the options that open the player:
      --state <file.json>                      keep the saved playlist and settings in this file
      --snapshot <file.png> [--snapshot-after N]
                                               after N seconds (default 2) write a picture of the live window
                                               and <file.png>.json with the player's status, then quit
    """

    private static func err(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    private static func usageError(_ message: String) -> Int32 {
        err("macamp: \(message)\nRun 'macamp --help' for usage.")
        return 2
    }

    private static func report(_ result: SkinParseResult) {
        for issue in result.issues {
            err("\(issue.severity == .error ? "error" : "warning"): \(issue)")
        }
    }

    /// Returns an exit status when a command-line mode handled the launch, or nil to start the app.
    static func run(_ arguments: [String]) -> Int32? {
        // Drop arguments macOS adds when launching an app (for example "-NSDocumentRevisionsDebugMode YES").
        var args: [String] = []
        var skipNext = false
        for a in arguments {
            if skipNext { skipNext = false; continue }
            if a.hasPrefix("-psn_") { continue }
            if a.hasPrefix("-NS") || a.hasPrefix("-Apple") { skipNext = true; continue }
            args.append(a)
        }
        guard let first = args.first else { return nil }

        switch first {
        case "--help", "-h":
            print(usage)
            return 0
        case "--version":
            print(Macamp.version)
            return 0
        case "--skin-guide":
            print(BuiltinSkins.guide)
            return 0
        case "--skin-schema":
            print(BuiltinSkins.schema)
            return 0
        case "--control-guide":
            print(ControlCommand.guide)
            return 0
        case "--list-skins":
            BuiltinSkins.names.forEach { print($0) }
            return 0
        case "--copy-skin":
            guard args.count == 3 else { return usageError("--copy-skin needs a built-in name and a destination file") }
            return copySkin(name: args[1], to: args[2])
        case "--validate-skin":
            guard args.count == 2 else { return usageError("--validate-skin needs one skin file") }
            return validate(path: args[1])
        case "--render-skin":
            return render(Array(args.dropFirst()))
        default:
            if let control = parseControl(args) { return runControl(control) }
            return parseLaunch(args)
        }
    }

    // MARK: Controlling a running player

    /// Recognizes `[--json] [--state file] <command> [arguments…]`. Returns nil when the
    /// arguments are not a control command, so they can be treated as files to open.
    static func parseControl(_ args: [String]) -> ControlInvocation? {
        var json = false
        var stateFile: URL?
        var words: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--json" {
                json = true
            } else if arg == "--state", words.isEmpty, i + 1 < args.count {
                stateFile = absolute(args[i + 1])
                i += 1
            } else if words.isEmpty, arg.hasPrefix("--") {
                return nil
            } else {
                words.append(arg)
            }
            i += 1
        }
        guard let command = words.first, ControlCommand.all.contains(command) else { return nil }
        var arguments = Array(words.dropFirst())
        if ControlCommand.pathCommands.contains(command) {
            // The player has its own working folder, so paths must not depend on ours.
            arguments = arguments.map { command == "skin" && BuiltinSkins.canonicalName($0) != nil ? $0 : absolute($0).path }
        }
        return ControlInvocation(request: ControlRequest(command: command, arguments: arguments), json: json, stateFile: stateFile)
    }

    private static func runControl(_ invocation: ControlInvocation) -> Int32 {
        let socket = socketPath(stateFile: invocation.stateFile)
        let command = invocation.request.command

        func finish(_ reply: ControlReply, status: Int32? = nil) -> Int32 {
            if invocation.json {
                print(String(decoding: (try? reply.encoded()) ?? Data("{\"ok\":false}".utf8), as: UTF8.self))
            } else if reply.ok {
                print(reply.summary)
            } else {
                err("macamp: \(reply.summary)")
            }
            return status ?? (reply.ok ? 0 : 1)
        }
        func fail(_ message: String) -> Int32 { finish(ControlReply(ok: false, error: message)) }

        var started = false
        while true {
            do {
                return finish(try ControlClient.send(invocation.request, to: socket))
            } catch ControlError.notRunning {
                if command == "status" { return finish(.notRunning, status: 3) }
                if command == "quit" { return finish(.notRunning) }
                if started { return fail("the player stopped before it could answer") }
                guard startPlayer(stateFile: invocation.stateFile, socket: socket) else {
                    return fail("started macamp, but it did not answer within 15 seconds. An older copy without command-line control may already be running; quit it and try again")
                }
                started = true
            } catch ControlError.timedOut {
                return fail("the player did not answer in time")
            } catch ControlError.pathTooLong {
                return fail("the path \(socket.path) is too long for a control socket")
            } catch ControlError.failed(let message) {
                return fail(message)
            } catch {
                return fail("could not reach the player")
            }
        }
    }

    /// Starts a player in the background and waits for it to listen. Returns false if it never does.
    private static func startPlayer(stateFile: URL?, socket: URL) -> Bool {
        var arguments = ["--background"]
        if let stateFile { arguments += ["--state", stateFile.path] }
        let process = Process()
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            // -g keeps it in the background. A player with its own state file is a separate
            // instance by intent, so -n lets it start alongside one that is already running.
            process.arguments = (stateFile == nil ? ["-g"] : ["-g", "-n"]) + ["-a", bundle.path, "--args"] + arguments
        } else {
            process.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = arguments
        }
        // The player must not hold on to this command's output, or whoever is reading it would wait forever.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if ControlClient.isRunning(at: socket) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    /// Options that open the player instead of running a one-shot command.
    private static func parseLaunch(_ args: [String]) -> Int32? {
        var options = LaunchOptions()
        var i = 0
        while i < args.count {
            let arg = args[i]
            guard arg.hasPrefix("--") else {
                options.files.append(absolute(arg))
                i += 1
                continue
            }
            if arg == "--background" {
                options.background = true
                i += 1
                continue
            }
            guard i + 1 < args.count else { return usageError("\(arg) needs a value") }
            let value = args[i + 1]
            switch arg {
            case "--skin": options.skinPath = BuiltinSkins.canonicalName(value) ?? absolute(value).path
            case "--state": options.stateFile = absolute(value)
            case "--snapshot": options.snapshotFile = absolute(value)
            case "--snapshot-after":
                guard let seconds = Double(value), seconds >= 0, seconds <= 600 else {
                    return usageError("--snapshot-after must be a number of seconds from 0 to 600")
                }
                options.snapshotDelay = seconds
            default: return usageError("unknown option \(arg)")
            }
            i += 2
        }
        // Plain `macamp song.mp3` with a player already running hands the files to that player,
        // the way opening them from Finder would, instead of starting a second one.
        let plainOpen = !options.files.isEmpty && options.skinPath == nil && options.stateFile == nil
            && options.snapshotFile == nil && !options.background
        if plainOpen, ControlClient.isRunning(at: socketPath(stateFile: nil)) {
            let request = ControlRequest(command: "play", arguments: options.files.map(\.path))
            if let reply = try? ControlClient.send(request, to: socketPath(stateFile: nil)) {
                if !reply.ok { err("macamp: \(reply.summary)") }
                return reply.ok ? 0 : 1
            }
        }
        launchOptions = options
        return nil
    }

    private static func absolute(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    private static func copySkin(name: String, to destination: String) -> Int32 {
        guard let data = BuiltinSkins.data(named: name) else {
            err("macamp: no built-in skin named '\(name)'. Built-in skins: \(BuiltinSkins.names.joined(separator: ", "))")
            return 1
        }
        let url = absolute(destination)
        if FileManager.default.fileExists(atPath: url.path) {
            err("macamp: \(url.path) already exists; choose another name or remove it first")
            return 1
        }
        do {
            try data.write(to: url)
            print("Wrote \(url.path)")
            return 0
        } catch {
            err("macamp: could not write \(url.path): \(error.localizedDescription)")
            return 1
        }
    }

    private static func load(_ source: String, dark: Bool) -> SkinParseResult? {
        let url = absolute(source)
        if FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url) else {
                err("macamp: could not read \(url.path)")
                return nil
            }
            return SkinParser.parse(data: data, dark: dark)
        }
        if let data = BuiltinSkins.data(named: source) { return SkinParser.parse(data: data, dark: dark) }
        err("macamp: '\(source)' is neither a file nor a built-in skin name")
        return nil
    }

    private static func validate(path: String) -> Int32 {
        guard FileManager.default.fileExists(atPath: absolute(path).path) else {
            err("macamp: no such file: \(path)")
            return 1
        }
        guard let result = load(path, dark: false) else { return 1 }
        report(result)
        if result.skin == nil { return 1 }
        // A dark palette can hide its own mistakes, so check that variant too.
        if result.skin?.followsAppearance == true, let dark = load(path, dark: true), dark.skin == nil {
            err("in dark mode:")
            report(dark)
            return 1
        }
        let warnings = result.warnings.count
        print(warnings == 0 ? "OK: skin loads with no warnings" : "OK: skin loads, with \(warnings) warning\(warnings == 1 ? "" : "s")")
        return 0
    }

    private static func render(_ args: [String]) -> Int32 {
        guard let source = args.first, !source.hasPrefix("--") else {
            return usageError("--render-skin needs a skin file or built-in name")
        }
        var out: String?
        var playing = true
        var scale = 2.0
        var height: Double?
        var dark = false
        var i = 1
        while i < args.count {
            let flag = args[i]
            guard i + 1 < args.count else { return usageError("\(flag) needs a value") }
            let value = args[i + 1]
            switch flag {
            case "--out": out = value
            case "--state":
                guard value == "playing" || value == "stopped" else { return usageError("--state must be playing or stopped") }
                playing = value == "playing"
            case "--scale":
                guard let n = Double(value), n >= 0.25, n <= 8 else { return usageError("--scale must be a number from 0.25 to 8") }
                scale = n
            case "--height":
                guard let n = Double(value), n > 0 else { return usageError("--height must be a positive number") }
                height = n
            case "--appearance":
                guard value == "light" || value == "dark" else { return usageError("--appearance must be light or dark") }
                dark = value == "dark"
            default: return usageError("unknown option \(flag)")
            }
            i += 2
        }
        guard let out else { return usageError("--render-skin needs --out <file.png>") }
        guard let result = load(source, dark: dark) else { return 1 }
        report(result)
        guard let skin = result.skin else { return 1 }
        var state = RenderState.sample(playing: playing)
        state.drawWindowButtons = true
        guard let image = PNGRenderer.render(skin: skin, state: state, height: height.map { CGFloat($0) }, scale: CGFloat(scale)) else {
            err("macamp: could not render the skin")
            return 1
        }
        let url = absolute(out)
        do {
            try PNGRenderer.write(image, to: url)
            print("Wrote \(url.path) (\(image.width) by \(image.height) pixels)")
            return 0
        } catch {
            err("macamp: could not write \(url.path)")
            return 1
        }
    }
}
