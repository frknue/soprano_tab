import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// Private SkyLight / HIServices symbols a window switcher needs and the public SDK does
/// not offer: Spaces, cross-Space focus, window images of other Spaces, the CGWindowID of
/// an AX element. Resolved with `dlsym` at first use, so the binary links nothing private
/// and a symbol a future macOS removes degrades to `nil` instead of a launch failure.
/// Every wrapper returns nil / false / [] when its symbol is missing.
enum PrivateAPIs {
    typealias ConnectionID = Int32

    /// `kCPSUserGenerated`: the front-process change counts as a user action.
    static let userGeneratedFrontMode: UInt32 = 0x200
    /// `CGSSpaceMask` covering current, other and user Spaces.
    static let allSpacesMask: Int32 = 0x7

    /// `CGSWindowCaptureOptions`.
    struct CaptureOptions: OptionSet, Sendable {
        let rawValue: UInt32
        static let ignoreGlobalClipShape = CaptureOptions(rawValue: 1 << 11)
        static let nominalResolution = CaptureOptions(rawValue: 1 << 9)
        static let bestResolution = CaptureOptions(rawValue: 1 << 8)
    }

    // MARK: - Symbols

    private typealias MainConnectionIDFn = @convention(c) () -> ConnectionID
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFn = @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias CopyActiveMenuBarDisplayIdentifierFn = @convention(c) (ConnectionID) -> Unmanaged<CFString>?
    private typealias HWCaptureWindowListFn = @convention(c) (
        ConnectionID, UnsafeMutablePointer<UInt32>, Int32, UInt32
    ) -> Unmanaged<CFArray>?
    private typealias SetFrontProcessWithOptionsFn = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32
    ) -> CGError
    private typealias PostEventRecordToFn = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>
    ) -> CGError
    private typealias AXUIElementGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError
    private typealias AXUIElementCreateWithRemoteTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private struct Symbols: @unchecked Sendable {
        let mainConnectionID: MainConnectionIDFn?
        let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn?
        let copySpacesForWindows: CopySpacesForWindowsFn?
        let copyActiveMenuBarDisplayIdentifier: CopyActiveMenuBarDisplayIdentifierFn?
        let hwCaptureWindowList: HWCaptureWindowListFn?
        let setFrontProcessWithOptions: SetFrontProcessWithOptionsFn?
        let postEventRecordTo: PostEventRecordToFn?
        let axUIElementGetWindow: AXUIElementGetWindowFn?
        let axUIElementCreateWithRemoteToken: AXUIElementCreateWithRemoteTokenFn?
        let getProcessForPID: GetProcessForPIDFn?
    }

    private static let symbols: Symbols = {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        // RTLD_DEFAULT: search every image already loaded (HIServices via ApplicationServices).
        let anyImage = UnsafeMutableRawPointer(bitPattern: -2)
        func load<T>(_ name: String, _ handle: UnsafeMutableRawPointer?) -> T? {
            guard let pointer = dlsym(handle, name) ?? dlsym(anyImage, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        return Symbols(
            mainConnectionID: load("CGSMainConnectionID", skyLight),
            copyManagedDisplaySpaces: load("CGSCopyManagedDisplaySpaces", skyLight),
            copySpacesForWindows: load("CGSCopySpacesForWindows", skyLight),
            copyActiveMenuBarDisplayIdentifier: load("CGSCopyActiveMenuBarDisplayIdentifier", skyLight),
            hwCaptureWindowList: load("CGSHWCaptureWindowList", skyLight),
            setFrontProcessWithOptions: load("_SLPSSetFrontProcessWithOptions", skyLight),
            postEventRecordTo: load("SLPSPostEventRecordTo", skyLight),
            axUIElementGetWindow: load("_AXUIElementGetWindow", anyImage),
            axUIElementCreateWithRemoteToken: load("_AXUIElementCreateWithRemoteToken", anyImage),
            getProcessForPID: load("GetProcessForPID", anyImage)
        )
    }()

    // MARK: - Connection and Spaces

    /// The process's WindowServer connection; nil when SkyLight is unavailable.
    static var mainConnection: ConnectionID? {
        symbols.mainConnectionID?()
    }

    /// `CGSCopyManagedDisplaySpaces`: one dictionary per display with "Display Identifier"
    /// (a display UUID string, or "Main"), "Current Space" (a Space dictionary) and "Spaces"
    /// (Space dictionaries in Mission Control order). A Space dictionary carries "id64" /
    /// "ManagedSpaceID" (the SpaceID) and "type" (0 user, 4 fullscreen).
    static func managedDisplaySpaces() -> [[String: Any]] {
        guard let connection = mainConnection,
              let function = symbols.copyManagedDisplaySpaces,
              let array = function(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return array
    }

    /// The Spaces a window is on (several when it is on all Spaces); [] when unknown.
    static func spaces(forWindow windowID: UInt32) -> [UInt64] {
        guard let connection = mainConnection, let function = symbols.copySpacesForWindows else { return [] }
        let windows = [NSNumber(value: windowID)] as CFArray
        guard let array = function(connection, allSpacesMask, windows)?.takeRetainedValue() as? [NSNumber] else {
            return []
        }
        return array.map(\.uint64Value)
    }

    /// The UUID string of the display showing the active menu bar.
    static func activeMenuBarDisplayIdentifier() -> String? {
        guard let connection = mainConnection, let function = symbols.copyActiveMenuBarDisplayIdentifier else {
            return nil
        }
        return function(connection)?.takeRetainedValue() as String?
    }

    // MARK: - Window images

    /// An image of one window, including windows on other Spaces and covered windows.
    /// Requires Screen Recording; nil when denied, minimized windows, or the symbol is missing.
    static func captureWindow(_ windowID: UInt32, options: CaptureOptions = [.ignoreGlobalClipShape, .nominalResolution]) -> CGImage? {
        guard let connection = mainConnection, let function = symbols.hwCaptureWindowList else { return nil }
        var id = windowID
        guard let array = function(connection, &id, 1, options.rawValue)?.takeRetainedValue() as? [CGImage] else {
            return nil
        }
        return array.first
    }

    // MARK: - Accessibility

    /// The CGWindowID behind an AX window element.
    static func windowID(of element: AXUIElement) -> UInt32? {
        guard let function = symbols.axUIElementGetWindow else { return nil }
        var id: UInt32 = 0
        guard function(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// An AX element of `pid` built from its remote token: how windows on other Spaces,
    /// which `kAXWindowsAttribute` omits, are recovered. Element ids are small integers;
    /// callers probe a bounded range (0..<1000) and keep elements whose role is a window.
    static func axElement(pid: pid_t, elementID: UInt64) -> AXUIElement? {
        guard let function = symbols.axUIElementCreateWithRemoteToken else { return nil }
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: pid, toByteOffset: 0, as: Int32.self)
            raw.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            raw.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self) // "coco"
            raw.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self)
        }
        return function(token as CFData)?.takeRetainedValue()
    }

    // MARK: - Focus

    static func processSerialNumber(for pid: pid_t) -> ProcessSerialNumber? {
        guard let function = symbols.getProcessForPID else { return nil }
        var psn = ProcessSerialNumber()
        guard function(pid, &psn) == noErr else { return nil }
        return psn
    }

    /// Makes `pid` the front process with `windowID` as its front window, switching to the
    /// window's Space. Returns false when the symbol is missing or the call fails.
    @discardableResult
    static func setFrontProcess(pid: pid_t, windowID: UInt32) -> Bool {
        guard var psn = processSerialNumber(for: pid), let function = symbols.setFrontProcessWithOptions else {
            return false
        }
        return function(&psn, windowID, userGeneratedFrontMode) == .success
    }

    /// Makes `windowID` the key window of `pid` (two synthetic window-server event records,
    /// as yabai and AltTab do), so the right window of a multi-window app gets focus.
    @discardableResult
    static func makeKeyWindow(pid: pid_t, windowID: UInt32) -> Bool {
        guard var psn = processSerialNumber(for: pid), let function = symbols.postEventRecordTo else { return false }
        var bytes = [UInt8](repeating: 0, count: 0xF8)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        withUnsafeBytes(of: windowID.littleEndian) { idBytes in
            for (offset, byte) in idBytes.enumerated() { bytes[0x3C + offset] = byte }
        }
        for offset in 0x20 ..< 0x30 { bytes[offset] = 0xFF }
        bytes[0x08] = 0x01
        let first = bytes.withUnsafeMutableBufferPointer { function(&psn, $0.baseAddress!) }
        bytes[0x08] = 0x02
        let second = bytes.withUnsafeMutableBufferPointer { function(&psn, $0.baseAddress!) }
        return first == .success && second == .success
    }
}
