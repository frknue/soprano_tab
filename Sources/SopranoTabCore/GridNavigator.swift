import CoreGraphics
import Foundation

/// Arrow-key movement through the tile grid.
public enum GridNavigator {
    /// moveLeft/moveRight step through the whole list and wrap; moveUp/moveDown go to the
    /// adjacent row's tile whose horizontal center is nearest, wrapping from the first row
    /// to the last and back. Other commands return `index`.
    ///
    /// Equal distances pick the earlier tile. An index outside the layout is returned as is.
    public static func index(from index: Int, command: SwitcherCommand, layout: TileLayout) -> Int {
        let count = layout.tileFrames.count
        guard count > 0, (0..<count).contains(index) else { return index }
        switch command {
        case .moveRight:
            return (index + 1) % count
        case .moveLeft:
            return (index - 1 + count) % count
        case .moveUp, .moveDown:
            guard let row = layout.rows.firstIndex(where: { $0.contains(index) }) else { return index }
            let rowCount = layout.rows.count
            let step = command == .moveDown ? 1 : rowCount - 1
            let target = layout.rows[(row + step) % rowCount].filter { $0 < count }
            let center = layout.tileFrames[index].midX
            return target.min { lhs, rhs in
                let left = abs(layout.tileFrames[lhs].midX - center)
                let right = abs(layout.tileFrames[rhs].midX - center)
                return left != right ? left < right : lhs < rhs
            } ?? index
        default:
            return index
        }
    }
}
