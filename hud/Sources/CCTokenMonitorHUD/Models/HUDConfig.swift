import Foundation
import SwiftUI

/// 显示模式
enum DisplayMode: String, Codable, CaseIterable {
    case floating = "floating"  // 悬浮窗模式
    case statusBar = "statusBar" // 状态栏模式
}

/// 状态栏显示内容
enum StatusBarDisplay: String, Codable, CaseIterable {
    case tokens = "tokens"       // 只显示 tokens
    case cost = "cost"           // 只显示 cost
    case both = "both"           // 显示 token + cost
}

/// 状态栏显示详细程度
enum StatusBarDetailLevel: String, Codable, CaseIterable {
    case simple = "simple"       // 简单：T:49.4M | C:39.53
    case detailed = "detailed"   // 详细：I:45M | O:4.4M | C:39.53
}

/// HUD 配置模型
struct HUDConfig: Codable {
    // 显示模式
    var displayMode: DisplayMode = .floating

    // L1 尺寸（固定，不可 UI 调整，需重启生效）
    var width: Double = 120
    var height: Double = 80
    var cornerRadius: Double = 12
    var opacity: Double = 0.95

    // 显示内容
    var showTokens: Bool = true
    var showCost: Bool = true
    var showComparison: Bool = true
    var currency: String = "USD"  // USD/CNY

    // 状态栏配置
    var statusBarDisplay: StatusBarDisplay = .both
    var statusBarDetailLevel: StatusBarDetailLevel = .simple  // simple: T/C, detailed: I/O/C

    // 行为
    var refreshInterval: Int = 30
    var autoStart: Bool = false
    var snapToEdges: Bool = true
    var autoHideL2: Bool = true  // 点击外部自动收起 L2

    // 位置（自动记忆）
    var position: Position?

    struct Position: Codable {
        var x: Double
        var y: Double
    }
}

/// 配置管理器
class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    private let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/token-stats")
    private let configFile: URL

    @Published var config: HUDConfig

    init() {
        configFile = configDir.appendingPathComponent("hud-config.plist")
        let loadedConfig = ConfigManager.loadConfig(from: configFile)
        _config = Published(wrappedValue: loadedConfig)
    }

    /// 更新配置
    func update(_ updater: (inout HUDConfig) -> Void) {
        updater(&config)
        saveConfig()
    }

    /// 保存位置
    func savePosition(x: Double, y: Double) {
        config.position = HUDConfig.Position(x: x, y: y)
        saveConfig()
    }

    /// 加载配置
    private static func loadConfig(from url: URL) -> HUDConfig {
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let config = try? PropertyListDecoder().decode(HUDConfig.self, from: data) {
            return config
        }

        return HUDConfig()
    }

    /// 保存配置
    private func saveConfig() {
        try? FileManager.default.createDirectory(
            at: configDir,
            withIntermediateDirectories: true
        )

        if let data = try? PropertyListEncoder().encode(config) {
            try? data.write(to: configFile)
        }
    }
}
