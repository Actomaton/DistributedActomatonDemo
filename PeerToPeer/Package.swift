// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "PeerToPeer",
    platforms: [.macOS("15.4")],
    products: [
        .library(name: "PeerToPeerCore", targets: ["PeerToPeerCore"]),
        .library(name: "PeerToPeerSwiftUI", targets: ["PeerToPeerSwiftUI"]),
        .executable(name: "PeerToPeerInMemoryDemo", targets: ["PeerToPeerInMemoryDemo"]),
        .executable(name: "PeerToPeerBonjourDemo", targets: ["PeerToPeerBonjourDemo"]),
        .executable(name: "PeerToPeerTCPDemo", targets: ["PeerToPeerTCPDemo"]),
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
            name: "PeerToPeerCore",
            dependencies: [
                .product(name: "DistributedActomaton", package: "Actomaton"),
            ]
        ),

        // SwiftUI view layer; re-exports PeerToPeerCore so apps keep a single import.
        .target(
            name: "PeerToPeerSwiftUI",
            dependencies: [
                "PeerToPeerCore",
                .product(name: "DistributedActomaton", package: "Actomaton"),
                .product(name: "SwiftUIDemoSupport", package: "DemoSupport"),
            ]
        ),

        .executableTarget(
            name: "PeerToPeerInMemoryDemo",
            dependencies: [
                "PeerToPeerSwiftUI",
                .product(name: "DistributedActomatonTesting", package: "Actomaton"),
                .product(name: "SwiftUIDemoSupport", package: "DemoSupport"),
            ]
        ),
        .executableTarget(
            name: "PeerToPeerBonjourDemo",
            dependencies: [
                "PeerToPeerSwiftUI",
                .product(name: "DistributedActomaton", package: "Actomaton"),
                .product(name: "BonjourTransport", package: "DemoTransport"),
                .product(name: "SwiftUIDemoSupport", package: "DemoSupport"),
            ]
        ),
        .executableTarget(
            name: "PeerToPeerTCPDemo",
            dependencies: [
                "PeerToPeerCore",
                .product(name: "DistributedActomaton", package: "Actomaton"),
                .product(name: "TCPTransport", package: "DemoTransport"),
            ]
        ),
        .testTarget(
            name: "PeerToPeerCoreTests",
            dependencies: ["PeerToPeerCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
