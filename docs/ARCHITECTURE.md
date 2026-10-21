# Soprano Tab architecture

Soprano Tab is a window switcher for macOS in the Soprano family: a copy of
[AltTab](https://alt-tab.app/features) (every window, not just every app; thumbnails,
app icons or titles; search; preview; window actions from the switcher; up to 9
shortcuts with their own filters; trackpad swipe; exceptions; command line) drawn in
Soprano's Folio chrome (Paper light, Ink dark). Swift 6 + programmatic AppKit, SPM, macOS 14+,
menu-bar app (no Dock icon). Behavior is reimplemented from AltTab's documented
behavior and defaults; no AltTab source is copied.

## Toolchain

Homebrew Swift with the Command Line Tools SDK. Xcode's newer SDK breaks Homebrew Swift,
so always pin `DEVELOPER_DIR`:

```bash
export DEVELOPER_DIR=/Library/Developer/CommandLineTools PATH="/opt/homebrew/opt/swift/bin:$PATH"
swift build
swift test
```

The `ld: warning: building for macOS-14.0 …` link warnings are expected.

## Identity

| What | Value |
|---|---|
| Product | Soprano Tab (`/Applications/Soprano Tab.app`) |
| Bundle id | `com.soprano.tab`; dev build `com.soprano.tab.dev` (`Soprano Tab Dev.app`) |
| Targets | `SopranoTabCore` (library), `SopranoTab` (executable), `SopranoTabTests` |
| Settings | `~/.config/soprano-tab/settings.json`; `SOPRANO_TAB_CONFIG` overrides the path |
| CLI port | CFMessagePort `<bundle id>.cli` |
| Signing | Soprano's shared "Soprano Local Development" identity, so macOS keeps the Accessibility and Screen Recording grants across rebuilds |

## Modules and ownership

| Path | Module | Contents |
|---|---|---|
| `Sources/SopranoTabCore/` | Core | Pure logic, Foundation + CoreGraphics only, no AppKit: models, settings, keys, list building, search, session, layout, input routing, swipe tracking, CLI messages. Everything `public`. |
| `Sources/SopranoTabCore/Vendored/JSONCText.swift` | — | Copied from Soprano by `scripts/sync-soprano-chrome.sh`. **Never edit.** |
| `Sources/SopranoTab/Vendored/` | — | Soprano chrome (Chrome, Theme, NSColor+Hex, AppVersion), copied by the sync script, which also copies `scripts/render-app-icon.swift`. **Never edit.** |
| `Sources/SopranoTab/System/` | System | The live macOS layer: private API bridge, window catalog, thumbnails, window actions, app icons, keyboard and gesture taps. |
| `Sources/SopranoTab/Switcher/` | Switcher | `SwitcherController` (state, input, actions) and `SwitcherWindow` (panel, tiles, search strip, preview). |
| `Sources/SopranoTab/App/`, `Shell/` | Shell | `main.swift`, app delegate (composition root), menu bar, login item, settings file/center, theme center, permissions + onboarding window, CLI server/client. |
| `Sources/SopranoTab/Fixtures/` | Fixtures | Fake desktop (windows, thumbnails, icons, recorded actions) and the `snapshot` harness. |

### Contract files

Written first; the shared interfaces every module codes against. Change them only
together with every consumer.

- `Sources/SopranoTabCore/Models.swift` — `ItemID`, `AppInfo`, `WindowInfo`, `ScreenInfo`, `SpaceInfo`, `WindowSnapshot`.
- `Sources/SopranoTabCore/Keys.swift` — `ModifierSet`, `NamedKey` (+ key codes), `KeySpec`, `KeyEvent`.
- `Sources/SopranoTabCore/Settings.swift` — every settings type with AltTab's defaults, `ConfigIssue`, `SettingsResolution`.
- `Sources/SopranoTabCore/Switching.swift` — `SwitcherCommand`, `TriggerAction`, `KeyDecision`, `KeyRouterState`, `TouchSample`, `SwipeAction`, `TileLayoutInput`, `TileLayout`, `SearchMatch`.
- `Sources/SopranoTabCore/CLIProtocol.swift` — `CLIRequest`, `CLIWindow`, `CLIResponse`.
- `Sources/SopranoTabCore/Geometry.swift` — Quartz ↔ AppKit coordinates, display lookup.
- `Sources/SopranoTab/System/SystemContracts.swift` — `WindowSource`, `ThumbnailProvider`, `WindowActing`, `AppIconProvider`, `KeyboardEventTap`, `GestureEventTap`, `EventTapError`.
- `Sources/SopranoTab/System/PrivateAPIs.swift` — dlsym bridge to SkyLight/HIServices (Spaces, cross-Space focus, key window, window capture, AX window ids, remote-token AX elements, PSNs).
- `Sources/SopranoTab/Switcher/SwitcherContracts.swift` — `TileControl`, `SwitcherHeading`, `KeyHint`, `TileViewModel`, `SearchFieldState`, `SwitcherViewModel`, `SwitcherPresenting`, `SwitcherEnvironment`.

### File ownership

