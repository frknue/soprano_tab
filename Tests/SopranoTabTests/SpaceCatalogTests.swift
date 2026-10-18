import AppKit
import Testing
@testable import SopranoTab
@testable import SopranoTabCore

struct SpaceCatalogTests {
    private static let leftUUID = "11111111-AAAA-4000-8000-000000000001"
    private static let rightUUID = "22222222-BBBB-4000-8000-000000000002"
    private static let mainDisplayID: DisplayID = 1

    private func parse(_ displays: [[String: Any]]) -> [SpaceInfo] {
        let displayIDs: [String: DisplayID] = [Self.leftUUID: 10, Self.rightUUID: 20]
        return SpaceCatalog.spaces(
            from: displays,
            displayIDForUUID: { displayIDs[$0] },
            mainDisplayID: Self.mainDisplayID
        )
    }

    private func display(_ identifier: String, current: UInt64, spaces: [[String: Any]]) -> [String: Any] {
        ["Display Identifier": identifier, "Current Space": ["id64": current], "Spaces": spaces]
    }

    @Test("spaces are numbered from 1 across displays in display order")
    func indexesRunAcrossDisplays() {
        let spaces = parse([
            display(Self.leftUUID, current: 3, spaces: [["id64": 3, "type": 0], ["id64": 5, "type": 0]]),
            display(Self.rightUUID, current: 8, spaces: [["id64": 8, "type": 0]]),
        ])

        #expect(spaces.map(\.id) == [3, 5, 8])
        #expect(spaces.map(\.index) == [1, 2, 3])
        #expect(spaces.map(\.displayID) == [10, 10, 20])
    }

    @Test("the Main identifier maps to the main display")
    func mainIdentifierUsesMainDisplay() {
        let spaces = parse([display("Main", current: 4, spaces: [["id64": 4, "type": 0]])])

        #expect(spaces == [SpaceInfo(id: 4, index: 1, displayID: Self.mainDisplayID, isVisible: true)])
    }

    @Test("only each display's current Space is visible")
    func currentSpaceIsVisible() {
        let spaces = parse([
            display(Self.leftUUID, current: 5, spaces: [["id64": 3, "type": 0], ["id64": 5, "type": 0]]),
            display(Self.rightUUID, current: 8, spaces: [["id64": 8, "type": 0], ["id64": 9, "type": 0]]),
        ])

        #expect(spaces.filter(\.isVisible).map(\.id) == [5, 8])
    }

    @Test("a Space of type 4 is a fullscreen Space")
    func fullscreenType() {
        let spaces = parse([
            display(Self.leftUUID, current: 3, spaces: [["id64": 3, "type": 0], ["id64": 7, "type": 4]]),
        ])

        #expect(spaces.map(\.isFullscreen) == [false, true])
    }

    @Test("ManagedSpaceID identifies a Space without id64")
    func managedSpaceIDFallback() {
        let spaces = parse([
            ["Display Identifier": Self.leftUUID,
             "Current Space": ["ManagedSpaceID": 12],
             "Spaces": [["ManagedSpaceID": 12, "type": 0]]],
        ])

        #expect(spaces == [SpaceInfo(id: 12, index: 1, displayID: 10, isVisible: true)])
    }

    @Test("Spaces without an id and displays without a known identifier are skipped without taking an index")
    func missingFieldsAreSkipped() {
        let spaces = parse([
            ["Current Space": ["id64": 1], "Spaces": [["id64": 1, "type": 0]]],
            display("33333333-CCCC-4000-8000-000000000003", current: 2, spaces: [["id64": 2, "type": 0]]),
            ["Display Identifier": Self.leftUUID, "Current Space": ["id64": 6]],
            display(Self.rightUUID, current: 8, spaces: [["type": 0], ["id64": 8, "type": 0]]),
        ])

        #expect(spaces == [SpaceInfo(id: 8, index: 1, displayID: 20, isVisible: true)])
    }

    @Test("a display without a current Space lists its Spaces as not visible")
    func missingCurrentSpace() {
        let spaces = parse([
            ["Display Identifier": Self.leftUUID, "Spaces": [["id64": 3, "type": 0]]],
        ])

        #expect(spaces == [SpaceInfo(id: 3, index: 1, displayID: 10, isVisible: false)])
    }
}
