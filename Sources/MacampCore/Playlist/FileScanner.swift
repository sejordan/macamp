import Foundation

/// Turns whatever the user dropped or opened into a flat list of audio files.
public enum FileScanner {
    public static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "flac", "wav", "wave", "aif", "aiff", "aifc", "caf",
    ]

    public static func isAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isSkinFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "json"
    }

    /// Files keep the order given. Each folder is read recursively and sorted the way Finder sorts names.
    public static func expand(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                if isAudioFile(url) { result.append(url) }
                continue
            }
            var found: [URL] = []
            let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let item = walker?.nextObject() as? URL {
                if isAudioFile(item), (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    found.append(item)
                }
            }
            found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            result.append(contentsOf: found)
        }
        return result
    }
}
