import CoreGraphics
import Foundation

/// Turns the unfiltered desktop snapshot into the list one shortcut shows.
public enum WindowListBuilder {
    /// The items a shortcut lists, in display order.
    ///
    /// Steps, in order: exceptions, apps, Spaces, screens, tabs, order, grouping, then the
    /// show policies for minimized, hidden, fullscreen and windowless items.
    public static func items(
        from snapshot: WindowSnapshot,
        filters: WindowFilters,
        exceptions: [ExceptionRule],
        switcherDisplayID: DisplayID?
    ) -> [WindowInfo] {
        let visibleSpaces = snapshot.visibleSpaceIDs
        var items = snapshot.windows.filter { passesExceptions($0, rules: exceptions) }
        items = filterApps(items, filter: filters.apps, snapshot: snapshot, visibleSpaces: visibleSpaces)
        items = items.filter { passesSpaces($0, filter: filters.spaces, visibleSpaces: visibleSpaces) }
        if filters.screens == .showingSwitcher {
            items = items.filter { $0.displayID == nil || $0.displayID == switcherDisplayID }
        }
        if filters.tabs == .singleWindow {
            items = items.filter { !$0.isBackgroundTab }
        }
        items.sort { precedes($0, $1, order: filters.order) }
        if filters.grouping == .oneWindowPerApp {
            var seen = Set<pid_t>()
            items = items.filter { seen.insert($0.app.pid).inserted }
        }
        return applyShowPolicies(items, filters: filters)
    }

    // MARK: Exceptions

    private static func passesExceptions(_ item: WindowInfo, rules: [ExceptionRule]) -> Bool {
        guard let rule = ExceptionMatcher.rule(forBundleID: item.app.bundleID, in: rules) else { return true }
        switch rule.hide {
        case .never:
            return true
        case .always:
            return false
        case .whenNoOpenWindow:
            return !item.isWindowlessApp
        case .whenTitleContains:
            guard !item.isWindowlessApp else { return true }
            return !rule.titleContains.contains { fragment in
                !fragment.isEmpty && item.title.range(of: fragment, options: .caseInsensitive) != nil
            }
        }
    }

    // MARK: Apps

    private static func filterApps(
        _ items: [WindowInfo],
        filter: AppsFilter,
        snapshot: WindowSnapshot,
        visibleSpaces: Set<SpaceID>
    ) -> [WindowInfo] {
        switch filter {
        case .all:
            return items
        case .active:
            return items.filter { snapshot.frontmostPID != nil && $0.app.pid == snapshot.frontmostPID }
        case .nonActive:
            return items.filter { snapshot.frontmostPID == nil || $0.app.pid != snapshot.frontmostPID }
        case .underCursor:
            return items.filter { isUnderCursor($0, snapshot: snapshot, visibleSpaces: visibleSpaces) }
        case .appUnderCursor:
            let frontmost = items
                .filter { isUnderCursor($0, snapshot: snapshot, visibleSpaces: visibleSpaces) }
                .min { lhs, rhs in
                    let left = lhs.zIndex ?? Int.max
                    let right = rhs.zIndex ?? Int.max
                    if left != right { return left < right }
                    return lhs.lastFocusOrder < rhs.lastFocusOrder
                }
            guard let pid = frontmost?.app.pid else { return [] }
            return items.filter { !$0.isWindowlessApp && $0.app.pid == pid }
        }
    }

    /// A real, unminimized window on a visible Space whose frame contains the mouse.
    private static func isUnderCursor(_ item: WindowInfo, snapshot: WindowSnapshot, visibleSpaces: Set<SpaceID>) -> Bool {
        !item.isWindowlessApp
            && !item.isMinimized
            && isOnVisibleSpace(item, visibleSpaces: visibleSpaces)
            && item.frame.contains(snapshot.mouseLocation)
    }

    // MARK: Spaces

    private static func passesSpaces(_ item: WindowInfo, filter: SpacesFilter, visibleSpaces: Set<SpaceID>) -> Bool {
        switch filter {
        case .all:
            return true
        case .visible:
            return countsAsVisible(item, visibleSpaces: visibleSpaces)
        case .nonVisible:
            return !countsAsVisible(item, visibleSpaces: visibleSpaces)
        }
    }

    /// Minimized windows and windowless entries without Spaces count as visible.
    private static func countsAsVisible(_ item: WindowInfo, visibleSpaces: Set<SpaceID>) -> Bool {
        if item.spaceIDs.isEmpty && (item.isMinimized || item.isWindowlessApp) { return true }
        return isOnVisibleSpace(item, visibleSpaces: visibleSpaces)
    }

    private static func isOnVisibleSpace(_ item: WindowInfo, visibleSpaces: Set<SpaceID>) -> Bool {
        item.isOnAllSpaces || item.spaceIDs.contains { visibleSpaces.contains($0) }
    }

    // MARK: Order

    /// Strict weak order for `order`; ties fall back to `lastFocusOrder`, then the item id.
    private static func precedes(_ lhs: WindowInfo, _ rhs: WindowInfo, order: WindowOrder) -> Bool {
        switch order {
        case .recentlyFocused:
            break
        case .recentlyCreated:
            if lhs.creationOrder != rhs.creationOrder { return lhs.creationOrder > rhs.creationOrder }
        case .alphabetical:
            let byApp = lhs.app.name.localizedStandardCompare(rhs.app.name)
            if byApp != .orderedSame { return byApp == .orderedAscending }
            let byTitle = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
            if byTitle != .orderedSame { return byTitle == .orderedAscending }
            return idPrecedes(lhs, rhs)
        case .space:
            let left = spaceRank(lhs)
            let right = spaceRank(rhs)
            if left != right { return left < right }
        }
        if lhs.lastFocusOrder != rhs.lastFocusOrder { return lhs.lastFocusOrder < rhs.lastFocusOrder }
        return idPrecedes(lhs, rhs)
    }

    /// On every Space first, then the lowest Mission Control index, unknown Spaces last.
    private static func spaceRank(_ item: WindowInfo) -> Int {
        if item.isOnAllSpaces { return Int.min }
        return item.spaceIndexes.min() ?? Int.max
    }

    /// Windows by window id, then windowless entries by pid.
    private static func idPrecedes(_ lhs: WindowInfo, _ rhs: WindowInfo) -> Bool {
        switch (lhs.id, rhs.id) {
        case let (.window(left), .window(right)): return left < right
        case (.window, .windowlessApp): return true
        case (.windowlessApp, .window): return false
        case let (.windowlessApp(left), .windowlessApp(right)): return left < right
        }
    }

    // MARK: Show policies

    /// `hide` from any matching policy drops the item; otherwise `showAtTheEnd` from any
    /// moves it to the tail group, which keeps the sorted order.
    private static func applyShowPolicies(_ items: [WindowInfo], filters: WindowFilters) -> [WindowInfo] {
        var head: [WindowInfo] = []
        var tail: [WindowInfo] = []
        for item in items {
            var policies: [ShowPolicy] = []
            if item.isMinimized { policies.append(filters.minimized) }
            if item.isHidden { policies.append(filters.hidden) }
            if item.isFullscreen { policies.append(filters.fullscreen) }
            if item.isWindowlessApp { policies.append(filters.windowlessApps) }
            if policies.contains(.hide) { continue }
            if policies.contains(.showAtTheEnd) {
                tail.append(item)
            } else {
                head.append(item)
            }
        }
        return head + tail
    }
}
