import AppKit
import SopranoTabCore

/// Turns the controller's state into the `SwitcherViewModel` the presenter draws: tile
/// titles, search highlights, chips, the header's heading and key hints, the empty text.
enum SwitcherModelBuilder {
    static func model(
        session: SwitcherSession,
        layout: TileLayout,
        settings: SopranoTabSettings,
        theme: AppTheme,
        style: SwitcherStyle,
        snapshot: WindowSnapshot,
        hoveredIndex: Int?,
        thumbnails: (WindowID) -> CGImage?,
        icons: (AppInfo) -> NSImage
    ) -> SwitcherViewModel {
        let appearance = settings.appearance
        let query = session.isSearching ? session.query : ""
        let tiles = session.items.map { item in
            let title = title(for: item, content: appearance.titles)
            return TileViewModel(
                id: item.id,
                title: title,
                highlightedRanges: highlightedRanges(of: query, in: title),
                appName: item.app.name,
                icon: icons(item.app),
                thumbnail: style == .thumbnails ? item.windowID.flatMap(thumbnails) : nil,
                chips: chips(for: item, appearance: appearance),
                isWindowlessApp: item.isWindowlessApp
            )
        }
        let index = session.shortcutIndex
        let shortcut = settings.shortcuts.indices.contains(index) ? settings.shortcuts[index] : nil
        return SwitcherViewModel(
            theme: theme,
            style: style,
            layout: layout,
            tiles: tiles,
            selectedIndex: session.selectedIndex,
            hoveredIndex: hoveredIndex.flatMap { tiles.indices.contains($0) ? $0 : nil },
            heading: heading(
                for: settings.filters(forShortcut: index),
                snapshot: snapshot,
                isSearching: session.isSearching,
                count: tiles.count
            ),
            hints: hints(controls: settings.controls, shortcut: shortcut, searchHint: appearance.searchHint),
            search: session.isSearching ? SearchFieldState(query: session.query, isActive: true) : nil,
            showsWindowControls: appearance.windowControls,
            titleTruncation: appearance.titleTruncation,
            emptyText: tiles.isEmpty ? emptyText(for: session) : nil
        )
    }

    /// The tile title. Windowless apps and untitled windows show the app name alone, so
    /// "App - Title" never repeats the app name.
    static func title(for item: WindowInfo, content: TitleContent) -> String {
        switch content {
        case .windowTitle:
            return item.displayTitle
        case .appName:
            return item.app.name
        case .appNameAndWindowTitle:
            let title = item.displayTitle
            return title == item.app.name ? title : "\(item.app.name) - \(title)"
        }
    }

    /// What the list shows and its count: "All windows", the active app's name, "Other
    /// apps", "Under the cursor", the name of the app under the cursor, or "Search" while
    /// searching.
    static func heading(for filters: WindowFilters, snapshot: WindowSnapshot, isSearching: Bool, count: Int) -> SwitcherHeading {
        let subject: String
        if isSearching {
            subject = "Search"
        } else {
            switch filters.apps {
            case .all:
                subject = "All windows"
            case .active:
                subject = activeAppName(in: snapshot) ?? "Active app"
            case .nonActive:
                subject = "Other apps"
            case .underCursor:
                subject = "Under the cursor"
            case .appUnderCursor:
                subject = appUnderCursorName(in: snapshot) ?? "Under the cursor"
            }
        }
        return SwitcherHeading(subject: subject, count: count)
    }

    /// Key hints from the bound keys, one keycap each: `⇥` next, `⇧` back, `↩` open,
    /// `W` close, `M` min, `Q` quit, `S` search. Unbound keys drop out; "next" needs a
    /// shortcut (the gesture has none); "search" only shows with `searchHint`.
    static func hints(controls: ControlSettings, shortcut: ShortcutSettings?, searchHint: Bool) -> [KeyHint] {
        var hints: [KeyHint] = []
        if let shortcut {
            hints.append(KeyHint(key: shortcut.key.symbol, label: "next"))
        }
        if !controls.previous.isEmpty {
            hints.append(KeyHint(key: controls.previous.symbols, label: "back"))
        }
        let labeled: [(KeySpec?, String)] = [
            (controls.focus, "open"),
            (controls.close, "close"),
            (controls.minimize, "min"),
            (controls.quit, "quit"),
            (searchHint ? controls.search : nil, "search"),
        ]
        for case let (key?, label) in labeled {
            hints.append(KeyHint(key: key.symbol, label: label))
        }
        return hints
    }

    private static func highlightedRanges(of query: String, in title: String) -> [NSRange] {
        guard !query.isEmpty, let match = SearchMatcher.match(query, in: title) else { return [] }
        return match.ranges.map { NSRange($0, in: title) }
    }

    /// Chip texts per `statusIcons` and `spaceLabels`: "Minimized", "Hidden", "Full
    /// screen", then "All Spaces" or "Space <first index>".
    private static func chips(for item: WindowInfo, appearance: AppearanceSettings) -> [String] {
        var chips: [String] = []
        if appearance.statusIcons {
            if item.isMinimized { chips.append("Minimized") }
            if item.isHidden { chips.append("Hidden") }
            if item.isFullscreen { chips.append("Full screen") }
        }
        if appearance.spaceLabels, !item.isWindowlessApp {
            if item.isOnAllSpaces {
                chips.append("All Spaces")
            } else if let space = item.spaceIndexes.first {
                chips.append("Space \(space)")
            }
        }
        return chips
    }

    private static func emptyText(for session: SwitcherSession) -> String {
        session.isSearching && !session.query.isEmpty ? "No matches" : "No windows"
    }

    private static func activeAppName(in snapshot: WindowSnapshot) -> String? {
        guard let pid = snapshot.frontmostPID else { return nil }
        return snapshot.windows.first { $0.app.pid == pid }?.app.name
    }

    /// The app owning the frontmost on-screen window under the mouse.
    private static func appUnderCursorName(in snapshot: WindowSnapshot) -> String? {
        snapshot.windows
            .filter { window in
                window.zIndex != nil && !window.isMinimized && !window.isWindowlessApp
                    && window.frame.contains(snapshot.mouseLocation)
            }
            .min { ($0.zIndex ?? .max) < ($1.zIndex ?? .max) }?
            .app.name
    }
}
