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
      macamp --help

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
            return parseLaunch(args)
        }
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
