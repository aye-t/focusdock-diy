// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FocusDockMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FocusDock", targets: ["FocusDockMac"])
    ],
    targets: [
        .executableTarget(
            name: "FocusDockMac",
            path: "Sources",
            exclude: [
                "Resources/AppIconBase.png",
                "Resources/AppIcon.icns",
                "Resources/Info.plist",
            ],
            resources: [.process("Resources/PetAssets")]
        ),
        .testTarget(
            name: "FocusDockMacTests",
            dependencies: ["FocusDockMac"],
            path: "Tests"
        )
    ]
)
