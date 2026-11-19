import Foundation

/// Everything remembered between launches.
public struct AppState: Codable, Equatable {
    public var tracks: [Track] = []
    public var currentID: UUID?
    public var volume = 0.8
    public var shuffle = false
    public var repeatMode = RepeatMode.off
    /// A built-in skin's name, or the absolute path of a skin file.
    public var skin = BuiltinSkins.defaultName
    /// The window's top-left corner in screen coordinates, as [x, y].
    public var windowOrigin: [Double]?
    public var windowHeight: Double?
    public var showRemaining = false
    public var scopeMode = false

    public static let `default` = AppState()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try c.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        currentID = try c.decodeIfPresent(UUID.self, forKey: .currentID)
        let v = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0.8
        volume = v.isFinite ? min(1, max(0, v)) : 0.8
        shuffle = try c.decodeIfPresent(Bool.self, forKey: .shuffle) ?? false
        repeatMode = try c.decodeIfPresent(RepeatMode.self, forKey: .repeatMode) ?? .off
        skin = try c.decodeIfPresent(String.self, forKey: .skin) ?? BuiltinSkins.defaultName
        if let origin = try c.decodeIfPresent([Double].self, forKey: .windowOrigin),
           origin.count == 2, origin.allSatisfy(\.isFinite) {
            windowOrigin = origin
        }
        if let height = try c.decodeIfPresent(Double.self, forKey: .windowHeight), height.isFinite, height > 0 {
            windowHeight = height
        }
        showRemaining = try c.decodeIfPresent(Bool.self, forKey: .showRemaining) ?? false
        scopeMode = try c.decodeIfPresent(Bool.self, forKey: .scopeMode) ?? false
    }

    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/macamp", isDirectory: true)
    }

    public static var defaultURL: URL { supportDirectory.appendingPathComponent("state.json") }

    /// A missing or unreadable file gives the defaults; saved state is a convenience, never a reason to fail.
    public static func load(from url: URL) -> AppState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(AppState.self, from: data) else { return .default }
        return state
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
