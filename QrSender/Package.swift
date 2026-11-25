// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QrTransfer",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "QrCore"),
        .executableTarget(name: "QrSender", dependencies: ["QrCore"]),
        .testTarget(name: "QrCoreTests", dependencies: ["QrCore"]),
    ]
)