| Owner | Files |
|---|---|
| Infra | `Package.swift`, `.gitignore`, `LICENSE`, `Support/Info.plist`, `Support/SopranoTab.entitlements`, `scripts/*.sh`, `scripts/render-app-icon.swift`, `Sources/SopranoTab/Resources/`, `Sources/SopranoTab/Vendored/`, `Sources/SopranoTabCore/Vendored/` |
| Core settings | `Core/KeyParsing.swift`, `Core/SettingsResolver.swift`, `Core/SettingsTemplate.swift`, `Core/SettingsEditor.swift`; tests `KeyParsingTests`, `SettingsResolverTests`, `SettingsTemplateTests`, `SettingsEditorTests` |
| Core engine | `Core/WindowListBuilder.swift`, `Core/ExceptionMatcher.swift`, `Core/ScreenChooser.swift`, `Core/SearchMatcher.swift`, `Core/SwitcherSession.swift`, `Core/TileLayoutEngine.swift`, `Core/GridNavigator.swift`; tests `WindowListBuilderTests`, `ExceptionMatcherTests`, `ScreenChooserTests`, `SearchMatcherTests`, `SwitcherSessionTests`, `TileLayoutTests`, `GridNavigatorTests` |
| Core input | `Core/SwitcherKeyRouter.swift`, `Core/SwipeTracker.swift`; tests `SwitcherKeyRouterTests`, `SwipeTrackerTests` |
| System catalog | `System/LiveWindowSource.swift`, `System/SpaceCatalog.swift`, `System/AXHelpers.swift`, `System/FocusOrder.swift`; tests `SpaceCatalogTests`, `FocusOrderTests` |
| System actions | `System/LiveWindowActions.swift`, `System/LiveThumbnailProvider.swift`, `System/LiveAppIconProvider.swift`; tests `ThumbnailScalingTests` |
| System input | `System/HotkeyMonitor.swift`, `System/GestureMonitor.swift`, `System/KeyEventConversion.swift`; tests `KeyEventConversionTests` |
| Switcher views | `Switcher/SwitcherWindow.swift`, `Switcher/SwitcherPanel.swift`, `Switcher/SwitcherContentView.swift`, `Switcher/TileView.swift`, `Switcher/SearchStripView.swift`, `Switcher/PreviewOverlay.swift`; tests `SwitcherWindowTests`, `SwitcherHeaderTests` |
| Switcher controller | `Switcher/SwitcherController.swift`, `Switcher/SwitcherModelBuilder.swift`; tests `SwitcherControllerTests`, `SwitcherModelBuilderTests`, `SwitcherTestSupport` (a `RecordingPresenter`) |
| App shell | `main.swift`, `App/AppDelegate.swift`, `App/MenuBarController.swift`, `App/LoginItem.swift`, `App/CLIServer.swift`, `App/CLIClient.swift`, `Shell/SettingsFile.swift`, `Shell/SettingsCenter.swift`, `Shell/ThemeCenter.swift`, `Shell/Permissions.swift`, `Shell/PermissionsWindowController.swift`, `Core/SopranoThemeFile.swift`; tests `SettingsCenterTests`, `ThemeCenterTests`, `SopranoThemeFileTests`, `CLIRoundTripTests`, `PermissionsWindowTests` |
| Fixtures | `Fixtures/FixtureWindowSource.swift`, `Fixtures/FixtureScenarios.swift`, `Fixtures/FixtureThumbnails.swift`, `Fixtures/FixtureIcons.swift`, `Fixtures/RecordingWindowActions.swift`, `Fixtures/SnapshotCommand.swift`; tests `FixtureScenarioTests`, `SnapshotCommandTests` |

(`Core/` = `Sources/SopranoTabCore/`, `System/` etc. = `Sources/SopranoTab/…`, tests in
`Tests/SopranoTabTests/<Name>.swift`.)

## Core APIs

Signatures are binding: other modules call them exactly like this.

### Keys (`KeyParsing.swift`)

