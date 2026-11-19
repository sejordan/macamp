import CoreGraphics
import Foundation

/// Where each element of a skin sits for a given window height, plus the
/// geometry questions the view and the renderer both need answered.
public struct SkinLayout {
    public let skin: Skin
    public let windowSize: CGSize
    /// One frame per skin element, in window coordinates with y pointing down.
    public let frames: [CGRect]

    public init(skin: Skin, windowHeight: CGFloat) {
        self.skin = skin
        self.windowSize = CGSize(width: skin.window.size.width, height: windowHeight)
        let delta = windowHeight - skin.window.size.height
        self.frames = skin.elements.map { element in
            var frame = element.frame
            switch element.anchor {
            case .top: break
            case .bottom: frame.origin.y += delta
            case .stretch: frame.size.height = max(1, frame.height + delta)
            }
            return frame
        }
    }

    public var windowRect: CGRect { CGRect(origin: .zero, size: windowSize) }

    /// The topmost element at `p` that responds to the mouse.
    public func interactiveElement(at p: CGPoint) -> Int? {
        for i in frames.indices.reversed() where frames[i].contains(p) {
            switch skin.elements[i].kind {
            case .button, .slider, .visualizer, .playlist: return i
            case .text(let text): if text.action != nil { return i }
            case .rect: break
            }
        }
        return nil
    }

    // MARK: Sliders

    private func slider(_ element: Int) -> (SliderElement, CGRect, horizontal: Bool, thumbLength: CGFloat)? {
        guard skin.elements.indices.contains(element),
              case .slider(let slider) = skin.elements[element].kind else { return nil }
        let frame = frames[element]
        let horizontal = frame.width >= frame.height
        let thumbLength: CGFloat = slider.thumb == nil ? 0 : (horizontal ? slider.thumbSize.width : slider.thumbSize.height)
        return (slider, frame, horizontal, min(thumbLength, horizontal ? frame.width : frame.height))
    }

    /// The value from 0 to 1 that a click or drag at `p` means.
    public func sliderValue(element: Int, at p: CGPoint) -> Double {
        guard let (_, frame, horizontal, thumbLength) = slider(element) else { return 0 }
        let travel = (horizontal ? frame.width : frame.height) - thumbLength
        guard travel > 0 else { return 0 }
        let along = horizontal ? p.x - frame.minX : frame.maxY - p.y
        return Double(min(1, max(0, (along - thumbLength / 2) / travel)))
    }

    public struct SliderGeometry: Equatable {
        public var track: CGRect
        public var progress: CGRect
        public var thumb: CGRect
    }

    public func sliderGeometry(element: Int, value: Double) -> SliderGeometry {
        guard let (slider, frame, horizontal, thumbLength) = slider(element) else {
            return SliderGeometry(track: .zero, progress: .zero, thumb: .zero)
        }
        let v = CGFloat(min(1, max(0, value.isFinite ? value : 0)))
        let cross = horizontal ? frame.height : frame.width
        let thickness = min(cross, CGFloat(slider.trackThickness ?? Double(cross)))
        if horizontal {
            let track = CGRect(x: frame.minX, y: frame.midY - thickness / 2, width: frame.width, height: thickness)
            let thumbX = frame.minX + v * (frame.width - thumbLength)
            let thumb = CGRect(x: thumbX, y: frame.midY - slider.thumbSize.height / 2,
                               width: thumbLength, height: slider.thumbSize.height)
            let progress = CGRect(x: track.minX, y: track.minY, width: thumbX + thumbLength / 2 - track.minX, height: thickness)
            return SliderGeometry(track: track, progress: progress, thumb: slider.thumb == nil ? .zero : thumb)
        } else {
            let track = CGRect(x: frame.midX - thickness / 2, y: frame.minY, width: thickness, height: frame.height)
            let thumbY = frame.maxY - thumbLength - v * (frame.height - thumbLength)
            let thumb = CGRect(x: frame.midX - slider.thumbSize.width / 2, y: thumbY,
                               width: slider.thumbSize.width, height: thumbLength)
            let top = thumbY + thumbLength / 2
            let progress = CGRect(x: track.minX, y: top, width: thickness, height: track.maxY - top)
            return SliderGeometry(track: track, progress: progress, thumb: slider.thumb == nil ? .zero : thumb)
        }
    }

    // MARK: Playlist

    private func playlist(_ element: Int) -> (PlaylistElement, CGRect)? {
        guard skin.elements.indices.contains(element),
              case .playlist(let list) = skin.elements[element].kind else { return nil }
        return (list, frames[element])
    }

    /// The row under `p`, or nil when `p` is outside the list or below the last row.
    public func playlistRow(element: Int, at p: CGPoint, scroll: CGFloat, count: Int) -> Int? {
        guard let (list, frame) = playlist(element), frame.contains(p) else { return nil }
        let row = Int(floor((p.y - frame.minY + scroll) / CGFloat(list.rowHeight)))
        return row >= 0 && row < count ? row : nil
    }

    /// Where a dragged row would land: 0 is before the first row, `count` is after the last.
    public func playlistInsertionIndex(element: Int, at p: CGPoint, scroll: CGFloat, count: Int) -> Int {
        guard let (list, frame) = playlist(element) else { return 0 }
        let index = Int(((p.y - frame.minY + scroll) / CGFloat(list.rowHeight)).rounded())
        return min(count, max(0, index))
    }

    public func maxPlaylistScroll(element: Int, count: Int) -> CGFloat {
        guard let (list, frame) = playlist(element) else { return 0 }
        return max(0, CGFloat(count) * CGFloat(list.rowHeight) - frame.height)
    }
}
