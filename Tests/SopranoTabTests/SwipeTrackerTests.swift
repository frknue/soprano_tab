import AppKit
import Testing
@testable import SopranoTabCore

struct SwipeTrackerTests {
    @Test("A swipe activates once past the distance and only when the axis dominates")
    func activationNeedsDistanceAndDominance() {
        var tracker = SwipeTracker(kind: .threeFingerHorizontal)
        #expect(tracker.handle(fingers(3, phase: .began)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.05)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.09, dy: 0.06)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.13, dy: 0.06)) == [.activate(reverse: false)])
        #expect(tracker.handle(fingers(3, dx: 0.14, dy: 0.06)).isEmpty)
    }

    @Test("Swiping left activates in reverse")
    func leftActivatesReversed() {
        var tracker = SwipeTracker(kind: .threeFingerHorizontal)
        _ = tracker.handle(fingers(3, phase: .began))
        #expect(tracker.handle(fingers(3, dx: -0.1)) == [.activate(reverse: true)])
    }

    @Test("Each further step distance emits one step in its direction")
    func stepsCountBothDirections() {
        var tracker = SwipeTracker(kind: .threeFingerHorizontal)
        _ = tracker.handle(fingers(3, phase: .began))
        #expect(tracker.handle(fingers(3, dx: 0.10)) == [.activate(reverse: false)])
        #expect(tracker.handle(fingers(3, dx: 0.15)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.19)) == [.step(reverse: false)])
        #expect(tracker.handle(fingers(3, dx: 0.35)) == [.step(reverse: false), .step(reverse: false)])
        #expect(tracker.handle(fingers(3, dx: 0.25)) == [.step(reverse: true)])
        #expect(tracker.handle(fingers(3, dx: 0.20)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.08)) == [.step(reverse: true), .step(reverse: true)])
    }

    @Test("Lifting a finger finishes once, then nothing until every touch ends")
    func finishThenRearm() {
        var tracker = SwipeTracker(kind: .threeFingerHorizontal)
        _ = tracker.handle(fingers(3, phase: .began))
        #expect(tracker.handle(fingers(3, dx: 0.1)) == [.activate(reverse: false)])

        var lifted = fingers(3, dx: 0.1)
        lifted[2].phase = .ended
        #expect(tracker.handle(lifted) == [.finish])
        #expect(tracker.handle(Array(fingers(3, dx: 0.3).prefix(2))).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.3)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.6)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.6, phase: .ended)).isEmpty)

        #expect(tracker.handle(fingers(3, phase: .began)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: -0.1)) == [.activate(reverse: true)])
        #expect(tracker.handle(fingers(3, dx: -0.1, phase: .cancelled)) == [.finish])
        #expect(tracker.handle(fingers(3, phase: .began)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.1)) == [.activate(reverse: false)])
    }

    @Test("Lifting before activation finishes nothing")
    func liftBeforeActivationIsSilent() {
        var tracker = SwipeTracker(kind: .threeFingerHorizontal)
        _ = tracker.handle(fingers(3, phase: .began))
        _ = tracker.handle(fingers(3, dx: 0.04))
        #expect(tracker.handle(fingers(3, dx: 0.04, phase: .ended)).isEmpty)
    }

    @Test("Only the configured finger count swipes; disabled never does")
    func wrongFingerCountIgnored() {
        var three = SwipeTracker(kind: .threeFingerHorizontal)
        _ = three.handle(fingers(4, phase: .began))
        #expect(three.handle(fingers(4, dx: 0.2)).isEmpty)

        var four = SwipeTracker(kind: .fourFingerHorizontal)
        _ = four.handle(fingers(3, phase: .began))
        #expect(four.handle(fingers(3, dx: 0.2)).isEmpty)
        _ = four.handle(fingers(4, dx: 0.2))
        #expect(four.handle(fingers(4, dx: 0.3)) == [.activate(reverse: false)])

        var disabled = SwipeTracker(kind: .disabled)
        for count in 3...4 {
            _ = disabled.handle(fingers(count, phase: .began))
            #expect(disabled.handle(fingers(count, dx: 0.3)).isEmpty)
        }
    }

    @Test("A finger-count change before activation restarts the distance")
    func fingerCountChangeResetsBaseline() {
        var tracker = SwipeTracker(kind: .threeFingerHorizontal)
        _ = tracker.handle(fingers(3, phase: .began))
        #expect(tracker.handle(fingers(4, dx: 0.05)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.06)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.12)).isEmpty)
        #expect(tracker.handle(fingers(3, dx: 0.15)) == [.activate(reverse: false)])
    }

    @Test("Vertical swipes go forward downwards and ignore sideways motion")
    func verticalAxisDirection() {
        var down = SwipeTracker(kind: .threeFingerVertical)
        _ = down.handle(fingers(3, phase: .began))
        #expect(down.handle(fingers(3, dx: 0.3)).isEmpty)

        var forward = SwipeTracker(kind: .fourFingerVertical)
        _ = forward.handle(fingers(4, phase: .began))
        #expect(forward.handle(fingers(4, dy: -0.1)) == [.activate(reverse: false)])
        #expect(forward.handle(fingers(4, dy: -0.19)) == [.step(reverse: false)])

        var backward = SwipeTracker(kind: .threeFingerVertical)
        _ = backward.handle(fingers(3, phase: .began))
        #expect(backward.handle(fingers(3, dy: 0.1)) == [.activate(reverse: true)])
    }

    @Test("Reset forgets an activated swipe")
    func resetForgetsSwipe() {
        var tracker = SwipeTracker(kind: .threeFingerHorizontal)
        _ = tracker.handle(fingers(3, phase: .began))
        _ = tracker.handle(fingers(3, dx: 0.1))
        tracker.reset()
        #expect(tracker.handle(fingers(3, dx: 0.1, phase: .ended)).isEmpty)
    }

    /// `count` fingers spread across the pad, each moved by (`dx`, `dy`) from its start.
    private func fingers(_ count: Int, dx: CGFloat = 0, dy: CGFloat = 0, phase: TouchSample.Phase = .moved) -> [TouchSample] {
        (0..<count).map { index in
            TouchSample(
                id: index,
                position: CGPoint(x: 0.2 + 0.1 * CGFloat(index) + dx, y: 0.5 + dy),
                phase: phase
            )
        }
    }
}
