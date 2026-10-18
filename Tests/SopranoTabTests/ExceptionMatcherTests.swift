import AppKit
import Testing
@testable import SopranoTabCore

struct ExceptionMatcherTests {
    private func frontmost(bundleID: String?, fullscreen: Bool, focused: Bool = true) -> WindowSnapshot {
        let app = AppInfo(pid: 7, bundleID: bundleID, name: "App", isActive: true)
        let other = AppInfo(pid: 8, bundleID: "test.other", name: "Other")
        return WindowSnapshot(
            windows: [
                WindowInfo(id: .window(1), app: app, title: "Main", isFullscreen: fullscreen),
                WindowInfo(id: .window(2), app: other, title: "Other", isFullscreen: true),
            ],
            frontmostPID: 7,
            focusedWindowID: focused ? 1 : nil
        )
    }

    @Test("an exact bundle id beats every prefix rule regardless of order")
    func exactBeatsPrefix() {
        let rules = [
            ExceptionRule(bundleID: "com.parallels.", hide: .always),
            ExceptionRule(bundleID: "com.parallels.desktop.console", hide: .whenNoOpenWindow),
        ]
        #expect(ExceptionMatcher.rule(forBundleID: "com.parallels.desktop.console", in: rules)?.hide == .whenNoOpenWindow)
    }

    @Test("the longest matching prefix rule wins")
    func longestPrefix() {
        let rules = [
            ExceptionRule(bundleID: "com.", hide: .always),
            ExceptionRule(bundleID: "com.parallels.desktop.", hide: .whenNoOpenWindow),
            ExceptionRule(bundleID: "com.parallels.", hide: .whenTitleContains),
        ]
        #expect(ExceptionMatcher.rule(forBundleID: "com.parallels.desktop.console", in: rules)?.bundleID == "com.parallels.desktop.")
        #expect(ExceptionMatcher.rule(forBundleID: "com.parallels.vm", in: rules)?.bundleID == "com.parallels.")
        #expect(ExceptionMatcher.rule(forBundleID: "com.apple.finder", in: rules)?.bundleID == "com.")
    }

    @Test("only rules ending in a dot match by prefix")
    func prefixNeedsTrailingDot() {
        let rules = [ExceptionRule(bundleID: "com.apple", hide: .always)]
        #expect(ExceptionMatcher.rule(forBundleID: "com.apple.finder", in: rules) == nil)
        #expect(ExceptionMatcher.rule(forBundleID: "com.apple", in: rules)?.hide == .always)
    }

    @Test("an app without a bundle id has no rule")
    func missingBundleID() {
        #expect(ExceptionMatcher.rule(forBundleID: nil, in: ExceptionRule.defaults) == nil)
        #expect(ExceptionMatcher.rule(forBundleID: "", in: [ExceptionRule(bundleID: "", hide: .always)]) == nil)
    }

    @Test("ignore always passes shortcuts through whenever the app is frontmost")
    func ignoreAlways() {
        let rules = [ExceptionRule(bundleID: "test.vm", ignoreShortcuts: .always)]
        #expect(ExceptionMatcher.shortcutsIgnored(in: frontmost(bundleID: "test.vm", fullscreen: false), rules: rules))
        #expect(!ExceptionMatcher.shortcutsIgnored(in: frontmost(bundleID: "test.editor", fullscreen: false), rules: rules))
    }

    @Test("ignore whenFullscreen depends on the focused window being fullscreen")
    func ignoreWhenFullscreen() {
        let rules = ExceptionRule.defaults
        #expect(ExceptionMatcher.shortcutsIgnored(in: frontmost(bundleID: "com.parallels.desktop.console", fullscreen: true), rules: rules))
        #expect(!ExceptionMatcher.shortcutsIgnored(in: frontmost(bundleID: "com.parallels.desktop.console", fullscreen: false), rules: rules))
        #expect(!ExceptionMatcher.shortcutsIgnored(in: frontmost(bundleID: "com.parallels.desktop.console", fullscreen: true, focused: false), rules: rules))
    }

    @Test("nothing is ignored without a frontmost app or with ignore never")
    func notIgnored() {
        var snapshot = frontmost(bundleID: "com.apple.finder", fullscreen: true)
        #expect(!ExceptionMatcher.shortcutsIgnored(in: snapshot, rules: ExceptionRule.defaults))
        snapshot.frontmostPID = nil
        #expect(!ExceptionMatcher.shortcutsIgnored(in: snapshot, rules: [ExceptionRule(bundleID: "com.apple.finder", ignoreShortcuts: .always)]))
    }
}
