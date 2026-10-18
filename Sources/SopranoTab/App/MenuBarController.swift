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

    /// The 18 pt template icon: two offset squares, the front one holding a ⇥ notch.
    /// Outlined strokes the front square; filled fills it and cuts the ⇥ out of it.
    static func statusImage(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let lineWidth: CGFloat = 1.5
            let back = NSRect(x: 1.75, y: 6.25, width: 10, height: 10)
            let front = NSRect(x: 6.25, y: 1.75, width: 10, height: 10)
            NSColor.black.set()

            let backPath = NSBezierPath(rect: back)
            backPath.lineWidth = lineWidth
            backPath.stroke()

            // The front square hides the back one where they overlap.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(rect: front.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            let frontPath = NSBezierPath(rect: front)
            frontPath.lineWidth = lineWidth
            if filled {
                frontPath.fill()
                frontPath.stroke()
            } else {
                frontPath.stroke()
            }

            // ⇥: an arrow to a bar, centered in the front square.
            let midY = front.midY
            let notch = NSBezierPath()
            notch.lineWidth = 1.25
            notch.lineCapStyle = .round
            notch.lineJoinStyle = .round
            notch.move(to: NSPoint(x: front.minX + 2.25, y: midY))
            notch.line(to: NSPoint(x: front.maxX - 3.25, y: midY))
            notch.move(to: NSPoint(x: front.maxX - 5.25, y: midY + 2))
            notch.line(to: NSPoint(x: front.maxX - 3.25, y: midY))
            notch.line(to: NSPoint(x: front.maxX - 5.25, y: midY - 2))
            notch.move(to: NSPoint(x: front.maxX - 2, y: midY + 2.5))
            notch.line(to: NSPoint(x: front.maxX - 2, y: midY - 2.5))
            if filled {
                NSGraphicsContext.current?.compositingOperation = .clear
                notch.stroke()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            } else {
                notch.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Soprano Tab"
        return image
    }
}
