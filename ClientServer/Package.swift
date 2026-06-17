// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "ClientServer",
    platforms: [.macOS("15.4")],
    products: [
        .library(name: "ClientServerCore", targets: ["ClientServerCore"]),
        .library(name: "ClientServerSwiftUI", targets: ["ClientServerSwiftUI"]),
        .executable(name: "ClientServerInMemoryDemo", targets: ["ClientServerInMemoryDemo"]),
        .executable(name: "ClientServerBonjourDemo", targets: ["ClientServerBonjourDemo"]),
        .executable(name: "ClientServerTCPDemo", targets: ["ClientServerTCPDemo"]),
    ],
    dependencies: [
        // .package(name: "Actomaton", path: "../.."),
        .package(url: "https://github.com/Actomaton/Actomaton.git", branch: "main"),
        .package(name: "DemoSupport", path: "../DemoSupport"),
        .package(name: "DemoTransport", path: "../DemoTransport"),
    ],
    targets: [
        // Pure logic, no SwiftUI.
        .target(
            name: "ClientServerCore",
            dependencies: [
                .product(name: "DistributedActomaton", package: "Actomaton"),
            ]
        ),

        // SwiftUI view layer; re-exports ClientServerCore so apps keep a single import.
        .target(
            name: "ClientServerSwiftUI",
            dependencies: [
                "ClientServerCore",
                .product(name: "DistributedActomaton", package: "Actomaton"),
                .product(name: "SwiftUIDemoSupport", package: "DemoSupport"),
            ]
        ),

        .executableTarget(
            name: "ClientServerInMemoryDemo",
            dependencies: [
                "ClientServerSwiftUI",
                .product(name: "DistributedActomatonTesting", package: "Actomaton"),
                .product(name: "SwiftUIDemoSupport", package: "DemoSupport"),
            ]
        ),
        .executableTarget(
            name: "ClientServerBonjourDemo",
            dependencies: [
                "ClientServerSwiftUI",
                .product(name: "DistributedActomaton", package: "Actomaton"),
                .product(name: "BonjourTransport", package: "DemoTransport"),
                .product(name: "SwiftUIDemoSupport", package: "DemoSupport"),
            ]
        ),
        .executableTarget(
            name: "ClientServerTCPDemo",
            dependencies: [
                "ClientServerCore",
                .product(name: "DistributedActomaton", package: "Actomaton"),
                .product(name: "TCPTransport", package: "DemoTransport"),
            ]
        ),
        .testTarget(
            name: "ClientServerCoreTests",
            dependencies: ["ClientServerCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