```swift
extension ModifierSet {
    /// "option"/"alt"/"opt"/"⌥", "command"/"cmd"/"⌘", "control"/"ctrl"/"⌃", "shift"/"⇧",
    /// "fn"/"function", joined with "+", case-insensitive, spaces ignored. nil when empty
    /// or any part is unknown.
    public init?(settingsText: String)
    /// Canonical spelling: "control+option+shift+command+fn" order, only the members present.
    public var settingsText: String { get }
    /// "⌃⌥⇧⌘" order, "fn" last.
    public var symbols: String { get }
}
extension KeySpec {
    /// A `NamedKey` raw value (case-insensitive) or alias — enter→return, esc→escape,
    /// backspace→delete, "`"/grave/backtick/section→keyAboveTab, spacebar→space —
    /// or exactly one non-space character → `.character(lowercased)`. nil otherwise.
    public init?(settingsText: String)
    /// Round-trips through `init(settingsText:)`.
    public var settingsText: String { get }
    /// ⇥ ␣ ↩ ⎋ ⌫ ⌦ ← → ↑ ↓ ↖ ↘ ⇞ ⇟ ` F1…F12; characters uppercased ("W").
    public var symbol: String { get }
    /// Named keys compare `event.keyCode` with `keyCodes`; characters compare
    /// `event.characters` lowercased (false when nil). Modifiers are not compared.
    public func matches(_ event: KeyEvent) -> Bool
}
```

### Settings (`SettingsResolver.swift`, `SettingsTemplate.swift`, `SettingsEditor.swift`)

```swift
public enum SettingsResolver {
    /// JSONC (comments, trailing commas) → settings over the defaults. A document that is
    /// not a JSON object gives `settings == nil` and one `.error` issue with its line.
    /// Every bad value is a `.warning` and keeps its default; unknown keys warn.
    public static func resolve(text: String, knownThemeIDs: Set<String>) -> SettingsResolution
}
public enum SettingsTemplate {
    /// The commented settings.json written on first launch. Resolves to `.defaults` with
    /// no issues; documents every key below with its default and allowed values.
    public static let text: String
}
public enum SettingsEditor {
    /// Sets `value` (Bool, Int, Double, String, [Any], [String: Any], NSNull) at `path`,
    /// keeping comments and key order (wraps the vendored `JSONCText.setting`).
    public static func setting(_ value: Any, at path: [String], in text: String) throws -> String
}
```

settings.json (every key optional; spellings are the `rawValue`s in `Settings.swift`):

```jsonc
{
  "theme": "soprano",                 // "soprano" (follow Soprano's theme + appearance), "folio" (follow macOS), or a Soprano theme id
  "shortcuts": [                      // 1–9; present → replaces the defaults
    { "hold": "option", "key": "tab" },                       // shortcut 1
    { "hold": "option", "key": "keyAboveTab", "apps": "active" } // shortcut 2
    // per shortcut: hold, key, apps, spaces, screens, minimized, hidden, fullscreen,
    // windowlessApps, order, grouping, tabs, onRelease, style, size, theme, preview
  ],
  "gesture": { "type": "disabled", "haptics": true },  // + the filter keys
  "controls": {
    "focus": "return", "previous": "shift", "cancel": "escape",
    "close": "w", "minimize": "m", "fullscreen": "f", "quit": "q", "hide": "h", "search": "s",
    "arrowKeys": true, "vimKeys": false              // a key value of null disables it
  },
  "mouse": { "hoverSelects": false, "cursorFollowsFocus": "never" },
  "appearance": {
    "style": "thumbnails", "size": "auto", "screen": "active",
    "titles": "windowTitle", "titleTruncation": "end",
    "windowControls": true, "spaceLabels": false, "statusIcons": true,
    "showDelayMs": 100, "fadeOut": false,
    "previewSelectedWindow": false, "previewFadeIn": true,
    "searchHint": true, "captureInBackground": true
  },
  "exceptions": [                     // present → replaces the defaults
    { "bundleId": "com.apple.finder", "hide": "whenNoOpenWindow" },
    { "bundleId": "com.parallels.", "ignoreShortcuts": "whenFullscreen" }
    // bundleId (required), hide, titleContains (string or [string]), ignoreShortcuts
  ],
  "app": { "startAtLogin": true, "menuBarIcon": "outlined" }
}
```

Resolution rules:
- A shortcut entry starts from `ShortcutSettings.defaultFilters(forIndex:)`; its `key`
  defaults to `tab` (index 0) and `keyAboveTab` (index 1); entries from index 2 without a
  `key` are dropped with a warning. `hold` must parse to a non-empty `ModifierSet`
  (default `option`). More than 9 entries: the first 9 are kept, with a warning. An empty array
  keeps the defaults and warns. A later shortcut with the same `hold`+`key` as an earlier
  one is dropped, with a warning.
- `preview` is a shortcut's `previewSelectedWindow` override; `theme` must be known.
- `controls.previous` is one modifier name or null (empty set = disabled). Two controls on
  the same key: the later in the order focus, cancel, close, minimize, fullscreen, quit,
  hide, search is disabled with a warning. `vimKeys: true` with an action on h/j/k/l
  warns that movement wins.
- `showDelayMs` is clamped to `AppearanceSettings.showDelayRange` with a warning.
- `hide: "whenTitleContains"` without `titleContains` warns.
- Integers accept JSON numbers with no fractional part; booleans only JSON booleans.

### Window list (`WindowListBuilder.swift`, `ExceptionMatcher.swift`, `ScreenChooser.swift`)

```swift
public enum WindowListBuilder {
    /// The items a shortcut lists, in display order.
    public static func items(
        from snapshot: WindowSnapshot,
        filters: WindowFilters,
        exceptions: [ExceptionRule],
        switcherDisplayID: DisplayID?
    ) -> [WindowInfo]
}
public enum ExceptionMatcher {
    /// An exact bundle id match wins over the longest matching prefix rule ("com.parallels.").
    public static func rule(forBundleID bundleID: String?, in rules: [ExceptionRule]) -> ExceptionRule?
    /// True when the frontmost app's rule says `always`, or `whenFullscreen` and the focused
    /// window is fullscreen.
    public static func shortcutsIgnored(in snapshot: WindowSnapshot, rules: [ExceptionRule]) -> Bool
}
public enum ScreenChooser {
    /// active: display of the focused window, else the one containing the mouse; withMouse:
    /// containing the mouse; withMenuBar: `hasMenuBar`. Falls back to the menu-bar screen,
    /// then the first screen. nil only when `snapshot.screens` is empty.
    public static func screen(for choice: ScreenChoice, in snapshot: WindowSnapshot) -> ScreenInfo?
}
```

`items` semantics, applied in this order:
1. **Exceptions**: `hide: always` drops every item of the app; `whenNoOpenWindow` drops
   the app's windowless entry; `whenTitleContains` drops windows whose title contains any
   string (case-insensitive).
2. **Apps**: `active` keeps `app.pid == frontmostPID`; `nonActive` the rest;
   `underCursor` keeps windows (not minimized, on a visible Space) whose frame contains
   `mouseLocation`; `appUnderCursor` keeps the app of the frontmost (lowest `zIndex`)
   such window. Windowless entries pass `all`, `active`, `nonActive` by pid and never
   pass the cursor filters.
3. **Spaces**: `visible` keeps `isOnAllSpaces` or any `spaceIDs` in
   `snapshot.visibleSpaceIDs`; `nonVisible` the complement. Minimized windows and
   windowless entries with empty `spaceIDs` count as visible.
4. **Screens**: `showingSwitcher` keeps `displayID == switcherDisplayID`; items with
   `displayID == nil` pass.
5. **Tabs**: `singleWindow` drops `isBackgroundTab`.
6. **Order**: `recentlyFocused` → `lastFocusOrder` ascending; `recentlyCreated` →
   `creationOrder` descending; `alphabetical` → app name, then `displayTitle`
   (`localizedStandardCompare`), then window id; `space` → lowest Space index ascending
   (on all Spaces first, unknown last), then `lastFocusOrder`. Ties fall back to
   `lastFocusOrder`, then window id, so the result is deterministic.
7. **Grouping**: `oneWindowPerApp` keeps each app's first item.
8. **ShowPolicy** for minimized, hidden (`isHidden`), fullscreen and windowless items:
   `hide` drops, `showAtTheEnd` moves to one tail group (keeping the order above), `show`
   keeps in place. An item matching several policies goes to the tail if any says so,
   and is dropped if any says `hide`.

### Search (`SearchMatcher.swift`)

```swift
public enum SearchMatcher {
    /// Fuzzy subsequence match, case- and diacritic-insensitive. Whitespace splits the
    /// query into terms that must all match (each anywhere). Consecutive characters and
    /// word starts score higher. Empty query: score 0, no ranges. nil when no match.
    public static func match(_ query: String, in text: String) -> SearchMatch?
    /// Items whose `displayTitle` or app name match, best score first, ties in input order.
    public static func filter(_ items: [WindowInfo], query: String) -> [WindowInfo]
}
```

### Session (`SwitcherSession.swift`)

```swift
public struct SwitcherSession: Equatable, Sendable {
    public init(items: [WindowInfo], shortcutIndex: Int, focusedWindowID: WindowID?, reverse: Bool)
    public let shortcutIndex: Int
    public private(set) var allItems: [WindowInfo]
    /// `allItems` filtered by `query`.
    public private(set) var items: [WindowInfo]
    /// Index into `items`; nil when empty.
    public private(set) var selectedIndex: Int?
    public private(set) var query: String
    public private(set) var isSearching: Bool
    public var selectedItem: WindowInfo? { get }
    public mutating func selectNext()            // wraps
    public mutating func selectPrevious()        // wraps
    public mutating func select(index: Int)      // ignored when out of range
    public mutating func select(id: ItemID)
    /// moveLeft/Right/Up/Down through `GridNavigator`; other commands are ignored.
    public mutating func move(_ command: SwitcherCommand, layout: TileLayout)
    public mutating func beginSearch()
    /// Clears the query and shows every item again, keeping the selected item.
    public mutating func endSearch()
    public mutating func setQuery(_ query: String)
    /// Live catalog update: keeps the selected item if still present, else the same index clamped.
    public mutating func update(items: [WindowInfo])
    /// Removes an item; the selection moves to the item that took its place (clamped).
    public mutating func remove(id: ItemID)
}
```

Initial selection (AltTab: the first press selects the window you came from): with `f`
the index of `focusedWindowID` in `items`, forward selects `(f + 1) % n` or 0 when the
focused window is not listed; `reverse` selects `(f - 1 + n) % n` or `n - 1`. `setQuery`
keeps the selected item when it still matches, else selects 0.

### Layout (`TileLayoutEngine.swift`, `GridNavigator.swift`)

```swift
extension TileLayout {
    public static let selectionRingGap: CGFloat     // 3
    public static let selectionRingWidth: CGFloat   // 2
    public static let selectionRingMargin: CGFloat  // gap + width
    public static func compute(_ input: TileLayoutInput) -> TileLayout
}
public enum GridNavigator {
    /// moveLeft/moveRight step through the whole list and wrap; moveUp/moveDown go to the
    /// adjacent row's tile whose horizontal center is nearest, wrapping from the first row
    /// to the last and back. Other commands return `index`.
    public static func index(from index: Int, command: SwitcherCommand, layout: TileLayout) -> Int
}
```

Metrics (points, every frame integral):
- Panel: at most 90% of the screen width and 80% of its height; padding 12 on top and
  16 on the sides and bottom; header strip 28 high at the top of the padded area; search
  strip 30 high, 8 below the header, when `showsSearchField`; the tile area starts 8
  below the last strip. Minimum panel width 360. Tile spacing 8 both ways.
- Selection ring margin: `contentFrame` (the scroll view) reaches
  `TileLayout.selectionRingMargin` (5 = ring gap 3 + ring width 2) past the tile area on
  every side, into the panel padding; `contentSize` includes it and `tileFrames` are
  offset by it, so a selected edge tile's ring is never clipped.
- **thumbnails**: rows per screen small 6, medium 4, large 3. Tile height = (max content
  height − (rows − 1) × 8) / rows, at least 29. Tile-local title strip (6, 0, w − 12, 22);
  image frame (6, 22, w − 12, h − 28). Tile width = image height × aspect + 12, aspect =
  item width / height clamped to 0.625…2.0 (16:10 for `.zero`), at least 140, at most the
  max content width. Rows fill left to right greedily; each row is centered in the
  content width (= widest row).
- **appIcons**: icon side small 64, medium 96, large 128. Tile = icon + 24 wide,
  8 + icon + 6 + 18 + 8 high; image frame (12, 8, icon, icon); title frame
  (4, 8 + icon + 6, w − 8, 18). Rows packed and centered like thumbnails.
- **titles**: one item per row, row height small 28, medium 34, large 40, no spacing;
  width = screen width × 0.4 / 0.5 / 0.6 clamped to 420…1100 and to the max content
  width; image frame (8, 4, h − 8, h − 8); title frame starts 8 after the icon, 18 high,
  vertically centered, ends 8 before the tile's trailing edge.
- Rows beyond what fits in the max height scroll: the panel stops growing and
  `contentSize.height` holds every row.
- **auto**: the largest of large, medium, small at which every item fits without
  scrolling; small (scrolling) when none does. `resolvedSize` reports the choice.
- No items: content area 80 high, no tiles, minimum width.

### Input (`SwitcherKeyRouter.swift`, `SwipeTracker.swift`)

```swift
public struct SwitcherKeyRouter: Sendable {
    public init(shortcuts: [ShortcutSettings], controls: ControlSettings)
    public private(set) var state: KeyRouterState
    /// `triggersEnabled == false` (exception "ignore shortcuts") lets activations pass through.
    public mutating func handle(_ event: KeyEvent, triggersEnabled: Bool) -> KeyDecision
    /// Active for `shortcut` with nothing held (menu, CLI `show`, gesture).
    public mutating func activateWithoutHold(shortcut: Int)
    public mutating func setSearching(_ searching: Bool)
    /// The switcher closed (focus, cancel, click, hide).
    public mutating func reset()
}
```

Router behavior. `.function` is ignored in modifier comparisons unless a hold set includes
it (arrow and F keys carry it).
- **Idle**: a non-repeat keyDown whose modifiers contain shortcut *i*'s `hold`, with the
  extra modifiers being none or `controls.previous`, and whose key matches shortcut *i*'s
  `key` → the first such shortcut: `activate(i, reverse: extra == previous)`, consume,
  state `active(i, holding: true, searching: false)`. With `triggersEnabled` false, or
  anything else: pass through.
- **Active, keyDown**: the active shortcut's key (any modifiers; repeats too) →
  `advance(reverse: modifiers contain previous)`, consume. Not searching: `focus` →
  `focusSelected`; `cancel` → `cancel`; arrows (when `arrowKeys`) → move commands; h/j/k/l
  (when `vimKeys`) → moveLeft/moveDown/moveUp/moveRight, before the actions; `close`,
  `minimize`, `fullscreen`, `quit`, `hide` → their commands; `search` → `beginSearch` and
  state searching. Any other key: consume with no action (nothing leaks to the app behind).
  Searching: `focus`, `cancel`, arrows and the trigger key act as above; every other key
  passes through to the search field.
- **Active, flagsChanged**: while `holding`, losing any `hold` modifier → `release`,
  holding false. A newly pressed `previous` modifier alone (not searching) →
  `advance(reverse: true)`. flagsChanged is never consumed.
- **Active, keyUp**: consumed when its keyDown was consumed.

```swift
public struct SwipeTracker: Sendable {
    public init(kind: GestureKind)
    public mutating func handle(_ touches: [TouchSample]) -> [SwipeAction]
    public mutating func reset()
    public static let activationDistance: CGFloat  // 0.08 trackpad widths
    public static let stepDistance: CGFloat        // 0.08
}
```

Swipe behavior: tracks while exactly 3 (or 4) touches are down (began/moved/stationary).
The mean displacement along the gesture's axis since the baseline activates once it
reaches `activationDistance` and is at least twice the cross-axis displacement:
`activate(reverse:)`; right (horizontal) or down (vertical, y decreasing) is forward.
Each further `stepDistance` emits `step(reverse:)`. When fewer fingers remain after
activation → `finish` once, then nothing until every touch has ended. A finger-count
change before activation resets the baseline. `disabled` always returns [].

## System APIs

```swift
@MainActor final class LiveWindowSource: WindowSource {
    init()
    /// The AX element of a known window; nil when unknown or gone.
    func axWindow(for windowID: WindowID) -> AXUIElement?
    func axApplication(for pid: pid_t) -> AXUIElement
}
@MainActor final class LiveThumbnailProvider: ThumbnailProvider { init() }
@MainActor final class LiveWindowActions: WindowActing { init(source: LiveWindowSource) }
@MainActor final class LiveAppIconProvider: AppIconProvider { init() }
@MainActor final class HotkeyMonitor: KeyboardEventTap { init() }
@MainActor final class GestureMonitor: GestureEventTap { init() }
/// Pure conversion used by HotkeyMonitor (and its tests).
enum KeyEventConversion {
    static func keyEvent(from event: CGEvent, type: CGEventType) -> KeyEvent?
    static func modifiers(from flags: CGEventFlags) -> ModifierSet
}
```

**Catalog** (`LiveWindowSource`): regular apps (plus accessory apps that own a standard
window), never Soprano Tab itself. Windows come from AX (`kAXWindowsAttribute`, with
`AXUIElementSetMessagingTimeout` 0.25 s per app) and, for windows on other Spaces that
AX omits, from `PrivateAPIs.axElement(pid:elementID:)` probing 0..<1000 when
`CGWindowListCopyWindowInfo(.optionAll)` shows layer-0 windows of the app that AX did not
return. A window is listed only with an AX element: role `AXWindow`, subrole
`AXStandardWindow` or `AXDialog`, a CGWindowID (`PrivateAPIs.windowID(of:)`), CG layer
0, at least 100 × 50 unless minimized. Per-app `AXObserver`s (window created, element
destroyed, focused/main window changed, title changed, (de)miniaturized, moved, resized,
app hidden/shown) and `NSWorkspace` notifications (launch, terminate, activate, hide,
unhide, active Space change) plus screen-parameter changes keep it current; AX reads run
off the main thread and publish to the main actor, coalesced. Spaces come from
`PrivateAPIs.managedDisplaySpaces()` (display UUIDs mapped to `DisplayID` with
`CGDisplayCreateUUIDFromDisplayID`), window Spaces from `PrivateAPIs.spaces(forWindow:)`.
`isFullscreen` = AX `AXFullScreen` or the window's Space is a fullscreen Space;
`isBackgroundTab` = not minimized, app not hidden, no Spaces and not on screen.
`lastFocusOrder` follows focus events (app activation → its focused window first);
at start it follows the on-screen z-order, then the rest; windowless apps rank after
every window by app activation recency. `creationOrder` is assigned on first sight
(ascending CGWindowID at start). Screens from `NSScreen` converted with `Geometry`;
`hasMenuBar` from `PrivateAPIs.activeMenuBarDisplayIdentifier()`, else the primary.
Pure parts are testable: `SpaceCatalog.spaces(from:displayIDForUUID:mainDisplayID:)` and
`FocusOrder`.

**Actions** (`LiveWindowActions`): focus = unhide the app if hidden, unminimize via
`kAXMinimizedAttribute`, `PrivateAPIs.setFrontProcess` + `makeKeyWindow`, then
`kAXRaiseAction`; without an AX element, `NSRunningApplication.activate()`. Windowless
app: activate; with no windows, `NSWorkspace.openApplication(at:)` so it reopens. Close =
press `kAXCloseButtonAttribute` (exit fullscreen first, wait 0.75 s). Minimize toggles
`kAXMinimizedAttribute` (exit fullscreen first). Fullscreen toggles `AXFullScreen`. Quit =
`terminate()`, except Finder unless `defaults read com.apple.finder QuitMenuItem` is
true. Hide toggles `hide()`/`unhide()`. Cursor: `CGWarpMouseCursorPosition` to the frame
center.

**Thumbnails** (`LiveThumbnailProvider`): `PrivateAPIs.captureWindow` (works across Spaces
and under other windows), falling back to ScreenCaptureKit
`SCScreenshotManager.captureImage(contentFilter: .init(desktopIndependentWindow:))` for
on-screen windows when it returns nil. Scaled to `maxPixelSize` off the main thread,
cached per window; `canCapture` = `CGPreflightScreenCaptureAccess()`.

**Icons**: `NSRunningApplication.icon`, else `NSWorkspace.icon(forFile: bundlePath)`,
cached per pid.

**Keyboard tap** (`HotkeyMonitor`): `CGEvent.tapCreate(.cgSessionEventTap,
.headInsertEventTap, .defaultTap)` for keyDown, keyUp, flagsChanged on the main run loop;
converts with `KeyEventConversion` (characters from
`NSEvent(cgEvent:)?.charactersIgnoringModifiers`; on ISO keyboards — the event's
`.keyboardEventKeyboardType` has `KBGetLayoutType == kKeyboardISO` — key codes 0x0A and
0x32 are swapped, so `keyAboveTab` is the key above Tab on every layout), returns nil for
consumed events, re-enables itself on `tapDisabledByTimeout` / `tapDisabledByUserInput`.
`start` throws `EventTapError.accessibilityDenied` when `AXIsProcessTrusted()` is false.

**Gesture tap** (`GestureMonitor`): listen-only tap for `NSEvent.EventType.gesture`
(raw 29); touches from `NSEvent(cgEvent:)?.allTouches()` → `TouchSample` (identity hashed
to `id`, `normalizedPosition`, phase).

## Switcher

```swift
@MainActor final class SwitcherWindow: SwitcherPresenting { init() }

