import AppKit
import Testing
@testable import SopranoTabCore

struct SettingsEditorTests {
    private let document = """
    // my settings
    {
      "theme": "nord", // favorite
      "appearance": {
        /* keep me */
        "style": "thumbnails"
      }
    }
    """

    @Test("replacing a value keeps comments and the other keys")
    func replaceKeepsComments() throws {
        let edited = try SettingsEditor.setting("appIcons", at: ["appearance", "style"], in: document)
        #expect(edited.contains("// my settings"))
        #expect(edited.contains("// favorite"))
        #expect(edited.contains("/* keep me */"))
        let settings = SettingsResolver.resolve(text: edited, knownThemeIDs: ["nord"]).settings
        #expect(settings?.appearance.style == .appIcons)
        #expect(settings?.theme == "nord")
    }

    @Test("setting a missing nested path creates its objects")
    func createsNestedPath() throws {
        var edited = try SettingsEditor.setting(true, at: ["mouse", "hoverSelects"], in: document)
        edited = try SettingsEditor.setting(NSNull(), at: ["controls", "quit"], in: edited)
        edited = try SettingsEditor.setting(300, at: ["appearance", "showDelayMs"], in: edited)
        let resolution = SettingsResolver.resolve(text: edited, knownThemeIDs: ["nord"])
        #expect(resolution.issues.isEmpty)
        #expect(resolution.settings?.mouse.hoverSelects == true)
        #expect(resolution.settings?.controls.quit == nil)
        #expect(resolution.settings?.appearance.showDelayMs == 300)
        #expect(edited.contains("/* keep me */"))
    }

    @Test("an unreadable document throws an edit error with its line")
    func parseErrorThrows() {
        #expect(throws: SettingsEditError.self) {
            try SettingsEditor.setting(true, at: ["mouse", "hoverSelects"], in: "{\n  \"mouse\": \n}")
        }
        do {
            _ = try SettingsEditor.setting(true, at: ["fadeOut"], in: "{\n\n  \"a\": nope\n}")
            Issue.record("expected an error")
        } catch let error as SettingsEditError {
            #expect(error.line == 3)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
