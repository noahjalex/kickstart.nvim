// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkdownPreview",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MarkdownPreview", targets: ["MarkdownPreview"])],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.6.0")],
    targets: [
        .target(name: "PreviewCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .executableTarget(name: "MarkdownPreview", dependencies: ["PreviewCore"]),
        .testTarget(name: "PreviewCoreTests", dependencies: ["PreviewCore"]),
    ]
)
