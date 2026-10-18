import AppKit
import SopranoTabCore
import UniformTypeIdentifiers

/// App icons of running apps, cached per pid.
@MainActor
final class LiveAppIconProvider: AppIconProvider {
    /// The bundle id an entry was looked up for: macOS reuses pids, and a pid that now
    /// belongs to another app must not keep the old app's icon.
    private struct Entry {
        var bundleID: String?
        var image: NSImage
    }

    private var cache: [pid_t: Entry] = [:]

    init() {}

    func icon(for app: AppInfo) -> NSImage {
        if let entry = cache[app.pid], entry.bundleID == app.bundleID {
            return entry.image
        }
        let image = NSRunningApplication(processIdentifier: app.pid)?.icon
            ?? app.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        cache[app.pid] = Entry(bundleID: app.bundleID, image: image)
        return image
    }
}
