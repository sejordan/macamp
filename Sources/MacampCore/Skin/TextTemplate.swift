import Foundation

/// Everything a text template can show. Missing values render as empty text.
public struct TemplateValues {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var fileName: String?
    /// 1-based position in the playlist.
    public var index: Int?
    public var count: Int = 0
    public var duration: Double?
    public var elapsed: Double?
    public var showRemaining = false
    public var codec: String?
    public var sampleRate: Double?
    /// Bits per second.
    public var bitrate: Double?
    public var channels: Int?
    public var state = "stopped"

    public init() {}
}

/// Formats seconds as `m:ss` or `h:mm:ss`. `pad` gives two-digit minutes.
public func formatTime(_ seconds: Double?, pad: Bool) -> String {
    var total = 0
    if let s = seconds, s.isFinite, s > 0 { total = Int(min(s, 359_999)) }
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: pad ? "%02d:%02d" : "%d:%02d", m, s)
}

/// Text with `{token}` placeholders, parsed once and rendered many times.
public struct TextTemplate: Equatable {
    public static let tokenNames: [String] = [
        "title", "artist", "album", "display", "index", "count",
        "duration", "elapsed", "remaining", "time",
        "codec", "sampleRate", "bitrate", "channels", "state",
    ]
    private static let timeTokens: Set<String> = ["duration", "elapsed", "remaining", "time"]

    enum Segment: Equatable {
        case literal(String)
        case token(name: String, pad: Bool)
    }

    public let source: String
    let segments: [Segment]
    public let unknownTokens: [String]

    public var isDynamic: Bool {
        segments.contains { if case .token = $0 { return true } else { return false } }
    }

    public init(_ source: String) {
        self.source = source
        var segments: [Segment] = []
        var unknown: [String] = []
        var literal = ""
        var i = source.startIndex
        while i < source.endIndex {
            let c = source[i]
            let next = source.index(after: i)
            if c == "{" {
                if next < source.endIndex, source[next] == "{" {
                    literal.append("{")
                    i = source.index(after: next)
                    continue
                }
                if let close = source[next...].firstIndex(of: "}"),
                   !source[next..<close].contains("{") {
                    let body = String(source[next..<close])
                    let parts = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    let name = String(parts[0])
                    let modifier = parts.count > 1 ? String(parts[1]) : nil
                    let known = Self.tokenNames.contains(name)
                        && (modifier == nil || (modifier == "pad" && Self.timeTokens.contains(name)))
                    if known {
                        if !literal.isEmpty { segments.append(.literal(literal)); literal = "" }
                        segments.append(.token(name: name, pad: modifier == "pad"))
                    } else {
                        unknown.append(body)
                        literal.append("{\(body)}")
                    }
                    i = source.index(after: close)
                    continue
                }
            }
            literal.append(c)
            i = next
        }
        if !literal.isEmpty { segments.append(.literal(literal)) }
        self.segments = segments
        self.unknownTokens = unknown
    }

    public func render(_ v: TemplateValues) -> String {
        var out = ""
        for segment in segments {
            switch segment {
            case .literal(let s): out += s
            case .token(let name, let pad): out += Self.value(name, pad: pad, v)
            }
        }
        return out
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    private static func baseName(_ v: TemplateValues) -> String {
        guard let f = nonEmpty(v.fileName) else { return "" }
        return (f as NSString).deletingPathExtension
    }

    private static func value(_ name: String, pad: Bool, _ v: TemplateValues) -> String {
        switch name {
        case "title": return nonEmpty(v.title) ?? baseName(v)
        case "artist": return v.artist ?? ""
        case "album": return v.album ?? ""
        case "display":
            if let t = nonEmpty(v.title) {
                if let a = nonEmpty(v.artist) { return "\(a) - \(t)" }
                return t
            }
            return baseName(v)
        case "index": return v.index.map(String.init) ?? ""
        case "count": return String(v.count)
        case "duration": return v.duration == nil ? "" : formatTime(v.duration, pad: pad)
        case "elapsed": return formatTime(v.elapsed, pad: pad)
        case "remaining": return remaining(v, pad: pad)
        case "time": return v.showRemaining ? remaining(v, pad: pad) : formatTime(v.elapsed, pad: pad)
        case "codec": return v.codec ?? ""
        case "sampleRate":
            guard let r = v.sampleRate, r > 0 else { return "" }
            let khz = (r / 100).rounded() / 10
            return khz == khz.rounded() ? "\(Int(khz)) kHz" : "\(khz) kHz"
        case "bitrate":
            guard let b = v.bitrate, b > 0 else { return "" }
            return "\(Int((b / 1000).rounded())) kbps"
        case "channels":
            guard let c = v.channels, c > 0 else { return "" }
            return c == 1 ? "mono" : c == 2 ? "stereo" : "\(c) ch"
        case "state": return v.state
        default: return ""
        }
    }

    private static func remaining(_ v: TemplateValues, pad: Bool) -> String {
        let left = max(0, (v.duration ?? 0) - (v.elapsed ?? 0))
        return "-" + formatTime(left, pad: pad)
    }
}
