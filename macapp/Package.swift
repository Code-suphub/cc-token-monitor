// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CCTokenMonitorApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "cc-token-monitor-app",
            targets: ["CCTokenMonitorApp"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CCTokenMonitorApp",
            path: "Sources/CCTokenMonitorApp"
        )
    ]
)
