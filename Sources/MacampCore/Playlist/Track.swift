import Foundation

/// One playlist entry. Kept small on purpose: a long playlist holds one of these per file.
public struct Track: Codable, Equatable, Identifiable {
    public let id: UUID
    public var url: URL
    public var title: String?
    public var artist: String?
    public var album: String?
    public var duration: Double?
    /// The file is missing, unreadable or not audio.
    public var unplayable = false
    /// Tags and duration have been read from the file.
    public var metadataLoaded = false

    public init(url: URL) {
        self.id = UUID()
        self.url = url
    }

    public var fileName: String { url.lastPathComponent }
}
