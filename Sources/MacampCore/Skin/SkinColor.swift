import CoreGraphics
import Foundation

/// A color with components in 0...1.
public struct RGBA: Equatable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// Parses `#rgb`, `#rrggbb` or `#rrggbbaa`.
    public init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        var digits = Array(hex.dropFirst())
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { digits = digits.flatMap { [$0, $0] } }
        guard digits.count == 6 || digits.count == 8 else { return nil }
        var parts: [Double] = []
        for i in stride(from: 0, to: digits.count, by: 2) {
            parts.append(Double(UInt8(String(digits[i...i + 1]), radix: 16)!) / 255)
        }
        self.init(parts[0], parts[1], parts[2], parts.count == 4 ? parts[3] : 1)
    }

    public func withAlpha(_ alpha: Double) -> RGBA { RGBA(r, g, b, a * alpha) }

    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

public enum Fill: Equatable {
    case solid(RGBA)
    /// `angle` in degrees: 0 runs left to right, 90 runs top to bottom.
    case gradient(stops: [RGBA], angle: Double)
}

public struct Border: Equatable {
    public var color: RGBA
    public var width: Double
}

/// A one-edge highlight and shadow, for a raised hardware look.
public struct Bevel: Equatable {
    public var light: RGBA
    public var dark: RGBA
    public var width: Double
}

public struct Glow: Equatable {
    /// Nil means "use the color of the thing that glows".
    public var color: RGBA?
    public var radius: Double
}

public struct FontSpec: Equatable {
    public static let weights = ["light", "regular", "medium", "semibold", "bold"]
    public var family: String
    public var size: Double
    public var weight: String

    public static let standard = FontSpec(family: "systemMono", size: 11, weight: "regular")
}

public struct BoxStyle: Equatable {
    public var fill: Fill?
    public var border: Border?
    public var cornerRadius: Double = 0
    public var bevel: Bevel?

    public init(fill: Fill? = nil, border: Border? = nil, cornerRadius: Double = 0, bevel: Bevel? = nil) {
        self.fill = fill; self.border = border; self.cornerRadius = cornerRadius; self.bevel = bevel
    }
}
