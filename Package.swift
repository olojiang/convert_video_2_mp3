// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ConvertVideo2MP3",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ConvertCore", targets: ["ConvertCore"]),
        .executable(name: "ConvertVideo2MP3", targets: ["ConvertVideo2MP3App"])
    ],
    targets: [
        .target(name: "ConvertCore"),
        .executableTarget(
            name: "ConvertVideo2MP3App",
            dependencies: ["ConvertCore"]
        ),
        .testTarget(
            name: "ConvertCoreTests",
            dependencies: ["ConvertCore"]
        )
    ]
)
