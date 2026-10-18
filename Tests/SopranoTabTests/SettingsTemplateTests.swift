import AppKit
import Testing
@testable import SopranoTabCore

struct SettingsTemplateTests {
    @Test("the template resolves to exactly the defaults with no issues")
    func resolvesToDefaults() {
        let resolution = SettingsResolver.resolve(text: SettingsTemplate.text, knownThemeIDs: [])
        #expect(resolution.issues.isEmpty)
        #expect(resolution.settings == .defaults)
    }

    @Test("the template documents the allowed values of every choice")
    func documentsAllowedValues() {
        let text = SettingsTemplate.text
        let values = AppsFilter.allCases.map(\.rawValue) + GestureKind.allCases.map(\.rawValue)
            + ExceptionHide.allCases.map(\.rawValue) + CursorFollowsFocus.allCases.map(\.rawValue)
        for value in values {
            #expect(text.contains("\"\(value)\""), "missing \(value)")
        }
    }

    @Test("editing the template keeps its comments and applies the new value")
    func editableTemplate() throws {
        let edited = try SettingsEditor.setting("titles", at: ["appearance", "style"], in: SettingsTemplate.text)
        #expect(edited.contains("// Soprano Tab settings."))
        let resolution = SettingsResolver.resolve(text: edited, knownThemeIDs: [])
        #expect(resolution.issues.isEmpty)
        #expect(resolution.settings?.appearance.style == .titles)
    }
}
