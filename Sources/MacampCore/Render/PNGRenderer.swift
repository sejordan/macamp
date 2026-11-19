import CoreGraphics
import Foundation
import ImageIO

/// Draws a skin to an image without a window, for previews and tests.
public enum PNGRenderer {
    /// A bitmap context whose coordinates are in points with y pointing down.
    public static func makeContext(width: CGFloat, height: CGFloat, scale: CGFloat) -> CGContext? {
        let w = Int((width * scale).rounded()), h = Int((height * scale).rounded())
        guard w > 0, h > 0, w <= 16_000, h <= 16_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        return ctx
    }

    /// `height` defaults to the skin's own height and is kept within the skin's limits.
    public static func render(skin: Skin, state: RenderState, height: CGFloat?, scale: CGFloat) -> CGImage? {
        let scale = min(8, max(0.25, scale))
        var h = height ?? skin.window.size.height
        if skin.window.resize == .vertical {
            h = min(CGFloat(skin.window.maxHeight), max(CGFloat(skin.window.minHeight), h))
        } else {
            h = skin.window.size.height
        }
        guard let ctx = makeContext(width: skin.window.size.width, height: h, scale: scale) else { return nil }
        let renderer = SkinRenderer(skin: skin, windowHeight: h)
        renderer.shadowScale = scale
        renderer.draw(in: ctx, state: state, dirty: nil)
        return ctx.makeImage()
    }

    public static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
