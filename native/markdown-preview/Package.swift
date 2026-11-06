// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MarkdownPreview",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MarkdownPreview", targets: ["MarkdownPreview"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.6.0"),
        .package(url: "https://github.com/2389-research/MermaidKit.git", exact: "2.9.1"),
    ],
    targets: [
        .target(name: "PreviewCore", dependencies: [
            .product(name: "Markdown", package: "swift-markdown"),
            .product(name: "MermaidRender", package: "MermaidKit"),
        ]),
        .executableTarget(name: "MarkdownPreview", dependencies: ["PreviewCore"]),
        .testTarget(name: "PreviewCoreTests", dependencies: ["PreviewCore"]),
    ],
    swiftLanguageModes: [.v5]
)