@MainActor final class SwitcherController {
    init(source: WindowSource, thumbnails: ThumbnailProvider, actions: WindowActing,
         icons: AppIconProvider, presenter: SwitcherPresenting, environment: SwitcherEnvironment)
    var isActive: Bool { get }
    var session: SwitcherSession? { get }
    /// For the keyboard tap; true swallows the event.
    func handleKeyEvent(_ event: KeyEvent) -> Bool
    /// For the gesture tap.
    func handleTouches(_ touches: [TouchSample])
    /// Opens without held keys (menu, CLI `show`): presents at once, stays open until
    /// Return, Escape, a click or `hide()`.
    func show(shortcut: Int)
    /// Closes without focusing.
    func hide()
    /// The search text changed (from the presenter, or the harness).
    func searchTextDidChange(_ text: String)
    /// Rebuilds the router and swipe tracker; closes an open switcher first.
    func settingsDidChange()
}

enum SwitcherModelBuilder {
    static func model(session: SwitcherSession, layout: TileLayout, settings: SopranoTabSettings,
                      theme: AppTheme, style: SwitcherStyle, snapshot: WindowSnapshot,
                      hoveredIndex: Int?, thumbnails: (WindowID) -> CGImage?,
                      icons: (AppInfo) -> NSImage) -> SwitcherViewModel
    static func title(for item: WindowInfo, content: TitleContent) -> String
    static func heading(for filters: WindowFilters, snapshot: WindowSnapshot, isSearching: Bool, count: Int) -> String
    static func hints(controls: ControlSettings, shortcut: ShortcutSettings?, searchHint: Bool) -> String
}
```

Controller behavior:
- Owns `source.onChange`, a `SwitcherKeyRouter` and a `SwipeTracker` built from settings.
- `handleKeyEvent`: `triggersEnabled = !ExceptionMatcher.shortcutsIgnored(in:rules:)`; runs
  the router; executes the action; returns `consume`.
- **Activate** (shortcut *i*): `source.refresh()`; screen = `ScreenChooser` for
  `appearance.screen`; items = `WindowListBuilder.items` with shortcut *i*'s filters and
  that screen's id; `SwitcherSession(items:shortcutIndex:focusedWindowID:reverse:)`;
  layout via `TileLayout.compute` (style/size per shortcut overrides, the screen's
  `visibleFrame.size`, window sizes); request thumbnails (thumbnails style or preview)
  with `maxPixelSize` = the image frame's longest side × screen scale. Presents after
  `appearance.showDelayMs` through `environment.schedule`; a release before then focuses
  the selection without ever presenting (quick ⌥⇥ = previous window).
- **advance**: next/previous; redraw when presented. **release**: per the shortcut's
  `onRelease`: `focus` → focus the selection and close; `hold` → stay open; `search` →
  begin search. Commands: focusSelected, cancel, moves (`session.move` with the current
  layout), closeWindow (windowless: ignored) → `actions.close`; quitApp →
  `actions.quitApp`; toggleMinimize, toggleFullscreen, toggleHideApp → the action. Items
  are never removed optimistically: they leave (or their badges update) through the live
  catalog update once the window is really closed or the app really quit, so a refused
  quit (Finder) or a "Save changes?" sheet keeps its tiles. beginSearch →
  `session.beginSearch()`, relayout with the search strip,
  `presenter.setSearchFocused(true)`, `router.setSearching(true)`. A live update that
  empties the list closes the switcher.
- **Focus** = `actions.focus(item)`; then `mouse.cursorFollowsFocus` (`always`, or
  `differentScreen` when the item's display differs from the mouse's) →
  `actions.moveCursor`; then close.
- **Close** = `presenter.dismiss(animated: appearance.fadeOut)`, hide the preview,
  `router.reset()`, cancel a pending present, session nil.
- Pointer: hover sets `hoveredIndex` (and selects when `mouse.hoverSelects`); click
  selects and focuses; a window control runs close/minimize/fullscreen/quit on that tile's item.
- Search: `onQueryChange` / `searchTextDidChange` → `session.setQuery`, relayout, redraw.
- Preview (`previewSelectedWindow` per shortcut): on every selection change,
  `presenter.showPreview(image, frame: item.frame, fadeIn: appearance.previewFadeIn)`
  (nil for windowless or minimized items).
- Live updates while open: catalog change → rebuild items, `session.update(items:)`,
  relayout, redraw; new thumbnails arrive through `presenter.updateThumbnail`.
- Background capture (`appearance.captureInBackground`, closed switcher): on catalog
  change, at most every 2 s, request thumbnails (640 px) for on-screen, non-minimized
  windows; `thumbnails.prune(keeping:)` the catalog's window ids.
- Gesture: `activate` opens the `SopranoTabSettings.gestureIndex` filters at once (no
  delay), `step` moves and calls `environment.haptic()` when `gesture.hapticFeedback`,
  `finish` focuses and closes.
- Model text: `SwitcherHeading` subject "All windows" / the active app's name / "Other
  apps" / "Under the cursor" / the app under the cursor's name, "Search" while searching,
  plus the count; hints are `[KeyHint]`, one keycap legend per bound key (`KeySpec.symbol`,
  K1: `⇥`, `⇧`, `↩`, `esc`, uppercase letters) and its word: next, back, open, close,
  min, quit, search ("search" only with `searchHint`); empty text "No windows" or
  "No matches"; titles per `appearance.titles` ("App - Title" for both); chips per
  `statusIcons` / `spaceLabels`: "Minimized", "Hidden", "Full screen", then "All Spaces"
  or "Space <first index>".

## Shell

- `main.swift`: before `NSApplication` starts, `snapshot` → `SnapshotCommand.run(arguments:)`;
  `list`, `focus`, `show`, `hide`, `help`, `--help` → `CLIClient.run(arguments:)`; both
  exit. Otherwise the GUI: `.accessory` activation policy, `AppDelegate`.
- `AppDelegate` is the composition root. Order: quit if another instance with this bundle
  id runs; `SettingsCenter.shared.start()`; `ThemeCenter.shared.start()`;
  `LiveWindowSource` start; `LiveThumbnailProvider`, `LiveWindowActions`,
  `LiveAppIconProvider`, `SwitcherWindow`; `SwitcherController` with an environment using
  `SettingsCenter.shared.settings`, `ThemeCenter.shared.theme(forOverride:)`,
  `DispatchQueue.main.asyncAfter` scheduling and `NSHapticFeedbackManager`; `HotkeyMonitor`
  started with `controller.handleKeyEvent` as soon as Accessibility is granted (polls
  every second until then); `GestureMonitor` while `gesture.kind != .disabled`;
  `MenuBarController`; `LoginItem.sync`; `CLIServer.start()`. Settings changes re-apply
  the controller, menu bar icon, login item and gesture tap. First launch with a missing
  permission opens the permissions window (and asks macOS for both once). Reopening the
  app (Spotlight, Finder) opens the permissions window when something is missing, else
  settings.json.
- `SettingsFile` / `SettingsCenter`: adapted from Soprano Git's `SettingsFile.swift` and
  `AppEnvironment.swift` — path from `SOPRANO_TAB_CONFIG` or the default, created from
  `SettingsTemplate.text` when missing, debounced file watching, `SettingsResolver` with
  the vendored theme ids (`AppTheme.options`: `folio`, `folio-paper`, `folio-ink`, the
  seven dark themes), last good settings kept on parse errors, issues logged with
  `OSLog` and exposed (`issues`), `addObserver`. `write(_ value: Any, at path: [String])`
  edits through `SettingsEditor`. Tests inject the file URL.
- `ThemeCenter`: adapted from Soprano Git. `"soprano"` (the default) follows the `theme`
  and `appearance` keys of `~/.config/soprano/settings.json` live (read by the Core
  `SopranoThemeFile`; missing or unknown values give `folio` / `system`): Soprano's
  `folio` becomes Folio Paper or Folio Ink from its appearance, `system` meaning macOS.
  Tab's own `folio` follows `NSApp.effectiveAppearance` (KVO-observed); `folio-paper`,
  `folio-ink` and the dark themes are pinned; unknown ids resolve like `folio`
  (`AppTheme.theme(for:appearance:)`). Observers fire when a resolved palette changes,
  system flips included. `theme(forOverride:)` resolves a shortcut's override id the same
  way. Soprano Tab never sets `NSApp.appearance`: the switcher panel, the preview and the
  permissions window take `theme.appearance.nsAppearance`. Tests inject both settings URLs
  and the system appearance (`start(watching: false)`).
- `MenuBarController`: an `NSStatusItem` with the Folio 16 pt template glyph drawn in
  code (an open back sheet, a front sheet with a → in it, 1.5 pt round strokes; filled
  fills the front sheet and knocks the arrow out), removed while
  `menuBarIcon == .hidden`. Menu: "Show Switcher" (shortcut 1 via `controller.show`),
  "Open settings.json…" (⌘,), a disabled "settings.json: N warnings" line while issues
  exist, "Permissions…", "Launch at Login" (checkmark; toggling writes
  `app.startAtLogin`), "About Soprano Tab" (`AppVersion`), "Quit Soprano Tab" (⌘Q).
- `LoginItem.sync(enabled:)`: `SMAppService.mainApp` register/unregister; no-op for an
  unbundled binary; errors logged, never fatal.
- `Permissions`: `isAccessibilityTrusted`, `isScreenRecordingGranted`,
  `requestAccessibility()` (prompting `AXIsProcessTrustedWithOptions`),
  `requestScreenRecording()` (`CGRequestScreenCaptureAccess`), `openSettings(for:)`
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` /
  `?Privacy_ScreenCapture`).
