// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ConvertVideo2MP3",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ConvertCore", targets: ["ConvertCore"]),
        .executable(name: "ConvertVideo2MP3", targets: ["ConvertVideo2MP3App"]),
        .executable(name: "ConvertVideo2MP3CLI", targets: ["ConvertVideo2MP3CLI"])
    ],
    targets: [
        .target(name: "ConvertCore"),
        .executableTarget(
            name: "ConvertVideo2MP3App",
            dependencies: ["ConvertCore"]
        ),
        .executableTarget(
            name: "ConvertVideo2MP3CLI",
            dependencies: ["ConvertCore"]
        ),
        .testTarget(
            name: "ConvertCoreTests",
            dependencies: ["ConvertCore"]
        )
    ]
)
