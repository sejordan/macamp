import CoreGraphics
import CoreText
import Foundation

/// Turns skin JSON into a `Skin`, reporting every problem with the JSON path it was found at.
public enum SkinParser {
    public static let formatVersion = 1
    public static let elementTypes = ["rect", "text", "visualizer", "slider", "button", "playlist"]
    public static let maxElements = 500
    public static let windowSizeRange = 80.0...2000.0
    /// Element positions and sizes must stay within this many points. Far larger than any
    /// window, and small enough that nothing downstream overflows or loops for minutes.
    public static let maxCoordinate = 10_000.0
    public static let defaultForeground = RGBA(hex: "#d0d0d0")!
    public static let defaultBackground = RGBA(hex: "#1e1e1e")!

    /// Every field the parser reads, by the kind of object it appears in.
    /// The reader refuses to read a field missing from this table, which keeps
    /// the unknown-field warning and the documentation honest.
    public static let knownFields: [String: [String]] = [
        "top": ["format", "name", "author", "window", "palette", "paletteDark", "elements"],
        "window": ["size", "cornerRadius", "background", "border", "titleBar", "resize", "minHeight", "maxHeight"],
        "element": ["type", "frame", "anchor"],
        "rect": ["fill", "border", "cornerRadius", "bevel"],
        "text": ["text", "font", "color", "glow", "align", "overflow", "action"],
        "visualizer": ["bars", "gap", "colors", "segment", "peaks", "peakColor", "cornerRadius", "glow",
                       "scopeColor", "scopeWidth", "background"],
        "slider": ["binds", "track", "progress", "thumb"],
        "button": ["action", "icon", "label", "font", "iconSize", "style", "hover", "pressed", "on"],
        "playlist": ["rowHeight", "font", "text", "detail", "color", "detailColor", "currentColor",
                     "currentBackground", "selectedColor", "selectedBackground", "unplayableColor",
                     "background", "padding", "rowCornerRadius", "rowInset"],
        "font": ["family", "size", "weight"],
        "border": ["color", "width"],
        "bevel": ["light", "dark", "width"],
        "glow": ["radius", "color"],
        "gradient": ["gradient", "angle"],
        "box": ["fill", "border", "cornerRadius", "bevel"],
        "track": ["fill", "border", "cornerRadius", "bevel", "thickness"],
        "thumb": ["fill", "border", "cornerRadius", "bevel", "size"],
        "buttonStyle": ["fill", "border", "cornerRadius", "bevel", "color", "glow"],
    ]

    public static func parse(data: Data, dark: Bool = false) -> SkinParseResult {
        let log = IssueLog()
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
            log.error("$", "not valid JSON: \(detail ?? error.localizedDescription)")
            return SkinParseResult(skin: nil, issues: log.issues)
        }
        guard let dict = json as? [String: Any] else {
            log.error("$", "expected an object at the top level")
            return SkinParseResult(skin: nil, issues: log.issues)
        }
        let skin = SkinBuilder(log: log, dark: dark).build(dict)
        return SkinParseResult(skin: log.hasErrors ? nil : skin, issues: log.issues)
    }
}

final class IssueLog {
    private(set) var issues: [SkinIssue] = []
    var hasErrors: Bool { issues.contains { $0.severity == .error } }
    func error(_ path: String, _ message: String) {
        issues.append(SkinIssue(severity: .error, path: path, message: message))
    }
    func warning(_ path: String, _ message: String) {
        issues.append(SkinIssue(severity: .warning, path: path, message: message))
    }
}

/// Reads fields of one JSON object, remembering where it is for error messages.
final class ObjectReader {
    let dict: [String: Any]
    let path: String
    let log: IssueLog
    let palette: [String: RGBA]
    private var allowed: Set<String> = []

    init(_ dict: [String: Any], path: String, kinds: [String], log: IssueLog, palette: [String: RGBA]) {
        self.dict = dict
        self.path = path
        self.log = log
        self.palette = palette
        for kind in kinds { allowed.formUnion(SkinParser.knownFields[kind] ?? []) }
    }

