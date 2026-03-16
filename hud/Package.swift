// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CCTokenMonitorHUD",
    platforms: [
        .macOS(.v13)  // Swift Charts 需要 macOS 13+
    ],
    products: [
        .executable(
            name: "cc-token-monitor-hud",
            targets: ["CCTokenMonitorHUD"]
        )
    ],
    dependencies: [
        // 无需外部依赖，使用原生 SwiftUI 和 Swift Charts
    ],
    targets: [
        .executableTarget(
            name: "CCTokenMonitorHUD",
            path: "Sources/CCTokenMonitorHUD"
        )
    ]
)