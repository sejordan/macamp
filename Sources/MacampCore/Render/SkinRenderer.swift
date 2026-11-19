import AppKit
import CoreGraphics
import CoreText
import Foundation

/// Draws a skin into a graphics context whose y axis points down.
///
/// The live window and the PNG preview both draw through this class, which is
/// what keeps a preview honest. Every element is clipped to its own frame.
public final class SkinRenderer {
    public static let systemCornerRadius: CGFloat = 10
    public static let bannerHeight: CGFloat = 18
    static let marqueeSpeed = 30.0
    static let marqueeGap: CGFloat = 36

    public let skin: Skin
    public let layout: SkinLayout
    /// Shadow blur is measured in device pixels for contexts scaled by hand, so previews set this to their scale.
    public var shadowScale: CGFloat = 1

    private var fonts: [String: CTFont] = [:]
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public init(skin: Skin, windowHeight: CGFloat) {
        self.skin = skin
        self.layout = SkinLayout(skin: skin, windowHeight: windowHeight)
    }

    // MARK: Questions the view asks

    /// The text a text element would show, or nil for other elements.
    public func renderedText(element: Int, state: RenderState) -> String? {
        guard skin.elements.indices.contains(element), case .text(let text) = skin.elements[element].kind else { return nil }
        return text.template.render(state.values)
    }

    /// True when a scrolling text element is too long for its frame and must animate.
    public func needsMarquee(element: Int, state: RenderState) -> Bool {
        guard skin.elements.indices.contains(element), case .text(let text) = skin.elements[element].kind,
              text.overflow == .scroll else { return false }
        let string = text.template.render(state.values)
        guard !string.isEmpty else { return false }
        return lineWidth(makeLine(string, font: text.font, color: text.color)) > layout.frames[element].width
    }

    public func barCount(element: Int) -> Int {
        guard skin.elements.indices.contains(element), case .visualizer(let viz) = skin.elements[element].kind else { return 0 }
        return viz.bars
    }

    // MARK: Drawing

    public func draw(in ctx: CGContext, state: RenderState, dirty: CGRect?) {
        let window = layout.windowRect
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if let dirty { ctx.clip(to: dirty) }

        let radius: CGFloat
        switch skin.window.titleBar {
        case .none: radius = CGFloat(skin.window.cornerRadius)
        case .system: radius = state.drawWindowButtons ? Self.systemCornerRadius : 0
        }
        if radius > 0 {
            ctx.addPath(roundedPath(window, radius))
            ctx.clip()
        }
        paint(skin.window.background, path: CGPath(rect: window, transform: nil), bounds: window, ctx)

        for (i, element) in skin.elements.enumerated() {
            let frame = layout.frames[i]
            if let dirty, !frame.intersects(dirty) { continue }
            ctx.saveGState()
            ctx.clip(to: frame)
            switch element.kind {
            case .rect(let rect): drawBox(rect.box, in: frame, ctx)
            case .text(let text):
                drawText(text.template.render(state.values), font: text.font, color: text.color, glow: text.glow,
                         in: frame, align: text.align, overflow: text.overflow, marqueeTime: state.marqueeTime, ctx)
            case .visualizer(let viz): drawVisualizer(viz, in: frame, state: state, ctx)
            case .slider(let slider): drawSlider(slider, index: i, state: state, ctx)
            case .button(let button): drawButton(button, index: i, in: frame, state: state, ctx)
            case .playlist(let list): drawPlaylist(list, in: frame, state: state, ctx)
            }
            ctx.restoreGState()
        }

        if let border = skin.window.border, border.width > 0 {
            let w = CGFloat(border.width)
            ctx.addPath(roundedPath(window.insetBy(dx: w / 2, dy: w / 2), max(0, radius - w / 2)))
            ctx.setStrokeColor(border.color.cgColor)
            ctx.setLineWidth(w)
            ctx.strokePath()
        }
        if let message = state.errorBanner { drawBanner(message, window: window, ctx) }
        if state.drawWindowButtons, skin.window.titleBar == .system { drawWindowButtons(ctx) }
    }

    // MARK: Primitives

