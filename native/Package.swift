// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VocoNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VocoAppCore", targets: ["VocoAppCore"]),
        .executable(name: "Voco", targets: ["VocoApp"])
    ],
    targets: [
        .target(
            name: "VocoAppCore",
            path: "Sources/VocoAppCore",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .executableTarget(
            name: "VocoApp",
            dependencies: ["VocoAppCore"],
            path: "Sources/VocoApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "VocoAppCoreTests",
            dependencies: ["VocoAppCore"],
            path: "Tests/VocoAppCoreTests"
        ),
        .testTarget(
            name: "VocoAppTests",
            dependencies: ["VocoApp", "VocoAppCore"],
            path: "Tests/VocoAppTests"
        )
    ]
)
