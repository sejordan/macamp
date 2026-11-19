import Foundation

/// The short track that ships with the app and sits in the playlist the first time it is opened.
public enum WelcomeTrack {
    public static let fileName = "macamp.mp3"

    /// Copies the bundled track into `folder` and returns where it now lives, or nil if there is
    /// no bundled track or it cannot be copied. The copy is what goes in the playlist, so the
    /// entry keeps working if the app itself is later moved or replaced.
    public static func install(from bundled: URL?, into folder: URL) -> URL? {
        let fm = FileManager.default
        guard let bundled, fm.fileExists(atPath: bundled.path) else { return nil }
        let destination = folder.appendingPathComponent(fileName)
        if fm.fileExists(atPath: destination.path) { return destination }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.copyItem(at: bundled, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
