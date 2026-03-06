// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OneLaunch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OneLaunch", targets: ["OneLaunch"])
    ],
    targets: [
        .executableTarget(
            name: "OneLaunch",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
