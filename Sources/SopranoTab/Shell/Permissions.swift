import AppKit
import ApplicationServices

/// The two privacy grants Soprano Tab uses.
struct PermissionStatus: Equatable {
    /// Required: the keyboard tap, window focus and window actions.
    var accessibility: Bool
    /// Optional: thumbnails and previews (app icons without it).
    var screenRecording: Bool

    var allGranted: Bool { accessibility && screenRecording }
}

/// Reads and requests the privacy grants.
@MainActor
enum Permissions {
    enum Kind {
        case accessibility
        case screenRecording
    }

    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    static var isScreenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    static var status: PermissionStatus {
        PermissionStatus(accessibility: isAccessibilityTrusted, screenRecording: isScreenRecordingGranted)
    }

    /// Shows macOS's Accessibility prompt (once per call while not trusted), which also adds
    /// the app to the list in System Settings.
    static func requestAccessibility() {
        // The value of `kAXTrustedCheckOptionPrompt`: the imported global is a mutable C
        // variable, which Swift 6 rejects as not concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Asks macOS for Screen Recording; macOS prompts only the first time.
    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// Opens the matching pane of System Settings → Privacy & Security.
    static func openSettings(for kind: Kind) {
        let anchor = switch kind {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
