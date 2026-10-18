import AppKit
import SopranoTabCore

/// The switcher's state machine: turns key events, swipes and pointer input into a
/// `SwitcherSession`, runs window actions on its items and keeps the presenter drawing the
/// current `SwitcherViewModel`. Everything outside it (catalog, captures, actions, icons,
/// drawing, settings, timing) comes in through protocols, so the tests and the snapshot
/// harness run it on fixtures.
@MainActor
final class SwitcherController {
    /// Thumbnail size for captures made while the switcher is closed.
    static let backgroundCapturePixelSize: CGFloat = 640
    /// At most one background capture per this interval.
    static let backgroundCaptureIntervalMs = 2000
    /// Largest preview capture, in pixels.
    static let maxPreviewPixelSize: CGFloat = 2048

    private let source: WindowSource
    private let thumbnails: ThumbnailProvider
    private let actions: WindowActing
    private let icons: AppIconProvider
    private let presenter: SwitcherPresenting
    private let environment: SwitcherEnvironment

    /// The settings the router and tracker were built from; reloaded by `settingsDidChange`.
    private var settings: SopranoTabSettings
    private var router: SwitcherKeyRouter
    private var swipeTracker: SwipeTracker

    private(set) var session: SwitcherSession?
    /// The display the open switcher lists and draws on.
    private var screen: ScreenInfo?
    private var layout: TileLayout?
    private var hoveredIndex: Int?
    /// The panel is on screen; false while the show delay runs.
    private var isShown = false
    /// Bumped whenever a switcher opens or closes, so a stale scheduled present does nothing.
    private var generation = 0
    private var cancelPendingPresent: (() -> Void)?
    /// The item the preview currently shows (nil: nothing or a windowless/minimized item).
    private var previewedID: ItemID?
    private var isPreviewShown = false
    private var isBackgroundCaptureThrottled = false
    private var isBackgroundCaptureDue = false

    init(
        source: WindowSource,
        thumbnails: ThumbnailProvider,
        actions: WindowActing,
        icons: AppIconProvider,
        presenter: SwitcherPresenting,
        environment: SwitcherEnvironment
    ) {
        self.source = source
        self.thumbnails = thumbnails
        self.actions = actions
        self.icons = icons
        self.presenter = presenter
        self.environment = environment
        let settings = environment.settings()
        self.settings = settings
        router = SwitcherKeyRouter(shortcuts: settings.shortcuts, controls: settings.controls)
        swipeTracker = SwipeTracker(kind: settings.gesture.kind)

        source.onChange = { [weak self] in self?.catalogDidChange() }
        presenter.onHover = { [weak self] index in self?.pointerDidHover(index) }
        presenter.onClick = { [weak self] index in self?.pointerDidClick(index) }
        presenter.onControl = { [weak self] index, control in self?.pointerDidPressControl(control, at: index) }
        presenter.onQueryChange = { [weak self] text in self?.searchTextDidChange(text) }
    }

    var isActive: Bool { session != nil }

    // MARK: - Input

