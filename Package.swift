// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SopranoTab",
    platforms: [.macOS(.v14)],
    targets: [
        // Switching engine: models, keys, settings, ordering and layout math. Foundation only, no AppKit.
        .target(
            name: "SopranoTabCore",
            path: "Sources/SopranoTabCore"
        ),
        .executableTarget(
            name: "SopranoTab",
            dependencies: ["SopranoTabCore"],
            path: "Sources/SopranoTab",
            exclude: ["Vendored/SOPRANO_COMMIT"],
            resources: [
                .copy("Resources/DepartureMono-Regular.woff2"),
                .copy("Resources/AppIcon.icns"),
            ],
            linkerSettings: [
                .linkedFramework("CoreText"),
                .linkedFramework("CoreServices"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "SopranoTabTests",
            dependencies: ["SopranoTab", "SopranoTabCore"],
            path: "Tests/SopranoTabTests",
            swiftSettings: [
                .unsafeFlags(["-F/Library/Developer/CommandLineTools/Library/Developer/Frameworks"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
                .linkedFramework("Testing"),
            ]
        ),
    ]
)