    private func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        guard r > 0, rect.width > 0, rect.height > 0 else { return CGPath(rect: rect, transform: nil) }
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    private func paint(_ fill: Fill, path: CGPath, bounds: CGRect, _ ctx: CGContext) {
        switch fill {
        case .solid(let color):
            ctx.addPath(path)
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
        case .gradient(let stops, let angle):
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: stops.map(\.cgColor) as CFArray, locations: nil) else { return }
            let radians = CGFloat(angle) * .pi / 180
            let dx = cos(radians), dy = sin(radians)
            let reach = abs(bounds.width / 2 * dx) + abs(bounds.height / 2 * dy)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: center.x - dx * reach, y: center.y - dy * reach),
                                   end: CGPoint(x: center.x + dx * reach, y: center.y + dy * reach),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }

    private func drawBox(_ box: BoxStyle, in rect: CGRect, _ ctx: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = CGFloat(box.cornerRadius)
        let path = roundedPath(rect, radius)
        if let fill = box.fill { paint(fill, path: path, bounds: rect, ctx) }
        if let bevel = box.bevel, bevel.width > 0 {
            let w = CGFloat(bevel.width)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.setFillColor(bevel.light.cgColor)
            ctx.fill([CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: w),
                      CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height)])
            ctx.setFillColor(bevel.dark.cgColor)
            ctx.fill([CGRect(x: rect.minX, y: rect.maxY - w, width: rect.width, height: w),
                      CGRect(x: rect.maxX - w, y: rect.minY, width: w, height: rect.height)])
            ctx.restoreGState()
        }
        if let border = box.border, border.width > 0 {
            let w = CGFloat(border.width)
            ctx.addPath(roundedPath(rect.insetBy(dx: w / 2, dy: w / 2), max(0, radius - w / 2)))
            ctx.setStrokeColor(border.color.cgColor)
            ctx.setLineWidth(w)
            ctx.strokePath()
        }
    }

    private func setGlow(_ glow: Glow?, fallback: RGBA, _ ctx: CGContext) {
        guard let glow, glow.radius > 0 else { return }
        ctx.setShadow(offset: .zero, blur: CGFloat(glow.radius) * shadowScale, color: (glow.color ?? fallback).cgColor)
    }

    // MARK: Text

    private func font(_ spec: FontSpec) -> CTFont {
        let key = "\(spec.family)|\(spec.size)|\(spec.weight)"
        if let cached = fonts[key] { return cached }
        let weight: NSFont.Weight
        switch spec.weight {
        case "light": weight = .light
        case "medium": weight = .medium
        case "semibold": weight = .semibold
        case "bold": weight = .bold
        default: weight = .regular
        }
        let size = CGFloat(spec.size)
        let family = spec.family.lowercased()
        var font: NSFont?
        if family == "system" {
            font = .systemFont(ofSize: size, weight: weight)
        } else if family != "systemmono", FontCatalog.isAvailable(spec.family) {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: spec.family,
                .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
            ])
            font = NSFont(descriptor: descriptor, size: size)
        }
        let result = (font ?? .monospacedSystemFont(ofSize: size, weight: weight)) as CTFont
        fonts[key] = result
        return result
    }

    private func makeLine(_ string: String, font spec: FontSpec, color: RGBA) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(spec),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    private func lineWidth(_ line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func truncated(_ line: CTLine, to width: CGFloat, font spec: FontSpec, color: RGBA) -> CTLine {
        guard lineWidth(line) > width else { return line }
        let token = makeLine("\u{2026}", font: spec, color: color)
        return CTLineCreateTruncatedLine(line, Double(max(0, width)), .end, token) ?? token
    }

    private func draw(_ line: CTLine, x: CGFloat, centeredIn frame: CGRect, font spec: FontSpec, _ ctx: CGContext) {
        let baseline = frame.midY + CTFontGetCapHeight(font(spec)) / 2
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, ctx)
    }

    private func drawText(_ string: String, font spec: FontSpec, color: RGBA, glow: Glow?, in frame: CGRect,
                          align: TextAlign, overflow: TextOverflow, marqueeTime: Double, _ ctx: CGContext) {
        guard !string.isEmpty else { return }
        var line = makeLine(string, font: spec, color: color)
        var width = lineWidth(line)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        setGlow(glow, fallback: color, ctx)

        if width > frame.width {
            switch overflow {
            case .scroll:
                let period = width + Self.marqueeGap
                let offset = CGFloat((marqueeTime * Self.marqueeSpeed).truncatingRemainder(dividingBy: Double(period)))
                draw(line, x: frame.minX - offset, centeredIn: frame, font: spec, ctx)
                draw(line, x: frame.minX - offset + period, centeredIn: frame, font: spec, ctx)
                return
            case .ellipsis:
                line = truncated(line, to: frame.width, font: spec, color: color)
                width = lineWidth(line)
            case .clip:
                draw(line, x: frame.minX, centeredIn: frame, font: spec, ctx)
                return
            }
        }
        let x: CGFloat
        switch align {
        case .left: x = frame.minX
        case .center: x = frame.midX - width / 2
        case .right: x = frame.maxX - width
        }
        draw(line, x: x, centeredIn: frame, font: spec, ctx)
    }

    // MARK: Visualizer

    private func level(_ values: [Float], bar: Int, of count: Int) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let v = values[min(values.count - 1, bar * values.count / count)]
        return v.isFinite ? CGFloat(min(1, max(0, v))) : 0
    }

    private func drawVisualizer(_ viz: VisualizerElement, in frame: CGRect, state: RenderState, _ ctx: CGContext) {
        if let background = viz.background {
            paint(background, path: CGPath(rect: frame, transform: nil), bounds: frame, ctx)
        }
        if state.scopeMode {
            drawScope(viz, in: frame, samples: state.scope, ctx)
            return
        }
        let n = viz.bars
        let h = frame.height
        let gap = n > 1 ? max(0, min(CGFloat(viz.gap), (frame.width - CGFloat(n) * 0.5) / CGFloat(n - 1))) : 0
        let barWidth = max(0.5, (frame.width - gap * CGFloat(n - 1)) / CGFloat(n))
        ctx.saveGState()
        defer { ctx.restoreGState() }
        setGlow(viz.glow, fallback: viz.colors[0], ctx)

        if viz.segment > 0 {
            let segment = CGFloat(viz.segment), unit = segment + 1
            var rects = [[CGRect]](repeating: [], count: viz.colors.count)
            for bar in 0..<n {
                let barHeight = level(state.bars, bar: bar, of: n) * h
                guard barHeight > 0.01 else { continue }
                let x = frame.minX + CGFloat(bar) * (barWidth + gap)
                for k in 0..<Int((barHeight / unit).rounded(.up)) {
                    let fraction = CGFloat(k) * unit / h
                    let color = min(viz.colors.count - 1, Int(fraction * CGFloat(viz.colors.count)))
                    rects[color].append(CGRect(x: x, y: frame.maxY - CGFloat(k) * unit - segment, width: barWidth, height: segment))
                }
            }
            for (i, list) in rects.enumerated() where !list.isEmpty {
                ctx.setFillColor(viz.colors[i].cgColor)
                ctx.fill(list)
            }
        } else {
            let path = CGMutablePath()
            for bar in 0..<n {
                let barHeight = level(state.bars, bar: bar, of: n) * h
                guard barHeight > 0.01 else { continue }
                let x = frame.minX + CGFloat(bar) * (barWidth + gap)
                path.addPath(roundedPath(CGRect(x: x, y: frame.maxY - barHeight, width: barWidth, height: barHeight),
                                         CGFloat(viz.cornerRadius)))
            }
            if !path.isEmpty {
                let fill: Fill = viz.colors.count == 1 ? .solid(viz.colors[0]) : .gradient(stops: viz.colors.reversed(), angle: 90)
                paint(fill, path: path, bounds: frame, ctx)
            }
        }

        if viz.peaks {
            var rects: [CGRect] = []
            for bar in 0..<n {
                let peak = level(state.peaks, bar: bar, of: n)
                guard peak > 0.01 else { continue }
                let x = frame.minX + CGFloat(bar) * (barWidth + gap)
                let y = min(frame.maxY - 1, max(frame.minY, frame.maxY - peak * h))
                rects.append(CGRect(x: x, y: y, width: barWidth, height: 1))
            }
            ctx.setFillColor(viz.peakColor.cgColor)
            ctx.fill(rects)
        }
    }

    private func drawScope(_ viz: VisualizerElement, in frame: CGRect, samples: [Float], _ ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        setGlow(viz.glow, fallback: viz.scopeColor, ctx)
        let path = CGMutablePath()
        if samples.count < 2 {
            path.move(to: CGPoint(x: frame.minX, y: frame.midY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
        } else {
            let reach = frame.height / 2 - CGFloat(viz.scopeWidth) / 2
            for (i, sample) in samples.enumerated() {
                let s = sample.isFinite ? CGFloat(min(1, max(-1, sample))) : 0
                let point = CGPoint(x: frame.minX + CGFloat(i) / CGFloat(samples.count - 1) * frame.width,
                                    y: frame.midY - s * reach)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        ctx.addPath(path)
        ctx.setStrokeColor(viz.scopeColor.cgColor)
        ctx.setLineWidth(CGFloat(viz.scopeWidth))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    // MARK: Controls

    private func drawSlider(_ slider: SliderElement, index: Int, state: RenderState, _ ctx: CGContext) {
        var value = slider.binds == .seek ? state.seekFraction : state.volume
        if let drag = state.dragSlider, drag.element == index { value = drag.value }
        let geometry = layout.sliderGeometry(element: index, value: value)
        drawBox(slider.track, in: geometry.track, ctx)
        if let progress = slider.progress { drawBox(progress, in: geometry.progress, ctx) }
        if let thumb = slider.thumb { drawBox(thumb, in: geometry.thumb, ctx) }
    }

    private func isOn(_ action: ButtonAction, _ state: RenderState) -> Bool {
        switch action {
        case .shuffle: return state.shuffle
        case .repeat: return state.repeatOn
        case .play: return state.isPlaying
        case .pause: return state.isPaused
        case .toggleTime: return state.values.showRemaining
        case .toggleVisualizer: return state.scopeMode
        default: return false
        }
    }

    private func drawButton(_ button: ButtonElement, index: Int, in frame: CGRect, state: RenderState, _ ctx: CGContext) {
        let style: ButtonStateStyle
        if state.pressedElement == index {
            style = button.pressed
        } else if isOn(button.action, state) {
            style = button.on
        } else if state.hoverElement == index {
            style = button.hover
        } else {
            style = button.normal
        }
        drawBox(style.box, in: frame, ctx)

        if let label = button.label, !label.isEmpty {
            drawText(label, font: button.font, color: style.color, glow: style.glow, in: frame,
                     align: .center, overflow: .clip, marqueeTime: 0, ctx)
            return
        }
        guard var name = button.icon else { return }
        if name == "playPause" { name = state.isPlaying ? "pause" : "play" }
        guard let icon = Icons.path(for: name) else { return }
        let size = CGFloat(button.iconSize)
        var transform = CGAffineTransform(translationX: frame.midX - size / 2, y: frame.midY - size / 2)
            .scaledBy(x: size / 16, y: size / 16)
        guard let placed = icon.copy(using: &transform) else { return }
        ctx.saveGState()
        setGlow(style.glow, fallback: style.color, ctx)
        ctx.addPath(placed)
        if name == "repeat", state.repeatOne {
            ctx.addEllipse(in: CGRect(x: frame.midX - size * 0.09, y: frame.midY - size * 0.09, width: size * 0.18, height: size * 0.18))
        }
        ctx.setFillColor(style.color.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: Playlist

    private func drawPlaylist(_ list: PlaylistElement, in frame: CGRect, state: RenderState, _ ctx: CGContext) {
        if let background = list.background {
            paint(background, path: CGPath(rect: frame, transform: nil), bounds: frame, ctx)
        }
        let rowHeight = CGFloat(list.rowHeight)
        let padding = CGFloat(list.padding), inset = CGFloat(list.rowInset)
        let first = max(0, Int(floor(state.playlistScroll / rowHeight)))
        let last = min(state.rowCount - 1, Int(floor((state.playlistScroll + frame.height) / rowHeight)))
        if first <= last {
            for row in first...last {
                let rect = CGRect(x: frame.minX, y: frame.minY + CGFloat(row) * rowHeight - state.playlistScroll,
                                  width: frame.width, height: rowHeight)
                let info = state.row(row)
                let isCurrent = state.currentRow == row
                let isSelected = state.selection.contains(row)
                let highlight = roundedPath(rect.insetBy(dx: inset, dy: 0), CGFloat(list.rowCornerRadius))
                if isSelected, let fill = list.selectedBackground { paint(fill, path: highlight, bounds: rect, ctx) }
                if isCurrent, let fill = list.currentBackground { paint(fill, path: highlight, bounds: rect, ctx) }

                var values = TemplateValues()
                values.title = info.title; values.artist = info.artist; values.album = info.album
                values.fileName = info.fileName; values.duration = info.duration
                values.index = row + 1; values.count = state.rowCount

                let color = info.unplayable ? list.unplayableColor
                    : isCurrent ? list.currentColor : isSelected ? list.selectedColor : list.color
                let detailColor = info.unplayable ? list.unplayableColor
                    : isCurrent ? list.currentColor : isSelected ? list.selectedColor : list.detailColor

                var textRight = rect.maxX - padding
                let detail = list.detail.render(values)
                if !detail.isEmpty {
                    let line = makeLine(detail, font: list.font, color: detailColor)
                    let width = lineWidth(line)
                    draw(line, x: rect.maxX - padding - width, centeredIn: rect, font: list.font, ctx)
                    textRight -= width + 8
                }
                let available = textRight - (rect.minX + padding)
                let text = list.text.render(values)
                if !text.isEmpty, available > 4 {
                    let line = truncated(makeLine(text, font: list.font, color: color), to: available, font: list.font, color: color)
                    draw(line, x: rect.minX + padding, centeredIn: rect, font: list.font, ctx)
                }
            }
        }
        if let drop = state.dropIndicatorRow {
            let y = frame.minY + CGFloat(drop) * rowHeight - state.playlistScroll
            ctx.setFillColor(list.currentColor.cgColor)
            ctx.fill(CGRect(x: frame.minX + inset, y: min(frame.maxY - 2, max(frame.minY, y - 1)),
                            width: frame.width - inset * 2, height: 2))
        }
        let contentHeight = CGFloat(state.rowCount) * rowHeight
        if contentHeight > frame.height, frame.height > 12 {
            let barHeight = max(12, frame.height * frame.height / contentHeight)
            let travel = frame.height - barHeight
            let position = travel * min(1, max(0, state.playlistScroll / (contentHeight - frame.height)))
            ctx.addPath(roundedPath(CGRect(x: frame.maxX - 4, y: frame.minY + position, width: 3, height: barHeight), 1.5))
            ctx.setFillColor(list.color.withAlpha(0.35).cgColor)
            ctx.fillPath()
        }
    }

    // MARK: Chrome

    private func drawBanner(_ message: String, window: CGRect, _ ctx: CGContext) {
        let rect = CGRect(x: 0, y: window.maxY - Self.bannerHeight, width: window.width, height: Self.bannerHeight)
        ctx.setFillColor(RGBA(hex: "#b3261e")!.cgColor)
        ctx.fill(rect)
        ctx.saveGState()
        ctx.clip(to: rect)
        let font = FontSpec(family: "system", size: 10.5, weight: "medium")
        drawText(message, font: font, color: RGBA(1, 1, 1), glow: nil, in: rect.insetBy(dx: 6, dy: 0),
                 align: .left, overflow: .ellipsis, marqueeTime: 0, ctx)
        ctx.restoreGState()
    }

    private func drawWindowButtons(_ ctx: CGContext) {
        for (i, hex) in ["#ff5f57", "#febc2e", "#28c840"].enumerated() {
            ctx.setFillColor(RGBA(hex: hex)!.cgColor)
            ctx.fillEllipse(in: CGRect(x: 8 + CGFloat(i) * 20, y: 8, width: 12, height: 12))
        }
    }
}
