import Foundation

/// Finds the app-specific exception (AltTab's blacklist entry) that applies to an app.
public enum ExceptionMatcher {
    /// An exact bundle id match wins over the longest matching prefix rule ("com.parallels.").
    /// A prefix rule is one whose `bundleID` ends in "."; among equally long prefixes the
    /// first rule wins.
    public static func rule(forBundleID bundleID: String?, in rules: [ExceptionRule]) -> ExceptionRule? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let exact = rules.first(where: { $0.bundleID == bundleID }) { return exact }
        var best: ExceptionRule?
        for rule in rules where rule.bundleID.hasSuffix(".") && bundleID.hasPrefix(rule.bundleID) {
            if let current = best, current.bundleID.count >= rule.bundleID.count { continue }
            best = rule
        }
        return best
    }

    /// True when the frontmost app's rule says `always`, or `whenFullscreen` and the focused
    /// window is fullscreen.
    public static func shortcutsIgnored(in snapshot: WindowSnapshot, rules: [ExceptionRule]) -> Bool {
        guard let pid = snapshot.frontmostPID,
              let app = snapshot.windows.first(where: { $0.app.pid == pid })?.app,
              let rule = rule(forBundleID: app.bundleID, in: rules)
        else { return false }
        switch rule.ignoreShortcuts {
        case .never:
            return false
        case .always:
            return true
        case .whenFullscreen:
            guard let focusedID = snapshot.focusedWindowID else { return false }
            return snapshot.windows.first { $0.id == .window(focusedID) }?.isFullscreen ?? false
        }
    }
}
