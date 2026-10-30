// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MonitorDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FO48UKit"),
        .executableTarget(name: "MonitorDeck", dependencies: ["FO48UKit"]),
    ]
)
