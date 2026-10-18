# Changelog

All notable changes to Soprano Tab are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Window switcher in the Mission Control chrome that lists every window, not just every app, in thumbnails, app icons or titles style, sized small, medium, large or auto.
- Two default shortcuts: `⌥⇥` for the windows of every app and `` ⌥` `` for the windows of the active app; a quick `⌥⇥` jumps to the previous window without showing the panel.
- Keys while the switcher is open: `⇥` / `⇧⇥` next / previous, `⇧` alone steps back, arrow keys, `↩` open, `⎋` cancel, `W` close, `M` minimize, `F` fullscreen, `Q` quit app, `H` hide app, `S` search, and optional vim keys (`controls.vimKeys`).
- Mouse: click a tile to switch, hover to highlight (`mouse.hoverSelects` to select), and close / minimize / fullscreen lamps on the hovered tile.
- Search by window title or app name with fuzzy matching (`S`).
- Preview of the selected window at its real position (`appearance.previewSelectedWindow`).
- Up to 9 shortcuts, each with its own filters (apps, Spaces, screens, minimized, hidden, fullscreen, windowless apps), order, grouping, tab handling, release behavior and appearance.
- Trackpad swipe with three or four fingers to open and step through the switcher (`gesture.type`).
- Exceptions per app: hide its windows or let its shortcuts pass through while fullscreen; Finder without windows and remote desktops / virtual machines are covered by default.
- Menu bar item with Show Switcher, settings.json, warnings, Permissions and Launch at Login (on by default).
- `~/.config/soprano-tab/settings.json` with live reload; bad values are ignored with a warning shown in the menu.
- Command line: `SopranoTab list`, `focus`, `show` and `hide` against the running app, with JSON output.
- Permissions window for Accessibility and Screen Recording on first launch and from the menu.
