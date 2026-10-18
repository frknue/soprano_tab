import AppKit
import Testing
@testable import SopranoTab
@testable import SopranoTabCore

struct FocusOrderTests {
    @Test("the initial order is the on-screen z-order followed by the remaining windows")
    func seedingFollowsZOrderThenRest() {
        let order = FocusOrder(zOrderedWindows: [30, 10], remainingWindows: [10, 50, 20, 30])

        #expect(order.windowIDs == [30, 10, 50, 20])
        #expect(order.rank(of: 30) == 0)
        #expect(order.rank(of: 20) == 3)
    }

    @Test("focusing a window moves it to the front and shifts the ones it passed")
    func focusMovesToFront() {
        var order = FocusOrder(zOrderedWindows: [1, 2, 3, 4])

        order.focus(3)

        #expect(order.windowIDs == [3, 1, 2, 4])
        #expect(order.rank(of: 1) == 1)
        #expect(order.rank(of: 4) == 3)
    }

    @Test("focusing an unknown window adds it at the front")
    func focusAddsUnknownWindow() {
        var order = FocusOrder(zOrderedWindows: [1, 2])

        order.focus(9)

        #expect(order.windowIDs == [9, 1, 2])
    }

    @Test("focusing the front window changes nothing")
    func refocusingFrontWindow() {
        var order = FocusOrder(zOrderedWindows: [1, 2, 3])

        order.focus(1)

        #expect(order == FocusOrder(zOrderedWindows: [1, 2, 3]))
    }

    @Test("a removed window has no rank and later windows move up")
    func removeClosesGap() {
        var order = FocusOrder(zOrderedWindows: [1, 2, 3])

        order.remove(2)

        #expect(order.rank(of: 2) == nil)
        #expect(order.rank(of: 3) == 1)
    }

    @Test("pruning keeps only existing windows in their order")
    func pruneKeepsOrder() {
        var order = FocusOrder(zOrderedWindows: [5, 4, 3, 2, 1])

        order.prune(keeping: [1, 3, 5, 7])

        #expect(order.windowIDs == [5, 3, 1])
        #expect(order.windowRanks == [5: 0, 3: 1, 1: 2])
    }

    @Test("app activation recency ranks apps, most recent first")
    func appActivationRecency() {
        var order = FocusOrder(appsByRecency: [100, 200, 300])

        order.activate(300)
        order.activate(400)

        #expect(order.appPIDs == [400, 300, 100, 200])
        #expect(order.appRank(of: 100) == 2)
        #expect(order.appRank(of: 999) == nil)
    }

    @Test("a quit app loses its rank without touching window order")
    func removeApp() {
        var order = FocusOrder(zOrderedWindows: [1, 2], appsByRecency: [100, 200])

        order.removeApp(100)

        #expect(order.appPIDs == [200])
        #expect(order.windowIDs == [1, 2])
    }
}
