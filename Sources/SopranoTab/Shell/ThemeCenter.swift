import AppKit
import SopranoTabCore

/// The live theme (adapted from Soprano Git's `ThemeCenter`).
///
/// `theme: "soprano"` follows the `theme` key of Soprano's settings.json, watched live;
/// Mission Control when that file or key is missing or unknown. Shortcut overrides resolve
/// through `theme(forOverride:)`, where "soprano" follows Soprano too.
@MainActor
final class ThemeCenter {
    static let shared = ThemeCenter()

    /// Soprano's settings.json, read while anything follows Soprano.
    let sopranoSettingsURL: URL
    /// The global theme (settings.json `theme`).
    private(set) var theme = AppTheme.missionControl

    private let settingsCenter: SettingsCenter
    /// Soprano's current theme; kept up to date only while something follows it.
    private var sopranoTheme = AppTheme.missionControl
    private var sopranoWatcher: ConfigFileWatcher?
    private let observers = ObserverList<Void>()
    private var isStarted = false

    init(sopranoSettingsURL: URL = SettingsFile.sopranoURL(), settings: SettingsCenter = .shared) {
        self.sopranoSettingsURL = sopranoSettingsURL
        self.settingsCenter = settings
    }

    /// Applies the current settings and follows their changes.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        apply()
        settingsCenter.addObserver(self) { [weak self] in
            self?.apply()
        }
    }

    /// The theme for a shortcut's override id; nil (or an unknown id) is the global theme.
    func theme(forOverride id: String?) -> AppTheme {
        guard let id else { return theme }
        if id == "soprano" { return sopranoTheme }
        return AppTheme.allThemes.first { $0.id == id } ?? theme
    }

    /// Handlers fire after the global theme or Soprano's theme changes, until `owner` is
    /// deallocated.
    func addObserver(_ owner: AnyObject, _ handler: @escaping @MainActor () -> Void) {
        observers.add(owner) { _ in handler() }
    }

    private func apply() {
        let settings = settingsCenter.settings
        let followsSoprano = settings.theme == "soprano"
            || settings.shortcuts.contains { $0.overrides.theme == "soprano" }
        updateSopranoWatcher(enabled: followsSoprano)
        if followsSoprano {
            sopranoTheme = readSopranoTheme()
        }
        let previous = (theme.id, sopranoTheme.id)
        theme = settings.theme == "soprano"
            ? sopranoTheme
            : AppTheme.allThemes.first { $0.id == settings.theme } ?? .missionControl
        if previous != (theme.id, sopranoTheme.id) {
            observers.notify(())
        }
    }

    private func reloadSopranoTheme() {
        guard sopranoWatcher != nil else { return }
        apply()
    }

    /// Soprano's settings.json shares the top-level `theme` key and its ids, so the
    /// public JSONC resolver reads it; every other Soprano key is ignored.
    private func readSopranoTheme() -> AppTheme {
        guard let text = try? SettingsFile.read(at: sopranoSettingsURL) else { return .missionControl }
        let ids = Set(AppTheme.allThemes.map(\.id))
        guard let id = SettingsResolver.resolve(text: text, knownThemeIDs: ids).settings?.theme else {
            return .missionControl
        }
        return AppTheme.allThemes.first { $0.id == id } ?? .missionControl
    }

    private func updateSopranoWatcher(enabled: Bool) {
        if enabled {
            guard sopranoWatcher == nil else { return }
            let watcher = ConfigFileWatcher(url: sopranoSettingsURL) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.reloadSopranoTheme()
                }
            }
            watcher.start()
            sopranoWatcher = watcher
        } else {
            sopranoWatcher?.stop()
            sopranoWatcher = nil
        }
    }
}
