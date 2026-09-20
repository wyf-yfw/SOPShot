// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SOPShot",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SOPShot", targets: ["SOPShot"])
    ],
    targets: [
        .executableTarget(
            name: "SOPShot",
            path: "Sources/SOPShot",
            resources: [
                .process("Resources")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
