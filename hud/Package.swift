// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VocoHUD",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "voco-hud", targets: ["VocoHUD"])
    ],
    targets: [
        .target(
            name: "VocoHUDCore",
            path: "Sources/VocoHUDCore"
        ),
        .executableTarget(
            name: "VocoHUD",
            dependencies: ["VocoHUDCore"],
            path: "Sources/VocoHUD"
        ),
        .testTarget(
            name: "VocoHUDTests",
            dependencies: ["VocoHUDCore"],
            path: "Tests/VocoHUDTests"
        )
    ]
)
