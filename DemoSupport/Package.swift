// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "DemoSupport",
    platforms: [.macOS("15.4")],
    products: [
        .library(name: "SwiftUIDemoSupport", targets: ["SwiftUIDemoSupport"]),
    ],
    targets: [
        .target(name: "SwiftUIDemoSupport"),
        .testTarget(
            name: "SwiftUIDemoSupportTests",
            dependencies: ["SwiftUIDemoSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
