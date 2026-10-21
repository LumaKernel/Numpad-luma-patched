// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrackpadNumpad",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TrackpadNumpad", targets: ["TrackpadNumpad"])],
    targets: [
        .target(name: "CTrackpad", linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("IOKit")]),
        .target(name: "TrackpadCore"),
        .executableTarget(name: "TrackpadNumpad", dependencies: ["CTrackpad", "TrackpadCore"],
                          linkerSettings: [.linkedFramework("Carbon")]),
        .testTarget(name: "TrackpadCoreTests", dependencies: ["TrackpadCore"])
    ]
)
