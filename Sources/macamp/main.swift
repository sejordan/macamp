import AppKit
import MacampCore

if let status = CLI.run(Array(CommandLine.arguments.dropFirst())) {
    exit(status)
}

let app = NSApplication.shared
let delegate = AppDelegate(options: CLI.launchOptions)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
