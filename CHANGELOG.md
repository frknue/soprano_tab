# Changelog

All notable changes to Soprano Tab are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Window switcher in the Mission Control chrome that lists every window, not just every app, including windows on other Spaces and screens, minimized, hidden and fullscreen windows, and apps without windows at the end.
- Three styles (`appearance.style`: thumbnails, app icons, titles) in small, medium, large or auto size, with `min` / `hidden` / `full` badges, optional Space labels, and a header showing what is listed, the count and the bound keys.
- Two default shortcuts: `⌥⇥` for the windows of every app and `⌥` + the key above Tab for the windows of the active app; the key above Tab works on every keyboard layout (`` ` `` on US, `^` on German).
- A quick `⌥⇥`, released before `appearance.showDelayMs` (100 ms), switches to the previous window without showing the panel.
- Keys while the switcher is open: `⇥` / `⇧⇥` next / previous, `⇧` alone steps back, arrow keys, `↩` open, `⎋` cancel, `W` close, `M` minimize, `F` fullscreen, `Q` quit app, `H` hide app, `S` search, and optional vim keys (`controls.vimKeys`); every key can be rebound or disabled under `controls`.
- Mouse: click a tile to switch, hover to highlight (`mouse.hoverSelects` to select), close / minimize / fullscreen lamps on the hovered tile, and `mouse.cursorFollowsFocus`.
- Search by window title or app name with fuzzy matching (`S`); releasing `⌥` while searching keeps the switcher open.
- Preview of the selected window at its real position (`appearance.previewSelectedWindow`).
- Up to 9 shortcuts, each with its own filters (apps, Spaces, screens, minimized, hidden, fullscreen, windowless apps), order, grouping, tab handling, appearance, and release behavior (`onRelease`: focus, hold or search).
- Trackpad swipe with three or four fingers to open and step through the switcher (`gesture.type`), with haptic feedback.
- Exceptions per app: hide its windows (always, without windows, or by title) or let the shortcuts pass through to it; Finder without windows and fullscreen remote desktops / virtual machines are covered by default.
- Menu bar item with Show Switcher, Open settings.json… (`⌘,`), Permissions…, Launch at Login (on by default) and a choice of icon (`app.menuBarIcon`).
- `~/.config/soprano-tab/settings.json` (or `$XDG_CONFIG_HOME/soprano-tab/`, or `SOPRANO_TAB_CONFIG`) with live reload; bad values keep their default and show as "settings.json: N warnings" in the menu with the messages in its tooltip.
- Command line: `SopranoTab list [--detailed]`, `focus <window-id>`, `focus --last-focus-order <n>`, `show [<1-9>]`, `hide` against the running app with JSON output, and `help` / `--help`.
- Permissions window for Accessibility and Screen Recording: macOS asks once on first launch, the window opens while a permission is missing, and the shortcuts start as soon as Accessibility is granted.