- `PermissionsWindowController(status: @escaping @MainActor () -> PermissionStatus)` with
  `PermissionStatus { accessibility: Bool; screenRecording: Bool }`: a titled window on
  `bgBase` with the theme's appearance, the New York headline "Permissions", then one row
  per permission split by a `borderSubtle` hairline: a `ChromeStatusMark` (success dot when
  granted, danger diamond when missing), the name in SF Pro 13 ("Accessibility", "Screen
  recording"), what it enables in SF Pro 12 muted ("Switch and focus windows. Required." /
  "Thumbnails and previews. Without it, Soprano Tab shows app icons."), and an "Open
  System Settings" `ChromeButton` (`.ink` while missing, `.standard` once granted);
  polling every second while visible; `renderImage() -> CGImage?` renders offscreen for
  the harness.
- `CLIServer(controller:source:actions:)`: a local `CFMessagePort` named `<bundle id>.cli`
  on the main run loop; JSON `CLIRequest` → `CLIResponse`. `list` returns every
  non-windowless window by `lastFocusOrder`; `focus` / `focusLastFocusOrder` focus through
  `actions` (`ok: false` with "No window <id>" when unknown); `show` / `hide` call the
  controller. `CLIClient`: `SopranoTab list [--detailed]`, `focus <window-id>`,
  `focus --last-focus-order <n>`, `show [<1-9>]` (1-based on the command line), `hide`;
  prints the response JSON (pretty, sorted keys) and exits 0, or prints the error to
  stderr and exits 1; "Soprano Tab is not running." when the port is missing. The bundle
  id is `Bundle.main.bundleIdentifier ?? "com.soprano.tab"`.

