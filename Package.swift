// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WalkWrite",
    platforms: [
        .iOS(.v17)
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.20.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "2.21.0")
    ],
    targets: [
        .target(
            name: "WalkWrite",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples")
            ]
        )
    ]
)