import Foundation
import SopranoTabCore

/// Focus recency: windows by last focus and apps by last activation, most recent first.
/// A pure value the live catalog feeds focus events into and ranks snapshot items with
/// (`WindowInfo.lastFocusOrder`); ids it never heard of rank after every known one.
struct FocusOrder: Equatable, Sendable {
    /// Most recently focused first.
    private(set) var windowIDs: [WindowID]
    /// Most recently activated first.
    private(set) var appPIDs: [pid_t]

    /// The initial order: the on-screen z-order (front to back), followed by the remaining
    /// windows in the order given. A repeated id keeps its first position.
    init(zOrderedWindows: [WindowID] = [], remainingWindows: [WindowID] = [], appsByRecency: [pid_t] = []) {
        windowIDs = Self.unique(zOrderedWindows + remainingWindows)
        appPIDs = Self.unique(appsByRecency)
    }

    /// `windowID` got focus: it moves (or is added) to the front.
    mutating func focus(_ windowID: WindowID) {
        windowIDs.removeAll { $0 == windowID }
        windowIDs.insert(windowID, at: 0)
    }

    mutating func remove(_ windowID: WindowID) {
        windowIDs.removeAll { $0 == windowID }
    }

    /// Drops every window not in `windowIDs` (closed windows), keeping the order of the rest.
    mutating func prune(keeping windowIDs: Set<WindowID>) {
        self.windowIDs.removeAll { !windowIDs.contains($0) }
    }

    /// 0 = most recently focused; nil when unknown.
    func rank(of windowID: WindowID) -> Int? {
        windowIDs.firstIndex(of: windowID)
    }

    /// Every known window's rank, for sorting many items at once.
    var windowRanks: [WindowID: Int] {
        Dictionary(uniqueKeysWithValues: windowIDs.enumerated().map { ($1, $0) })
    }

    /// `pid` became the active app: it moves (or is added) to the front.
    mutating func activate(_ pid: pid_t) {
        appPIDs.removeAll { $0 == pid }
        appPIDs.insert(pid, at: 0)
    }

    mutating func removeApp(_ pid: pid_t) {
        appPIDs.removeAll { $0 == pid }
    }

    /// 0 = most recently activated; nil when unknown.
    func appRank(of pid: pid_t) -> Int? {
        appPIDs.firstIndex(of: pid)
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
}