## Fixtures and the snapshot harness

```swift
enum FixtureScenario: String, CaseIterable { case standard, crowded, windowless, empty, multiScreen }
@MainActor final class FixtureWindowSource: WindowSource {
    init(scenario: FixtureScenario)
    init(snapshot: WindowSnapshot)
    var snapshot: WindowSnapshot { get set }          // setting it fires onChange
    func mutate(_ change: (inout WindowSnapshot) -> Void)
}
@MainActor final class FixtureThumbnails: ThumbnailProvider {
    init(source: FixtureWindowSource, colors: ThemeColors = AppTheme.folioPaper.colors)
}
@MainActor final class FixtureIcons: AppIconProvider { init() }
enum WindowActionRecord: Equatable {
    case focus(ItemID), close(ItemID), toggleMinimize(ItemID), toggleFullscreen(ItemID)
    case quitApp(pid_t), toggleHideApp(pid_t), moveCursor(ItemID)
}
@MainActor final class RecordingWindowActions: WindowActing {
    init(source: FixtureWindowSource)
    private(set) var log: [WindowActionRecord]       // and applies each action to the source
}
```

Scenarios: `standard` — one 1512 × 982 screen (visible frame below a 33 pt menu bar), 3
Spaces, ~12 windows: Soprano (2), Safari (3, one minimized), Finder (1), Mail (app
hidden), Slack (fullscreen Space 3), System Settings (Space 2), Soprano Git, Stickies (all
Spaces), windowless Notes and Music; focus on a Soprano window. `crowded` — 40 windows
over 12 apps. `windowless` — only windowless apps plus a windowless Finder (hidden by the
default exception). `empty` — no windows. `multiScreen` — the laptop screen plus a
2560 × 1440 display to its right, windows on both. Thumbnails are deterministic drawings
of a window in the theme's mode (a `raised` title bar with the macOS traffic lights and
the title, content blocks seeded by the window id, the app's colour in a few of them);
icons are square tiles in the app's color with its initial.

