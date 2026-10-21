import AppKit
import Testing
@testable import SopranoTab

@MainActor
struct SwitcherHeaderTests {
    private let hints = [
        KeyHint(key: "⇥", label: "next"), KeyHint(key: "⇧", label: "back"), KeyHint(key: "↩", label: "open"),
        KeyHint(key: "W", label: "close"), KeyHint(key: "M", label: "min"), KeyHint(key: "Q", label: "quit"),
        KeyHint(key: "S", label: "search"),
    ]

    private func header(width: CGFloat) -> SwitcherHeaderView {
        _ = NSApplication.shared
        let header = SwitcherHeaderView()
        header.frame = CGRect(x: 0, y: 0, width: width, height: 28)
        header.configure(heading: SwitcherHeading(subject: "All windows", count: 13), hints: hints, theme: .folioPaper)
        return header
    }

    @Test("a wide header shows every hint")
    func wideShowsAll() {
        #expect(header(width: 900).visibleHintCount == hints.count)
    }

    @Test("a narrow header drops whole hints from the end and keeps the first ones")
    func narrowDropsFromTheEnd() {
        let narrow = header(width: 328)
        #expect(narrow.visibleHintCount > 0)
        #expect(narrow.visibleHintCount < hints.count)
        #expect(header(width: 120).visibleHintCount == 0)
    }
}
