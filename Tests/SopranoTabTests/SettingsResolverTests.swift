import AppKit
import Testing
@testable import SopranoTabCore

struct SettingsResolverTests {
    private func resolve(_ text: String, themes: Set<String> = ["nord"]) -> SettingsResolution {
        SettingsResolver.resolve(text: text, knownThemeIDs: themes)
    }

    private func settings(_ text: String) -> SopranoTabSettings {
        resolve(text).settings ?? SopranoTabSettings()
    }

    private func warnings(_ resolution: SettingsResolution) -> [String] {
        resolution.issues.filter { $0.severity == .warning }.map(\.message)
    }

    private func warns(_ resolution: SettingsResolution, _ fragment: String) -> Bool {
        warnings(resolution).contains { $0.contains(fragment) }
    }

    @Test("an empty object resolves to the defaults without issues")
    func emptyObject() {
        let resolution = resolve("{}")
        #expect(resolution.settings == .defaults)
        #expect(resolution.issues.isEmpty)
    }

    @Test("comments, trailing commas and every section apply over the defaults")
    func fullDocument() {
        let resolution = resolve("""
        // header
        {
          "theme": "nord",
          "shortcuts": [
            { "hold": "cmd", "key": "tab", "onRelease": "search", "style": "titles", "theme": "soprano", "preview": true },
          ],
          "gesture": { "type": "threeFingerHorizontal", "haptics": false, "apps": "active" },
          "controls": { "previous": "option", "quit": null, "arrowKeys": false },
          "mouse": { "hoverSelects": true, "cursorFollowsFocus": "always" },
          "appearance": { "size": "large", "showDelayMs": 250, "spaceLabels": true },
          "app": { "startAtLogin": false, "menuBarIcon": "hidden" }, /* trailing */
        }
        """)
        #expect(resolution.issues.isEmpty)
        let settings = resolution.settings ?? SopranoTabSettings()
        #expect(settings.theme == "nord")
        #expect(settings.shortcuts == [ShortcutSettings(
            hold: .command,
            key: .named(.tab),
            onRelease: .search,
            overrides: AppearanceOverrides(style: .titles, theme: "soprano", previewSelectedWindow: true)
        )])
        #expect(settings.gesture == GestureSettings(kind: .threeFingerHorizontal, filters: WindowFilters(apps: .active), hapticFeedback: false))
        #expect(settings.controls.previous == .option)
        #expect(settings.controls.quit == nil)
        #expect(!settings.controls.arrowKeys)
        #expect(settings.mouse == MouseSettings(hoverSelects: true, cursorFollowsFocus: .always))
        #expect(settings.appearance.size == .large)
        #expect(settings.appearance.showDelayMs == 250)
        #expect(settings.appearance.spaceLabels)
        #expect(settings.app == AppBehaviorSettings(startAtLogin: false, menuBarIcon: .hidden))
        #expect(settings.exceptions == ExceptionRule.defaults)
    }

    @Test("a document that is not a JSON object is an error with its line and no settings")
    func nonObjectDocument() {
        let resolution = resolve("// comment\n\n[1, 2]\n")
        #expect(resolution.settings == nil)
        #expect(resolution.issues.count == 1)
        #expect(resolution.issues.first?.severity == .error)
        #expect(resolution.issues.first?.line == 3)
    }

    @Test("a syntax error is an error at its line")
    func syntaxError() {
        let resolution = resolve("{\n  \"theme\": \"nord\",\n  \"mouse\": { \"hoverSelects\": tru }\n}")
        #expect(resolution.settings == nil)
        #expect(resolution.issues.count == 1)
        #expect(resolution.issues.first?.severity == .error)
        #expect(resolution.issues.first?.line == 3)
    }

    @Test("shortcut keys default by position and entries without a key from shortcut 3 are dropped")
    func shortcutKeyDefaults() {
        let resolution = resolve("""
        { "shortcuts": [ { "hold": "control" }, { "spaces": "visible" }, { "hold": "command" }, { "key": "f1" } ] }
        """)
        let shortcuts = resolution.settings?.shortcuts ?? []
        #expect(shortcuts.count == 3)
        #expect(shortcuts[0] == ShortcutSettings(hold: .control, key: .named(.tab)))
        #expect(shortcuts[1] == ShortcutSettings(hold: .option, key: .named(.keyAboveTab), filters: WindowFilters(apps: .active, spaces: .visible)))
        #expect(shortcuts[2].key == .named(.f1))
        // Filters follow the entry's position in the array (index 3 → all apps).
        #expect(shortcuts[2].filters == ShortcutSettings.defaultFilters(forIndex: 3))
        #expect(warns(resolution, "shortcuts[2] has no \"key\""))
    }

    @Test("the third shortcut starts from the non-active apps filter")
    func thirdShortcutFilters() {
        let shortcuts = settings("""
        { "shortcuts": [ {}, {}, { "key": "f2" } ] }
        """).shortcuts
        #expect(shortcuts.map(\.filters.apps) == [.all, .active, .nonActive])
    }

    @Test("a bad hold keeps option and an empty hold is rejected")
    func badHold() {
        let resolution = resolve("""
        { "shortcuts": [ { "hold": "", "key": "tab" }, { "hold": "hyper" } ] }
        """)
        #expect(resolution.settings?.shortcuts.map(\.hold) == [.option, .option])
        #expect(warns(resolution, "shortcuts[0].hold: \"\""))
        #expect(warns(resolution, "shortcuts[1].hold: \"hyper\""))
    }

    @Test("more than nine shortcuts keeps the first nine with a warning")
    func tooManyShortcuts() {
        let entries = (1...11).map { "{ \"key\": \"f\($0)\" }" }.joined(separator: ", ")
        let resolution = resolve("{ \"shortcuts\": [\(entries)] }")
        let keys = resolution.settings?.shortcuts.map(\.key) ?? []
        #expect(keys == (1...9).compactMap { KeySpec(settingsText: "f\($0)") })
        #expect(warns(resolution, "only the first 9"))
    }

    @Test("an empty shortcut array keeps the defaults with a warning")
    func emptyShortcuts() {
        let resolution = resolve("{ \"shortcuts\": [] }")
        #expect(resolution.settings?.shortcuts == ShortcutSettings.defaults)
        #expect(warns(resolution, "shortcuts is empty"))
    }

    @Test("a later shortcut repeating an earlier hold and key is dropped")
    func duplicateShortcut() {
        let resolution = resolve("""
        { "shortcuts": [ { "key": "tab" }, { "key": "tab", "apps": "active" }, { "hold": "alt", "key": "Tab" }, { "hold": "command", "key": "tab" } ] }
        """)
        let shortcuts = resolution.settings?.shortcuts ?? []
        #expect(shortcuts.map(\.hold) == [.option, .command])
        #expect(warnings(resolution).filter { $0.contains("repeats option+tab of shortcuts[0]") }.count == 2)
    }

    @Test("two controls on one key disable the later one in the documented order")
    func controlConflicts() {
        let resolution = resolve("""
        { "controls": { "search": "w", "hide": "Return", "cancel": "escape" } }
        """)
        let controls = resolution.settings?.controls ?? ControlSettings()
        #expect(controls.focus == .named(.return))
        #expect(controls.hide == nil)
        #expect(controls.close == .character("w"))
        #expect(controls.search == nil)
        #expect(warns(resolution, "controls.hide uses \"return\" like controls.focus"))
        #expect(warns(resolution, "controls.search uses \"w\" like controls.close"))
    }

    @Test("vim keys warn about actions on h, j, k or l")
    func vimConflict() {
        let resolution = resolve("""
        { "controls": { "vimKeys": true, "quit": "k" } }
        """)
        let controls = resolution.settings?.controls ?? ControlSettings()
        #expect(controls.vimKeys)
        #expect(controls.quit == .character("k"))
        #expect(warns(resolution, "controls.quit is \"k\""))
        #expect(warns(resolution, "controls.hide is \"h\""))
        #expect(warnings(resolution).count == 2)
    }

    @Test("null disables a control key and previous; previous must be one modifier")
    func nullControls() {
        let disabled = settings("""
        { "controls": { "close": null, "focus": null, "previous": null } }
        """).controls
        #expect(disabled.close == nil)
        #expect(disabled.focus == nil)
        #expect(disabled.previous == [])

        let resolution = resolve("{ \"controls\": { \"previous\": \"shift+option\" } }")
        #expect(resolution.settings?.controls.previous == .shift)
        #expect(warns(resolution, "controls.previous: \"shift+option\""))
    }

    @Test("showDelayMs is clamped to its range and must be a whole number")
    func showDelayClamp() {
        let high = resolve("{ \"appearance\": { \"showDelayMs\": 5000 } }")
        #expect(high.settings?.appearance.showDelayMs == AppearanceSettings.showDelayRange.upperBound)
        #expect(warns(high, "clamped to 2000"))

        let low = resolve("{ \"appearance\": { \"showDelayMs\": -3 } }")
        #expect(low.settings?.appearance.showDelayMs == 0)

        let fractional = resolve("{ \"appearance\": { \"showDelayMs\": 12.5 } }")
        #expect(fractional.settings?.appearance.showDelayMs == 100)
        #expect(warns(fractional, "appearance.showDelayMs: 12.5"))

        #expect(settings("{ \"appearance\": { \"showDelayMs\": 300.0 } }").appearance.showDelayMs == 300)
    }

    @Test("booleans accept only JSON booleans")
    func strictBooleans() {
        let resolution = resolve("{ \"appearance\": { \"fadeOut\": 1 }, \"mouse\": { \"hoverSelects\": \"true\" } }")
        #expect(resolution.settings?.appearance.fadeOut == false)
        #expect(resolution.settings?.mouse.hoverSelects == false)
        #expect(warnings(resolution).count == 2)
    }

    @Test("unknown keys warn with their dotted path")
    func unknownKeys() {
        let resolution = resolve("""
        { "foo": 1, "appearance": { "bar": true }, "shortcuts": [ { "baz": 1 } ], "exceptions": [ { "bundleId": "a", "qux": 1 } ] }
        """)
        #expect(resolution.settings != nil)
        #expect(Set(warnings(resolution)) == [
            "Unknown setting \"foo\".",
            "Unknown setting \"appearance.bar\".",
            "Unknown setting \"shortcuts[0].baz\".",
            "Unknown setting \"exceptions[0].qux\".",
        ])
    }

    @Test("a bad enum value keeps the default and names the allowed values")
    func badEnum() {
        let resolution = resolve("{ \"appearance\": { \"style\": \"grid\", \"titles\": 3 } }")
        #expect(resolution.settings?.appearance.style == .thumbnails)
        #expect(resolution.settings?.appearance.titles == .windowTitle)
        #expect(warnings(resolution).contains(
            "appearance.style: \"grid\" is not one of \"thumbnails\", \"appIcons\", \"titles\"; kept \"thumbnails\"."
        ))
        #expect(warns(resolution, "appearance.titles: 3 is not one of"))
    }

    @Test("a section that is not an object is ignored with a warning")
    func badSection() {
        let resolution = resolve("{ \"mouse\": true }")
        #expect(resolution.settings?.mouse == MouseSettings())
        #expect(warns(resolution, "mouse: true is not an object"))
    }

    @Test("exceptions replace the defaults; titleContains takes a string or an array")
    func exceptions() {
        let resolution = resolve("""
        { "exceptions": [
            { "bundleId": "com.example.a", "hide": "whenTitleContains", "titleContains": "Picture in Picture" },
            { "bundleId": "com.example.b", "hide": "whenTitleContains", "titleContains": ["Debug", "Log"], "ignoreShortcuts": "always" },
            { "hide": "always" }
        ] }
        """)
        #expect(resolution.settings?.exceptions == [
            ExceptionRule(bundleID: "com.example.a", hide: .whenTitleContains, titleContains: ["Picture in Picture"]),
            ExceptionRule(bundleID: "com.example.b", hide: .whenTitleContains, titleContains: ["Debug", "Log"], ignoreShortcuts: .always),
        ])
        #expect(warns(resolution, "exceptions[2].bundleId: missing"))
        #expect(settings("{ \"exceptions\": [] }").exceptions.isEmpty)
    }

    @Test("hiding by title without titleContains warns")
    func titleContainsMissing() {
        let resolution = resolve("{ \"exceptions\": [ { \"bundleId\": \"com.example\", \"hide\": \"whenTitleContains\" } ] }")
        #expect(resolution.settings?.exceptions.count == 1)
        #expect(warns(resolution, "exceptions[0].hide is \"whenTitleContains\" without titleContains"))
    }

    @Test("unknown themes keep the global theme and list the known ids")
    func unknownTheme() {
        let resolution = resolve("""
        { "theme": "neon", "shortcuts": [ { "theme": "dracula" }, { "theme": "nord" } ] }
        """)
        #expect(resolution.settings?.theme == "soprano")
        #expect(resolution.settings?.shortcuts.map(\.overrides.theme) == [nil, "nord"])
        #expect(warns(resolution, "theme: \"neon\" is not a known theme; kept \"soprano\". Known themes: \"soprano\", \"nord\"."))
        #expect(warns(resolution, "shortcuts[0].theme: \"dracula\""))
        #expect(resolve("{ \"theme\": \"soprano\" }", themes: []).issues.isEmpty)
    }
}
