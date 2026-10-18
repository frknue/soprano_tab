import AppKit
import Testing
@testable import SopranoTabCore

struct GridNavigatorTests {
    /// Rows of 4 tiles 100 wide, 2 tiles 150 wide and 1 tile 100 wide, 10 apart, each row
    /// centered in 430 pt: centers 50 160 270 380 / 135 295 / 215.
    private let grid: TileLayout = {
        let widths: [[CGFloat]] = [[100, 100, 100, 100], [150, 150], [100]]
        var frames: [CGRect] = []
        var rows: [Range<Int>] = []
        for (rowIndex, row) in widths.enumerated() {
            rows.append(frames.count..<(frames.count + row.count))
            var x = ((430 - (row.reduce(0, +) + CGFloat(row.count - 1) * 10)) / 2).rounded(.down)
            for width in row {
                frames.append(CGRect(x: x, y: CGFloat(rowIndex) * 110, width: width, height: 100))
                x += width + 10
            }
        }
        return TileLayout(
            resolvedSize: .medium,
            panelSize: CGSize(width: 462, height: 394),
            headerFrame: .zero,
            searchFieldFrame: nil,
            contentFrame: CGRect(x: 16, y: 48, width: 430, height: 330),
            contentSize: CGSize(width: 430, height: 330),
            tileFrames: frames,
            imageFrames: Array(repeating: .zero, count: frames.count),
            titleFrames: Array(repeating: .zero, count: frames.count),
            rows: rows
        )
    }()

    private func move(_ index: Int, _ command: SwitcherCommand) -> Int {
        GridNavigator.index(from: index, command: command, layout: grid)
    }

    @Test("left and right step through the whole list and wrap")
    func leftRight() {
        #expect(move(3, .moveRight) == 4)
        #expect(move(6, .moveRight) == 0)
        #expect(move(4, .moveLeft) == 3)
        #expect(move(0, .moveLeft) == 6)
    }

    @Test("down goes to the next row's tile with the nearest center")
    func down() {
        #expect(move(0, .moveDown) == 4)
        #expect(move(1, .moveDown) == 4)
        #expect(move(2, .moveDown) == 5)
        #expect(move(3, .moveDown) == 5)
        #expect(move(5, .moveDown) == 6)
    }

    @Test("up goes to the previous row's tile with the nearest center")
    func up() {
        #expect(move(4, .moveUp) == 1)
        #expect(move(5, .moveUp) == 2)
        // Center 215 is 80 from both 135 and 295: the earlier tile wins.
        #expect(move(6, .moveUp) == 4)
    }

    @Test("up from the first row wraps to the last row, down from the last to the first")
    func verticalWrap() {
        #expect(move(0, .moveUp) == 6)
        #expect(move(3, .moveUp) == 6)
        // Center 215 is 55 from both 160 and 270: the earlier tile wins.
        #expect(move(6, .moveDown) == 1)
    }

    @Test("a single row keeps vertical moves on the same tile")
    func singleRow() {
        var oneRow = grid
        oneRow.tileFrames = Array(grid.tileFrames[0..<4])
        oneRow.rows = [0..<4]
        #expect(GridNavigator.index(from: 2, command: .moveUp, layout: oneRow) == 2)
        #expect(GridNavigator.index(from: 2, command: .moveDown, layout: oneRow) == 2)
        #expect(GridNavigator.index(from: 3, command: .moveRight, layout: oneRow) == 0)
    }

    @Test("other commands and indexes outside the layout return the index unchanged")
    func passthrough() {
        #expect(move(2, .selectNext) == 2)
        #expect(move(2, .focusSelected) == 2)
        #expect(move(12, .moveRight) == 12)
        #expect(move(-1, .moveDown) == -1)
        let empty = TileLayout.compute(TileLayoutInput(style: .titles, size: .small, screenSize: CGSize(width: 1000, height: 800), itemSizes: []))
        #expect(GridNavigator.index(from: 0, command: .moveLeft, layout: empty) == 0)
    }
}
