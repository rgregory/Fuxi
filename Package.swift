// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fuxi",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Fuxi", path: "Sources/Fuxi")
    ]
)
