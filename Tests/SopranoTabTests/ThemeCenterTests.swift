import AppKit
import Testing
@testable import SopranoTab
@testable import SopranoTabCore

@MainActor
struct ThemeCenterTests {
    /// The macOS appearance the center sees; tests flip it.
    @MainActor
    private final class SystemBox {
        var appearance: AppTheme.Appearance
        /// What the center last set `NSApp.appearance` to (`.some(nil)` = follow macOS).
        var applicationAppearance: NSAppearance.Name??

        init(_ appearance: AppTheme.Appearance) {
            self.appearance = appearance
        }
    }

    private struct Fixture {
        let directory: URL
        let tabURL: URL
        let sopranoURL: URL
        let settings: SettingsCenter
        let system: SystemBox
        let center: ThemeCenter
    }

    /// Tab's and Soprano's settings.json in a fresh temporary directory; nothing is watched.
    private func makeFixture(tab: String, soprano: String?, system: AppTheme.Appearance) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("soprano-tab-theme-\(UUID().uuidString)", isDirectory: true)
        let tabURL = directory.appendingPathComponent("tab.json")
        let sopranoURL = directory.appendingPathComponent("soprano.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try SettingsFile.write(tab, to: tabURL)
        if let soprano {
            try SettingsFile.write(soprano, to: sopranoURL)
        }
        let settings = SettingsCenter(fileURL: tabURL)
        settings.start(watching: false)
        let box = SystemBox(system)
        let center = ThemeCenter(
            sopranoSettingsURL: sopranoURL,
            settings: settings,
            systemAppearance: { box.appearance },
            setApplicationAppearance: { box.applicationAppearance = .some($0?.name) }
        )
        center.start(watching: false)
        return Fixture(directory: directory, tabURL: tabURL, sopranoURL: sopranoURL, settings: settings, system: box, center: center)
    }

    @Test("folio follows the macOS appearance and notifies when it flips")
    func folioFollowsSystem() throws {
        let fixture = try makeFixture(tab: #"{ "theme": "folio" }"#, soprano: nil, system: .light)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let owner = NSObject()
        var notifications = 0
        fixture.center.addObserver(owner) { notifications += 1 }
        #expect(fixture.center.theme.id == AppTheme.folioPaper.id)

        fixture.system.appearance = .dark
        fixture.center.systemAppearanceDidChange()

        #expect(fixture.center.theme.id == AppTheme.folioInk.id)
        #expect(notifications == 1)
        fixture.center.systemAppearanceDidChange()
        #expect(notifications == 1)
        withExtendedLifetime(owner) {}
    }

    @Test("soprano follows Soprano's theme and its appearance, system meaning macOS")
    func sopranoFollowsThemeAndAppearance() throws {
        let fixture = try makeFixture(tab: #"{ "theme": "soprano" }"#, soprano: #"{ "theme": "folio", "appearance": "dark" }"#, system: .light)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        #expect(fixture.center.theme.id == AppTheme.folioInk.id)

        try SettingsFile.write(#"{ "theme": "folio", "appearance": "system" }"#, to: fixture.sopranoURL)
        fixture.center.systemAppearanceDidChange()
        #expect(fixture.center.theme.id == AppTheme.folioPaper.id)

        try SettingsFile.write(#"{ "theme": "nord", "appearance": "light" }"#, to: fixture.sopranoURL)
        fixture.center.systemAppearanceDidChange()
        #expect(fixture.center.theme.id == AppTheme.nord.id)
    }

    @Test("without Soprano's settings, soprano is folio on the macOS appearance")
    func missingSopranoFileIsFolio() throws {
        let fixture = try makeFixture(tab: #"{ "theme": "soprano" }"#, soprano: nil, system: .dark)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        #expect(fixture.center.theme.id == AppTheme.folioInk.id)
    }

    @Test("pinned themes ignore the appearance, and overrides resolve the same way")
    func pinnedAndOverrides() throws {
        let fixture = try makeFixture(tab: #"{ "theme": "folio-paper" }"#, soprano: #"{ "appearance": "dark" }"#, system: .dark)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        #expect(fixture.center.theme.id == AppTheme.folioPaper.id)
        #expect(fixture.center.theme(forOverride: "folio").id == AppTheme.folioInk.id)
        #expect(fixture.center.theme(forOverride: "soprano").id == AppTheme.folioInk.id)
        #expect(fixture.center.theme(forOverride: "folio-paper").id == AppTheme.folioPaper.id)
        #expect(fixture.center.theme(forOverride: nil).id == AppTheme.folioPaper.id)
    }

    @Test("the app appearance is unset while the global theme follows macOS and pinned otherwise")
    func applicationAppearanceFollowsTheGlobalTheme() throws {
        let cases: [(tab: String, soprano: String?, expected: NSAppearance.Name?)] = [
            (#"{ "theme": "folio" }"#, nil, nil),
            (#"{ "theme": "soprano" }"#, #"{ "theme": "folio", "appearance": "system" }"#, nil),
            (#"{ "theme": "soprano" }"#, #"{ "theme": "folio", "appearance": "light" }"#, .aqua),
            (#"{ "theme": "soprano" }"#, #"{ "theme": "nord", "appearance": "system" }"#, .darkAqua),
            (#"{ "theme": "folio-ink" }"#, nil, .darkAqua),
            (#"{ "theme": "folio-paper" }"#, nil, .aqua),
            (#"{ "theme": "dracula" }"#, nil, .darkAqua),
        ]
        for (tab, soprano, expected) in cases {
            let fixture = try makeFixture(tab: tab, soprano: soprano, system: .dark)
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            #expect(fixture.system.applicationAppearance == .some(expected), "\(tab) \(soprano ?? "")")
        }
    }

    @Test("by default the center sets the real NSApp.appearance")
    func defaultSetterDrivesTheApplication() throws {
        let app = NSApplication.shared
        let original = app.appearance
        defer { app.appearance = original }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("soprano-tab-theme-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tabURL = directory.appendingPathComponent("tab.json")
        try SettingsFile.write(#"{ "theme": "folio-ink" }"#, to: tabURL)
        let settings = SettingsCenter(fileURL: tabURL)
        settings.start(watching: false)
        let center = ThemeCenter(
            sopranoSettingsURL: directory.appendingPathComponent("soprano.json"),
            settings: settings,
            systemAppearance: { .light }
        )
        center.start(watching: false)
        #expect(app.appearance?.name == .darkAqua)

        try SettingsFile.write(#"{ "theme": "folio" }"#, to: tabURL)
        settings.reload()
        #expect(app.appearance == nil)
        #expect(center.theme.id == AppTheme.folioPaper.id)
    }
}
