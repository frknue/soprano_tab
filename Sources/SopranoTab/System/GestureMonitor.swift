import AppKit
import ApplicationServices
import SopranoTabCore

/// The system-wide trackpad tap: a listen-only session tap for `NSEvent.EventType.gesture`
/// (raw 29) on the main run loop. Every gesture event's trackpad touches go to `handler`
/// as `TouchSample`s; events always pass on unchanged.
///
/// While running, the tap's refcon holds a retained reference to the monitor; `stop()`
/// releases it.
@MainActor
final class GestureMonitor: GestureEventTap {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var refcon: UnsafeMutableRawPointer?
    private var handler: (@MainActor ([TouchSample]) -> Void)?

    init() {}

    var isRunning: Bool { tap != nil }

    /// Starts the tap. Calling it while running only replaces the handler. Throws
    /// `accessibilityDenied` without Accessibility access, which macOS requires for a tap
    /// that sees other apps' gesture events.
    func start(handler: @escaping @MainActor ([TouchSample]) -> Void) throws {
        if isRunning {
            self.handler = handler
            return
        }
        guard AXIsProcessTrusted() else { throw EventTapError.accessibilityDenied }

        let refcon = Unmanaged.passRetained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << gestureEventType,
            callback: gestureTapCallback,
            userInfo: refcon
        ) else {
            Unmanaged<GestureMonitor>.fromOpaque(refcon).release()
            throw EventTapError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.handler = handler
        self.tap = tap
        self.runLoopSource = source
        self.refcon = refcon
    }

    /// Removes the tap; a no-op when it is not running.
    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        handler = nil
        if let refcon {
            self.refcon = nil
            Unmanaged<GestureMonitor>.fromOpaque(refcon).release()
        }
    }

    /// Re-enables the tap after macOS disabled it (slow callback or secure input);
    /// otherwise hands the touches of a gesture event to the handler.
    fileprivate func receive(type: CGEventType, touches: [TouchSample]?) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        default:
            guard let touches, let handler else { return }
            handler(touches)
        }
    }

    /// The trackpad touches of a gesture event, ordered by `id`; nil for any other event.
    /// Only `NSTouch.TouchType.indirect` touches (trackpad fingers) are kept; each
    /// touch's identity is hashed into a stable `id` for the life of the touch.
    nonisolated fileprivate static func touchSamples(from event: CGEvent, type: CGEventType) -> [TouchSample]? {
        // `allTouches()` raises for event types without touches, so check both sides.
        guard type.rawValue == gestureEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .gesture
        else { return nil }
        return nsEvent.allTouches()
            .filter { $0.type == .indirect }
            .map { touch in
                TouchSample(id: touch.identity.hash, position: touch.normalizedPosition, phase: phase(of: touch.phase))
            }
            .sorted { $0.id < $1.id }
    }

    nonisolated private static func phase(of phase: NSTouch.Phase) -> TouchSample.Phase {
        if phase.contains(.began) { return .began }
        if phase.contains(.moved) { return .moved }
        if phase.contains(.ended) { return .ended }
        if phase.contains(.cancelled) { return .cancelled }
        return .stationary
    }
}

/// `NSEvent.EventType.gesture`, which `CGEventType` has no case for.
private let gestureEventType = UInt32(NSEvent.EventType.gesture.rawValue)

/// The C callback. The run-loop source is on the main run loop, so this runs on the main
/// thread; only Sendable values cross into the main-actor closure. Listen-only taps ignore
/// the return value; the event is passed back unchanged.
private func gestureTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitorAddress = Int(bitPattern: refcon)
    let touches = GestureMonitor.touchSamples(from: event, type: type)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: monitorAddress) else { return }
        Unmanaged<GestureMonitor>.fromOpaque(pointer).takeUnretainedValue().receive(type: type, touches: touches)
    }
    return Unmanaged.passUnretained(event)
}
