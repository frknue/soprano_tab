import AppKit
import Testing
@testable import SopranoTab

struct ThumbnailScalingTests {
    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test("a landscape image shrinks so its width is the limit")
    func landscapeDownscale() {
        let size = ThumbnailScaling.targetSize(for: CGSize(width: 1000, height: 500), maxPixelSize: 100)
        #expect(size == CGSize(width: 100, height: 50))
    }

    @Test("a portrait image shrinks so its height is the limit")
    func portraitDownscale() {
        let size = ThumbnailScaling.targetSize(for: CGSize(width: 500, height: 1000), maxPixelSize: 100)
        #expect(size == CGSize(width: 50, height: 100))
    }

    @Test("the aspect ratio survives downscaling to the nearest whole pixel")
    func aspectPreserved() {
        #expect(ThumbnailScaling.targetSize(for: CGSize(width: 1920, height: 1080), maxPixelSize: 640)
            == CGSize(width: 640, height: 360))
        #expect(ThumbnailScaling.targetSize(for: CGSize(width: 1000, height: 333), maxPixelSize: 100)
            == CGSize(width: 100, height: 33))
        #expect(ThumbnailScaling.targetSize(for: CGSize(width: 3024, height: 1964), maxPixelSize: 500)
            == CGSize(width: 500, height: 325))
    }

    @Test("an image within the limit keeps its size")
    func noUpscale() {
        #expect(ThumbnailScaling.targetSize(for: CGSize(width: 200, height: 100), maxPixelSize: 640)
            == CGSize(width: 200, height: 100))
        #expect(ThumbnailScaling.targetSize(for: CGSize(width: 640, height: 480), maxPixelSize: 640)
            == CGSize(width: 640, height: 480))
    }

    @Test("a fractional limit rounds down to whole pixels")
    func fractionalLimit() {
        let size = ThumbnailScaling.targetSize(for: CGSize(width: 1000, height: 1000), maxPixelSize: 100.9)
        #expect(size == CGSize(width: 100, height: 100))
    }

    @Test("a very thin image keeps at least one pixel on its short side")
    func thinImage() {
        let size = ThumbnailScaling.targetSize(for: CGSize(width: 3000, height: 1), maxPixelSize: 100)
        #expect(size == CGSize(width: 100, height: 1))
    }

    @Test("degenerate sizes and limits still give a one-pixel image")
    func degenerateSizes() {
        let onePixel = CGSize(width: 1, height: 1)
        #expect(ThumbnailScaling.targetSize(for: .zero, maxPixelSize: 100) == onePixel)
        #expect(ThumbnailScaling.targetSize(for: CGSize(width: -40, height: -20), maxPixelSize: 100) == onePixel)
        #expect(ThumbnailScaling.targetSize(for: CGSize(width: 800, height: 600), maxPixelSize: 0) == onePixel)
        #expect(ThumbnailScaling.targetSize(for: CGSize(width: 800, height: 600), maxPixelSize: -5) == onePixel)
        #expect(ThumbnailScaling.targetSize(for: CGSize(width: 800, height: 600), maxPixelSize: .nan) == onePixel)
        #expect(ThumbnailScaling.targetSize(for: CGSize(width: CGFloat.infinity, height: 10), maxPixelSize: 100)
            == onePixel)
    }

    @Test("an unlimited size never upscales")
    func infiniteLimit() {
        let size = ThumbnailScaling.targetSize(for: CGSize(width: 300, height: 200), maxPixelSize: .infinity)
        #expect(size == CGSize(width: 300, height: 200))
    }

    @Test("scaling a large image produces a bitmap of the target size")
    func scaledImageDimensions() throws {
        let source = try image(width: 400, height: 200)
        let scaled = try #require(ThumbnailScaling.scaled(source, maxPixelSize: 100))
        #expect(scaled.width == 100)
        #expect(scaled.height == 50)
    }

    @Test("an image that already fits is returned unchanged")
    func scaledImageFits() throws {
        let source = try image(width: 120, height: 80)
        let scaled = try #require(ThumbnailScaling.scaled(source, maxPixelSize: 640))
        #expect(scaled === source)
    }
}
