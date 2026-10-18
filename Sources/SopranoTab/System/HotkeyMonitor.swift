import AppKit
import ApplicationServices
import SopranoTabCore

/// The system-wide keyboard tap: an active session tap at the head of the event stream for
/// keyDown, keyUp and flagsChanged. Its run-loop source lives on the main run loop, so the
/// callback runs on the main thread and calls `handler` synchronously; a true result
/// swallows the event (the tap returns nil), false passes it on unchanged.
///
/// While running, the tap's refcon holds a retained reference to the monitor; `stop()`
/// releases it, so the monitor stays alive for as long as its tap can call back.
@MainActor
final class HotkeyMonitor: KeyboardEventTap {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var refcon: UnsafeMutableRawPointer?
    private var handler: (@MainActor (KeyEvent) -> Bool)?

    init() {}

    var isRunning: Bool { tap != nil }

    /// Starts the tap. Calling it while running only replaces the handler.
    func start(handler: @escaping @MainActor (KeyEvent) -> Bool) throws {
        if isRunning {
            self.handler = handler
            return
        }
        guard AXIsProcessTrusted() else { throw EventTapError.accessibilityDenied }

        let refcon = Unmanaged.passRetained(self).toOpaque()
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: refcon
        ) else {
            Unmanaged<HotkeyMonitor>.fromOpaque(refcon).release()
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
            Unmanaged<HotkeyMonitor>.fromOpaque(refcon).release()
        }
    }

    /// Returns true to swallow the event. macOS disables a tap whose callback was too slow
    /// or that secure input interrupted; it then sends a `tapDisabledBy…` event, and the
    /// tap turns itself back on and lets that event through.
    fileprivate func receive(type: CGEventType, keyEvent: KeyEvent?) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        default:
            guard let keyEvent, let handler else { return false }
            return handler(keyEvent)
        }
    }
}

/// The C callback. The run-loop source is on the main run loop, so this runs on the main
/// thread; only Sendable values (the converted event, the monitor's address) cross into
/// the main-actor closure.
private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitorAddress = Int(bitPattern: refcon)
    let keyEvent = KeyEventConversion.keyEvent(from: event, type: type)
    let swallow = MainActor.assumeIsolated { () -> Bool in
        guard let pointer = UnsafeRawPointer(bitPattern: monitorAddress) else { return false }
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(pointer).takeUnretainedValue()
        return monitor.receive(type: type, keyEvent: keyEvent)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
