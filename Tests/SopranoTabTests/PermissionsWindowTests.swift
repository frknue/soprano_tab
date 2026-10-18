import AppKit
import Testing
@testable import SopranoTab

@MainActor
struct PermissionsWindowTests {
    /// The status the window polls; tests flip it between renders.
    @MainActor
    private final class StatusBox {
        var status: PermissionStatus

        init(_ status: PermissionStatus) {
            self.status = status
        }
    }

    private func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    @Test("the window renders offscreen with every permission missing and with both granted")
    func rendersBothStatesOffscreen() throws {
        let missing = PermissionsWindowController(
            status: { PermissionStatus(accessibility: false, screenRecording: false) },
            theme: AppTheme.missionControl
        )
        let granted = PermissionsWindowController(
            status: { PermissionStatus(accessibility: true, screenRecording: true) },
            theme: AppTheme.missionControl
        )

        let missingImage = try #require(missing.renderImage())
        let grantedImage = try #require(granted.renderImage())

        #expect(missingImage.width >= Int(PermissionsWindowController.contentSize.width))
        #expect(missingImage.height >= Int(PermissionsWindowController.contentSize.height))
        #expect(missingImage.width == grantedImage.width)
        #expect(missingImage.height == grantedImage.height)
        #expect(pngData(missingImage) != pngData(grantedImage))
        #expect(missing.window?.isVisible == false)
        #expect(granted.window?.isVisible == false)
    }

    @Test("a granted permission relights its lamp on the next render")
    func renderFollowsStatusChanges() throws {
        let box = StatusBox(PermissionStatus(accessibility: false, screenRecording: true))
        let controller = PermissionsWindowController(status: { box.status }, theme: AppTheme.missionControl)

        let before = try #require(controller.renderImage())
        box.status.accessibility = true
        let after = try #require(controller.renderImage())
        let again = try #require(controller.renderImage())

        #expect(pngData(before) != pngData(after))
        #expect(pngData(after) == pngData(again))
    }
}