    /// For the keyboard tap; true swallows the event.
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        let triggersEnabled = router.state != .idle
            || !ExceptionMatcher.shortcutsIgnored(in: source.snapshot, rules: settings.exceptions)
        let decision = router.handle(event, triggersEnabled: triggersEnabled)
        if let action = decision.action {
            perform(action)
        }
        return decision.consume
    }

    /// For the gesture tap. The swipe opens the gesture's list at once, steps through it
    /// with a haptic tick per step, and focuses the selection when the fingers lift.
    func handleTouches(_ touches: [TouchSample]) {
        let gestureIndex = SopranoTabSettings.gestureIndex
        for action in swipeTracker.handle(touches) {
            switch action {
            case .activate(let reverse):
                guard session == nil else { continue }
                router.activateWithoutHold(shortcut: gestureIndex)
                open(shortcut: gestureIndex, reverse: reverse, immediately: true)
            case .step(let reverse):
                guard session?.shortcutIndex == gestureIndex else { continue }
                advance(reverse: reverse)
                if settings.gesture.hapticFeedback {
                    environment.haptic()
                }
            case .finish:
                guard session?.shortcutIndex == gestureIndex else { continue }
                focusSelected()
            }
        }
    }

    /// Opens without held keys (menu, CLI `show`): presents at once, stays open until
    /// Return, Escape, a click or `hide()`. Unknown shortcut indexes are ignored.
    func show(shortcut: Int) {
        guard settings.shortcuts.indices.contains(shortcut) else { return }
        router.activateWithoutHold(shortcut: shortcut)
        open(shortcut: shortcut, reverse: false, immediately: true)
    }

    /// Closes without focusing.
    func hide() {
        close()
    }

    /// The search text changed (from the presenter, or the harness). Begins search first
    /// when it is not running yet.
    func searchTextDidChange(_ text: String) {
        guard session != nil else { return }
        if session?.isSearching == false {
            beginSearch()
        }
        session?.setQuery(text)
        relayout()
        render()
        updatePreview()
    }

    /// Rebuilds the router and swipe tracker; closes an open switcher first.
    func settingsDidChange() {
        close()
        settings = environment.settings()
        router = SwitcherKeyRouter(shortcuts: settings.shortcuts, controls: settings.controls)
        swipeTracker = SwipeTracker(kind: settings.gesture.kind)
    }

    private func perform(_ action: TriggerAction) {
        switch action {
        case .activate(let shortcut, let reverse):
            open(shortcut: shortcut, reverse: reverse, immediately: false)
        case .advance(let reverse):
            advance(reverse: reverse)
        case .release:
            release()
        case .command(let command):
            perform(command)
        }
    }

    private func perform(_ command: SwitcherCommand) {
        guard let session else { return }
        let item = session.selectedItem
        switch command {
        case .selectNext:
            advance(reverse: false)
        case .selectPrevious:
            advance(reverse: true)
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            guard let layout else { return }
            self.session?.move(command, layout: layout)
            selectionDidChange()
        case .focusSelected:
            focusSelected()
        case .cancel:
            close()
        case .closeWindow:
            if let item { closeWindow(item) }
        case .toggleMinimize:
            if let item { toggleMinimize(item) }
        case .toggleFullscreen:
            if let item { toggleFullscreen(item) }
        case .quitApp:
            if let item { quitApp(item) }
        case .toggleHideApp:
            if let item { actions.toggleHideApp(item) }
        case .beginSearch:
            beginSearch()
        }
    }

    private func advance(reverse: Bool) {
        guard session != nil else { return }
        if reverse {
            session?.selectPrevious()
        } else {
            session?.selectNext()
        }
        selectionDidChange()
    }

    /// The hold modifiers went up: per the shortcut's `onRelease`. While searching the
    /// switcher stays open (letting go of ⌥ to type must not switch windows).
    private func release() {
        guard let session, !session.isSearching else { return }
        switch settings.onRelease(forShortcut: session.shortcutIndex) {
        case .focus:
            focusSelected()
        case .hold:
            if !isShown { present() }
        case .search:
            beginSearch()
        }
    }

    // MARK: - Opening and closing

    /// Builds the session for `shortcut` and presents it, at once or after
    /// `appearance.showDelayMs`. A release before the delay ends focuses the selection
    /// without the panel ever showing (a quick ⌥⇥ switches to the previous window).
    private func open(shortcut: Int, reverse: Bool, immediately: Bool) {
        tearDown()
        source.refresh()
        let snapshot = source.snapshot
        guard let screen = ScreenChooser.screen(for: settings.appearance.screen, in: snapshot) else {
            router.reset()
            return
        }
        let items = listedItems(forShortcut: shortcut, in: snapshot, on: screen)
        session = SwitcherSession(
            items: items,
            shortcutIndex: shortcut,
            focusedWindowID: snapshot.focusedWindowID,
            reverse: reverse
        )
        self.screen = screen
        generation += 1
        relayout()
        requestThumbnails(for: items)

        if immediately {
            present()
            return
        }
        let openGeneration = generation
        let cancel = environment.schedule(settings.appearance.showDelayMs) { [weak self] in
            guard let self, self.generation == openGeneration, self.session != nil, !self.isShown else { return }
            self.cancelPendingPresent = nil
            self.present()
        }
        // An immediate scheduler has already run `work`; only a pending present is cancellable.
        if generation == openGeneration, session != nil, !isShown {
            cancelPendingPresent = cancel
        }
    }

    private func present() {
        guard let screen, let model = makeModel() else { return }
        cancelPendingPresent?()
        cancelPendingPresent = nil
        isShown = true
        presenter.present(model, on: screen)
        updatePreview()
    }

    /// Hides the panel and the preview, cancels a pending present and resets the router.
    private func close() {
        tearDown()
        router.reset()
    }

    /// Everything `close` does except resetting the router (an activation that replaces
    /// an open switcher has already moved the router to its new state).
    private func tearDown() {
        guard session != nil else { return }
        generation += 1
        cancelPendingPresent?()
        cancelPendingPresent = nil
        if isShown {
            if isPreviewShown {
                presenter.showPreview(nil, frame: nil, fadeIn: false)
            }
            if session?.isSearching == true {
                presenter.setSearchFocused(false)
            }
            presenter.dismiss(animated: settings.appearance.fadeOut)
        }
        isShown = false
        isPreviewShown = false
        previewedID = nil
        session = nil
        screen = nil
        layout = nil
        hoveredIndex = nil
    }

    // MARK: - Actions

    /// Focuses `session.selectedItem` (closing an empty switcher).
    private func focusSelected() {
        guard let item = session?.selectedItem else {
            close()
            return
        }
        actions.focus(item)
        if cursorFollows(to: item) {
            actions.moveCursor(toCenterOf: item)
        }
        close()
    }

    private func cursorFollows(to item: WindowInfo) -> Bool {
        guard !item.isWindowlessApp else { return false }
        switch settings.mouse.cursorFollowsFocus {
        case .never:
            return false
        case .always:
            return true
        case .differentScreen:
            let snapshot = source.snapshot
            return item.displayID != snapshot.screen(containing: snapshot.mouseLocation)?.id
        }
    }

    /// Windowless apps have no window to close. The tile stays until the catalog reports
    /// the window gone: the app may refuse or ask first ("Save changes?").
    private func closeWindow(_ item: WindowInfo) {
        guard !item.isWindowlessApp else { return }
        actions.close(item)
    }

    /// The app's tiles stay until the catalog reports it terminated (Finder refuses to
    /// quit unless its Quit menu item is enabled; apps may ask to save).
    private func quitApp(_ item: WindowInfo) {
        actions.quitApp(item)
    }

    /// The item stays; its badges follow from the catalog update the action causes.
    private func toggleMinimize(_ item: WindowInfo) {
        guard !item.isWindowlessApp else { return }
        actions.toggleMinimize(item)
    }

    private func toggleFullscreen(_ item: WindowInfo) {
        guard !item.isWindowlessApp else { return }
        actions.toggleFullscreen(item)
    }

    private func beginSearch() {
        guard let session, !session.isSearching else { return }
        self.session?.beginSearch()
        router.setSearching(true)
        relayout()
        if isShown {
            render()
        } else {
            present()
        }
        presenter.setSearchFocused(true)
    }

    // MARK: - Pointer

    private func pointerDidHover(_ index: Int?) {
        guard let session else { return }
        let index = index.flatMap { session.items.indices.contains($0) ? $0 : nil }
        guard index != hoveredIndex else { return }
        hoveredIndex = index
        if let index, settings.mouse.hoverSelects {
            self.session?.select(index: index)
            selectionDidChange()
        } else {
            render()
        }
    }

    private func pointerDidClick(_ index: Int) {
        guard let session, session.items.indices.contains(index) else { return }
        self.session?.select(index: index)
        focusSelected()
    }

    private func pointerDidPressControl(_ control: TileControl, at index: Int) {
        guard let session, session.items.indices.contains(index) else { return }
        let item = session.items[index]
        switch control {
        case .close:
            closeWindow(item)
        case .minimize:
            toggleMinimize(item)
        case .fullscreen:
            toggleFullscreen(item)
        }
    }

    // MARK: - Catalog and thumbnails

    private func catalogDidChange() {
        let snapshot = source.snapshot
        thumbnails.prune(keeping: Set(snapshot.windows.compactMap(\.windowID)))
        if session != nil {
            refreshOpenSwitcher(with: snapshot)
        } else {
            captureInBackground()
        }
    }

    /// Live update: re-lists the shortcut's items, keeping the selection where possible.
    /// A list that a catalog change empties (the last window closed, its app quit) closes
    /// the switcher; a list empty at activation stays and shows "no windows".
    private func refreshOpenSwitcher(with snapshot: WindowSnapshot) {
        guard let session, let current = screen else { return }
        let screen = snapshot.screen(withID: current.id)
            ?? ScreenChooser.screen(for: settings.appearance.screen, in: snapshot)
            ?? current
        let items = listedItems(forShortcut: session.shortcutIndex, in: snapshot, on: screen)
        if items.isEmpty, !session.allItems.isEmpty {
            close()
            return
        }
        let knownIDs = Set(session.allItems.map(\.id))
        self.session?.update(items: items)
        self.screen = screen
        relayout()
        requestThumbnails(for: items.filter { !knownIDs.contains($0.id) })
        if isShown, screen != current, let model = makeModel() {
            presenter.present(model, on: screen)
        } else {
            render()
        }
        updatePreview()
    }

    private func listedItems(forShortcut index: Int, in snapshot: WindowSnapshot, on screen: ScreenInfo) -> [WindowInfo] {
        WindowListBuilder.items(
            from: snapshot,
            filters: settings.filters(forShortcut: index),
            exceptions: settings.exceptions,
            switcherDisplayID: screen.id
        )
    }

    /// Captures for the open switcher: the thumbnails style needs the largest image frame
    /// × the screen scale; the preview needs the window at full size, capped.
    private func requestThumbnails(for items: [WindowInfo]) {
        guard let session, let screen, let layout, thumbnails.canCapture else { return }
        let index = session.shortcutIndex
        let wantsThumbnails = settings.style(forShortcut: index) == .thumbnails
        let wantsPreview = settings.previewSelectedWindow(forShortcut: index)
        let windows = items.filter { !$0.isWindowlessApp }
        guard wantsThumbnails || wantsPreview, !windows.isEmpty else { return }

        var maxPixelSize: CGFloat = 0
        if wantsThumbnails {
            let longestImageSide = layout.imageFrames.map { max($0.width, $0.height) }.max() ?? 0
            maxPixelSize = longestImageSide * screen.scale
        }
        if wantsPreview {
            let longestWindowSide = windows.map { max($0.frame.width, $0.frame.height) }.max() ?? 0
            maxPixelSize = max(maxPixelSize, min(longestWindowSide * screen.scale, Self.maxPreviewPixelSize))
        }
        guard maxPixelSize > 0 else { return }
        thumbnails.requestThumbnails(for: windows, maxPixelSize: maxPixelSize) { [weak self] id, image in
            self?.thumbnailDidArrive(image, for: id)
        }
    }

    private func thumbnailDidArrive(_ image: CGImage, for windowID: WindowID) {
        guard isShown, let session else { return }
        let id = ItemID.window(windowID)
        guard session.items.contains(where: { $0.id == id }) else { return }
        if settings.style(forShortcut: session.shortcutIndex) == .thumbnails {
            presenter.updateThumbnail(image, for: id)
        }
        if session.selectedItem?.id == id {
            updatePreview(force: true)
        }
    }

    /// Keeps thumbnails fresh while the switcher is closed, at most once per
    /// `backgroundCaptureIntervalMs`; a change during the pause captures when it ends.
    private func captureInBackground() {
        guard settings.appearance.captureInBackground, thumbnails.canCapture else { return }
        guard !isBackgroundCaptureThrottled else {
            isBackgroundCaptureDue = true
            return
        }
        isBackgroundCaptureThrottled = true
        let windows = source.snapshot.windows.filter { window in
            !window.isWindowlessApp && !window.isMinimized && window.zIndex != nil
        }
        if !windows.isEmpty {
            thumbnails.requestThumbnails(for: windows, maxPixelSize: Self.backgroundCapturePixelSize) { [weak self] id, image in
                self?.thumbnailDidArrive(image, for: id)
            }
        }
        _ = environment.schedule(Self.backgroundCaptureIntervalMs) { [weak self] in
            guard let self else { return }
            self.isBackgroundCaptureThrottled = false
            if self.isBackgroundCaptureDue {
                self.isBackgroundCaptureDue = false
                if self.session == nil { self.captureInBackground() }
            }
        }
    }

    // MARK: - Drawing

    private func relayout() {
        guard let session, let screen else { return }
        let index = session.shortcutIndex
        layout = TileLayout.compute(TileLayoutInput(
            style: settings.style(forShortcut: index),
            size: settings.size(forShortcut: index),
            screenSize: screen.visibleFrame.size,
            itemSizes: session.items.map(\.frame.size),
            showsSearchField: session.isSearching
        ))
        if let hoveredIndex, !session.items.indices.contains(hoveredIndex) {
            self.hoveredIndex = nil
        }
    }

    private func makeModel() -> SwitcherViewModel? {
        guard let session, let layout else { return nil }
        let index = session.shortcutIndex
        let thumbnails = self.thumbnails
        let icons = self.icons
        return SwitcherModelBuilder.model(
            session: session,
            layout: layout,
            settings: settings,
            theme: environment.theme(settings.themeOverride(forShortcut: index)),
            style: settings.style(forShortcut: index),
            snapshot: source.snapshot,
            hoveredIndex: hoveredIndex,
            thumbnails: { thumbnails.cachedThumbnail(for: $0) },
            icons: { icons.icon(for: $0) }
        )
    }

    /// Redraws in place when the panel is shown.
    private func render() {
        guard isShown, let model = makeModel() else { return }
        presenter.update(model)
    }

    private func selectionDidChange() {
        render()
        updatePreview()
    }

    /// Shows the selected window behind the panel when the shortcut previews; nil for
    /// windowless and minimized items. Only calls the presenter when the selection changed,
    /// or with `force` (a fresh capture of the selected window arrived).
    private func updatePreview(force: Bool = false) {
        guard isShown, let session, settings.previewSelectedWindow(forShortcut: session.shortcutIndex) else { return }
        let item = session.selectedItem
        guard force || !isPreviewShown || item?.id != previewedID else { return }
        isPreviewShown = true
        previewedID = item?.id
        let fadeIn = settings.appearance.previewFadeIn
        if let item, let windowID = item.windowID, !item.isMinimized {
            presenter.showPreview(thumbnails.cachedThumbnail(for: windowID), frame: item.frame, fadeIn: fadeIn)
        } else {
            presenter.showPreview(nil, frame: nil, fadeIn: fadeIn)
        }
    }
}
