import Foundation

/// The ordered list of tracks and which one is current.
public final class Playlist {
    public private(set) var tracks: [Track] = []
    /// The current track is tracked by identity, so edits to the list never lose it.
    public var currentID: UUID?

    public init() {}

    public var count: Int { tracks.count }
    public var ids: [UUID] { tracks.map(\.id) }

    /// Where the current track was last found. It is asked for on every frame,
    /// so the common case must not search the whole list.
    private var currentIndexHint = 0

    public var currentIndex: Int? {
        guard let currentID else { return nil }
        if tracks.indices.contains(currentIndexHint), tracks[currentIndexHint].id == currentID { return currentIndexHint }
        guard let found = tracks.firstIndex(where: { $0.id == currentID }) else { return nil }
        currentIndexHint = found
        return found
    }

    public var current: Track? { currentIndex.map { tracks[$0] } }

    public func index(of id: UUID) -> Int? { tracks.firstIndex { $0.id == id } }

    @discardableResult
    public func append(_ urls: [URL]) -> Range<Int> {
        let start = tracks.count
        tracks.append(contentsOf: urls.map(Track.init(url:)))
        return start..<tracks.count
    }

    public func remove(at indexes: IndexSet) {
        let valid = indexes.filteredIndexSet { $0 >= 0 && $0 < tracks.count }
        guard !valid.isEmpty else { return }
        if let current = currentIndex, valid.contains(current) { currentID = nil }
        for index in valid.reversed() { tracks.remove(at: index) }
    }

    /// Moves rows so they sit before the row that was at `destination`. Returns their new positions.
    @discardableResult
    public func move(from indexes: IndexSet, to destination: Int) -> IndexSet {
        let valid = indexes.filteredIndexSet { $0 >= 0 && $0 < tracks.count }
        guard !valid.isEmpty else { return IndexSet() }
        let target = min(max(destination, 0), tracks.count)
        let moving = valid.map { tracks[$0] }
        let insertAt = target - valid.count(in: 0..<target)
        for index in valid.reversed() { tracks.remove(at: index) }
        tracks.insert(contentsOf: moving, at: insertAt)
        return IndexSet(integersIn: insertAt..<insertAt + moving.count)
    }

    public func clear() {
        tracks.removeAll()
        currentID = nil
    }

    public func update(id: UUID, _ change: (inout Track) -> Void) {
        guard let index = index(of: id) else { return }
        change(&tracks[index])
    }

    public func replaceAll(_ newTracks: [Track], currentID: UUID?) {
        tracks = newTracks
        self.currentID = newTracks.contains { $0.id == currentID } ? currentID : nil
    }
}
