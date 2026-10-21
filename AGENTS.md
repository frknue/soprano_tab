# Soprano Tab

Window switcher for macOS in the Soprano family: a copy of AltTab (every window, thumbnails,
search, preview, window actions, up to 9 shortcuts with filters, trackpad swipe, exceptions,
command line) in Soprano's Folio chrome (Paper light, Ink dark). Swift 6 + programmatic AppKit (no
storyboards/xibs/SwiftUI), SPM, macOS 14+, menu-bar app (no Dock icon). Shipped as a
hand-packaged `.app` via `scripts/install.sh`. GitHub:
[`frknue/soprano_tab`](https://github.com/frknue/soprano_tab) (public).

## Commands

Homebrew Swift with the Command Line Tools SDK. Xcode's newer SDK breaks Homebrew Swift,
so pin `DEVELOPER_DIR` on every direct Swift command:

```bash
export DEVELOPER_DIR=/Library/Developer/CommandLineTools PATH="/opt/homebrew/opt/swift/bin:$PATH"
swift build
swift test
swift test --filter SwitcherKeyRouterTests
./scripts/dev.sh --build-only        # package .build/debug/Soprano Tab Dev.app (com.soprano.tab.dev)
./scripts/install.sh                 # release build → /Applications/Soprano Tab.app
.build/debug/SopranoTab snapshot --out /tmp/tab.png --keys "tab tab" --report /tmp/tab.json
.build/debug/SopranoTab snapshot --out /tmp/tab-ink.png --keys "tab tab" --theme folio-ink
.build/debug/SopranoTab snapshot --out /tmp/perm.png --onboarding --permissions accessibility=missing,screen=granted
.build/debug/SopranoTab list         # no bundle → falls back to com.soprano.tab: talks to the INSTALLED app
```

`ld: warning: building for macOS-14.0 …` link warnings are expected. There is no linter or
formatter; match surrounding style.

## Verification

- Verify source changes with `swift build` and `swift test`.
- Verify UI with the offscreen `snapshot` subcommand and read the PNG. It runs the real
  `SwitcherController` and `SwitcherWindow` on fixtures, with no delay, permission or
  persisted state; `--report` writes active state, selection, item titles, query and the
  action log as JSON. Usage (`SnapshotCommand.usage`):

  ```text
  usage: SopranoTab snapshot --out <png> [--scenario standard|crowded|windowless|empty|multiScreen]
                             [--screen 1512x982] [--style thumbnails|appIcons|titles]
                             [--size small|medium|large|auto] [--theme <id>] [--shortcut <1-9>]
                             [--settings <jsonc>] [--keys "<token> …"] [--search "<text>"]
                             [--hover <index>] [--preview]
                             [--onboarding [--permissions accessibility=granted|missing,screen=granted|missing]]
                             [--report <json>]
    key tokens: tab shift+tab shift release left right up down return escape <letter>
  ```
- Snapshots render Folio Paper by default (they never read Soprano's settings or the Mac's
  mode); check a visual change in Ink too with `--theme folio-ink`.
- Never launch the GUI or run `./scripts/dev.sh` without `--build-only` unless the user
  asks: the app asks for Accessibility and Screen Recording and grabs `⌥⇥` system-wide.

## Installing completed changes

After a verified change to the app or its packaging, run `./scripts/install.sh` as the last
step. It replaces `/Applications/Soprano Tab.app` without restarting a running instance.
Never use `sudo`; report permission problems instead. Docs-only work needs no install.

## Commits and changelog

- Push, open PRs, or create tags only when the user asks for that remote action.
- Short imperative subjects, `feat:` / `fix:` / `docs:` / `test:` / `chore:` prefixes.
- User-visible changes get a line under `## [Unreleased]` in `CHANGELOG.md` (Keep a
  Changelog groups: Added, Changed, Deprecated, Removed, Fixed, Security), written for the
  user and naming the shortcut or setting. Never add a version heading during feature work.
- Releases: rename `[Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`, add a fresh `[Unreleased]`,
  set `CFBundleShortVersionString` and `CFBundleVersion` in `Support/Info.plist` (the only
  version source), `swift test`, install, commit `release: vX.Y.Z`.

## Architecture

`docs/ARCHITECTURE.md` is the contract: modules and file ownership, the contract files,
binding Core signatures, settings schema and resolution rules, key router, system APIs,
switcher behavior, harness options and the visual spec. Keep it current when a seam,
setting, key or harness option changes. `docs/ROADMAP.md` lists what is deliberately not
copied or not built.

- `Sources/SopranoTabCore/` — pure logic, Foundation + CoreGraphics, no AppKit: models,
  keys, settings, window list, exceptions, search, session, tile layout, key router,
  swipe tracker, CLI messages.
- `Sources/SopranoTab/System/` — the live macOS layer: private API bridge, window catalog,
  thumbnails, window actions, app icons, keyboard and gesture taps.
- `Sources/SopranoTab/Switcher/` — `SwitcherController` (state, input, actions) and
  `SwitcherWindow` (panel, tiles, search strip, preview).
- `Sources/SopranoTab/App/`, `Shell/` — `main.swift`, app delegate (composition root),
  menu bar, login item, settings and theme centers, permissions window, CLI server/client.
- `Sources/SopranoTab/Fixtures/` — fake desktop and the `snapshot` harness.
- `Sources/SopranoTab/Vendored/`, `Sources/SopranoTabCore/Vendored/` — Soprano chrome and
  `JSONCText`, synced from Soprano.

## Conventions

- Chrome comes from Soprano's vendored `Chrome.swift` and `Theme.swift` (Folio spec in
  Soprano `docs/design/2026-10-21-calm-family/b/`): `ThemeColors` and its derived tokens
  only, system fonts through `ChromeFont` (New York only at 15 pt or more), radii and sizes
  from `Chrome`. The accent marks the selection (ring, tick, preview frame), the caret and
  search hits on the selected tile. Every window takes `theme.appearance.nsAppearance`
  from its resolved theme. Only `ThemeCenter` sets `NSApp.appearance`: nil while the
  global theme follows macOS, the theme's appearance otherwise.
