import AppKit
import OSLog
import SopranoTabCore

private let menuLog = Logger(subsystem: "com.soprano.tab", category: "menu-bar")

/// The status item and its menu. The icon follows `app.menuBarIcon` (removed while
/// `hidden`); the menu is rebuilt each time it opens, so the warning line and the Launch at
/// Login checkmark are always current.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let controller: SwitcherController
    private let settings: SettingsCenter
    private let openPermissions: @MainActor () -> Void
    private var statusItem: NSStatusItem?
    private var appliedIcon: MenuBarIcon?

    init(
        controller: SwitcherController,
        settings: SettingsCenter = .shared,
        openPermissions: @escaping @MainActor () -> Void
    ) {
        self.controller = controller
        self.settings = settings
        self.openPermissions = openPermissions
        super.init()
        apply()
    }

    /// Re-applies `app.menuBarIcon`.
    func apply() {
        let icon = settings.settings.app.menuBarIcon
        guard icon != appliedIcon else { return }
        appliedIcon = icon
        guard icon != .hidden else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            return
        }
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.statusImage(filled: icon == .filled)
        item.button?.toolTip = "Soprano Tab"
        if item.menu == nil {
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
        }
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Show Switcher", action: #selector(showSwitcher)))
        menu.addItem(.separator())
        menu.addItem(item("Open settings.json…", action: #selector(openSettingsFile), key: ","))
        let issues = settings.issues
        if !issues.isEmpty {
            let count = issues.count
            let warning = NSMenuItem(
                title: "settings.json: \(count) warning\(count == 1 ? "" : "s")",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            warning.toolTip = issues.map { issue in
                issue.line.map { "line \($0): \(issue.message)" } ?? issue.message
            }.joined(separator: "\n")
            menu.addItem(warning)
        }
        menu.addItem(item("Permissions…", action: #selector(showPermissions)))
        menu.addItem(.separator())
        let launchAtLogin = item("Launch at Login", action: #selector(toggleLaunchAtLogin))
        launchAtLogin.state = settings.settings.app.startAtLogin ? .on : .off
        menu.addItem(launchAtLogin)
        menu.addItem(item("About Soprano Tab", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Soprano Tab", action: #selector(quit), key: "q"))
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showSwitcher() {
        controller.show(shortcut: 0)
    }

    @objc private func openSettingsFile() {
        settings.openInEditor()
    }

    @objc private func showPermissions() {
        openPermissions()
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = !settings.settings.app.startAtLogin
        do {
            try settings.write(enabled, at: ["app", "startAtLogin"])
        } catch {
            menuLog.error("Could not write app.startAtLogin: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Soprano Tab",
            .applicationVersion: AppVersion.current,
            .version: "",
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// The Folio 16 pt template glyph (b/components.css `.tpl` Tab): an open back sheet, a
    /// front sheet, and a → in it; 1.5 pt strokes with round caps and joins. Outlined
    /// strokes the front sheet; filled fills it and knocks the arrow out of it.
    static func statusImage(filled: Bool) -> NSImage {
        // SVG coordinates (top-left origin, 16 × 16 view box).
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            let lineWidth: CGFloat = 1.5
            NSColor.black.set()

            // M5.5 9.5 H3 A1.5 … 1.5 8 V4 A1.5 … 3 2.5 h6 A1.5 … 10.5 4 v2.5
            let back = NSBezierPath()
            back.move(to: NSPoint(x: 5.5, y: 9.5))
            back.line(to: NSPoint(x: 3, y: 9.5))
            back.appendArc(from: NSPoint(x: 1.5, y: 9.5), to: NSPoint(x: 1.5, y: 8), radius: 1.5)
            back.line(to: NSPoint(x: 1.5, y: 4))
            back.appendArc(from: NSPoint(x: 1.5, y: 2.5), to: NSPoint(x: 3, y: 2.5), radius: 1.5)
            back.line(to: NSPoint(x: 9, y: 2.5))
            back.appendArc(from: NSPoint(x: 10.5, y: 2.5), to: NSPoint(x: 10.5, y: 4), radius: 1.5)
            back.line(to: NSPoint(x: 10.5, y: 6.5))

            // rect 5.5, 6.5, 9 × 7, rx 1.5
            let front = NSBezierPath(roundedRect: NSRect(x: 5.5, y: 6.5, width: 9, height: 7), xRadius: 1.5, yRadius: 1.5)

            // M8.3 10 h3.4 · M10.6 8.8 L11.8 10 l-1.2 1.2
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 8.3, y: 10))
            arrow.line(to: NSPoint(x: 11.7, y: 10))
            arrow.move(to: NSPoint(x: 10.6, y: 8.8))
            arrow.line(to: NSPoint(x: 11.8, y: 10))
            arrow.line(to: NSPoint(x: 10.6, y: 11.2))

            for path in [back, front, arrow] {
                path.lineWidth = lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
            }
            back.stroke()
            front.stroke()
            if filled {
                front.fill()
                NSGraphicsContext.current?.compositingOperation = .clear
                arrow.stroke()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            } else {
                arrow.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Soprano Tab"
        return image
    }
}
