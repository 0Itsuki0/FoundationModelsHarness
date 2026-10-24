// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FoundationModelsHarness",
    platforms: [
        .iOS("27.2"), .macOS("27.2"), .visionOS("27.2"), .watchOS("27.2"),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "FoundationModelsHarness",
            targets: ["FoundationModelsHarness"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            branch: "master",
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "FoundationModelsHarness",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "SQLiteStore",
            dependencies: [
                "FoundationModelsHarness",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .executableTarget(
            name: "Examples",
            dependencies: [
                "FoundationModelsHarness",
                "SQLiteStore"
            ],
            path: "Examples"
        ),
        .testTarget(
            name: "FoundationModelsHarnessTests",
            dependencies: ["FoundationModelsHarness"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
