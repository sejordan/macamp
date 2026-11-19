import Foundation

public enum RepeatMode: String, Codable, CaseIterable {
    case off, all, one

    public var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// Decides which track follows which, given shuffle and repeat settings.
public struct PlaybackOrder {
    public var shuffle = false {
        didSet { if shuffle != oldValue { playedThisRound.removeAll() } }
    }
    public var repeatMode = RepeatMode.off

    /// Tracks already played in the current shuffle round.
    private var playedThisRound: Set<UUID> = []
    /// Tracks in the order they started, newest last.
    private var history: [UUID] = []

    public init() {}

    /// Call whenever a track starts playing, however it was chosen.
    public mutating func noteStarted(_ id: UUID) {
        playedThisRound.insert(id)
        if history.last != id { history.append(id) }
        if history.count > 500 { history.removeFirst(history.count - 500) }
    }

    /// The track to play after `current`. `auto` is true when the track ended by itself.
    public mutating func next(in ids: [UUID], current: UUID?, auto: Bool) -> UUID? {
        guard !ids.isEmpty else { return nil }
        if auto, repeatMode == .one, let current, ids.contains(current) { return current }

        if shuffle {
            let unplayed = ids.filter { !playedThisRound.contains($0) && $0 != current }
            if let pick = unplayed.randomElement() { return pick }
            playedThisRound.removeAll()
            guard repeatMode != .off else { return nil }
            let others = ids.filter { $0 != current }
            return others.randomElement() ?? ids[0]
        }

        guard let current, let index = ids.firstIndex(of: current) else { return ids[0] }
        if index + 1 < ids.count { return ids[index + 1] }
        return repeatMode == .off ? nil : ids[0]
    }

    /// The track to go back to from `current`.
    public mutating func previous(in ids: [UUID], current: UUID?) -> UUID? {
        guard !ids.isEmpty else { return nil }
        if shuffle {
            if let current, history.last == current { history.removeLast() }
            while let candidate = history.popLast() {
                if ids.contains(candidate) { return candidate }
            }
            return current.flatMap { ids.contains($0) ? $0 : nil } ?? ids[0]
        }
        guard let current, let index = ids.firstIndex(of: current) else { return ids[0] }
        if index > 0 { return ids[index - 1] }
        return repeatMode == .all ? ids[ids.count - 1] : ids[0]
    }
}
