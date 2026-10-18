import AppKit
import Testing
@testable import SopranoTab
@testable import SopranoTabCore

@MainActor
struct SettingsCenterTests {
    /// A settings.json path inside a fresh temporary directory that does not exist yet.
    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("soprano-tab-settings-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    private func removeDirectory(of url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("a missing settings file is created from the template and resolves to the defaults")
    func createsMissingFileFromTemplate() throws {
        let url = temporaryFileURL()
        defer { removeDirectory(of: url) }
        let center = SettingsCenter(fileURL: url)

        center.start(watching: false)

        #expect(try SettingsFile.read(at: url) == SettingsTemplate.text)
        #expect(center.settings == .defaults)
        #expect(center.issues.isEmpty)
    }

    @Test("an edited file applies on reload and notifies observers")
    func reloadAppliesEdits() throws {
        let url = temporaryFileURL()
        defer { removeDirectory(of: url) }
        let center = SettingsCenter(fileURL: url)
        center.start(watching: false)
        let owner = NSObject()
        var notifications = 0
        center.addObserver(owner) { notifications += 1 }

        try SettingsFile.write(
            #"{ "appearance": { "showDelayMs": 250 }, "app": { "menuBarIcon": "filled" } }"#,
            to: url
        )
        center.reload()

        #expect(center.settings.appearance.showDelayMs == 250)
        #expect(center.settings.app.menuBarIcon == .filled)
        #expect(notifications == 1)

        center.reload()
        #expect(notifications == 1)
        withExtendedLifetime(owner) {}
    }

    @Test("a document that does not parse keeps the last good settings and reports an error")
    func invalidDocumentKeepsLastGoodSettings() throws {
        let url = temporaryFileURL()
        defer { removeDirectory(of: url) }
        let center = SettingsCenter(fileURL: url)
        center.start(watching: false)
        try SettingsFile.write(#"{ "appearance": { "showDelayMs": 250 } }"#, to: url)
        center.reload()

        try SettingsFile.write(#"{ "appearance": { "showDelayMs": "#, to: url)
        center.reload()

        #expect(center.settings.appearance.showDelayMs == 250)
        #expect(center.issues.contains { $0.severity == .error })

        try SettingsFile.write(#"{ "appearance": { "showDelayMs": 300 } }"#, to: url)
        center.reload()

        #expect(center.settings.appearance.showDelayMs == 300)
        #expect(!center.issues.contains { $0.severity == .error })
    }

    @Test("writing a value keeps the file's comments and applies it")
    func writePreservesComments() throws {
        let url = temporaryFileURL()
        defer { removeDirectory(of: url) }
        try SettingsFile.write(
            """
            // My switcher.
            {
              // Follow Soprano.
              "theme": "soprano"
            }

            """,
            to: url
        )
        let center = SettingsCenter(fileURL: url)
        center.start(watching: false)

        try center.write(false, at: ["app", "startAtLogin"])

        let text = try SettingsFile.read(at: url)
        #expect(text.contains("// My switcher."))
        #expect(text.contains("// Follow Soprano."))
        #expect(center.settings.app.startAtLogin == false)
        #expect(center.settings.theme == "soprano")
    }
}
