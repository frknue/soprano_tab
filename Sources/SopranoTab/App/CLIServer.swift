import AppKit
import OSLog
import SopranoTabCore

private let cliLog = Logger(subsystem: "com.soprano.tab", category: "cli")

/// Answers `SopranoTab <command>` from the running app: a local `CFMessagePort` named
/// `<bundle id>.cli` on the main run loop, JSON `CLIRequest` in, JSON `CLIResponse` out.
@MainActor
final class CLIServer {
    /// The port both sides use.
    nonisolated static var portName: String {
        "\(Bundle.main.bundleIdentifier ?? "com.soprano.tab").cli"
    }

    private let controller: SwitcherController
    private let source: WindowSource
    private let actions: WindowActing
    private var port: CFMessagePort?
    private var runLoopSource: CFRunLoopSource?

    init(controller: SwitcherController, source: WindowSource, actions: WindowActing) {
        self.controller = controller
        self.source = source
        self.actions = actions
    }

    /// Opens the port. Logs and stays inert when the name is taken (another instance).
    func start() {
        guard port == nil else { return }
        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        var shouldFreeInfo: DarwinBoolean = false
        let callback: CFMessagePortCallBack = { _, _, data, info in
            guard let info else { return nil }
            let request = data.map { $0 as Data }
            // Safe: the port's run loop source is on the main run loop, so assumeIsolated
            // holds and the pointer never crosses an isolation boundary.
            nonisolated(unsafe) let serverPointer = info
            let reply = MainActor.assumeIsolated {
                Unmanaged<CLIServer>.fromOpaque(serverPointer).takeUnretainedValue().reply(to: request)
            }
            return Unmanaged.passRetained(reply as CFData)
        }
        guard let port = CFMessagePortCreateLocal(nil, Self.portName as CFString, callback, &context, &shouldFreeInfo) else {
            cliLog.error("Could not open the CLI port \(Self.portName, privacy: .public)")
            return
        }
        let runLoopSource = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        self.port = port
        self.runLoopSource = runLoopSource
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let port {
            CFMessagePortInvalidate(port)
        }
        runLoopSource = nil
        port = nil
    }

    private func reply(to data: Data?) -> Data {
        let response: CLIResponse
        if let data, let request = try? JSONDecoder().decode(CLIRequest.self, from: data) {
            response = Self.response(for: request, source: source, actions: actions, controller: controller)
        } else {
            response = CLIResponse(ok: false, error: "Bad request.")
        }
        return (try? Self.encoder.encode(response)) ?? Data()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// The answer to one request. `list` returns every window (no windowless apps) in
    /// `lastFocusOrder`; `focusLastFocusOrder(n)` focuses the n-th of that list (0 = the
    /// most recently focused). `show` / `hide` need a controller.
    static func response(
        for request: CLIRequest,
        source: WindowSource,
        actions: WindowActing,
        controller: SwitcherController?
    ) -> CLIResponse {
        switch request {
        case .list(let detailed):
            source.refresh()
            let windows = focusOrderedWindows(in: source.snapshot)
            return CLIResponse(ok: true, windows: windows.map { CLIWindow(window: $0, detailed: detailed) })
        case .focus(let windowID):
            source.refresh()
            guard let window = source.snapshot.windows.first(where: { $0.windowID == windowID }) else {
                return CLIResponse(ok: false, error: "No window \(windowID)")
            }
            actions.focus(window)
            return CLIResponse(ok: true)
        case .focusLastFocusOrder(let order):
            source.refresh()
            let windows = focusOrderedWindows(in: source.snapshot)
            guard windows.indices.contains(order) else {
                return CLIResponse(ok: false, error: "No window at last focus order \(order)")
            }
            actions.focus(windows[order])
            return CLIResponse(ok: true)
        case .show(let shortcut):
            guard let controller else { return CLIResponse(ok: false, error: "The switcher is not available.") }
            let count = SettingsCenter.shared.settings.shortcuts.count
            guard (0..<count).contains(shortcut) else {
                return CLIResponse(ok: false, error: "No shortcut \(shortcut + 1); \(count) configured")
            }
            controller.show(shortcut: shortcut)
            return CLIResponse(ok: true)
        case .hide:
            guard let controller else { return CLIResponse(ok: false, error: "The switcher is not available.") }
            controller.hide()
            return CLIResponse(ok: true)
        }
    }

    private static func focusOrderedWindows(in snapshot: WindowSnapshot) -> [WindowInfo] {
        snapshot.windows
            .filter { !$0.isWindowlessApp }
            .sorted { lhs, rhs in
                if lhs.lastFocusOrder != rhs.lastFocusOrder { return lhs.lastFocusOrder < rhs.lastFocusOrder }
                return (lhs.windowID ?? 0) < (rhs.windowID ?? 0)
            }
    }
}
