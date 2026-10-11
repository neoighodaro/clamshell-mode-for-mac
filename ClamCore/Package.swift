// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClamCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClamCore", targets: ["ClamCore"]),
        .executable(name: "clam-probe", targets: ["ClamProbe"]),
    ],
    targets: [
        .target(name: "ClamSignal", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "ClamCore", dependencies: ["ClamSignal"]),
        .executableTarget(name: "ClamProbe", dependencies: ["ClamCore"]),
        .testTarget(name: "ClamCoreTests", dependencies: ["ClamCore", "ClamSignal"]),
    ],
    swiftLanguageModes: [.v5]
)
