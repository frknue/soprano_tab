import AppKit
import Testing
@testable import SopranoTab
@testable import SopranoTabCore

@MainActor
struct SwitcherControllerTests {
    private func settings(_ change: (inout SopranoTabSettings) -> Void) -> SopranoTabSettings {
        var settings = SopranoTabSettings()
        change(&settings)
        return settings
    }

    private func itemIDs(_ harness: SwitcherHarness) -> [ItemID] {
        harness.controller.session?.items.map(\.id) ?? []
    }

    // MARK: - Activation and release

    @Test("Option-Tab opens on the window after the focused one and waits for the show delay")
    func activationSelectsNextWindow() {
        let harness = SwitcherHarness()
        #expect(harness.pressOptionTab())
        #expect(harness.controller.isActive)
        #expect(harness.selectedID == .window(3))
        #expect(!harness.presenter.isPresented)
        #expect(harness.scheduler.pendingDelays.contains(100))
    }

    @Test("A release before the show delay focuses the selection without ever presenting")
    func quickReleaseFocusesWithoutPresenting() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.setModifiers()
        #expect(harness.actions.log == [.focus(.window(3))])
        #expect(!harness.controller.isActive)
        harness.scheduler.fireAll()
        #expect(harness.presenter.presentCount == 0)
    }

    @Test("The show delay ending presents the list on the chosen screen")
    func delayPresents() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        #expect(harness.presenter.isPresented)
        #expect(harness.presenter.screen?.id == 1)
        #expect(harness.presenter.model?.tiles.map(\.id) == [.window(1), .window(3), .window(2), .window(4), .window(5)])
        #expect(harness.presenter.model?.selectedIndex == 1)
    }

    @Test("Tab advances and Shift-Tab steps back, redrawing the selection")
    func tabAdvances() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        #expect(harness.press(.tab, holding: .option))
        #expect(harness.selectedID == .window(2))
        #expect(harness.presenter.model?.selectedIndex == 2)
        harness.press(.tab, holding: [.option, .shift])
        #expect(harness.selectedID == .window(3))
    }

    @Test("Releasing Option focuses the selection and closes, and the next Option-Tab opens again")
    func releaseFocusesAndCloses() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        harness.press(.tab, holding: .option)
        harness.setModifiers()
        #expect(harness.actions.log == [.focus(.window(2))])
        #expect(!harness.controller.isActive)
        #expect(!harness.presenter.isPresented)
        #expect(harness.presenter.dismissCount == 1)

        #expect(harness.pressOptionTab())
        #expect(harness.controller.isActive)
    }

    @Test("With onRelease hold the switcher stays open after the release and Return focuses")
    func holdKeepsOpenUntilReturn() {
        let harness = SwitcherHarness(settings: settings { $0.shortcuts[0].onRelease = .hold })
        harness.pressOptionTab()
        harness.setModifiers()
        #expect(harness.controller.isActive)
        #expect(harness.presenter.isPresented)
        #expect(harness.actions.log.isEmpty)

        #expect(harness.press(.return))
        #expect(harness.actions.log == [.focus(.window(3))])
        #expect(!harness.controller.isActive)
    }

    @Test("Escape closes without any window action")
    func escapeCancels() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        #expect(harness.press(.escape, holding: .option))
        #expect(harness.actions.log.isEmpty)
        #expect(!harness.controller.isActive)
        #expect(harness.presenter.dismissCount == 1)
    }

    // MARK: - Window actions

    @Test("W closes the selected window and drops its tile")
    func closeRemovesItem() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        #expect(harness.type("w", holding: .option))
        #expect(harness.actions.log == [.close(.window(3))])
        #expect(harness.controller.isActive)
        #expect(!itemIDs(harness).contains(.window(3)))
        #expect(harness.presenter.model?.tiles.contains { $0.id == .window(3) } == false)
    }

    @Test("Q quits the selected app and drops every one of its tiles")
    func quitRemovesAppItems() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        harness.type("q", holding: .option)
        #expect(harness.actions.log == [.quitApp(SwitcherTestDesktop.browser.pid)])
        #expect(harness.controller.isActive)
        #expect(harness.controller.session?.allItems.contains { $0.app.pid == SwitcherTestDesktop.browser.pid } == false)
    }

    @Test("The catalog losing the last listed window closes the switcher")
    func emptiedListCloses() {
        let only = SwitcherTestDesktop.snapshot(windows: [SwitcherTestDesktop.windows[0]])
        let harness = SwitcherHarness(snapshot: only, settings: settings { $0.shortcuts[0].filters.windowlessApps = .hide })
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        harness.type("w", holding: .option)
        #expect(harness.actions.log == [.close(.window(1))])
        #expect(!harness.controller.isActive)
        #expect(!harness.presenter.isPresented)
    }

    @Test("A refused close or quit leaves every tile in place and the switcher open")
    func refusedActionsKeepItems() {
        let harness = SwitcherHarness(refusesActions: true)
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        let listed = itemIDs(harness)

        harness.type("w", holding: .option)
        harness.type("q", holding: .option)
        harness.presenter.onControl?(4, .close)
        #expect(harness.refusingActions.log == [
            .close(.window(3)), .quitApp(SwitcherTestDesktop.browser.pid), .close(.window(5)),
        ])
        #expect(harness.controller.isActive)
        #expect(itemIDs(harness) == listed)
        #expect(harness.presenter.model?.tiles.map(\.id) == listed)
        #expect(harness.selectedID == .window(3))
    }

    @Test("A list empty at activation shows no windows and stays open through catalog changes")
    func emptyAtActivationStaysOpen() {
        let harness = SwitcherHarness(
            snapshot: SwitcherTestDesktop.snapshot(windows: []),
            settings: settings { $0.shortcuts[0].onRelease = .hold }
        )
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        #expect(harness.presenter.model?.emptyText == "no windows")
        harness.source.mutate { $0.mouseLocation = CGPoint(x: 10, y: 10) }
        #expect(harness.controller.isActive)
        #expect(harness.presenter.isPresented)
    }

    // MARK: - Exceptions, show, settings

    @Test("An ignore-shortcuts exception for the frontmost app passes Option-Tab through")
    func exceptionPassesThrough() {
        let harness = SwitcherHarness(settings: settings {
            $0.exceptions = [ExceptionRule(bundleID: "test.editor", ignoreShortcuts: .always)]
        })
        #expect(!harness.pressOptionTab())
        #expect(!harness.controller.isActive)
        #expect(harness.actions.log.isEmpty)
    }

    @Test("show presents at once and stays open through modifier changes until Escape")
    func showStaysOpen() {
        let harness = SwitcherHarness()
        harness.controller.show(shortcut: 0)
        #expect(harness.presenter.presentCount == 1)
        #expect(harness.selectedID == .window(3))

        harness.setModifiers(.option)
        harness.setModifiers(.shift)
        harness.setModifiers()
        #expect(harness.controller.isActive)
        #expect(harness.presenter.isPresented)
        #expect(harness.actions.log.isEmpty)

        harness.press(.escape)
        #expect(!harness.controller.isActive)
    }

    @Test("A settings change closes an open switcher without focusing")
    func settingsChangeCloses() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        harness.settings.shortcuts[0].onRelease = .hold
        harness.controller.settingsDidChange()
        #expect(!harness.controller.isActive)
        #expect(!harness.presenter.isPresented)
        #expect(harness.actions.log.isEmpty)

        harness.pressOptionTab()
        harness.setModifiers()
        #expect(harness.controller.isActive)
    }

    // MARK: - Search

    @Test("S begins search, letters pass through to the field, and the query filters the list")
    func searchFilters() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        #expect(harness.type("s", holding: .option))
        #expect(harness.controller.session?.isSearching == true)
        #expect(harness.presenter.isSearchFocused)
        #expect(harness.presenter.model?.search != nil)
        #expect(harness.presenter.model?.layout.searchFieldFrame != nil)

        harness.setModifiers()
        #expect(harness.controller.isActive)
        #expect(!harness.type("x"))

        harness.controller.searchTextDidChange("news")
        #expect(itemIDs(harness) == [.window(4)])
        #expect(harness.presenter.model?.tiles.first?.highlightedRanges.isEmpty == false)

        harness.controller.searchTextDidChange("zzzz")
        #expect(harness.presenter.model?.tiles.isEmpty == true)
        #expect(harness.presenter.model?.emptyText == "no matches")
    }

    // MARK: - Pointer

    @Test("Hover highlights a tile and selects it only with hoverSelects")
    func hoverSelectsOnlyWhenEnabled() {
        let plain = SwitcherHarness()
        plain.pressOptionTab()
        plain.scheduler.fireAll()
        plain.presenter.onHover?(3)
        #expect(plain.presenter.model?.hoveredIndex == 3)
        #expect(plain.selectedID == .window(3))

        let selecting = SwitcherHarness(settings: settings { $0.mouse.hoverSelects = true })
        selecting.pressOptionTab()
        selecting.scheduler.fireAll()
        selecting.presenter.onHover?(3)
        #expect(selecting.presenter.model?.hoveredIndex == 3)
        #expect(selecting.presenter.model?.selectedIndex == 3)
        #expect(selecting.selectedID == .window(4))
    }

    @Test("Clicking a tile focuses its window and closes")
    func clickFocuses() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        harness.presenter.onClick?(2)
        #expect(harness.actions.log == [.focus(.window(2))])
        #expect(!harness.controller.isActive)
    }

    @Test("A tile's close lamp closes that tile's window, not the selected one")
    func controlLampCloses() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        harness.presenter.onControl?(4, .close)
        #expect(harness.actions.log == [.close(.window(5))])
        #expect(harness.controller.isActive)
        #expect(!itemIDs(harness).contains(.window(5)))
        #expect(harness.selectedID == .window(3))
    }

    // MARK: - Preview and cursor

    @Test("The preview follows the selection and hides for minimized windows")
    func previewFollowsSelection() {
        let harness = SwitcherHarness(settings: settings { $0.appearance.previewSelectedWindow = true })
        harness.pressOptionTab()
        #expect(harness.presenter.previewCalls.isEmpty)
        harness.scheduler.fireAll()
        #expect(harness.presenter.previewCalls.last?.frame == SwitcherTestDesktop.windows[2].frame)

        harness.press(.tab, holding: .option)
        #expect(harness.presenter.previewCalls.last?.frame == SwitcherTestDesktop.windows[1].frame)

        harness.press(.tab, holding: .option)
        #expect(harness.selectedID == .window(4))
        #expect(harness.presenter.previewCalls.last == RecordingPresenter.PreviewCall(hasImage: false, frame: nil, fadeIn: true))
    }

    @Test("cursorFollowsFocus always moves the cursor even on the same screen; differentScreen does not")
    func cursorFollowsFocus() {
        let always = SwitcherHarness(settings: settings { $0.mouse.cursorFollowsFocus = .always })
        always.pressOptionTab()
        always.setModifiers()
        #expect(always.actions.log == [.focus(.window(3)), .moveCursor(.window(3))])

        let different = SwitcherHarness(settings: settings { $0.mouse.cursorFollowsFocus = .differentScreen })
        different.pressOptionTab()
        different.setModifiers()
        #expect(different.actions.log == [.focus(.window(3))])
    }

    // MARK: - Catalog

    @Test("A catalog change while open lists the new window and keeps the selection")
    func liveUpdate() {
        let harness = SwitcherHarness()
        harness.pressOptionTab()
        harness.scheduler.fireAll()
        let fresh = SwitcherTestDesktop.window(6, SwitcherTestDesktop.terminal, "Logs", focus: 5, z: 4)
        harness.source.mutate { $0.windows.append(fresh) }
        #expect(itemIDs(harness).contains(.window(6)))
        #expect(harness.presenter.model?.tiles.count == 6)
        #expect(harness.selectedID == .window(3))
    }

    @Test("Catalog changes while closed capture in the background at most once per two seconds")
    func backgroundCaptureThrottles() {
        let harness = SwitcherHarness()
        let fresh = SwitcherTestDesktop.window(6, SwitcherTestDesktop.terminal, "Logs", focus: 5, z: 4)
        harness.source.mutate { $0.windows.append(fresh) }
        harness.source.mutate { $0.windows.removeLast() }
        #expect(harness.scheduler.pendingDelays == [2000])

        // The change during the pause captures once the pause ends, starting a new pause.
        harness.scheduler.fireAll()
        #expect(harness.scheduler.pendingDelays == [2000])
        harness.scheduler.fireAll()
        #expect(harness.scheduler.pendingDelays.isEmpty)
    }

    // MARK: - Gesture

    @Test("A three-finger swipe opens at once, steps with a haptic tick and focuses on lift")
    func gestureSwitches() {
        let harness = SwitcherHarness(settings: settings { $0.gesture.kind = .threeFingerHorizontal })
        func touches(_ x: CGFloat, _ phase: TouchSample.Phase) -> [TouchSample] {
            (1...3).map { TouchSample(id: $0, position: CGPoint(x: x, y: 0.3 + CGFloat($0) * 0.1), phase: phase) }
        }
        harness.controller.handleTouches(touches(0.3, .began))
        harness.controller.handleTouches(touches(0.4, .moved))
        #expect(harness.presenter.presentCount == 1)
        #expect(harness.selectedID == .window(3))

        harness.controller.handleTouches(touches(0.5, .moved))
        #expect(harness.selectedID == .window(2))
        #expect(harness.hapticCount == 1)

        harness.controller.handleTouches(touches(0.5, .ended))
        #expect(harness.actions.log == [.focus(.window(2))])
        #expect(!harness.controller.isActive)
    }
}
