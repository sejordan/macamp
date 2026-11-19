import AudioToolbox
import Foundation

/// Tags and length read from an audio file.
public struct TrackTags: Equatable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var duration: Double?
}

public enum TrackMetadata {
    /// Reads tags without decoding audio. Returns nil when the file cannot be read as audio.
    /// This touches the disk, so call it off the main thread.
    public static func read(_ url: URL) -> TrackTags? {
        var handle: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &handle) == noErr, let file = handle else { return nil }
        defer { AudioFileClose(file) }

        var tags = TrackTags()
        var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        var dictionary: Unmanaged<CFDictionary>?
        if AudioFileGetProperty(file, kAudioFilePropertyInfoDictionary, &size, &dictionary) == noErr,
           let values = dictionary?.takeRetainedValue() as? [String: Any] {
            func text(_ key: String) -> String? {
                guard let s = (values[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
                return s
            }
            tags.title = text(kAFInfoDictionary_Title)
            tags.artist = text(kAFInfoDictionary_Artist)
            tags.album = text(kAFInfoDictionary_Album)
        }
        var seconds: Float64 = 0
        var secondsSize = UInt32(MemoryLayout<Float64>.size)
        if AudioFileGetProperty(file, kAudioFilePropertyEstimatedDuration, &secondsSize, &seconds) == noErr,
           seconds.isFinite, seconds > 0 {
            tags.duration = seconds
        }
        if tags.duration == nil, tags.title == nil, tags.artist == nil { return nil }
        return tags
    }
}
