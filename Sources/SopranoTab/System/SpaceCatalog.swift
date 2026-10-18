import Foundation
import SopranoTabCore

/// Parses `PrivateAPIs.managedDisplaySpaces()` (CGSCopyManagedDisplaySpaces) into
/// `SpaceInfo`s. Pure, so the parsing is tested without WindowServer.
enum SpaceCatalog {
    /// `type` of a fullscreen app's Space (0 is a user Space).
    static let fullscreenSpaceType = 4
    /// "Display Identifier" when displays do not have separate Spaces.
    static let mainDisplayIdentifier = "Main"

    /// Every Space in Mission Control order. `index` is 1-based and runs across displays in
    /// the order given; a display whose identifier is missing or unknown to
    /// `displayIDForUUID`, and a Space without an id, are skipped and take no index.
    /// "Main" maps to `mainDisplayID`. `isVisible` marks each display's "Current Space";
    /// `isFullscreen` marks Spaces of type 4.
    static func spaces(
        from displays: [[String: Any]],
        displayIDForUUID: (String) -> DisplayID?,
        mainDisplayID: DisplayID
    ) -> [SpaceInfo] {
        var result: [SpaceInfo] = []
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let displayID = identifier == mainDisplayIdentifier ? mainDisplayID : displayIDForUUID(identifier),
                  let spaces = display["Spaces"] as? [[String: Any]]
            else { continue }
            let currentID = (display["Current Space"] as? [String: Any]).flatMap(spaceID(of:))
            for space in spaces {
                guard let id = spaceID(of: space) else { continue }
                let type = (space["type"] as? NSNumber)?.intValue
                result.append(SpaceInfo(
                    id: id,
                    index: result.count + 1,
                    displayID: displayID,
                    isVisible: id == currentID,
                    isFullscreen: type == fullscreenSpaceType
                ))
            }
        }
        return result
    }

    /// A Space dictionary's id: "id64", else "ManagedSpaceID".
    static func spaceID(of space: [String: Any]) -> SpaceID? {
        let number = (space["id64"] as? NSNumber) ?? (space["ManagedSpaceID"] as? NSNumber)
        return number?.uint64Value
    }
}
