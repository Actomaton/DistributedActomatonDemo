// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "DemoTransport",
    platforms: [.macOS("15.4")],
    products: [
        .library(name: "BonjourTransport", targets: ["BonjourTransport"]),
        .library(name: "TCPTransport", targets: ["TCPTransport"]),
    ],
    targets: [
        // A real-transport DistributedActorSystem over Bonjour discovery + TCP.
        .target(name: "BonjourTransport"),

        // A portable DistributedActorSystem over plain POSIX-socket TCP.
        .target(name: "TCPTransport"),

        .testTarget(
            name: "DemoTransportTests",
            dependencies: [
                "BonjourTransport",
                "TCPTransport",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