`SopranoTab snapshot --out <png> [--scenario standard|crowded|windowless|empty|multiScreen]
[--screen 1512x982] [--style thumbnails|appIcons|titles] [--size small|medium|large|auto]
[--theme <id>] [--shortcut <1-9>] [--settings <jsonc>] [--keys "<token> …"]
[--search "<text>"] [--hover <index>] [--preview] [--onboarding
[--permissions accessibility=granted|missing,screen=granted|missing]] [--report <json>]`
runs the real `SwitcherController` and `SwitcherWindow` on fixtures with an immediate
scheduler (no display delay), offscreen, no Dock icon, no persisted state, no
permission. It presses the shortcut (hold modifiers + key through
`controller.handleKeyEvent`), replays `--keys` the same way — `tab` (the trigger key
again), `shift+tab`, `shift` (the previous modifier alone), `release` (hold modifiers
up), `left right up down return escape`, single letters — applies `--search` through
`searchTextDidChange` (after `s` or on its own, which begins search first), hovers
`--hover`, and writes `presenter.renderSnapshot(screen:backdrop:)` over a backdrop that
draws the fixture desktop in the theme's mode (Folio's `--desktop-wallpaper`, menu bar and
`--shadow-window`). Themes resolve against a light system appearance and never read
Soprano's settings: the default (`soprano`), `folio` and `folio-paper` render Folio Paper;
`--theme folio-ink` renders Ink; the dark themes render dark. `--report` writes JSON: active, selected index, item titles,
query, and the action log. `--onboarding` renders the permissions window instead. Agents
verify UI with it and `read` the PNG; they never launch the GUI.

