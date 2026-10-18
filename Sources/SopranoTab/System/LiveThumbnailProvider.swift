import AppKit
@preconcurrency import ScreenCaptureKit
import SopranoTabCore

/// Window images from the WindowServer, captured off the main thread.
///
/// Requests are coalesced per window: a window already waiting or being captured is not
/// captured twice; its callers share the result. A larger size requested while a smaller
/// capture runs is captured again right after it. At most `maxConcurrentCaptures` captures
/// run at once; the rest wait in request order.
@MainActor
final class LiveThumbnailProvider: ThumbnailProvider {
    typealias Update = @MainActor (WindowID, CGImage) -> Void

    private static let maxConcurrentCaptures = 4
    /// The synchronous SkyLight capture and the scaling run here, never on the main thread.
    private nonisolated static let captureQueue = DispatchQueue(
        label: "com.soprano.tab.thumbnails",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// One window's pending capture: waiting in `waiting`, or running.
    private struct Flight {
        var maxPixelSize: CGFloat
        var isOnScreen: Bool
        var isRunning = false
        var updates: [Update]
        /// A larger size requested while this capture ran.
        var followUpPixelSize: CGFloat?
        var followUpUpdates: [Update] = []
    }

    private var cache: [WindowID: CGImage] = [:]
    private var flights: [WindowID: Flight] = [:]
    private var waiting: [WindowID] = []
    private var runningCount = 0

    init() {}

    var canCapture: Bool { CGPreflightScreenCaptureAccess() }

    func cachedThumbnail(for windowID: WindowID) -> CGImage? {
        cache[windowID]
    }

    func requestThumbnails(
        for windows: [WindowInfo],
        maxPixelSize: CGFloat,
        update: @escaping @MainActor (WindowID, CGImage) -> Void
    ) {
        guard canCapture else { return }
        for window in windows {
            guard let windowID = window.windowID, !window.isMinimized else { continue }
            enqueue(windowID, maxPixelSize: maxPixelSize, isOnScreen: window.zIndex != nil, update: update)
        }
        startWaitingCaptures()
    }

    func prune(keeping windowIDs: Set<WindowID>) {
        cache = cache.filter { windowIDs.contains($0.key) }
        // Captures that have not started yet would only fail for a window that is gone.
        for windowID in waiting where !windowIDs.contains(windowID) {
            flights[windowID] = nil
        }
        waiting.removeAll { !windowIDs.contains($0) }
    }

    // MARK: - Scheduling

    private func enqueue(_ windowID: WindowID, maxPixelSize: CGFloat, isOnScreen: Bool, update: @escaping Update) {
        guard var flight = flights[windowID] else {
            flights[windowID] = Flight(maxPixelSize: maxPixelSize, isOnScreen: isOnScreen, updates: [update])
            waiting.append(windowID)
            return
        }
        if !flight.isRunning {
            flight.maxPixelSize = max(flight.maxPixelSize, maxPixelSize)
            flight.isOnScreen = isOnScreen
            flight.updates.append(update)
        } else if maxPixelSize <= flight.maxPixelSize {
            flight.updates.append(update)
        } else {
            flight.followUpPixelSize = max(flight.followUpPixelSize ?? 0, maxPixelSize)
            flight.followUpUpdates.append(update)
            flight.isOnScreen = isOnScreen
        }
        flights[windowID] = flight
    }

    private func startWaitingCaptures() {
        while runningCount < Self.maxConcurrentCaptures, !waiting.isEmpty {
            let windowID = waiting.removeFirst()
            guard var flight = flights[windowID] else { continue }
            flight.isRunning = true
            flights[windowID] = flight
            runningCount += 1
            let maxPixelSize = flight.maxPixelSize
            let isOnScreen = flight.isOnScreen
            Task { [weak self] in
                let captured = await Self.capture(windowID, maxPixelSize: maxPixelSize, isOnScreen: isOnScreen)
                self?.finish(windowID, image: captured?.image)
            }
        }
    }

    private func finish(_ windowID: WindowID, image: CGImage?) {
        runningCount -= 1
        if let flight = flights.removeValue(forKey: windowID) {
            if let image {
                cache[windowID] = image
                for update in flight.updates { update(windowID, image) }
            }
            if let followUpPixelSize = flight.followUpPixelSize {
                flights[windowID] = Flight(
                    maxPixelSize: followUpPixelSize,
                    isOnScreen: flight.isOnScreen,
                    updates: flight.followUpUpdates
                )
                waiting.append(windowID)
            }
        }
        startWaitingCaptures()
    }

    // MARK: - Capture

    /// A captured image crossing from the capture queue to the main actor. A `CGImage`
    /// is immutable once created.
    private struct CapturedImage: @unchecked Sendable {
        let image: CGImage
    }

    /// SkyLight first (any Space, covered windows); ScreenCaptureKit for on-screen windows
    /// when that fails.
    private nonisolated static func capture(
        _ windowID: WindowID,
        maxPixelSize: CGFloat,
        isOnScreen: Bool
    ) async -> CapturedImage? {
        let hardware: CapturedImage? = await withCheckedContinuation { continuation in
            captureQueue.async {
                let image = PrivateAPIs.captureWindow(windowID)
                    .flatMap { ThumbnailScaling.scaled($0, maxPixelSize: maxPixelSize) }
                continuation.resume(returning: image.map(CapturedImage.init))
            }
        }
        if let hardware { return hardware }
        guard isOnScreen else { return nil }
        return await screenCaptureKitCapture(windowID, maxPixelSize: maxPixelSize)
    }

    private nonisolated static func screenCaptureKitCapture(
        _ windowID: WindowID,
        maxPixelSize: CGFloat
    ) async -> CapturedImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let pixelSize = CGSize(width: filter.contentRect.width * scale, height: filter.contentRect.height * scale)
            let target = ThumbnailScaling.targetSize(for: pixelSize, maxPixelSize: maxPixelSize)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(target.width)
            configuration.height = Int(target.height)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return ThumbnailScaling.scaled(image, maxPixelSize: maxPixelSize).map(CapturedImage.init)
        } catch {
            return nil
        }
    }
}

