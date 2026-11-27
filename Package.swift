// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sonote",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SonoteCore", targets: ["SonoteCore"]),
        .executable(name: "Sonote", targets: ["Sonote"])
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "c7755e2504181a771941bb6f9f26ea79b3cdfce3"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.33.0")),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", .upToNextMajor(from: "1.0.1")),
        .package(url: "https://github.com/huggingface/swift-transformers.git", .upToNextMajor(from: "1.4.0"))
    ],
    targets: [
        .target(
            name: "SonoteCore",
            dependencies: [
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCodecs", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioVAD", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Transformers", package: "swift-transformers")
            ],
            path: "Sources/SonoteCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "Sonote",
            dependencies: ["SonoteCore"],
            path: "Sources/Sonote",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "SonoteTests",
            dependencies: [
                "SonoteCore",
                .product(name: "MLXAudioVAD", package: "mlx-audio-swift")
            ],
            path: "Tests/SonoteTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
