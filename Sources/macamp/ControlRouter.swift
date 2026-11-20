import Foundation
import MacampCore

/// Answers control requests arriving from the command line. Player commands go to
/// `PlayerCommands`; the few that concern the app itself (its skin, quitting) are handled here.
final class ControlRouter {
    private let controller: PlayerController
    private let skins: SkinManager
    /// Called after files were added, so their tags get read.
    var onFilesAdded: (() -> Void)?
    /// Called when the player was asked to quit. The reply is sent first.
    var onQuit: (() -> Void)?

    init(controller: PlayerController, skins: SkinManager) {
        self.controller = controller
        self.skins = skins
    }

    func handle(_ request: ControlRequest) -> ControlReply {
        var reply: ControlReply
        switch request.command {
        case "skin":
            reply = ControlReply(ok: true)
            if let problem = setSkin(request.arguments) { reply = ControlReply(ok: false, error: problem) }
            reply.status = PlayerCommands.status(of: controller)
        case "quit":
            reply = ControlReply(ok: true, status: PlayerCommands.status(of: controller))
            if request.arguments.isEmpty { onQuit?() } else { reply = ControlReply(ok: false, error: "'quit' takes no arguments", status: reply.status) }
        default:
            reply = PlayerCommands.run(request, on: controller)
            if reply.ok, request.command == "play" || request.command == "add" { onFilesAdded?() }
        }
        reply.status?.skin = skins.current.name
        return reply
    }

    /// Returns a description of what went wrong, or nil on success.
    private func setSkin(_ arguments: [String]) -> String? {
        guard arguments.count == 1 else {
            return "'skin' needs a built-in skin name (\(BuiltinSkins.names.joined(separator: ", "))) or a skin file"
        }
        let wanted = arguments[0]
        if let name = BuiltinSkins.canonicalName(wanted) {
            skins.select(builtin: name)
            return nil
        }
        guard FileManager.default.fileExists(atPath: wanted) else {
            return "'\(wanted)' is neither a built-in skin (\(BuiltinSkins.names.joined(separator: ", "))) nor an existing file"
        }
        skins.open(file: URL(fileURLWithPath: wanted))
        // A broken file stays selected and watched, so the author can fix it; say what is wrong with it.
        return skins.currentError
    }
}
