import CoreGraphics
import Foundation

/// Picks the display the switcher opens on.
public enum ScreenChooser {
    /// active: display of the focused window, else the one containing the mouse; withMouse:
    /// containing the mouse; withMenuBar: `hasMenuBar`. Falls back to the menu-bar screen,
    /// then the first screen. nil only when `snapshot.screens` is empty.
    public static func screen(for choice: ScreenChoice, in snapshot: WindowSnapshot) -> ScreenInfo? {
        let chosen: ScreenInfo?
        switch choice {
        case .active:
            chosen = focusedWindowScreen(in: snapshot) ?? snapshot.screen(containing: snapshot.mouseLocation)
        case .withMouse:
            chosen = snapshot.screen(containing: snapshot.mouseLocation)
        case .withMenuBar:
            chosen = nil
        }
        return chosen ?? snapshot.screens.first(where: \.hasMenuBar) ?? snapshot.screens.first
    }

    /// The focused window's display: its `displayID`, else the screen overlapping its frame most.
    private static func focusedWindowScreen(in snapshot: WindowSnapshot) -> ScreenInfo? {
        guard let focusedID = snapshot.focusedWindowID,
              let window = snapshot.windows.first(where: { $0.id == .window(focusedID) }),
              let displayID = window.displayID ?? Geometry.displayID(for: window.frame, in: snapshot.screens)
        else { return nil }
        return snapshot.screen(withID: displayID)
    }
}
