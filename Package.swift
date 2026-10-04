// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DotsCompanion",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DotsCompanion", targets: ["DotsCompanion"])],
    targets: [
        .target(name: "DotsCore"),
        .executableTarget(name: "DotsCompanion", dependencies: ["DotsCore"]),
        .testTarget(name: "DotsCoreTests", dependencies: ["DotsCore"])
    ],
    swiftLanguageModes: [.v5]
)
