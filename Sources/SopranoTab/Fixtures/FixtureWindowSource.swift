import CoreGraphics
import SopranoTabCore

/// A window catalog that holds a fixed snapshot. Nothing changes unless a test, the
/// harness or `RecordingWindowActions` sets `snapshot`, which reports through `onChange`
/// right away (no coalescing).
@MainActor
final class FixtureWindowSource: WindowSource {
    var snapshot: WindowSnapshot {
        didSet { onChange?() }
    }

    var onChange: (() -> Void)?

    init(scenario: FixtureScenario, screenSize: CGSize = FixtureScenario.defaultScreenSize) {
        snapshot = scenario.snapshot(screenSize: screenSize)
    }

    init(snapshot: WindowSnapshot) {
        self.snapshot = snapshot
    }

    /// Applies `change` and reports it once.
    func mutate(_ change: (inout WindowSnapshot) -> Void) {
        var next = snapshot
        change(&next)
        snapshot = next
    }

    func start() {}

    func stop() {}

    /// The fixture is always current.
    func refresh() {}
}
