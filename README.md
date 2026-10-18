# Soprano Tab

**A window switcher for macOS, in the Soprano family.**

Soprano Tab is a copy of [AltTab](https://alt-tab.app/features) in Soprano's "Mission
Control" chrome: `⌥⇥` shows every window, not just every app, with thumbnails, app icons
or titles. Search, preview, close, minimize or quit right from the switcher, set up to 9
shortcuts with their own filters, or swipe on the trackpad. It lives in the menu bar and
has no Dock icon.

## Install

```bash
./scripts/install.sh        # release build → /Applications/Soprano Tab.app
```

The installer never restarts a running Soprano Tab; the update applies on the next
launch. On first launch Soprano Tab opens its permissions window and asks macOS for:

- **Accessibility** (required): reading, switching and focusing windows, and the
  keyboard shortcuts.
- **Screen Recording** (optional): window thumbnails and the preview. Without it the
  switcher shows app icons.

The icon in the menu bar (two offset squares) means it is running. Launch at login is on
by default.

## The first minute

1. Hold `⌥` and tap `⇥`: the switcher opens with the window you came from selected.
2. Keep holding `⌥`; tap `⇥` to step forward, `⇧⇥` or `⇧` alone to step back.
3. Release `⌥` to switch to the selected window. `⎋` cancels.
4. A quick `⌥⇥` (released within 100 ms) jumps to the previous window without showing the
   panel.
5. `` ⌥` `` (the key above Tab) does the same for the windows of the active app only.

## The switcher

- **Styles**: thumbnails of each window (default), large app icons, or a list of titles.
  Size small, medium, large, or auto (the largest size where every window fits).
- **Every window**: windows on other Spaces and screens, minimized and hidden windows,
  fullscreen windows, and apps with no open window (listed at the end; selecting one opens
  it).
- **Badges** on each tile: `min`, `hidden`, `full`, and optionally the Space number
  (`all` for windows on every Space).
- **Window controls**: hovering a tile shows close (red), minimize (yellow) and fullscreen
  (green) lamps.
- **Search**: press `S` while the switcher is open and type; matches on the window title
  or app name, fuzzy, accent-insensitive, several words all need to match.
- **Preview**: optionally shows the selected window full size at its position behind the
  switcher.
- **Screens and Spaces**: the switcher opens on the screen of the focused window (or the
  one with the mouse, or the one with the menu bar). Focusing a window on another Space
  switches to that Space.

## Keyboard and mouse while open

| Keys | Action |
|---|---|
| `⇥` / `⇧⇥` | Next / previous window (the trigger key of the shortcut you pressed) |
| `⇧` alone | Previous window |
| `←` `→` `↑` `↓` | Move through the grid |
| `↩` | Switch to the selected window |
| Release the held modifier | Switch to the selected window |
| `⎋` | Cancel |
| `W` | Close window |
| `M` | Minimize / restore window |
| `F` | Fullscreen / exit fullscreen |
| `Q` | Quit app |
| `H` | Hide / show app |
| `S` | Search |
| `h` `j` `k` `l` | Move left / down / up / right, when `controls.vimKeys` is on (they then win over `H`) |

While searching, `↩`, `⎋`, the arrows and the trigger key still work; every other key types
into the search field. Keys that do nothing are swallowed, never passed to the app behind.

Mouse: hovering highlights a tile (and selects it with `mouse.hoverSelects`), a click
switches to it, and the lamps on the hovered tile close, minimize or fullscreen its window.

## Shortcuts

Up to 9 shortcuts, each a held modifier plus a key, with its own filters, order, grouping
and appearance. The defaults:

| Shortcut | Lists |
|---|---|
| `⌥⇥` | Every window of every app |
| `` ⌥` `` | Windows of the active app |

A third shortcut without filters lists the windows of every other app; the 4th to 9th list
everything until you set filters. Shortcuts 3–9 need a `key`.

**Trackpad gesture**: `gesture.type` turns on a three- or four-finger horizontal or
vertical swipe. Swiping opens the switcher, each further swipe steps (with haptic
feedback), lifting a finger switches.

## Settings

Settings live in `~/.config/soprano-tab/settings.json` (`SOPRANO_TAB_CONFIG` overrides the
path). The file is created with comments on first launch, accepts comments and trailing
commas, and reloads as soon as you save it. A bad value is ignored with a warning and keeps
its default; it never stops the app. The menu shows "settings.json: N warnings" while there
are any. Open the file from the menu (`⌘,`). Every key is optional.

```jsonc
{
  // A Soprano theme id, or "soprano" to follow Soprano's own theme setting.
  "theme": "soprano",

  // 1 to 9 shortcuts. Present → replaces both defaults.
  "shortcuts": [
    { "hold": "option", "key": "tab" },
    { "hold": "option", "key": "keyAboveTab", "apps": "active" },
    {
      "hold": "option",               // option, command, control, shift, fn, joined with "+"
      "key": "e",                     // tab, keyAboveTab, space, return, escape, f1…f12, arrows, or one character
      "apps": "all",                  // all, active, nonActive, underCursor, appUnderCursor
      "spaces": "all",                // all, visible, nonVisible
      "screens": "all",               // all, showingSwitcher
      "minimized": "show",            // show, hide, showAtTheEnd
      "hidden": "show",               // show, hide, showAtTheEnd   (windows of hidden apps)
      "fullscreen": "show",           // show, hide, showAtTheEnd
      "windowlessApps": "showAtTheEnd", // show, hide, showAtTheEnd
      "order": "recentlyFocused",     // recentlyFocused, recentlyCreated, alphabetical, space
      "grouping": "allWindows",       // allWindows, oneWindowPerApp
      "tabs": "singleWindow",         // singleWindow (hide background tabs), separateWindows
      "onRelease": "focus",           // focus, hold (stay open; ↩ switches), search
      "style": "thumbnails",          // overrides appearance.style for this shortcut
      "size": "auto",                 // overrides appearance.size
      "theme": "soprano",             // overrides theme
      "preview": false                // overrides appearance.previewSelectedWindow
    }
  ],

  // Trackpad swipe; takes the same filter keys as a shortcut (apps … tabs).
  "gesture": {
    "type": "disabled",   // disabled, threeFingerHorizontal, threeFingerVertical,
                          // fourFingerHorizontal, fourFingerVertical
    "haptics": true
  },

  // Keys while the switcher is open. null disables one.
  "controls": {
    "focus": "return",
    "previous": "shift",    // one modifier, pressed alone or with the trigger key; null disables
    "cancel": "escape",
    "close": "w",
    "minimize": "m",
    "fullscreen": "f",
    "quit": "q",
    "hide": "h",
    "search": "s",
    "arrowKeys": true,
    "vimKeys": false        // h/j/k/l move; they win over actions on the same letters
  },

  "mouse": {
    "hoverSelects": false,          // hovering selects (tiles always highlight)
    "cursorFollowsFocus": "never"   // never, always, differentScreen
  },

  "appearance": {
    "style": "thumbnails",          // thumbnails, appIcons, titles
    "size": "auto",                 // small, medium, large, auto
    "screen": "active",             // active (focused window's screen), withMouse, withMenuBar
    "titles": "windowTitle",        // windowTitle, appName, appNameAndWindowTitle
    "titleTruncation": "end",       // start, middle, end
    "windowControls": true,         // close / minimize / fullscreen lamps on hover
    "spaceLabels": false,           // Space number badges
    "statusIcons": true,            // min / hidden / full badges
    "showDelayMs": 100,             // 0–2000; a quicker tap switches without showing the panel
    "fadeOut": false,               // fade the panel out when it closes
    "previewSelectedWindow": false, // show the selected window full size behind the panel
    "previewFadeIn": true,
    "searchHint": true,             // "s search" hint in the panel header
    "captureInBackground": true     // keep thumbnails fresh while closed
  },

  // Present → replaces the defaults (see Exceptions).
  "exceptions": [
    { "bundleId": "com.apple.finder", "hide": "whenNoOpenWindow" },
    { "bundleId": "com.parallels.", "ignoreShortcuts": "whenFullscreen" },
    { "bundleId": "com.example.app", "hide": "whenTitleContains", "titleContains": ["Untitled", "Picture in Picture"] }
  ],

  "app": {
    "startAtLogin": true,
    "menuBarIcon": "outlined"       // outlined, filled, hidden
  }
}
```

Notes:

- Modifiers: `option`/`alt`/`opt`/`⌥`, `command`/`cmd`/`⌘`, `control`/`ctrl`/`⌃`,
  `shift`/`⇧`, `fn`/`function`. Key aliases: `enter`, `esc`, `backspace`, `spacebar`,
  and `` ` ``/`grave`/`backtick`/`section` for `keyAboveTab`.
- A shortcut that repeats an earlier `hold` + `key` is dropped with a warning; so are
  shortcuts beyond the 9th. An empty `shortcuts` array keeps the defaults.
- Two controls on the same key: the later one in the order focus, cancel, close,
  minimize, fullscreen, quit, hide, search is disabled with a warning.
- With `menuBarIcon: "hidden"`, open Soprano Tab again from Spotlight or Finder to get
  settings.json (or the permissions window while a permission is missing).

## Exceptions

Each rule matches a `bundleId`; a value ending in `.` matches every bundle id with that
prefix, and an exact match wins over a prefix.

- `hide`: `never`, `always` (none of the app's windows are listed),
  `whenNoOpenWindow` (the app is not listed while it has no window),
  `whenTitleContains` (windows whose title contains one of `titleContains`,
  case-insensitive).
- `ignoreShortcuts`: `never`, `always` (the shortcuts reach the app while it is
  frontmost), `whenFullscreen` (only while its focused window is fullscreen).

The defaults hide Finder while it has no window, hide McAfee's Safari host, and let the
shortcuts through to fullscreen remote desktops and virtual machines: Screen Sharing,
Microsoft Remote Desktop, TeamViewer, VirtualBox, Parallels (`com.parallels.`), Citrix
Workspace and Receiver, NICE DCV, VMware Fusion and UTM.

## Command line

The app binary doubles as a command line client for the running app. Every command prints
JSON (exit 0), or an error on stderr (exit 1), e.g. "Soprano Tab is not running.".

```bash
TAB="/Applications/Soprano Tab.app/Contents/MacOS/SopranoTab"
"$TAB" list                          # every window, most recently focused first
"$TAB" list --detailed               # with more fields per window
"$TAB" focus <window-id>             # a window id from list
"$TAB" focus --last-focus-order 1    # by position in the focus order
"$TAB" show                          # open the switcher with shortcut 1
"$TAB" show 2                        # … with shortcut 2 (1–9)
"$TAB" hide                          # close the switcher
```

## Menu bar

Show Switcher (shortcut 1), Open settings.json… (`⌘,`), the warning count while
settings.json has problems, Permissions…, Launch at Login, About Soprano Tab, and Quit
Soprano Tab (`⌘Q`).

## Permissions

The permissions window (first launch, and Permissions… in the menu) shows each permission
with a lamp, green when granted and red when missing, and an Open System Settings button.
It updates as soon as you grant one.

- **Accessibility** is required. Without it no shortcut works.
- **Screen Recording** gives thumbnails and the preview; without it the switcher shows app
  icons.

Shortcuts do nothing while a password field has focus (macOS Secure Input blocks every
keyboard tap).

## Development

```bash
export DEVELOPER_DIR=/Library/Developer/CommandLineTools PATH="/opt/homebrew/opt/swift/bin:$PATH"
swift build
swift test
./scripts/dev.sh                      # build, package and launch Soprano Tab Dev.app
.build/debug/SopranoTab snapshot --out /tmp/tab.png --keys "tab tab"
.build/debug/SopranoTab snapshot --out /tmp/tab.png --scenario crowded --style appIcons --size medium
.build/debug/SopranoTab snapshot --out /tmp/tab.png --keys "s" --search "saf" --report /tmp/tab.json
.build/debug/SopranoTab snapshot --out /tmp/perm.png --onboarding --permissions accessibility=missing,screen=granted
```

`DEVELOPER_DIR` pins the Command Line Tools SDK, because Homebrew Swift can't read Xcode's
newer one. `snapshot` renders the real switcher on a fake desktop offscreen, without
permissions. The dev app (`com.soprano.tab.dev`) has its own permissions, and its command
line only reaches the dev app. The design system (`Sources/SopranoTab/Vendored/`) comes
from Soprano; update it with `scripts/sync-soprano-chrome.sh` instead of editing it here.
`docs/ARCHITECTURE.md` describes the modules, and `docs/ROADMAP.md` lists what is not
copied.

## License

[MIT](LICENSE). Departure Mono is © Helena Zhang, SIL Open Font License
(`Support/Licenses/LICENSE-departure-mono`).
