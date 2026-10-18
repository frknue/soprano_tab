import AppKit
import SopranoTabCore

// The seam between `SwitcherController` (state, input, actions) and `SwitcherWindow`
// (the panel and everything drawn in it). The controller builds a `SwitcherViewModel`;
// the presenter only renders it and reports pointer and text input back.

/// A window control shown on the hovered tile (AltTab's colored circles, drawn as lamps).
enum TileControl: Equatable, CaseIterable {
    case close
    case minimize
    case fullscreen
}

/// Badges on a tile.
struct TileBadges: Equatable {
    var minimized = false
    var hidden = false
    var fullscreen = false
    /// "2", or "all" for windows on every Space; nil when Space labels are off.
    var spaceLabel: String?
}

/// One tile, ready to draw.
struct TileViewModel {
    var id: ItemID
    /// The title text per `appearance.titles` (window title, app name, or both).
    var title: String
    /// Search hits in `title` to highlight; empty when not searching.
    var highlightedRanges: [NSRange]
    var appName: String
    var icon: NSImage?
    /// nil draws the app icon centered in the image area (windowless apps, no capture yet,
    /// Screen Recording denied).
    var thumbnail: CGImage?
    var badges: TileBadges
    var isWindowlessApp: Bool
}

/// The search strip's state.
struct SearchFieldState: Equatable {
    var query: String
    /// The field has keyboard focus.
    var isActive: Bool
}

/// Everything the panel shows.
struct SwitcherViewModel {
    var theme: AppTheme
    var style: SwitcherStyle
    var layout: TileLayout
    var tiles: [TileViewModel]
    var selectedIndex: Int?
    var hoveredIndex: Int?
    /// Header text, e.g. "all windows", "active app", "search".
    var heading: String
    /// Right side of the header: key hints such as "⇥ next  ⇧ back  w close  s search".
    var hints: String
    /// nil hides the search strip.
    var search: SearchFieldState?
    var showsWindowControls: Bool
    var titleTruncation: TitleTruncation
    /// Shown instead of tiles when `tiles` is empty ("no windows", "no matches").
    var emptyText: String?
}

/// Draws the switcher.
@MainActor
protocol SwitcherPresenting: AnyObject {
    var isPresented: Bool { get }
    /// Shows the panel centered on `screen.visibleFrame`, or moves and redraws it when
    /// already shown. Never activates Soprano Tab.
    func present(_ model: SwitcherViewModel, on screen: ScreenInfo)
    /// Redraws in place (selection, hover, tiles, layout).
    func update(_ model: SwitcherViewModel)
    /// Swaps one tile's thumbnail without a full redraw.
    func updateThumbnail(_ image: CGImage, for id: ItemID)
    /// Hides the panel and the preview, fading out when `animated`.
    func dismiss(animated: Bool)
    /// Shows `image` at `frame` (global Quartz coordinates) below the panel as the preview
    /// of the selected window; nil hides the preview.
    func showPreview(_ image: CGImage?, frame: CGRect?, fadeIn: Bool)
    /// Gives the search field keyboard focus (the panel becomes key without activating the
    /// app) or takes it away.
    func setSearchFocused(_ focused: Bool)

    /// The pointer entered a tile (index) or left all tiles (nil).
    var onHover: ((Int?) -> Void)? { get set }
    var onClick: ((Int) -> Void)? { get set }
    var onControl: ((Int, TileControl) -> Void)? { get set }
    /// The search text changed (the user typed into the focused search field; text keys
    /// reach it because the keyboard tap passes them through while searching).
    var onQueryChange: ((String) -> Void)? { get set }

    /// Renders a `screen.frame`-sized image: `backdrop` (or the theme's base color), the
    /// preview if shown, and the panel at its on-screen position. For the snapshot harness;
    /// works offscreen. nil when nothing is presented.
    func renderSnapshot(screen: ScreenInfo, backdrop: CGImage?) -> CGImage?
}

/// What `SwitcherController` needs from the app, injectable so the snapshot harness and the
/// tests run it deterministically.
struct SwitcherEnvironment {
    var settings: @MainActor () -> SopranoTabSettings
    /// The theme for a shortcut's override id, or the global theme for nil.
    var theme: @MainActor (_ overrideID: String?) -> AppTheme
    /// Runs `work` after `milliseconds` on the main actor and returns a cancel closure.
    var schedule: @MainActor (_ milliseconds: Int, _ work: @escaping @MainActor () -> Void) -> (() -> Void)
    /// Trackpad haptic tick for gesture steps.
    var haptic: @MainActor () -> Void
}
