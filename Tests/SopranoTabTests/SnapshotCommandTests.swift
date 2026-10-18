import AppKit
import Testing
@testable import SopranoTab
@testable import SopranoTabCore

@MainActor
struct SnapshotCommandTests {
    private typealias Command = SnapshotCommand

    private func parse(_ arguments: [String]) throws -> Command.Options {
        try Command.parse(["--out", "/tmp/soprano-tab-snapshot.png"] + arguments)
    }

    @Test("only --out is required; everything else has a default")
    func defaults() throws {
        let options = try parse([])
        #expect(options.out.path == "/tmp/soprano-tab-snapshot.png")
        #expect(options.scenario == .standard)
        #expect(options.screenSize == CGSize(width: 1512, height: 982))
        #expect(options.style == nil && options.size == nil && options.theme == nil)
        #expect(options.shortcutIndex == 0)
        #expect(options.keys.isEmpty && options.search == nil && options.hover == nil)
        #expect(!options.preview && !options.onboarding && options.report == nil && options.settings == nil)
    }

    @Test("every option parses into its field")
    func everyOption() throws {
        let options = try parse([
            "--scenario", "multiScreen", "--screen", "1920x1200", "--style", "appIcons", "--size", "large",
            "--theme", "nord", "--shortcut", "2", "--settings", "/tmp/tab.jsonc",
            "--keys", "tab shift+tab  shift release left right up down return escape W",
            "--search", "saf", "--hover", "3", "--preview", "--report", "/tmp/report.json",
        ])
        #expect(options.scenario == .multiScreen)
        #expect(options.screenSize == CGSize(width: 1920, height: 1200))
        #expect(options.style == .appIcons)
        #expect(options.size == .large)
        #expect(options.theme == "nord")
        #expect(options.shortcutIndex == 1)
        #expect(options.settings?.path == "/tmp/tab.jsonc")
        #expect(options.keys == [
            .trigger, .reverseTrigger, .previousModifier, .release,
            .named(.left), .named(.right), .named(.up), .named(.down), .named(.return), .named(.escape),
            .character("w"),
        ])
        #expect(options.search == "saf")
        #expect(options.hover == 3)
        #expect(options.preview)
        #expect(options.report?.path == "/tmp/report.json")
    }

    @Test("onboarding takes the permission states")
    func onboarding() throws {
        let options = try parse(["--onboarding", "--permissions", "accessibility=granted,screen=missing"])
        #expect(options.onboarding)
        #expect(options.accessibilityGranted)
        #expect(!options.screenRecordingGranted)
        let missing = try parse(["--onboarding"])
        #expect(!missing.accessibilityGranted && !missing.screenRecordingGranted)
    }

    @Test("bad input is rejected with the matching error")
    func errors() {
        #expect(throws: Command.OptionError.missingOut) { try Command.parse(["--scenario", "standard"]) }
        #expect(throws: Command.OptionError.missingValue("--keys")) { try parse(["--keys"]) }
        #expect(throws: Command.OptionError.unknownOption("--wait")) { try parse(["--wait", "1"]) }
        #expect(throws: Command.OptionError.badScenario("busy")) { try parse(["--scenario", "busy"]) }
        #expect(throws: Command.OptionError.badScreen("1512")) { try parse(["--screen", "1512"]) }
        #expect(throws: Command.OptionError.badScreen("400x300")) { try parse(["--screen", "400x300"]) }
        #expect(throws: Command.OptionError.badSize("huge")) { try parse(["--size", "huge"]) }
        #expect(throws: Command.OptionError.badStyle("grid")) { try parse(["--style", "grid"]) }
        #expect(throws: Command.OptionError.badShortcut("10")) { try parse(["--shortcut", "10"]) }
        #expect(throws: Command.OptionError.badShortcut("0")) { try parse(["--shortcut", "0"]) }
        #expect(throws: Command.OptionError.badHover("-1")) { try parse(["--hover", "-1"]) }
        #expect(throws: Command.OptionError.unknownKeyToken("ctrl+tab")) { try parse(["--keys", "tab ctrl+tab"]) }
        #expect(throws: Command.OptionError.unknownKeyToken("!")) { try parse(["--keys", "!"]) }
        #expect(throws: Command.OptionError.badPermissions("accessibility=yes")) {
            try parse(["--onboarding", "--permissions", "accessibility=yes"])
        }
        #expect(throws: Command.OptionError.permissionsWithoutOnboarding) {
            try parse(["--permissions", "accessibility=granted"])
        }
    }

    @Test("the standard snapshot is the screen at 2x with the window after the focused one selected")
    func renderStandard() throws {
        let result = try Command.render(try parse([]))
        #expect(result.image.width == 1512 * 2)
        #expect(result.image.height == 982 * 2)
        #expect(result.report.active)
        #expect(result.report.selectedIndex == 1)
        #expect(result.report.items.first == "soprano-tab — claude")
        #expect(result.report.items[1] == "Features – AltTab")
        #expect(result.report.actions.isEmpty)
        #expect(result.report.query == "")
    }

    @Test("releasing the hold modifier focuses the selection and closes the switcher")
    func renderRelease() throws {
        let result = try Command.render(try parse(["--keys", "release"]))
        #expect(!result.report.active)
        #expect(result.report.selectedIndex == nil)
        #expect(result.report.actions == ["focus window 1003"])
        #expect(result.image.width == 1512 * 2)
    }

    @Test("the report writes a missing selection as null")
    func reportJSON() throws {
        let report = SnapshotReport(active: false, selectedIndex: nil, items: [], query: "", actions: ["focus window 1003"])
        let text = String(decoding: try report.jsonData(), as: UTF8.self)
        #expect(text.contains("\"selectedIndex\" : null"))
        #expect(text.contains("\"actions\" : [\n    \"focus window 1003\"\n  ]"))
    }
}
