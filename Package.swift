// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Parallel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Parallel", targets: ["Parallel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Parallel",
            dependencies: ["SwiftTerm"],
            path: "Sources/Parallel"
        ),
        .testTarget(
            name: "ParallelTests",
            dependencies: ["Parallel"],
            path: "Tests/ParallelTests"
        ),
    ]
)
