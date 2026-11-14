// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CleanDisk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CleanDisk", path: "Sources/CleanDisk")
    ]
)