- Core is AppKit-free and everything in it is `public`.
- `System/` is the only place that touches AX, SkyLight, ScreenCaptureKit or
  `CGEventTap`. The switcher talks to it only through the protocols in
  `System/SystemContracts.swift`, and the shell to the switcher only through
  `Switcher/SwitcherContracts.swift`. Contract files change only together with every
  consumer.
- Settings live only in `~/.config/soprano-tab/settings.json` (`$XDG_CONFIG_HOME/soprano-tab/`
  when set; `SOPRANO_TAB_CONFIG` overrides the path). A new setting needs its type in
  `Settings.swift`, the resolver, the template, the README settings section, and a
  changelog line. The only `UserDefaults` key is `didRequestPermissions` (first-launch
  permission prompt).
- Tests: swift-testing, one `struct …Tests` per file, sentence-style names. Test files
  `import AppKit`, never `Foundation` (the `_Testing_Foundation` overlay breaks the build).
  Tests never touch real settings, real windows, permissions or the user's defaults:
  settings tests inject the file URL, switcher tests use the fixtures, system tests cover
  only the pure parts.

## Gotchas

- `Sources/SopranoTab/Vendored/`, `Sources/SopranoTabCore/Vendored/JSONCText.swift` and
  `scripts/render-app-icon.swift` are copied from Soprano by `scripts/sync-soprano-chrome.sh`
  (committed Soprano state only; source commit in `Vendored/SOPRANO_COMMIT`). Never edit
  them here: change Soprano, commit there, re-run the script.
- Private APIs (SkyLight, HIServices) go only through `System/PrivateAPIs.swift` via
  `dlsym`. Any of them may vanish in a macOS update; every caller handles the nil path.
- TCC grants (Accessibility, Screen Recording) are tied to the signing identity. Sign with
  the shared "Soprano Local Development" identity (`scripts/sign-app.sh`,
  `scripts/ensure-local-signing-identity.sh`), or macOS forgets the permissions on every
  rebuild.
- Dev (`com.soprano.tab.dev`) and installed (`com.soprano.tab`) apps are separate TCC
  entries and keep separate state.
- The keyboard event tap needs Accessibility. Secure Input (password fields) blocks it, so
  the shortcuts do nothing while a password field has focus.
- The CLI talks to the running app over CFMessagePort `<bundle id>.cli`, so the dev app's
  CLI only reaches the dev app and the installed CLI only the installed app. The bare
  `.build/debug/SopranoTab` has no bundle id and falls back to `com.soprano.tab`, so it
  reaches the installed app.
- Keys are ANSI-positional codes. ISO keyboards report the key above Tab as 0x0A and the
  key beside left Shift as 0x32; `KeyEventConversion` swaps them, so `keyAboveTab` (0x32)
  is the key above Tab on every layout. Keep that swap when touching key codes.