/// Fits window images into a thumbnail's pixel budget.
enum ThumbnailScaling {
    /// The size of an image of `imageSize` pixels whose longest side is at most
    /// `maxPixelSize` (rounded down to whole pixels, at least 1): the aspect ratio is kept,
    /// images are never upscaled, and both sides are whole numbers of at least 1 pixel.
    static func targetSize(for imageSize: CGSize, maxPixelSize: CGFloat) -> CGSize {
        guard imageSize.width.isFinite, imageSize.height.isFinite else { return CGSize(width: 1, height: 1) }
        let width = max(imageSize.width, 0)
        let height = max(imageSize.height, 0)
        let limit = maxPixelSize.isNaN ? 1 : max(maxPixelSize.rounded(.down), 1)
        let longest = max(width, height)
        let factor = longest > limit ? limit / longest : 1
        return CGSize(
            width: max((width * factor).rounded(), 1),
            height: max((height * factor).rounded(), 1)
        )
    }

    /// `image` itself when it already fits, else a redrawn copy at `targetSize`; nil when
    /// the bitmap context cannot be created.
    static func scaled(_ image: CGImage, maxPixelSize: CGFloat) -> CGImage? {
        let size = targetSize(for: CGSize(width: image.width, height: image.height), maxPixelSize: maxPixelSize)
        let width = Int(size.width)
        let height = Int(size.height)
        if width == image.width && height == image.height { return image }
        // The image's own color space keeps its colors; not every space can back an
        // 8-bit bitmap context, so sRGB is the fallback.
        func makeContext(_ space: CGColorSpace) -> CGContext? {
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        }
        guard let context = image.colorSpace.flatMap({ $0.model == .rgb ? makeContext($0) : nil })
            ?? CGColorSpace(name: CGColorSpace.sRGB).flatMap(makeContext)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
