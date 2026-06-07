// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "StockfishCloud",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "StockfishCloud", targets: ["StockfishCloudApp"])
    ],
    targets: [
        .executableTarget(
            name: "StockfishCloudApp",
            path: "Sources/StockfishCloudApp"
        )
    ]
)
