import ApplicationServices
import CoreGraphics

/// Thin, typed wrappers over the Accessibility C API. Nonisolated and callable from any
/// thread: every call is a synchronous IPC to the target app (bounded by the element's
/// messaging timeout), so the live catalog makes them on per-app background queues.
enum AX {
    /// The attribute's value cast with a Swift dynamic cast. Bridged types (String, Bool,
    /// numbers, arrays) cast reliably; for CF types (AXUIElement, AXValue) use
    /// `element(_:_:)` / `frame(of:)`, which check the CF type id.
    static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else {
            return nil
        }
        return value as? T
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute)
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        value(element, attribute)
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else {
            return nil
        }
        return asElement(value)
    }

    /// The attribute's elements; [] when it is missing or holds no elements.
    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let items = value as? [AnyObject]
        else { return [] }
        return items.compactMap(asElement)
    }

    /// kAXPosition + kAXSize, global Quartz coordinates.
    static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = axValue(element, kAXPositionAttribute),
              AXValueGetType(position) == .cgPoint,
              AXValueGetValue(position, .cgPoint, &origin),
              let dimensions = axValue(element, kAXSizeAttribute),
              AXValueGetType(dimensions) == .cgSize,
              AXValueGetValue(dimensions, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// The pid of the app owning `element` (local, no IPC).
    static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return pid
    }

    private static func asElement(_ value: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }
}