    func at(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    func has(_ key: String) -> Bool { raw(key) != nil }

    func raw(_ key: String) -> Any? {
        precondition(allowed.contains(key), "field '\(key)' is missing from SkinParser.knownFields")
        guard let value = dict[key], !(value is NSNull) else { return nil }
        return value
    }

    /// Warns about fields nothing reads, suggesting the nearest known name.
    func warnAboutUnknownFields() {
        for key in dict.keys.sorted() where !allowed.contains(key) {
            let near = allowed.map { ($0, editDistance($0.lowercased(), key.lowercased())) }
                .filter { $0.1 <= 2 }.min { $0.1 < $1.1 }?.0
            log.warning(at(key), "unknown field" + (near.map { "; did you mean '\($0)'?" } ?? ""))
        }
    }

    private static func isBool(_ value: Any) -> Bool {
        guard let n = value as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    static func asNumber(_ value: Any) -> Double? {
        guard let n = value as? NSNumber, !isBool(value) else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    func number(_ key: String, default fallback: Double, min: Double = -.infinity, max: Double = .infinity) -> Double {
        guard let value = raw(key) else { return fallback }
        guard let d = Self.asNumber(value) else {
            log.error(at(key), "expected a number")
            return fallback
        }
        guard d >= min, d <= max else {
            log.error(at(key), "must be \(Self.rangeText(min, max)), got \(Self.trim(d))")
            return fallback
        }
        return d
    }

    func optionalNumber(_ key: String, min: Double = -.infinity, max: Double = .infinity) -> Double? {
        has(key) ? number(key, default: 0, min: min, max: max) : nil
    }

    func int(_ key: String, default fallback: Int, min: Int, max: Int) -> Int {
        guard let value = raw(key) else { return fallback }
        guard let d = Self.asNumber(value), d == d.rounded() else {
            log.error(at(key), "expected a whole number")
            return fallback
        }
        guard d >= Double(min), d <= Double(max) else {
            log.error(at(key), "must be from \(min) to \(max), got \(Self.trim(d))")
            return fallback
        }
        return Int(d)
    }

    func bool(_ key: String, default fallback: Bool) -> Bool {
        guard let value = raw(key) else { return fallback }
        guard Self.isBool(value), let b = value as? Bool else {
            log.error(at(key), "expected true or false")
            return fallback
        }
        return b
    }

    func string(_ key: String) -> String? {
        guard let value = raw(key) else { return nil }
        guard let s = value as? String else {
            log.error(at(key), "expected text")
            return nil
        }
        return s
    }

    func choice<E: RawRepresentable & CaseIterable>(_ key: String, default fallback: E) -> E where E.RawValue == String {
        optionalChoice(key) ?? fallback
    }

    func optionalChoice<E: RawRepresentable & CaseIterable>(_ key: String) -> E? where E.RawValue == String {
        guard let value = raw(key) else { return nil }
        if let s = value as? String, let e = E(rawValue: s) { return e }
        let options = E.allCases.map(\.rawValue).joined(separator: ", ")
        log.error(at(key), "expected one of: \(options)")
        return nil
    }

    func numbers(_ key: String, count: Int) -> [Double]? {
        guard let value = raw(key) else { return nil }
        guard let array = value as? [Any] else {
            log.error(at(key), "expected \(count) numbers")
            return nil
        }
        let parsed = array.compactMap(Self.asNumber)
        guard parsed.count == array.count, array.count == count else {
            log.error(at(key), "expected \(count) numbers, got \(parsed.count == array.count ? "\(array.count)" : "other values")")
            return nil
        }
        return parsed
    }

    func child(_ key: String, kinds: [String]) -> ObjectReader? {
        guard let value = raw(key) else { return nil }
        guard let d = value as? [String: Any] else {
            log.error(at(key), "expected an object")
            return nil
        }
        return ObjectReader(d, path: at(key), kinds: kinds, log: log, palette: palette)
    }

    // MARK: Colors and fills

    func parseColor(_ value: Any, at where: String) -> RGBA? {
        guard let s = value as? String else {
            log.error(`where`, "expected a color such as \"#rrggbb\" or \"$name\"")
            return nil
        }
        if s.hasPrefix("$") {
            let name = String(s.dropFirst())
            if let c = palette[name] { return c }
            let names = palette.keys.sorted().map { "$" + $0 }.joined(separator: ", ")
            log.error(`where`, "unknown palette color '\(s)'" + (names.isEmpty ? "; the skin has no palette" : "; palette has \(names)"))
            return nil
        }
        if let c = RGBA(hex: s) { return c }
        log.error(`where`, "'\(s)' is not a color; use #rgb, #rrggbb, #rrggbbaa or $name")
        return nil
    }

    func color(_ key: String) -> RGBA? {
        guard let value = raw(key) else { return nil }
        return parseColor(value, at: at(key))
    }

    func color(_ key: String, default fallback: RGBA) -> RGBA { color(key) ?? fallback }

    func colors(_ key: String) -> [RGBA]? {
        guard let value = raw(key) else { return nil }
        guard let array = value as? [Any], !array.isEmpty else {
            log.error(at(key), "expected a list of at least one color")
            return nil
        }
        var out: [RGBA] = []
        for (i, item) in array.enumerated() {
            guard let c = parseColor(item, at: "\(at(key))[\(i)]") else { return nil }
            out.append(c)
        }
        return out
    }

    func fill(_ key: String) -> Fill? {
        guard let value = raw(key) else { return nil }
        let here = at(key)
        if let d = value as? [String: Any] {
            let r = ObjectReader(d, path: here, kinds: ["gradient"], log: log, palette: palette)
            guard let list = d["gradient"] as? [Any] else {
                log.error(here, "expected a color or {\"gradient\": [colors], \"angle\": degrees}")
                return nil
            }
            guard list.count >= 2 else {
                log.error(here, "a gradient needs at least 2 colors, got \(list.count)")
                return nil
            }
            var stops: [RGBA] = []
            for (i, item) in list.enumerated() {
                guard let c = parseColor(item, at: "\(here).gradient[\(i)]") else { return nil }
                stops.append(c)
            }
            let angle = r.number("angle", default: 90)
            r.warnAboutUnknownFields()
            return .gradient(stops: stops, angle: angle)
        }
        return parseColor(value, at: here).map(Fill.solid)
    }

    func border(_ key: String) -> Border? {
        guard let r = child(key, kinds: ["border"]) else { return nil }
        defer { r.warnAboutUnknownFields() }
        guard let color = r.color("color") else {
            if !r.has("color") { log.error(r.at("color"), "missing") }
            return nil
        }
        return Border(color: color, width: r.number("width", default: 1, min: 0, max: 100))
    }

    func bevel(_ key: String) -> Bevel? {
        guard let r = child(key, kinds: ["bevel"]) else { return nil }
        defer { r.warnAboutUnknownFields() }
        return Bevel(light: r.color("light", default: RGBA(1, 1, 1, 0.35)),
                     dark: r.color("dark", default: RGBA(0, 0, 0, 0.5)),
                     width: r.number("width", default: 1, min: 0, max: 20))
    }

    func glow(_ key: String) -> Glow? {
        guard let value = raw(key) else { return nil }
        if let radius = Self.asNumber(value) {
            guard radius >= 0, radius <= 100 else {
                log.error(at(key), "must be from 0 to 100, got \(Self.trim(radius))")
                return nil
            }
            return Glow(color: nil, radius: radius)
        }
        guard let r = child(key, kinds: ["glow"]) else { return nil }
        defer { r.warnAboutUnknownFields() }
        return Glow(color: r.color("color"), radius: r.number("radius", default: 4, min: 0, max: 100))
    }

    func font(_ key: String, default fallback: FontSpec = .standard) -> FontSpec {
        guard let r = child(key, kinds: ["font"]) else { return fallback }
        defer { r.warnAboutUnknownFields() }
        var spec = fallback
        if let family = r.string("family") {
            spec.family = family
            if !FontCatalog.isAvailable(family) {
                log.warning(r.at("family"), "font '\(family)' is not installed; the system monospaced font will be used")
            }
        }
        spec.size = r.number("size", default: fallback.size, min: 4, max: 200)
        if let weight = r.string("weight") {
            if FontSpec.weights.contains(weight) {
                spec.weight = weight
            } else {
                log.error(r.at("weight"), "expected one of: \(FontSpec.weights.joined(separator: ", "))")
            }
        }
        return spec
    }

    /// Reads fill, border, cornerRadius and bevel from this object, starting from `base`.
    func box(over base: BoxStyle = BoxStyle()) -> BoxStyle {
        var box = base
        if has("fill") { box.fill = fill("fill") }
        if has("border") { box.border = border("border") }
        if has("cornerRadius") { box.cornerRadius = number("cornerRadius", default: 0, min: 0, max: 1000) }
        if has("bevel") { box.bevel = bevel("bevel") }
        return box
    }

    static func trim(_ d: Double) -> String {
        d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
    }

    private static func rangeText(_ min: Double, _ max: Double) -> String {
        if max == .infinity { return "at least \(trim(min))" }
        if min == -.infinity { return "at most \(trim(max))" }
        return "from \(trim(min)) to \(trim(max))"
    }
}

enum FontCatalog {
    static let special: Set<String> = ["system", "systemmono"]
    private static let families: Set<String> = {
        let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return Set(names.map { $0.lowercased() })
    }()

    static func isAvailable(_ family: String) -> Bool {
        let key = family.lowercased()
        return special.contains(key) || families.contains(key)
    }
}

func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var row = Array(0...b.count)
    for i in 1...a.count {
        var previous = row[0]
        row[0] = i
        for j in 1...b.count {
            let saved = row[j]
            row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
            previous = saved
        }
    }
    return row[b.count]
}

private struct SkinBuilder {
    let log: IssueLog
    let dark: Bool

    func build(_ dict: [String: Any]) -> Skin? {
        let palette = buildPalette(dict)
        let top = ObjectReader(dict, path: "", kinds: ["top"], log: log, palette: palette)
        _ = top.raw("palette"); _ = top.raw("paletteDark")

        if let value = top.raw("format") {
            if ObjectReader.asNumber(value) != Double(SkinParser.formatVersion) {
                log.error("format", "this app reads format \(SkinParser.formatVersion) only")
            }
        } else {
            log.error("format", "missing; expected \(SkinParser.formatVersion)")
        }

        let name = top.string("name") ?? "Untitled"
        let author = top.string("author")

        var window: SkinWindow?
        if top.has("window") {
            if let w = top.child("window", kinds: ["window"]) { window = buildWindow(w) }
        } else {
            log.error("window", "missing")
        }

        var elements: [SkinElement] = []
        if let value = top.raw("elements") {
            if let array = value as? [Any] {
                if array.count > SkinParser.maxElements {
                    log.error("elements", "a skin can have at most \(SkinParser.maxElements) elements, got \(array.count)")
                } else {
                    for (i, item) in array.enumerated() {
                        if let e = buildElement(item, index: i, palette: palette, window: window) { elements.append(e) }
                    }
                    if !log.hasErrors { warnIfUnplayable(elements) }
                }
            } else {
                log.error("elements", "expected a list")
            }
        } else {
            log.error("elements", "missing")
        }
        top.warnAboutUnknownFields()

        guard let window else { return nil }
        return Skin(name: name, author: author, window: window, elements: elements,
                    followsAppearance: dict["paletteDark"] is [String: Any])
    }

    private func buildPalette(_ dict: [String: Any]) -> [String: RGBA] {
        var palette: [String: RGBA] = [:]
        for key in ["palette"] + (dark ? ["paletteDark"] : []) {
            guard let value = dict[key], !(value is NSNull) else { continue }
            guard let entries = value as? [String: Any] else {
                log.error(key, "expected an object of name: color pairs")
                continue
            }
            for name in entries.keys.sorted() {
                if let s = entries[name] as? String, let c = RGBA(hex: s) {
                    palette[name] = c
                } else {
                    log.error("\(key).\(name)", "expected a color such as \"#rrggbb\"")
                }
            }
        }
        // Dark entries are still checked in light mode, so a typo there shows up either way.
        if !dark, let entries = dict["paletteDark"] as? [String: Any] {
            for name in entries.keys.sorted() where (entries[name] as? String).flatMap(RGBA.init(hex:)) == nil {
                log.error("paletteDark.\(name)", "expected a color such as \"#rrggbb\"")
            }
        }
        return palette
    }

    private func buildWindow(_ r: ObjectReader) -> SkinWindow? {
        defer { r.warnAboutUnknownFields() }
        let range = SkinParser.windowSizeRange
        var size: CGSize?
        if r.has("size") {
            if let n = r.numbers("size", count: 2) {
                if range.contains(n[0]), range.contains(n[1]) {
                    size = CGSize(width: n[0], height: n[1])
                } else {
                    log.error(r.at("size"), "width and height must each be from \(Int(range.lowerBound)) to \(Int(range.upperBound))")
                }
            }
        } else {
            log.error(r.at("size"), "missing; expected [width, height]")
        }
        let titleBar: TitleBar = r.choice("titleBar", default: .system)
        let cornerRadius = r.number("cornerRadius", default: 0, min: 0, max: 200)
        if titleBar == .system, cornerRadius != 0 {
            log.warning(r.at("cornerRadius"), "ignored when titleBar is \"system\"; the system sets the corner radius")
        }
        let background = r.fill("background") ?? .solid(SkinParser.defaultBackground)
        let border = r.border("border")
        let resize: ResizeMode = r.choice("resize", default: .none)
        guard let size else { return nil }
        let height = Double(size.height)
        let minHeight = r.number("minHeight", default: height, min: range.lowerBound, max: range.upperBound)
        let maxHeight = r.number("maxHeight", default: Swift.max(height, range.upperBound), min: range.lowerBound, max: range.upperBound)
        if minHeight > height {
            log.error(r.at("minHeight"), "must not be greater than the window height \(ObjectReader.trim(height))")
        }
        if maxHeight < height {
            log.error(r.at("maxHeight"), "must not be less than the window height \(ObjectReader.trim(height))")
        }
        return SkinWindow(size: size, cornerRadius: cornerRadius, background: background, border: border,
                          titleBar: titleBar, resize: resize, minHeight: minHeight, maxHeight: maxHeight)
    }

    private func buildElement(_ item: Any, index: Int, palette: [String: RGBA], window: SkinWindow?) -> SkinElement? {
        let path = "elements[\(index)]"
        guard let dict = item as? [String: Any] else {
            log.error(path, "expected an object")
            return nil
        }
        guard let type = dict["type"] as? String else {
            log.error("\(path).type", "missing; expected one of: \(SkinParser.elementTypes.joined(separator: ", "))")
            return nil
        }
        guard SkinParser.elementTypes.contains(type) else {
            log.error("\(path).type", "unknown type '\(type)'; expected one of: \(SkinParser.elementTypes.joined(separator: ", "))")
            return nil
        }
        let r = ObjectReader(dict, path: path, kinds: ["element", type], log: log, palette: palette)
        defer { r.warnAboutUnknownFields() }
        _ = r.raw("type")

        var frame: CGRect?
        if r.has("frame") {
            if let n = r.numbers("frame", count: 4) {
                let limit = SkinParser.maxCoordinate
                if n[2] <= 0 || n[3] <= 0 {
                    log.error(r.at("frame"), "width and height must be greater than 0, got \(ObjectReader.trim(n[2])) by \(ObjectReader.trim(n[3]))")
                } else if n.contains(where: { abs($0) > limit }) {
                    log.error(r.at("frame"), "every value must be within \(Int(limit)) points of zero")
                } else {
                    frame = CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
                }
            }
        } else {
            log.error(r.at("frame"), "missing; expected [x, y, width, height]")
        }
        let anchor: Anchor = r.choice("anchor", default: .top)

        let kind: SkinElement.Kind?
        switch type {
        case "rect": kind = .rect(RectElement(box: r.box()))
        case "text": kind = buildText(r).map(SkinElement.Kind.text)
        case "visualizer": kind = .visualizer(buildVisualizer(r))
        case "slider": kind = buildSlider(r, frame: frame).map(SkinElement.Kind.slider)
        case "button": kind = buildButton(r).map(SkinElement.Kind.button)
        default: kind = .playlist(buildPlaylist(r))
        }
        guard let frame, let kind else { return nil }
        if let window, !frame.intersects(CGRect(origin: .zero, size: window.size)) {
            log.warning(r.at("frame"), "lies entirely outside the \(Int(window.size.width)) by \(Int(window.size.height)) window")
        }
        return SkinElement(frame: frame, anchor: anchor, kind: kind)
    }

    private func template(_ r: ObjectReader, _ key: String, default fallback: String?) -> TextTemplate? {
        guard let source = r.string(key) ?? (r.has(key) ? nil : fallback) else { return nil }
        let t = TextTemplate(source)
        if !t.unknownTokens.isEmpty {
            let list = t.unknownTokens.map { "{\($0)}" }.joined(separator: ", ")
            log.warning(r.at(key), "unknown token \(list); known tokens are \(TextTemplate.tokenNames.joined(separator: ", "))")
        }
        return t
    }

    private func buildText(_ r: ObjectReader) -> TextElement? {
        if !r.has("text") { log.error(r.at("text"), "missing") }
        let t = template(r, "text", default: nil)
        let element = TextElement(template: t ?? TextTemplate(""),
                                  font: r.font("font"),
                                  color: r.color("color", default: SkinParser.defaultForeground),
                                  glow: r.glow("glow"),
                                  align: r.choice("align", default: .left),
                                  overflow: r.choice("overflow", default: .clip),
                                  action: r.optionalChoice("action"))
        return t == nil ? nil : element
    }

    private func buildVisualizer(_ r: ObjectReader) -> VisualizerElement {
        let colors = r.colors("colors") ?? [SkinParser.defaultForeground]
        return VisualizerElement(bars: r.int("bars", default: 19, min: 1, max: 128),
                                 gap: r.number("gap", default: 2, min: 0, max: 100),
                                 colors: colors,
                                 segment: r.number("segment", default: 0, min: 0, max: 100),
                                 peaks: r.bool("peaks", default: false),
                                 peakColor: r.color("peakColor", default: colors[colors.count - 1]),
                                 cornerRadius: r.number("cornerRadius", default: 0, min: 0, max: 100),
                                 glow: r.glow("glow"),
                                 scopeColor: r.color("scopeColor", default: colors[0]),
                                 scopeWidth: r.number("scopeWidth", default: 1.5, min: 0.25, max: 20),
                                 background: r.fill("background"))
    }

    private func buildSlider(_ r: ObjectReader, frame: CGRect?) -> SliderElement? {
        let binds: SliderBinding? = r.optionalChoice("binds")
        if !r.has("binds") { log.error(r.at("binds"), "missing; expected seek or volume") }

        var track = BoxStyle(fill: .solid(RGBA(hex: "#444444")!))
        var thickness: Double?
        if let t = r.child("track", kinds: ["track"]) {
            track = t.box(over: track)
            thickness = t.optionalNumber("thickness", min: 0.5, max: 500)
            t.warnAboutUnknownFields()
        }
        var progress: BoxStyle? = BoxStyle(fill: .solid(SkinParser.defaultForeground))
        if let p = r.child("progress", kinds: ["box"]) {
            progress = p.box()
            p.warnAboutUnknownFields()
        }
        var thumb: BoxStyle?
        let shortSide = frame.map { Double(min($0.width, $0.height)) } ?? 10
        var thumbSize = CGSize(width: shortSide, height: shortSide)
        if let t = r.child("thumb", kinds: ["thumb"]) {
            thumb = t.box(over: BoxStyle(fill: .solid(SkinParser.defaultForeground)))
            if t.has("size"), let n = t.numbers("size", count: 2) {
                if n[0] > 0, n[1] > 0, n[0] <= SkinParser.maxCoordinate, n[1] <= SkinParser.maxCoordinate {
                    thumbSize = CGSize(width: n[0], height: n[1])
                } else {
                    log.error(t.at("size"), "width and height must be greater than 0 and at most \(Int(SkinParser.maxCoordinate))")
                }
            }
            t.warnAboutUnknownFields()
        }
        guard let binds else { return nil }
        return SliderElement(binds: binds, track: track, trackThickness: thickness,
                             progress: progress, thumb: thumb, thumbSize: thumbSize)
    }

    private func buttonStyle(_ r: ObjectReader, _ key: String, over base: ButtonStateStyle) -> ButtonStateStyle {
        guard let s = r.child(key, kinds: ["buttonStyle"]) else { return base }
        defer { s.warnAboutUnknownFields() }
        var style = base
        style.box = s.box(over: base.box)
        if s.has("color") { style.color = s.color("color", default: base.color) }
        if s.has("glow") { style.glow = s.glow("glow") }
        return style
    }

    private func buildButton(_ r: ObjectReader) -> ButtonElement? {
        let action: ButtonAction? = r.optionalChoice("action")
        if !r.has("action") {
            log.error(r.at("action"), "missing; expected one of: \(ButtonAction.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        var icon: String? = action?.rawValue
        if let name = r.string("icon") {
            if name == "none" {
                icon = nil
            } else if ButtonAction(rawValue: name) != nil {
                icon = name
            } else {
                log.error(r.at("icon"), "expected \"none\" or an action name: \(ButtonAction.allCases.map(\.rawValue).joined(separator: ", "))")
            }
        }
        let normal = buttonStyle(r, "style", over: ButtonStateStyle(box: BoxStyle(), color: SkinParser.defaultForeground, glow: nil))
        let element = ButtonElement(action: action ?? .play,
                                    icon: icon,
                                    label: r.string("label"),
                                    font: r.font("font"),
                                    iconSize: r.number("iconSize", default: 11, min: 2, max: 200),
                                    normal: normal,
                                    hover: buttonStyle(r, "hover", over: normal),
                                    pressed: buttonStyle(r, "pressed", over: normal),
                                    on: buttonStyle(r, "on", over: normal))
        return action == nil ? nil : element
    }

    private func buildPlaylist(_ r: ObjectReader) -> PlaylistElement {
        let color = r.color("color", default: SkinParser.defaultForeground)
        return PlaylistElement(rowHeight: r.number("rowHeight", default: 16, min: 8, max: 100),
                               font: r.font("font"),
                               text: template(r, "text", default: "{index}. {display}") ?? TextTemplate(""),
                               detail: template(r, "detail", default: "{duration}") ?? TextTemplate(""),
                               color: color,
                               detailColor: r.color("detailColor", default: color),
                               currentColor: r.color("currentColor", default: color),
                               currentBackground: r.fill("currentBackground"),
                               selectedColor: r.color("selectedColor", default: color),
                               selectedBackground: r.has("selectedBackground") ? r.fill("selectedBackground") : .solid(RGBA(1, 1, 1, 0.13)),
                               unplayableColor: r.color("unplayableColor", default: color.withAlpha(0.4)),
                               background: r.fill("background"),
                               padding: r.number("padding", default: 8, min: 0, max: 200),
                               rowCornerRadius: r.number("rowCornerRadius", default: 0, min: 0, max: 100),
                               rowInset: r.number("rowInset", default: 0, min: 0, max: 100))
    }

    private func warnIfUnplayable(_ elements: [SkinElement]) {
        let playable = elements.contains { element in
            switch element.kind {
            case .playlist: return true
            case .button(let b): return b.action == .play || b.action == .playPause
            case .text(let t): return t.action == .play || t.action == .playPause
            default: return false
            }
        }
        if !playable {
            log.warning("elements", "no play button and no playlist; playback can only be started from the menu or keyboard")
        }
    }
}