## Visual design

Folio (Soprano `docs/design/2026-10-21-calm-family/b/`, direction.md §11 Tab, `tab.html`),
from the vendored `Chrome.swift` and `Theme.swift` only: `ThemeColors` slots and derived
tokens (`raised`, `hover`, `selection`, `focusMark`, `pencilTick`, `matchOnSelection`,
`fieldFocusEdge`, `keycapFill/Edge`, `shadowE2/E3`), `ChromeFont` (SF Pro; New York only
for the empty state and the permissions headline), `Chrome` metrics and radii,
`ChromeKeycapView`, `ChromeFieldView`, `ChromeStatusMark`, `ChromeButton`,
`ChromeRuleView`. The accent marks only the selection (ring, tick, preview frame), the
caret and search hits on the selected tile. Every window's appearance comes from its theme.

- **Panel**: `raised`, 1 pt `borderSubtle`, radius 12, e3 shadow (the system window
  shadow on screen; the offscreen render draws `shadowE3` and its contact ring). Header
  (28 pt, no rule): the subject in SF Pro 13 Medium ink, "· N" in SF Pro 13 muted
  tabular 4 pt after it; right-aligned hints 12 pt apart, each a 16 pt muted
  `ChromeKeycapView` (K1 legend) plus its word in SF Pro 11 muted, 5 pt apart. Hints that
  do not fit (16 pt after the heading) drop whole from the end.
- **Thumbnail tile**: `bgPanel`, radius 8, no border. Title strip 22 pt: the 16 pt app
  icon (radius 4), 6 pt, the title in SF Pro 12 `textMuted`. Hovered: `hover` fill and an
  ink title. Selected: a 2 pt `focusMark` ring 3 pt outside the tile (radius 13, inside
  the layout's ring margin), ink Medium title, no fill change. Image well: `raised`,
  radius 4, clipping the aspect-fit thumbnail (the app icon at half the well's height
  when there is none). Windowless apps: muted title, well content at 0.6.
- **Window controls** on the hovered tile: 12 pt circles 6 apart in the real macOS
  traffic-light colours (`TrafficLight`: close #ff5f57, minimize #febc2e, full screen
  #28c840, quit = close; 0.5 pt edge black 12 % Paper / 30 % dark) on an opaque corner
  chip at the image's top-left (`LampChipView`: `raised`, padding 8 × 6, only the
  bottom-right corner rounded 6, `shadowE2`), so the title keeps its full width. A
  windowless app's tile shows the quit control alone.
- **Chips** at the image's bottom-left, inset 4, 4 apart: 16 pt, padding 5, radius 4,
  `bgBase` at 90 %, SF Pro 11 Medium ink: "Minimized", "Hidden", "Full screen", "Space N"
  / "All Spaces". Chips that do not fit are hidden.
- **App icon tile**: the thumbnail tile's fill, ring and hover; the real app icon; the
  title centered below in SF Pro 12; the window-control chip over the icon's top-left.
- **Title row**: the list-row idiom through the vendored `ChromeSelectionPill`
  (`ChromeRowBackgroundView`, inset 0) — hover `.hover`, selected `.selected`: a
  `selection` pill (radius 6) with a 2 × 14 `pencilTick` 4 pt in; icon, title in SF Pro 13 ink, app name
  right-aligned in SF Pro 11 muted, then `.chip`-style chips (18 pt, `bgOverlay`, muted);
  window controls inline at the leading edge.
- **Search strip** (30 pt): a `ChromeFieldView` (`raised`, `borderStrong` edge, radius 6,
  `fieldFocusEdge` while focused, never accent), a 13 pt muted magnifier 8 pt in, the
  field in SF Pro 12 with the accent caret; placeholder "Search windows". Search hits are
  Semibold ink, `matchOnSelection` on the selected tile.
- **Empty**: New York Italic 17 `textMuted`, centered ("No windows", "No matches").
- **Preview**: the window image at the window's frame with a 2 pt `focusMark` frame,
  below the panel; 120 ms fade-in when `previewFadeIn`. Panel fade-out 0.15 s when
  `fadeOut`. Under Reduce Motion both are instant.
- Panel windows: borderless, non-activating `NSPanel`, level popUpMenu, collection
  behavior `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`, never
  hides on deactivate; becomes key only while search has focus. Tiles expose
  accessibility labels ("Title, App") so VoiceOver reads them.

## Tests

swift-testing (`import Testing`, `@Test`, `#expect`), one `struct …Tests` per file,
sentence-style names. Test files `import AppKit` (never `Foundation`: its
`_Testing_Foundation` overlay breaks the build) plus `@testable import SopranoTab` /
`SopranoTabCore`; main-actor tests are `@MainActor`. Tests never touch real settings,
real windows, permissions or the user's defaults; settings tests inject the file URL,
system tests cover only the pure parts. Test behavior consumers see (boundaries,
precedence, transitions, invariants), not wiring.

## Not copied from AltTab

Soprano family conventions replace these: the preferences window (settings.json, live
reloaded, opened from the menu), Sparkle updates and crash reports (install with
`scripts/install.sh`), the Pro license, 21 UI languages (the family's UI is English),
AltTab's own light/dark/system themes (Soprano's themes: Folio follows macOS).
