import Foundation

/// The open switcher's list, search and selection.
public struct SwitcherSession: Equatable, Sendable {
    public let shortcutIndex: Int
    public private(set) var allItems: [WindowInfo]
    /// `allItems` filtered by `query`.
    public private(set) var items: [WindowInfo]
    /// Index into `items`; nil when empty.
    public private(set) var selectedIndex: Int?
    public private(set) var query: String
    public private(set) var isSearching: Bool

    /// The first press selects the window you came from: with `f` the focused window's
    /// index, forward selects `(f + 1) % n` (0 when it is not listed), reverse selects
    /// `(f - 1 + n) % n` (`n - 1` when it is not listed).
    public init(items: [WindowInfo], shortcutIndex: Int, focusedWindowID: WindowID?, reverse: Bool) {
        self.shortcutIndex = shortcutIndex
        self.allItems = items
        self.items = items
        self.query = ""
        self.isSearching = false
        let count = items.count
        guard count > 0 else {
            self.selectedIndex = nil
            return
        }
        let focused = focusedWindowID.flatMap { id in items.firstIndex { $0.windowID == id } }
        if reverse {
            self.selectedIndex = focused.map { ($0 - 1 + count) % count } ?? count - 1
        } else {
            self.selectedIndex = focused.map { ($0 + 1) % count } ?? 0
        }
    }

    public var selectedItem: WindowInfo? {
        selectedIndex.map { items[$0] }
    }

    public mutating func selectNext() {
        guard let index = selectedIndex, !items.isEmpty else { return }
        selectedIndex = (index + 1) % items.count
    }

    public mutating func selectPrevious() {
        guard let index = selectedIndex, !items.isEmpty else { return }
        selectedIndex = (index - 1 + items.count) % items.count
    }

    /// Ignored when out of range.
    public mutating func select(index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Ignored when `id` is not listed.
    public mutating func select(id: ItemID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = index
    }

    /// moveLeft/Right/Up/Down through `GridNavigator`; other commands are ignored.
    public mutating func move(_ command: SwitcherCommand, layout: TileLayout) {
        switch command {
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            guard let index = selectedIndex else { return }
            select(index: GridNavigator.index(from: index, command: command, layout: layout))
        default:
            return
        }
    }

    public mutating func beginSearch() {
        isSearching = true
    }

    /// Clears the query and shows every item again, keeping the selected item.
    public mutating func endSearch() {
        isSearching = false
        refilter(query: "", keeping: selectedItem?.id, fallbackIndex: 0)
    }

    /// Keeps the selected item when it still matches, else selects the first match.
    public mutating func setQuery(_ query: String) {
        refilter(query: query, keeping: selectedItem?.id, fallbackIndex: 0)
    }

    /// Live catalog update: keeps the selected item if still present, else the same index clamped.
    public mutating func update(items: [WindowInfo]) {
        let selectedID = selectedItem?.id
        let previousIndex = selectedIndex ?? 0
        allItems = items
        refilter(query: query, keeping: selectedID, fallbackIndex: previousIndex)
    }

    /// Removes an item; the selection moves to the item that took its place (clamped).
    /// Removing another item keeps the selected one.
    public mutating func remove(id: ItemID) {
        let selectedID = selectedItem?.id
        let previousIndex = selectedIndex ?? 0
        allItems.removeAll { $0.id == id }
        refilter(query: query, keeping: selectedID == id ? nil : selectedID, fallbackIndex: previousIndex)
    }

    /// Recomputes `items` for `query` and selects `id` when listed, else `fallbackIndex`
    /// clamped to the list.
    private mutating func refilter(query: String, keeping id: ItemID?, fallbackIndex: Int) {
        self.query = query
        items = SearchMatcher.filter(allItems, query: query)
        guard !items.isEmpty else {
            selectedIndex = nil
            return
        }
        if let id, let index = items.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        } else {
            selectedIndex = min(max(fallbackIndex, 0), items.count - 1)
        }
    }
}
