import CoreGraphics
import Foundation

// Value types shared by the input router, the session, the layout engine and the UI.
// Their behavior lives in the files named in docs/ARCHITECTURE.md → Core APIs.

/// A command the open switcher executes.
public enum SwitcherCommand: Equatable, Sendable {
    case selectNext
    case selectPrevious
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case focusSelected
    case cancel
    case closeWindow
    case toggleMinimize
    case toggleFullscreen
    case quitApp
    case toggleHideApp
    case beginSearch
}

/// What `SwitcherKeyRouter` decided for one key event.
public enum TriggerAction: Equatable, Sendable {
    /// Open the switcher for shortcut `shortcut` (0-based), selecting backwards when `reverse`.
    case activate(shortcut: Int, reverse: Bool)
    /// The active shortcut's key was pressed again (or the previous modifier alone).
    case advance(reverse: Bool)
    /// The active shortcut's hold modifiers were released.
    case release
    /// A control key was pressed while the switcher is active.
    case command(SwitcherCommand)
}

/// The router's answer: what to do, and whether the event tap swallows the event.
public struct KeyDecision: Equatable, Sendable {
    public var action: TriggerAction?
    public var consume: Bool

    public init(action: TriggerAction? = nil, consume: Bool) {
        self.action = action
        self.consume = consume
    }

    public static let passThrough = KeyDecision(action: nil, consume: false)
}

/// The router's state.
public enum KeyRouterState: Equatable, Sendable {
    case idle
    /// The switcher is active for `shortcut`; `holding` while its hold modifiers are
    /// still down; `searching` while the search field takes text.
    case active(shortcut: Int, holding: Bool, searching: Bool)
}

/// One trackpad touch from a gesture event.
public struct TouchSample: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case began
        case moved
        case stationary
        case ended
        case cancelled
    }

    /// Stable identity of the finger for the duration of the touch.
    public var id: Int
    /// Normalized trackpad position, 0...1 on both axes, origin bottom-left (NSTouch).
    public var position: CGPoint
    public var phase: Phase

    public init(id: Int, position: CGPoint, phase: Phase) {
        self.id = id
        self.position = position
        self.phase = phase
    }
}

/// What `SwipeTracker` decided for one batch of touches.
public enum SwipeAction: Equatable, Sendable {
    /// The swipe crossed the activation distance: open the switcher.
    case activate(reverse: Bool)
    /// The swipe moved one more step.
    case step(reverse: Bool)
    /// The fingers lifted: focus the selection.
    case finish
}

/// Input to `TileLayout.compute`.
public struct TileLayoutInput: Equatable, Sendable {
    public var style: SwitcherStyle
    /// A concrete or `.auto` size.
    public var size: SwitcherSize
    /// The visible frame size of the display the switcher opens on, in points.
    public var screenSize: CGSize
    /// Each item's window size in points; `.zero` (windowless apps) counts as 16:10.
    public var itemSizes: [CGSize]
    /// Reserve the search field strip below the header.
    public var showsSearchField: Bool

    public init(style: SwitcherStyle, size: SwitcherSize, screenSize: CGSize, itemSizes: [CGSize], showsSearchField: Bool = false) {
        self.style = style
        self.size = size
        self.screenSize = screenSize
        self.itemSizes = itemSizes
        self.showsSearchField = showsSearchField
    }
}

/// Where everything in the switcher panel goes. Panel and content coordinates have
/// their origin at the top-left, y grows down.
public struct TileLayout: Equatable, Sendable {
    /// The size the layout resolved `.auto` to (never `.auto`).
    public var resolvedSize: SwitcherSize
    /// The panel's size in points.
    public var panelSize: CGSize
    /// The header strip, panel coordinates.
    public var headerFrame: CGRect
    /// The search field strip, panel coordinates; nil when not shown.
    public var searchFieldFrame: CGRect?
    /// The scrollable tile area, panel coordinates.
    public var contentFrame: CGRect
    /// The tile area's full size; taller than `contentFrame` when items overflow.
    public var contentSize: CGSize
    /// One frame per item, in content coordinates.
    public var tileFrames: [CGRect]
    /// The thumbnail or icon rect inside each tile, tile-local coordinates.
    public var imageFrames: [CGRect]
    /// The title rect inside each tile, tile-local coordinates.
    public var titleFrames: [CGRect]
    /// Item index ranges, one per row, top to bottom.
    public var rows: [Range<Int>]

    public init(
        resolvedSize: SwitcherSize,
        panelSize: CGSize,
        headerFrame: CGRect,
        searchFieldFrame: CGRect?,
        contentFrame: CGRect,
        contentSize: CGSize,
        tileFrames: [CGRect],
        imageFrames: [CGRect],
        titleFrames: [CGRect],
        rows: [Range<Int>]
    ) {
        self.resolvedSize = resolvedSize
        self.panelSize = panelSize
        self.headerFrame = headerFrame
        self.searchFieldFrame = searchFieldFrame
        self.contentFrame = contentFrame
        self.contentSize = contentSize
        self.tileFrames = tileFrames
        self.imageFrames = imageFrames
        self.titleFrames = titleFrames
        self.rows = rows
    }
}

/// A search hit: a score (higher is better) and the matched character ranges, for
/// highlighting.
public struct SearchMatch: Equatable, Sendable {
    public var score: Int
    public var ranges: [Range<String.Index>]

    public init(score: Int, ranges: [Range<String.Index>]) {
        self.score = score
        self.ranges = ranges
    }
}
