import AppKit
import Testing
@testable import SopranoTab
@testable import SopranoTabCore

@MainActor
struct CLIRoundTripTests {
    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    /// The standard scenario's windows (no windowless apps), most recently focused first.
    private func focusOrdered(_ source: FixtureWindowSource) -> [WindowInfo] {
        source.snapshot.windows
            .filter { !$0.isWindowlessApp }
            .sorted { ($0.lastFocusOrder, $0.windowID ?? 0) < ($1.lastFocusOrder, $1.windowID ?? 0) }
    }

    @Test("every request survives encoding and decoding")
    func requestsRoundTrip() throws {
        let requests: [CLIRequest] = [
            .list(detailed: false),
            .list(detailed: true),
            .focus(windowID: 4242),
            .focusLastFocusOrder(3),
            .show(shortcut: 8),
            .hide,
        ]
        for request in requests {
            #expect(try roundTrip(request) == request)
        }
    }

    @Test("a response with detailed windows survives encoding and decoding")
    func detailedResponseRoundTrips() throws {
        let source = FixtureWindowSource(scenario: .standard)
        let windows = focusOrdered(source).map { CLIWindow(window: $0, detailed: true) }
        let response = CLIResponse(ok: true, windows: windows)

        #expect(!windows.isEmpty)
        #expect(try roundTrip(response) == response)
        #expect(try roundTrip(CLIResponse(ok: false, error: "No window 7")) == CLIResponse(ok: false, error: "No window 7"))
    }

    @Test("command-line arguments map to requests with 1-based shortcuts")
    func argumentsMapToRequests() {
        #expect(CLIClient.request(from: ["list"]) == .list(detailed: false))
        #expect(CLIClient.request(from: ["list", "--detailed"]) == .list(detailed: true))
        #expect(CLIClient.request(from: ["focus", "4242"]) == .focus(windowID: 4242))
        #expect(CLIClient.request(from: ["focus", "--last-focus-order", "2"]) == .focusLastFocusOrder(2))
        #expect(CLIClient.request(from: ["show"]) == .show(shortcut: 0))
        #expect(CLIClient.request(from: ["show", "1"]) == .show(shortcut: 0))
        #expect(CLIClient.request(from: ["show", "9"]) == .show(shortcut: 8))
        #expect(CLIClient.request(from: ["hide"]) == .hide)
    }

    @Test("help and malformed arguments give no request")
    func malformedArgumentsAreRejected() {
        #expect(CLIClient.request(from: ["help"]) == nil)
        #expect(CLIClient.request(from: ["--help"]) == nil)
        #expect(CLIClient.request(from: ["show", "0"]) == nil)
        #expect(CLIClient.request(from: ["show", "10"]) == nil)
        #expect(CLIClient.request(from: ["focus", "window"]) == nil)
        #expect(CLIClient.request(from: ["focus", "--last-focus-order", "-1"]) == nil)
        #expect(CLIClient.request(from: ["list", "--verbose"]) == nil)
        #expect(CLIClient.request(from: ["hide", "now"]) == nil)
    }

    @Test("list returns every window by last focus order and leaves out windowless apps")
    func listOrdersByLastFocus() throws {
        let source = FixtureWindowSource(scenario: .standard)
        let actions = RecordingWindowActions(source: source)

        let response = CLIServer.response(for: .list(detailed: true), source: source, actions: actions, controller: nil)

        let windows = try #require(response.windows)
        #expect(response.ok)
        #expect(source.snapshot.windows.contains { $0.isWindowlessApp })
        #expect(windows.map(\.id) == focusOrdered(source).compactMap(\.windowID))
        let orders = windows.compactMap(\.lastFocusOrder)
        #expect(orders == orders.sorted())
        #expect(actions.log.isEmpty)
    }

    @Test("a brief list carries only ids and titles")
    func briefListOmitsDetails() throws {
        let source = FixtureWindowSource(scenario: .standard)
        let actions = RecordingWindowActions(source: source)

        let response = CLIServer.response(for: .list(detailed: false), source: source, actions: actions, controller: nil)

        let windows = try #require(response.windows)
        #expect(!windows.isEmpty)
        #expect(windows.allSatisfy { $0.appName == nil && $0.lastFocusOrder == nil && $0.size == nil })
    }

    @Test("focusing an unknown window id fails without acting")
    func unknownWindowIsAnError() {
        let source = FixtureWindowSource(scenario: .standard)
        let actions = RecordingWindowActions(source: source)

        let response = CLIServer.response(for: .focus(windowID: 4_242_424), source: source, actions: actions, controller: nil)

        #expect(response == CLIResponse(ok: false, error: "No window 4242424"))
        #expect(actions.log.isEmpty)
    }

    @Test("focusing a window id focuses that window through the actions")
    func focusRecordsAction() throws {
        let source = FixtureWindowSource(scenario: .standard)
        let actions = RecordingWindowActions(source: source)
        let target = try #require(focusOrdered(source).last?.windowID)

        let response = CLIServer.response(for: .focus(windowID: target), source: source, actions: actions, controller: nil)

        #expect(response.ok)
        #expect(actions.log == [.focus(.window(target))])
    }

    @Test("focusing by last focus order counts from the most recent window")
    func focusByLastFocusOrder() throws {
        let source = FixtureWindowSource(scenario: .standard)
        let actions = RecordingWindowActions(source: source)
        let ordered = focusOrdered(source)
        let second = try #require(ordered.dropFirst().first?.windowID)

        let response = CLIServer.response(for: .focusLastFocusOrder(1), source: source, actions: actions, controller: nil)
        let outOfRange = CLIServer.response(
            for: .focusLastFocusOrder(ordered.count),
            source: source,
            actions: actions,
            controller: nil
        )

        #expect(response.ok)
        #expect(!outOfRange.ok)
        #expect(actions.log == [.focus(.window(second))])
    }
}
