import CoreGraphics
import Foundation

/// What the renderer needs to know about one playlist row.
public struct PlaylistRow {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var fileName: String?
    public var duration: Double?
    public var unplayable: Bool

    public init(title: String? = nil, artist: String? = nil, album: String? = nil,
                fileName: String? = nil, duration: Double? = nil, unplayable: Bool = false) {
        self.title = title; self.artist = artist; self.album = album
        self.fileName = fileName; self.duration = duration; self.unplayable = unplayable
    }
}

/// A snapshot of everything a skin can show. The renderer reads it and nothing else.
public struct RenderState {
    public var values = TemplateValues()
    public var isPlaying = false
    public var isPaused = false
    /// Playback position from 0 to 1.
    public var seekFraction = 0.0
    public var volume = 1.0
    public var shuffle = false
    public var repeatOn = false
    public var repeatOne = false
    public var scopeMode = false
    /// Bar levels from 0 to 1, any count; the renderer maps them onto each visualizer's bars.
    public var bars: [Float] = []
    public var peaks: [Float] = []
    /// Waveform samples from -1 to 1.
    public var scope: [Float] = []
    public var rowCount = 0
    public var row: (Int) -> PlaylistRow = { _ in PlaylistRow() }
    public var currentRow: Int?
    public var selection = IndexSet()
    public var playlistScroll: CGFloat = 0
    /// Row index a dragged row would be inserted before.
    public var dropIndicatorRow: Int?
    public var hoverElement: Int?
    public var pressedElement: Int?
    /// A slider being dragged shows this value instead of the real one.
    public var dragSlider: (element: Int, value: Double)?
    /// Seconds; drives scrolling text.
    public var marqueeTime = 0.0
    public var errorBanner: String?
    /// Preview only: draw a likeness of the system window buttons and corner radius.
    public var drawWindowButtons = false

    public init() {}

    /// Made-up content for previews and tests.
    public static func sample(playing: Bool) -> RenderState {
        let tracks: [(String, Double)] = [
            ("Harbor Lights", 252), ("Paper Lanterns", 185), ("Low Tide Radio", 227),
            ("Salt and Static", 321), ("Last Boat Home", 280),
        ]
        var s = RenderState()
        s.values.title = tracks[2].0
        s.values.artist = "Night Ferry"
        s.values.album = "Harbor"
        s.values.fileName = "03 Low Tide Radio.flac"
        s.values.index = 3
        s.values.count = tracks.count
        s.values.duration = tracks[2].1
        s.values.elapsed = playing ? 84 : 0
        s.values.codec = "FLAC"
        s.values.sampleRate = 44100
        s.values.bitrate = 912_000
        s.values.channels = 2
        s.values.state = playing ? "playing" : "stopped"
        s.isPlaying = playing
        s.seekFraction = playing ? 84.0 / 227.0 : 0
        s.volume = 0.68
        s.rowCount = tracks.count
        s.row = { i in
            i < tracks.count
                ? PlaylistRow(title: tracks[i].0, artist: "Night Ferry", album: "Harbor", duration: tracks[i].1)
                : PlaylistRow(fileName: "Track \(i + 1).mp3", duration: 200)
        }
        s.currentRow = 2
        if playing {
            s.bars = (0..<64).map { i in
                let x = Float(i) / 64
                return min(1, (0.3 + 0.6 * abs(sin(Float(i) * 0.83 + 0.4))) * (1 - 0.55 * x))
            }
            s.peaks = s.bars.map { min(1, $0 + 0.1) }
            s.scope = (0..<256).map { i in
                let t = Float(i) / 256
                return 0.55 * sin(t * 19) + 0.25 * sin(t * 57 + 1)
            }
        }
        return s
    }
}
