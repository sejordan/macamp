import CoreGraphics
import Foundation

public enum Anchor: String, CaseIterable { case top, bottom, stretch }
public enum TitleBar: String, CaseIterable { case system, none }
public enum ResizeMode: String, CaseIterable { case none, vertical }
public enum SliderBinding: String, CaseIterable { case seek, volume }
public enum TextAlign: String, CaseIterable { case left, center, right }
public enum TextOverflow: String, CaseIterable { case clip, ellipsis, scroll }

public enum ButtonAction: String, CaseIterable {
    case play, pause, playPause, stop, previous, next, open, shuffle, `repeat`
    case close, minimize, toggleTime, toggleVisualizer
}

public struct SkinWindow: Equatable {
    public var size: CGSize
    public var cornerRadius: Double
    public var background: Fill
    public var border: Border?
    public var titleBar: TitleBar
    public var resize: ResizeMode
    public var minHeight: Double
    public var maxHeight: Double
}

public struct RectElement: Equatable {
    public var box: BoxStyle
}

public struct TextElement: Equatable {
    public var template: TextTemplate
    public var font: FontSpec
    public var color: RGBA
    public var glow: Glow?
    public var align: TextAlign
    public var overflow: TextOverflow
    public var action: ButtonAction?
}

public struct VisualizerElement: Equatable {
    public var bars: Int
    public var gap: Double
    /// Bottom to top.
    public var colors: [RGBA]
    /// Height of one segment in points; 0 draws solid bars.
    public var segment: Double
    public var peaks: Bool
    public var peakColor: RGBA
    public var cornerRadius: Double
    public var glow: Glow?
    public var scopeColor: RGBA
    public var scopeWidth: Double
    public var background: Fill?
}

public struct SliderElement: Equatable {
    public var binds: SliderBinding
    public var track: BoxStyle
    /// Nil means the full short side of the frame.
    public var trackThickness: Double?
    public var progress: BoxStyle?
    public var thumb: BoxStyle?
    public var thumbSize: CGSize
}

public struct ButtonStateStyle: Equatable {
    public var box: BoxStyle
    public var color: RGBA
    public var glow: Glow?
}

public struct ButtonElement: Equatable {
    public var action: ButtonAction
    /// Nil draws no icon.
    public var icon: String?
    public var label: String?
    public var font: FontSpec
    public var iconSize: Double
    public var normal: ButtonStateStyle
    public var hover: ButtonStateStyle
    public var pressed: ButtonStateStyle
    public var on: ButtonStateStyle
}

public struct PlaylistElement: Equatable {
    public var rowHeight: Double
    public var font: FontSpec
    public var text: TextTemplate
    public var detail: TextTemplate
    public var color: RGBA
    public var detailColor: RGBA
    public var currentColor: RGBA
    public var currentBackground: Fill?
    public var selectedColor: RGBA
    public var selectedBackground: Fill?
    public var unplayableColor: RGBA
    public var background: Fill?
    public var padding: Double
    public var rowCornerRadius: Double
    public var rowInset: Double
}

public struct SkinElement: Equatable {
    public enum Kind: Equatable {
        case rect(RectElement)
        case text(TextElement)
        case visualizer(VisualizerElement)
        case slider(SliderElement)
        case button(ButtonElement)
        case playlist(PlaylistElement)
    }

    public var frame: CGRect
    public var anchor: Anchor
    public var kind: Kind

    public var typeName: String {
        switch kind {
        case .rect: return "rect"
        case .text: return "text"
        case .visualizer: return "visualizer"
        case .slider: return "slider"
        case .button: return "button"
        case .playlist: return "playlist"
        }
    }
}

public struct Skin: Equatable {
    public var name: String
    public var author: String?
    public var window: SkinWindow
    public var elements: [SkinElement]
    /// True when the skin defines a dark-mode palette and should be reparsed on appearance change.
    public var followsAppearance: Bool
}

/// One problem found in a skin file, located by JSON path.
public struct SkinIssue: Equatable, CustomStringConvertible {
    public enum Severity: Equatable { case error, warning }
    public var severity: Severity
    /// For example `elements[3].frame`. `$` is the whole document.
    public var path: String
    public var message: String

    public var description: String { "\(path): \(message)" }
}

public struct SkinParseResult {
    /// Nil when there is at least one error.
    public var skin: Skin?
    public var issues: [SkinIssue]

    public var errors: [SkinIssue] { issues.filter { $0.severity == .error } }
    public var warnings: [SkinIssue] { issues.filter { $0.severity == .warning } }
}
