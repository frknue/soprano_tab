import AppKit
import Testing
@testable import SopranoTabCore

struct SwitcherSessionTests {
    private static let app = AppInfo(pid: 1, bundleID: "test.app", name: "App")
    private static let titles: [WindowID: String] = [1: "Alpha", 2: "Beta", 3: "Gamma", 4: "Delta", 5: "Epsilon"]

    private func items(_ ids: WindowID...) -> [WindowInfo] {
        ids.map { WindowInfo(id: .window($0), app: Self.app, title: Self.titles[$0] ?? "Window \($0)") }
    }

    private func session(_ items: [WindowInfo], focused: WindowID? = nil, reverse: Bool = false) -> SwitcherSession {
        SwitcherSession(items: items, shortcutIndex: 0, focusedWindowID: focused, reverse: reverse)
    }

    /// Four tiles in two rows of two, 100 wide, 10 apart.
    private let grid = TileLayout(
        resolvedSize: .medium,
        panelSize: CGSize(width: 242, height: 300),
        headerFrame: .zero,
        searchFieldFrame: nil,
        contentFrame: CGRect(x: 16, y: 48, width: 210, height: 210),
        contentSize: CGSize(width: 210, height: 210),
        tileFrames: [
            CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 110, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: 110, width: 100, height: 100), CGRect(x: 110, y: 110, width: 100, height: 100),
        ],
        imageFrames: Array(repeating: .zero, count: 4),
        titleFrames: Array(repeating: .zero, count: 4),
        rows: [0..<2, 2..<4]
    )

    @Test("forward selection starts after the focused window and wraps")
    func initialForward() {
        #expect(session(items(1, 2, 3), focused: 1).selectedIndex == 1)
        #expect(session(items(1, 2, 3), focused: 3).selectedIndex == 0)
        #expect(session(items(1, 2, 3), focused: 9).selectedIndex == 0)
        #expect(session(items(1, 2, 3)).selectedIndex == 0)
    }

    @Test("reverse selection starts before the focused window and wraps")
    func initialReverse() {
        #expect(session(items(1, 2, 3), focused: 2, reverse: true).selectedIndex == 0)
        #expect(session(items(1, 2, 3), focused: 1, reverse: true).selectedIndex == 2)
        #expect(session(items(1, 2, 3), focused: 9, reverse: true).selectedIndex == 2)
    }

    @Test("a single item is selected in both directions, and an empty list selects nothing")
    func initialEdgeCases() {
        #expect(session(items(1), focused: 1).selectedIndex == 0)
        #expect(session(items(1), focused: 1, reverse: true).selectedIndex == 0)
        let empty = session([], focused: 1)
        #expect(empty.selectedIndex == nil)
        #expect(empty.selectedItem == nil)
        #expect(empty.items.isEmpty)
    }

    @Test("next and previous wrap around")
    func nextPreviousWrap() {
        var state = session(items(1, 2, 3), focused: 2)
        #expect(state.selectedItem?.id == .window(3))
        state.selectNext()
        #expect(state.selectedIndex == 0)
        state.selectPrevious()
        #expect(state.selectedIndex == 2)
        var empty = session([])
        empty.selectNext()
        empty.selectPrevious()
        #expect(empty.selectedIndex == nil)
    }

    @Test("selecting by index ignores out-of-range values; selecting by id ignores unknown ids")
    func selectByIndexAndID() {
        var state = session(items(1, 2, 3))
        state.select(index: 2)
        #expect(state.selectedIndex == 2)
        state.select(index: 3)
        state.select(index: -1)
        #expect(state.selectedIndex == 2)
        state.select(id: .window(1))
        #expect(state.selectedIndex == 0)
        state.select(id: .windowlessApp(99))
        #expect(state.selectedIndex == 0)
    }

    @Test("moves go through the grid and other commands are ignored")
    func moves() {
        var state = session(items(1, 2, 3, 4))
        state.move(.moveDown, layout: grid)
        #expect(state.selectedIndex == 2)
        state.move(.moveRight, layout: grid)
        #expect(state.selectedIndex == 3)
        state.move(.moveRight, layout: grid)
        #expect(state.selectedIndex == 0)
        state.move(.selectNext, layout: grid)
        state.move(.closeWindow, layout: grid)
        #expect(state.selectedIndex == 0)
    }

    @Test("a query filters the items and keeps the selected item while it matches")
    func setQueryKeepsSelection() {
        var state = session(items(1, 2, 3, 4, 5))
        state.beginSearch()
        #expect(state.isSearching)
        state.select(id: .window(4))
        state.setQuery("ta")
        #expect(state.items.map(\.id) == [.window(2), .window(4)])
        #expect(state.selectedItem?.id == .window(4))
        state.setQuery("gam")
        #expect(state.items.map(\.id) == [.window(3)])
        #expect(state.selectedIndex == 0)
        state.setQuery("zzz")
        #expect(state.items.isEmpty)
        #expect(state.selectedIndex == nil)
        #expect(state.query == "zzz")
    }

    @Test("ending search clears the query, shows every item and keeps the selected one")
    func endSearch() {
        var state = session(items(1, 2, 3, 4, 5))
        state.beginSearch()
        state.setQuery("eps")
        state.endSearch()
        #expect(!state.isSearching)
        #expect(state.query == "")
        #expect(state.items == state.allItems)
        #expect(state.selectedItem?.id == .window(5))
    }

    @Test("a live update keeps the selected item, else clamps its index")
    func updateKeepsOrClamps() {
        var state = session(items(1, 2, 3, 4))
        state.select(index: 2)
        state.update(items: items(4, 3, 2, 1))
        #expect(state.selectedItem?.id == .window(3))
        #expect(state.selectedIndex == 1)

        state.select(index: 3)
        state.update(items: items(4, 3))
        #expect(state.selectedIndex == 1)
        #expect(state.selectedItem?.id == .window(3))

        state.update(items: items(5, 6, 7))
        #expect(state.selectedIndex == 1)
        state.update(items: [])
        #expect(state.selectedIndex == nil)
        state.update(items: items(1))
        #expect(state.selectedIndex == 0)
    }

    @Test("a live update keeps applying the current query")
    func updateKeepsQuery() {
        var state = session(items(1, 2))
        state.beginSearch()
        state.setQuery("delta")
        #expect(state.items.isEmpty)
        state.update(items: items(1, 2, 4))
        #expect(state.items.map(\.id) == [.window(4)])
        #expect(state.selectedIndex == 0)
    }

    @Test("removing the selected item selects the one that took its place, clamped at the end")
    func removeSelected() {
        var state = session(items(1, 2, 3))
        state.select(index: 1)
        state.remove(id: .window(2))
        #expect(state.selectedItem?.id == .window(3))
        state.remove(id: .window(3))
        #expect(state.selectedItem?.id == .window(1))
        state.remove(id: .window(1))
        #expect(state.selectedIndex == nil)
        #expect(state.allItems.isEmpty)
    }

    @Test("removing another item keeps the selected one")
    func removeOther() {
        var state = session(items(1, 2, 3))
        state.select(index: 2)
        state.remove(id: .window(1))
        #expect(state.selectedItem?.id == .window(3))
        #expect(state.selectedIndex == 1)
        state.remove(id: .window(42))
        #expect(state.selectedIndex == 1)
    }
}
