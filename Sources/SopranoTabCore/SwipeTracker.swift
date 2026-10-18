import CoreGraphics
import Foundation

/// Turns batches of trackpad touches into a 3- or 4-finger swipe: activate once the
/// fingers travel far enough along the gesture's axis, step every further
/// `stepDistance`, finish when a finger lifts.
///
/// See docs/ARCHITECTURE.md → Core APIs → Input for the rules.
public struct SwipeTracker: Sendable {
    /// Trackpad widths (normalized 0...1) along the axis before the switcher opens.
    public static let activationDistance: CGFloat = 0.08
    /// Trackpad widths per selection step after activation.
    public static let stepDistance: CGFloat = 0.08

    private enum Axis: Sendable {
        case horizontal
        case vertical
    }

    private enum Phase: Sendable {
        /// Not swiping yet; `baseline` holds each finger's start while the count is right.
        case tracking(baseline: [Int: CGPoint]?)
        /// Activated; `anchor` is the axis displacement of the last emitted step.
        case swiping(baseline: [Int: CGPoint], anchor: CGFloat)
        /// Finished; ignores everything until every touch has ended.
        case waitingForLift
    }

    private let fingerCount: Int?
    private let axis: Axis
    private var phase: Phase = .tracking(baseline: nil)

    public init(kind: GestureKind) {
        switch kind {
        case .disabled:
            fingerCount = nil
            axis = .horizontal
        case .threeFingerHorizontal:
            fingerCount = 3
            axis = .horizontal
        case .threeFingerVertical:
            fingerCount = 3
            axis = .vertical
        case .fourFingerHorizontal:
            fingerCount = 4
            axis = .horizontal
        case .fourFingerVertical:
            fingerCount = 4
            axis = .vertical
        }
    }

    /// `touches` is every touch in one gesture event; ended and cancelled ones count as lifted.
    public mutating func handle(_ touches: [TouchSample]) -> [SwipeAction] {
        guard let fingerCount else { return [] }
        let down = touches.filter { $0.phase == .began || $0.phase == .moved || $0.phase == .stationary }
        switch phase {
        case .waitingForLift:
            if down.isEmpty { phase = .tracking(baseline: nil) }
            return []
        case let .tracking(baseline):
            guard down.count == fingerCount else {
                phase = .tracking(baseline: nil)
                return []
            }
            guard let baseline, Set(baseline.keys) == Set(down.map(\.id)) else {
                phase = .tracking(baseline: Self.positions(down))
                return []
            }
            let (along, across) = displacement(of: down, from: baseline)
            guard abs(along) >= Self.activationDistance, abs(along) >= 2 * abs(across) else { return [] }
            phase = .swiping(baseline: baseline, anchor: along)
            return [.activate(reverse: along < 0)]
        case let .swiping(baseline, anchor):
            if down.count < fingerCount {
                phase = down.isEmpty ? .tracking(baseline: nil) : .waitingForLift
                return [.finish]
            }
            // An extra finger landing mid-swipe moves nothing; the original fingers keep steering.
            let (along, _) = displacement(of: down, from: baseline)
            var anchor = anchor
            var actions: [SwipeAction] = []
            while along - anchor >= Self.stepDistance {
                anchor += Self.stepDistance
                actions.append(.step(reverse: false))
            }
            while anchor - along >= Self.stepDistance {
                anchor -= Self.stepDistance
                actions.append(.step(reverse: true))
            }
            phase = .swiping(baseline: baseline, anchor: anchor)
            return actions
        }
    }

    public mutating func reset() {
        phase = .tracking(baseline: nil)
    }

    private static func positions(_ touches: [TouchSample]) -> [Int: CGPoint] {
        Dictionary(touches.map { ($0.id, $0.position) }, uniquingKeysWith: { first, _ in first })
    }

    /// Mean displacement of the fingers present in `baseline`, split into the gesture's
    /// axis (positive = forward: right, or down with y decreasing) and the cross axis.
    private func displacement(of touches: [TouchSample], from baseline: [Int: CGPoint]) -> (along: CGFloat, across: CGFloat) {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var count: CGFloat = 0
        for touch in touches {
            guard let start = baseline[touch.id] else { continue }
            dx += touch.position.x - start.x
            dy += touch.position.y - start.y
            count += 1
        }
        guard count > 0 else { return (0, 0) }
        dx /= count
        dy /= count
        switch axis {
        case .horizontal: return (dx, dy)
        case .vertical: return (-dy, dx)
        }
    }
}
