import Foundation
import SopranoTabCore

/// `SopranoTab <command>`: sends one `CLIRequest` to the running app over its
/// `CFMessagePort` and prints the `CLIResponse`.
enum CLIClient {
    /// First arguments that select the CLI instead of the GUI.
    static let commands: Set<String> = ["list", "focus", "show", "hide", "help", "--help"]

    static let usage = """
    Usage: SopranoTab <command>

      list [--detailed]               List windows, most recently focused first
      focus <window-id>               Focus a window by its id (from list)
      focus --last-focus-order <n>    Focus the n-th most recently focused window (0 = current)
      show [<1-9>]                    Open the switcher for shortcut n (default 1)
      hide                            Close the switcher
      help                            Show this help

    """

    /// The request for command-line arguments (without the executable); nil for `help`
    /// and anything malformed.
    static func request(from arguments: [String]) -> CLIRequest? {
        guard let command = arguments.first else { return nil }
        let rest = Array(arguments.dropFirst())
        switch (command, rest.count) {
        case ("list", 0):
            return .list(detailed: false)
        case ("list", 1) where rest[0] == "--detailed":
            return .list(detailed: true)
        case ("focus", 1):
            return WindowID(rest[0]).map { .focus(windowID: $0) }
        case ("focus", 2) where rest[0] == "--last-focus-order":
            guard let order = Int(rest[1]), order >= 0 else { return nil }
            return .focusLastFocusOrder(order)
        case ("show", 0):
            return .show(shortcut: 0)
        case ("show", 1):
            guard let number = Int(rest[0]), (1...SopranoTabSettings.maxShortcuts).contains(number) else { return nil }
            return .show(shortcut: number - 1)
        case ("hide", 0):
            return .hide
        default:
            return nil
        }
    }

    /// Runs the command and exits: 0 with the response JSON on stdout (or the usage for
    /// `help`); 1 with the error on stderr; 2 with the usage on stderr for malformed arguments.
    static func run(arguments: [String]) -> Never {
        if let command = arguments.first, command == "help" || command == "--help" {
            print(usage, terminator: "")
            exit(0)
        }
        guard let request = request(from: arguments) else {
            fail(usage, status: 2)
        }
        let response: CLIResponse
        do {
            response = try send(request)
        } catch {
            fail("\(error.message)\n", status: 1)
        }
        guard response.ok else {
            fail("\(response.error ?? "The request failed.")\n", status: 1)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(response), let text = String(data: data, encoding: .utf8) else {
            fail("Could not encode the response.\n", status: 1)
        }
        print(text)
        exit(0)
    }

    struct Failure: Error {
        let message: String
    }

    private static func send(_ request: CLIRequest) throws(Failure) -> CLIResponse {
        guard let port = CFMessagePortCreateRemote(nil, CLIServer.portName as CFString) else {
            throw Failure(message: "Soprano Tab is not running.")
        }
        defer { CFMessagePortInvalidate(port) }
        guard let body = try? JSONEncoder().encode(request) else {
            throw Failure(message: "Could not encode the request.")
        }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            port,
            0,
            body as CFData,
            2,
            2,
            CFRunLoopMode.defaultMode.rawValue,
            &reply
        )
        let replyData = reply?.takeRetainedValue()
        guard status == kCFMessagePortSuccess, let replyData else {
            throw Failure(message: status == kCFMessagePortReceiveTimeout || status == kCFMessagePortSendTimeout
                ? "Soprano Tab did not answer."
                : "Soprano Tab is not running.")
        }
        guard let response = try? JSONDecoder().decode(CLIResponse.self, from: replyData as Data) else {
            throw Failure(message: "Soprano Tab sent an unreadable response.")
        }
        return response
    }

    private static func fail(_ message: String, status: Int32) -> Never {
        FileHandle.standardError.write(Data(message.utf8))
        exit(status)
    }
}
