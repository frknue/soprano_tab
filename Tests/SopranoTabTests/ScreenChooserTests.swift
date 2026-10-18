import AppKit
import Testing
@testable import SopranoTabCore

struct ScreenChooserTests {
    private let laptop = ScreenInfo(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 33, width: 1512, height: 949), hasMenuBar: false
    )
    private let monitor = ScreenInfo(
        id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: 25, width: 2560, height: 1415), hasMenuBar: true
    )
    private let app = AppInfo(pid: 1, bundleID: "test.app", name: "App")

    private func desktop(
        focusedDisplay: DisplayID?? = nil,
        focusedFrame: CGRect = CGRect(x: 10, y: 10, width: 300, height: 200),
        mouse: CGPoint,
        menuBarOnMonitor: Bool = true
    ) -> WindowSnapshot {
        var screens = [laptop, monitor]
        screens[1].hasMenuBar = menuBarOnMonitor
        var windows: [WindowInfo] = []
        var focusedID: WindowID?
        if let focusedDisplay {
            windows.append(WindowInfo(id: .window(5), app: app, title: "Focused", frame: focusedFrame, displayID: focusedDisplay))
            focusedID = 5
        }
        return WindowSnapshot(windows: windows, screens: screens, mouseLocation: mouse, frontmostPID: 1, focusedWindowID: focusedID)
    }

    @Test("active prefers the focused window's display over the mouse")
    func activeUsesFocusedWindow() {
        let snapshot = desktop(focusedDisplay: .some(1), mouse: CGPoint(x: 2000, y: 500))
        #expect(ScreenChooser.screen(for: .active, in: snapshot)?.id == 1)
    }

    @Test("active finds the focused window's screen from its frame when the display is unknown")
    func activeUsesFrameWithoutDisplay() {
        let snapshot = desktop(focusedDisplay: .some(nil), focusedFrame: CGRect(x: 1600, y: 100, width: 800, height: 600), mouse: CGPoint(x: 100, y: 100))
        #expect(ScreenChooser.screen(for: .active, in: snapshot)?.id == 2)
    }

    @Test("active without a focused window uses the screen with the mouse")
    func activeFallsBackToMouse() {
        let snapshot = desktop(mouse: CGPoint(x: 100, y: 100))
        #expect(ScreenChooser.screen(for: .active, in: snapshot)?.id == 1)
    }

    @Test("withMouse ignores the focused window")
    func withMouse() {
        let snapshot = desktop(focusedDisplay: .some(1), mouse: CGPoint(x: 3000, y: 700))
        #expect(ScreenChooser.screen(for: .withMouse, in: snapshot)?.id == 2)
    }

    @Test("withMenuBar picks the menu-bar screen")
    func withMenuBar() {
        let snapshot = desktop(focusedDisplay: .some(1), mouse: CGPoint(x: 100, y: 100))
        #expect(ScreenChooser.screen(for: .withMenuBar, in: snapshot)?.id == 2)
    }

    @Test("a mouse outside every screen falls back to the menu-bar screen, then the first screen")
    func fallbacks() {
        let offscreen = CGPoint(x: -500, y: -500)
        #expect(ScreenChooser.screen(for: .withMouse, in: desktop(mouse: offscreen))?.id == 2)
        #expect(ScreenChooser.screen(for: .active, in: desktop(mouse: offscreen))?.id == 2)
        #expect(ScreenChooser.screen(for: .withMouse, in: desktop(mouse: offscreen, menuBarOnMonitor: false))?.id == 1)
        #expect(ScreenChooser.screen(for: .withMenuBar, in: desktop(mouse: offscreen, menuBarOnMonitor: false))?.id == 1)
    }

    @Test("no screens gives nil for every choice")
    func noScreens() {
        for choice in ScreenChoice.allCases {
            #expect(ScreenChooser.screen(for: choice, in: WindowSnapshot(mouseLocation: CGPoint(x: 10, y: 10))) == nil)
        }
    }
}
