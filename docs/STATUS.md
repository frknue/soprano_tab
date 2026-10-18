# Status

## Goal

Soprano Tab: a copy of AltTab (macOS window switcher) in the Soprano family, Mission
Control chrome. Full feature scope from the start: every window, three styles, search,
preview, window actions from the switcher, up to 9 shortcuts with their own filters,
trackpad swipe, exceptions, command line. `docs/ROADMAP.md` lists what is deliberately
not copied.

## Done

Phase 1 in progress; the modules in `docs/ARCHITECTURE.md` are being built in parallel:

- Contracts (models, keys, settings, switching, CLI protocol, geometry, system and
  switcher contracts).
- Core: settings resolver, template and editor; window list, exceptions, screen choice,
  search, session, tile layout, grid navigation; key router and swipe tracker.
- System: window catalog, Spaces, focus order, thumbnails, window actions, app icons,
  keyboard and gesture taps.
- Switcher: controller, model builder, panel window and views.
- Shell: app delegate, menu bar, login item, settings and theme centers, permissions
  window, CLI server and client.
- Fixtures and the offscreen `snapshot` harness; packaging scripts and vendored chrome.

## Next

1. Finish the build: `swift build` and `swift test` green.
2. Visual QA of every style, size, the search strip, preview and the permissions window
   through `snapshot` PNGs.
3. `./scripts/install.sh`, then a first manual run with the real permissions.

## Open decisions

None known. One assumption to check:

- **Key above Tab**: `keyAboveTab` is `kVK_ANSI_Grave` (0x32), the key above Tab on ANSI
  keyboards. On ISO keyboards (German) that position is `kVK_ISO_Section` (0x0A); the
  second default shortcut assumes the ANSI code. Check on an ISO keyboard.
