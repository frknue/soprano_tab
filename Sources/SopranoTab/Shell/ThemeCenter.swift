import AppKit
import SopranoTabCore

/// The live theme (adapted from Soprano Git's `ThemeCenter`).
///
/// - `theme: "soprano"` (the default) follows the `theme` and `appearance` keys of Soprano's
///   settings.json, watched live: `folio` there resolves to Paper or Ink from Soprano's
///   appearance (`system` follows macOS).
/// - `folio` follows the macOS appearance; `folio-paper`, `folio-ink` and the third-party
///   themes are pinned. Unknown ids resolve like `folio`.
///
/// `NSApp.appearance` follows the global theme (the same rule as Soprano and Soprano Git):
/// nil while it follows macOS, else the theme's appearance, so the status-item menu and any
/// sheet or popup match pinned and third-party themes. Each window also takes its appearance
/// from its resolved theme. Observers fire when a resolved palette changes, including when
/// macOS flips between light and dark.
@MainActor
final class ThemeCenter {
    static let shared = ThemeCenter()

    /// Soprano's settings.json, read while anything follows Soprano.
    let sopranoSettingsURL: URL
    /// The global theme (settings.json `theme`), resolved.
    private(set) var theme: AppTheme

    private let settingsCenter: SettingsCenter
    private let systemAppearance: @MainActor () -> AppTheme.Appearance
    private let setApplicationAppearance: @MainActor (NSAppearance?) -> Void
    /// Soprano's theme and appearance; kept up to date only while something follows it.
    private var soprano = SopranoThemeFile()
    private var sopranoTheme: AppTheme
    private var watchesSoprano = true
    private var sopranoWatcher: ConfigFileWatcher?
    private var appearanceObservation: NSKeyValueObservation?
    private let observers = ObserverList<Void>()
    private var isStarted = false

    /// `systemAppearance` is the macOS appearance and `setApplicationAppearance` sets
    /// `NSApp.appearance`; tests inject both.
    init(
        sopranoSettingsURL: URL = SettingsFile.sopranoURL(),
        settings: SettingsCenter = .shared,
        systemAppearance: @escaping @MainActor () -> AppTheme.Appearance = { AppTheme.Appearance(NSApp.effectiveAppearance) },
        setApplicationAppearance: @escaping @MainActor (NSAppearance?) -> Void = { appearance in
            if NSApp.appearance?.name != appearance?.name {
                NSApp.appearance = appearance
            }
        }
    ) {
        self.sopranoSettingsURL = sopranoSettingsURL
        self.settingsCenter = settings
        self.systemAppearance = systemAppearance
        self.setApplicationAppearance = setApplicationAppearance
        let initial = AppTheme.theme(for: AppTheme.folioId, appearance: systemAppearance())
        theme = initial
        sopranoTheme = initial
    }

    /// Applies the current settings and follows their changes, Soprano's settings.json
    /// (with `watching`) and the macOS appearance.
    func start(watching: Bool = true) {
        guard !isStarted else { return }
        isStarted = true
        watchesSoprano = watching
        apply()
        settingsCenter.addObserver(self) { [weak self] in
            self?.apply()
        }
        if watching {
            appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.systemAppearanceDidChange()
                }
            }
        }
    }

    /// Re-resolves `folio` (and Soprano's `system` appearance) after macOS changed between
    /// light and dark.
    func systemAppearanceDidChange() {
        apply()
    }

    /// The theme for a shortcut's override id; nil is the global theme.
    func theme(forOverride id: String?) -> AppTheme {
        guard let id else { return theme }
        return resolve(id)
    }

    /// Handlers fire after the resolved global theme or Soprano's theme changes, until
    /// `owner` is deallocated.
    func addObserver(_ owner: AnyObject, _ handler: @escaping @MainActor () -> Void) {
        observers.add(owner) { _ in handler() }
    }

    private func resolve(_ id: String) -> AppTheme {
        id == "soprano" ? sopranoTheme : AppTheme.theme(for: id, appearance: systemAppearance())
    }

    private func apply() {
        let settings = settingsCenter.settings
        let followsSoprano = settings.theme == "soprano"
            || settings.shortcuts.contains { $0.overrides.theme == "soprano" }
        updateSopranoWatcher(enabled: followsSoprano && watchesSoprano)
        if followsSoprano {
            soprano = readSoprano()
        }
        let previous = (theme.id, sopranoTheme.id)
        // Unpin first, so `systemAppearance` reads macOS again before `folio` resolves.
        let followsSystem = Self.followsSystem(settings.theme, soprano: soprano)
        if followsSystem {
            setApplicationAppearance(nil)
        }
        let sopranoAppearance: AppTheme.Appearance = switch soprano.appearance {
        case .system: systemAppearance()
        case .light: .light
        case .dark: .dark
        }
        sopranoTheme = AppTheme.theme(for: soprano.themeID, appearance: sopranoAppearance)
        theme = resolve(settings.theme)
        if !followsSystem {
            setApplicationAppearance(theme.appearance.nsAppearance)
        }
        if previous != (theme.id, sopranoTheme.id) {
            observers.notify(())
        }
    }

    /// Whether the global theme `id` resolves from the macOS appearance: `folio` or an
    /// unknown id, or `soprano` while Soprano uses `folio` with the `system` appearance.
    private static func followsSystem(_ id: String, soprano: SopranoThemeFile) -> Bool {
        let isPalette = { (id: String) in AppTheme.allThemes.contains { $0.id == id } }
        if id == "soprano" {
            return !isPalette(soprano.themeID) && soprano.appearance == .system
        }
        return !isPalette(id)
    }

    private func reloadSoprano() {
        guard sopranoWatcher != nil else { return }
        apply()
    }

    private func readSoprano() -> SopranoThemeFile {
        guard let text = try? SettingsFile.read(at: sopranoSettingsURL) else { return SopranoThemeFile() }
        return SopranoThemeFile.parse(text: text, knownThemeIDs: Set(AppTheme.options.map(\.id)))
    }

    private func updateSopranoWatcher(enabled: Bool) {
        if enabled {
            guard sopranoWatcher == nil else { return }
            let watcher = ConfigFileWatcher(url: sopranoSettingsURL) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.reloadSoprano()
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
