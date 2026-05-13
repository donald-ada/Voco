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
            name: "CSherpaOnnx",
            path: "Vendor/SherpaOnnx/CSherpaOnnx",
            publicHeadersPath: "include"
        ),
        .target(
            name: "VocoAppCore",
            path: "Sources/VocoAppCore",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .executableTarget(
            name: "VocoApp",
            dependencies: ["VocoAppCore", "CSherpaOnnx"],
            path: "Sources/VocoApp",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedLibrary("c++"),
                .unsafeFlags([
                    "-L", "Vendor/SherpaOnnx/lib",
                    "-lsherpa-onnx",
                    "-lonnxruntime",
                ])
            ]
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
