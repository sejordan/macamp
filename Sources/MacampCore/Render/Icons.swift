import CoreGraphics
import Foundation

/// Built-in button icons, drawn in a 16 by 16 box with y pointing down.
public enum Icons {
    public static func path(for name: String) -> CGPath? { paths[name] }

    private static func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
        CGPath(rect: CGRect(x: x, y: y, width: w, height: h), transform: nil)
    }

    private static func union(_ parts: [CGPath]) -> CGPath {
        let p = CGMutablePath()
        parts.forEach { p.addPath($0) }
        return p
    }

    private static func stroke(_ points: [(CGFloat, CGFloat)], width: CGFloat = 1.6) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        return p.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4)
    }

    private static let play = polygon([(3, 1.5), (3, 14.5), (14, 8)])
    private static let pause = union([rect(3, 2, 3.5, 12), rect(9.5, 2, 3.5, 12)])

    private static let paths: [String: CGPath] = [
        "play": play,
        "pause": pause,
        "playPause": play,
        "stop": rect(3, 3, 10, 10),
        "previous": union([rect(2, 2, 2, 12), polygon([(14, 2), (14, 14), (5, 8)])]),
        "next": union([rect(12, 2, 2, 12), polygon([(2, 2), (2, 14), (11, 8)])]),
        "open": union([polygon([(8, 2), (14, 9), (2, 9)]), rect(2, 11, 12, 3)]),
        "shuffle": union([
            stroke([(1.5, 4.5), (4.5, 4.5), (10, 11.5), (12, 11.5)]),
            stroke([(1.5, 11.5), (4.5, 11.5), (10, 4.5), (12, 4.5)]),
            polygon([(11.5, 2), (15, 4.5), (11.5, 7)]),
            polygon([(11.5, 9), (15, 11.5), (11.5, 14)]),
        ]),
        "repeat": union([
            stroke([(11, 4), (4, 4), (2, 6), (2, 10), (4, 12), (5, 12)]),
            stroke([(11, 12), (12, 12), (14, 10), (14, 6), (13, 5)]),
            polygon([(10.5, 1.5), (14, 4), (10.5, 6.5)]),
            polygon([(5.5, 9.5), (9, 12), (5.5, 14.5)]),
        ]),
        "close": union([stroke([(4, 4), (12, 12)], width: 1.8), stroke([(12, 4), (4, 12)], width: 1.8)]),
        "minimize": rect(3, 7.1, 10, 1.8),
        "toggleTime": union([
            CGPath(ellipseIn: CGRect(x: 2, y: 2, width: 12, height: 12), transform: nil)
                .copy(strokingWithWidth: 1.5, lineCap: .round, lineJoin: .round, miterLimit: 4),
            stroke([(8, 4.8), (8, 8), (10.4, 9.6)], width: 1.4),
        ]),
        "toggleVisualizer": union([rect(2, 8, 3, 6), rect(6.5, 3, 3, 11), rect(11, 6, 3, 8)]),
    ]
}
