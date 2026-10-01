// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StockCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StockCore", targets: ["StockCore"]),
    ],
    targets: [
        .target(name: "StockCore"),
        .testTarget(
            name: "StockCoreTests",
            dependencies: ["StockCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
