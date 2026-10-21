# Status

## Goal

Soprano Tab: a copy of AltTab (macOS window switcher) in the Soprano family, Folio
chrome. Full feature scope from the start: every window, three styles, search,
preview, window actions from the switcher, up to 9 shortcuts with their own filters,
trackpad swipe, exceptions, command line. `docs/ROADMAP.md` lists what is deliberately
not copied.

## Done (phase 1)

- Core (`SopranoTabCore`): settings resolver with per-key warnings, commented template
  and comment-preserving editor; window list (exceptions, filters, order, grouping, show
  policies), screen choice, fuzzy search, session, tile layout for the three styles and
  auto size, grid navigation; key router and swipe tracker.
- Live window catalog: AX plus SkyLight, including windows on other Spaces through
  remote-token AX elements, Spaces, focus and creation order, live updates from AX
  observers and workspace notifications.
- Window actions with cross-Space focus (front process + key window + raise), close,
  minimize, fullscreen, quit (Finder only with `QuitMenuItem`), hide; cursor follows focus.
- Thumbnails via `CGSHWCaptureWindowList` with a ScreenCaptureKit fallback, cached and
  refreshed in the background; app icons.
- Keyboard tap (ISO keyboards mapped so the key above Tab is shortcut 2 on every layout)
  and trackpad gesture tap.
- Switcher panel in thumbnails, app icons and titles styles with search strip, preview,
  traffic-light window controls, chips, header and keycap hints, in Folio Paper or Ink.
- Menu bar item, login item, `settings.json` with live reload and warnings in the menu,
  Soprano theme and appearance following, command line (`list`, `focus`, `show`, `hide`, `help`),
  permissions window with first-launch prompts.
- Offscreen `snapshot` harness with fixture desktops (standard, crowded, windowless,
  empty, multiScreen) and the permissions window; packaging, signing and sync scripts.
- 275 tests.

## Next

1. First live run by Furkan: install, grant Accessibility and Screen Recording, use the
   switcher on the real desktop (Spaces, fullscreen apps, several screens, German
   keyboard).
2. Fixes from that run.

## Open decisions

None known.
