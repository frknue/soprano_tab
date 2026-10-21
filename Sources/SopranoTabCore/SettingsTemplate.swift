import Foundation

/// The commented settings.json written on first launch: the schema is the documentation.
/// Every value is the default, so the template resolves to `SopranoTabSettings.defaults`;
/// allowed values are generated from the enums so they never drift.
public enum SettingsTemplate {
    /// The commented settings.json written on first launch. Resolves to `.defaults` with
    /// no issues; documents every key below with its default and allowed values.
    public static let text: String = """
    // Soprano Tab settings. JSON with comments; saved changes apply immediately.
    // Every key is optional. Unknown keys and bad values are ignored with a warning.
    {
      // "soprano" follows Soprano's theme and appearance (~/.config/soprano/settings.json);
      // "folio" follows macOS (Folio Paper in light mode, Folio Ink in dark mode);
      // "folio-paper", "folio-ink", or a dark theme: "gruvbox-dark", "catppuccin-mocha",
      // "dracula", "solarized-dark", "nord", "tokyo-night", "atom-one-dark".
      "theme": "soprano",

      // 1 to 9 shortcuts: hold "hold", press "key" to open the switcher and step forward.
      // Present → replaces the two defaults below.
      //   hold:     modifiers joined with "+": "option" (alt, opt, ⌥), "command" (cmd, ⌘),
      //             "control" (ctrl, ⌃), "shift" (⇧), "fn". Default "option".
      //   key:      "tab", "keyAboveTab" (` on US, ^ on German keyboards), "space", "return",
      //             "escape", "delete", "forwardDelete", arrows ("left" …), "home", "end",
      //             "pageUp", "pageDown", "f1"…"f12", or one character ("w").
      //             Shortcut 1 defaults to "tab", shortcut 2 to "keyAboveTab"; later ones need a key.
      //   apps:           \(values(AppsFilter.self))
      //                   default "all"; shortcut 2 "active", shortcut 3 "nonActive"
      //   spaces:         \(values(SpacesFilter.self)), default "all"
      //   screens:        \(values(ScreensFilter.self)), default "all"
      //   minimized, hidden, fullscreen:
      //                   \(values(ShowPolicy.self)), default "show"
      //   windowlessApps: \(values(ShowPolicy.self)), default "showAtTheEnd"
      //   order:          \(values(WindowOrder.self)), default "recentlyFocused"
      //   grouping:       \(values(AppGrouping.self)), default "allWindows"
      //   tabs:           \(values(TabGrouping.self)), default "singleWindow"
      //   onRelease:      \(values(ReleaseAction.self)), default "focus"
      //   style, size, theme, preview: this shortcut's appearance.style, appearance.size,
      //                   theme and appearance.previewSelectedWindow (default: the global value).
      "shortcuts": [
        { "hold": "option", "key": "tab" },
        { "hold": "option", "key": "keyAboveTab", "apps": "active" }
      ],

      // Trackpad swipe trigger. Takes the same filter keys as a shortcut
      // (apps, spaces, screens, minimized, hidden, fullscreen, windowlessApps, order,
      // grouping, tabs), all defaulting to their shortcut 1 values.
      "gesture": {
        // \(values(GestureKind.self))
        "type": "disabled",
        // A haptic tick on each step.
        "haptics": true
      },

      // Keys while the switcher is open. Same key names as shortcuts; null disables one.
      // Two controls on one key: the later one in this list is disabled.
      "controls": {
        "focus": "return",
        // Hold or press this one modifier to step backwards ("shift", "option", "control",
        // "command", "fn"), or null.
        "previous": "shift",
        "cancel": "escape",
        "close": "w",
        "minimize": "m",
        "fullscreen": "f",
        "quit": "q",
        "hide": "h",
        "search": "s",
        "arrowKeys": true,
        // h/j/k/l move the selection; they win over controls on the same letters.
        "vimKeys": false
      },

      "mouse": {
        // Hovering a tile selects it.
        "hoverSelects": false,
        // Move the pointer to the focused window: \(values(CursorFollowsFocus.self))
        "cursorFollowsFocus": "never"
      },

      "appearance": {
        // \(values(SwitcherStyle.self))
        "style": "thumbnails",
        // \(values(SwitcherSize.self)) ("auto" fits every window without scrolling)
        "size": "auto",
        // Display the switcher opens on: \(values(ScreenChoice.self))
        "screen": "active",
        // \(values(TitleContent.self))
        "titles": "windowTitle",
        // \(values(TitleTruncation.self))
        "titleTruncation": "end",
        // Close / minimize / fullscreen buttons on the hovered tile, quit for apps without windows.
        "windowControls": true,
        // "Space 2" / "All Spaces" chips on tiles.
        "spaceLabels": false,
        // "Minimized" / "Hidden" / "Full screen" chips on tiles.
        "statusIcons": true,
        // A quick tap switches without showing the switcher when shorter than this
        // (\(AppearanceSettings.showDelayRange.lowerBound)–\(AppearanceSettings.showDelayRange.upperBound) ms).
        "showDelayMs": 100,
        "fadeOut": false,
        // Show the selected window full size behind the switcher.
        "previewSelectedWindow": false,
        "previewFadeIn": true,
        // The search hint in the switcher header.
        "searchHint": true,
        // Keep thumbnails fresh while the switcher is closed (instant first show).
        "captureInBackground": true
      },

      // Per-app rules. Present → replaces this whole list.
      //   bundleId:        required; ending in "." matches every id with that prefix
      //   hide:            \(values(ExceptionHide.self)), default "never"
      //   titleContains:   a string or an array of strings, for hide "whenTitleContains"
      //   ignoreShortcuts: \(values(ExceptionIgnore.self)), default "never"
      //                    (shortcuts pass through to the app)
      "exceptions": [
        { "bundleId": "com.apple.finder", "hide": "whenNoOpenWindow" },
        { "bundleId": "com.apple.ScreenSharing", "ignoreShortcuts": "whenFullscreen" },
        { "bundleId": "com.microsoft.rdc.macos", "ignoreShortcuts": "whenFullscreen" },
        { "bundleId": "com.teamviewer.TeamViewer", "ignoreShortcuts": "whenFullscreen" },
        { "bundleId": "org.virtualbox.app.VirtualBoxVM", "ignoreShortcuts": "whenFullscreen" },
        { "bundleId": "com.parallels.", "ignoreShortcuts": "whenFullscreen" },
        { "bundleId": "com.citrix.XenAppViewer", "ignoreShortcuts": "whenFullscreen" },
        { "bundleId": "com.citrix.receiver.icaviewer.mac", "ignoreShortcuts": "whenFullscreen" },
        { "bundleId": "com.nicesoftware.dcvviewer", "ignoreShortcuts": "whenFullscreen" },
        { "bundleId": "com.vmware.fusion", "ignoreShortcuts": "whenFullscreen" },
        { "bundleId": "com.utmapp.UTM", "ignoreShortcuts": "whenFullscreen" },
        { "bundleId": "com.McAfee.McAfeeSafariHost", "hide": "always" }
      ],

      "app": {
        "startAtLogin": true,
        // \(values(MenuBarIcon.self))
        "menuBarIcon": "outlined"
      }
    }

    """

    /// `"a" | "b" | "c"` for an enum's settings.json spellings.
    private static func values<Value: RawRepresentable & CaseIterable>(_: Value.Type) -> String where Value.RawValue == String {
        Value.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: " | ")
    }
}
