// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FO48UControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FO48UKit"),
        .executableTarget(name: "FO48UControl", dependencies: ["FO48UKit"]),
    ]
)
