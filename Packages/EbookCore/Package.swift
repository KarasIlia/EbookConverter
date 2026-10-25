// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EbookCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EbookCore", targets: ["EbookCore"]),
        .library(name: "ConverterFeature", targets: ["ConverterFeature"]),
    ],
    targets: [
        .target(name: "EbookCore"),
        .target(name: "ConverterFeature", dependencies: ["EbookCore"]),
        .testTarget(name: "EbookCoreTests", dependencies: ["EbookCore"]),
        .testTarget(name: "ConverterFeatureTests", dependencies: ["ConverterFeature", "EbookCore"]),
    ],
    swiftLanguageModes: [.v6]
)
