import Foundation

/// HUD 配置模型
struct HUDConfig: Codable {
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
class ConfigManager {
    static let shared = ConfigManager()

    private let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cc-token-monitor")
    private let configFile: URL

    private(set) var config: HUDConfig {
        didSet {
            saveConfig()
        }
    }

    init() {
        configFile = configDir.appendingPathComponent("hud-config.yaml")
        config = ConfigManager.loadConfig(from: configFile)
    }

    /// 更新配置
    func update(_ updater: (inout HUDConfig) -> Void) {
        updater(&config)
    }

    /// 保存位置
    func savePosition(x: Double, y: Double) {
        config.position = HUDConfig.Position(x: x, y: y)
    }

    /// 加载配置
    private static func loadConfig(from url: URL) -> HUDConfig {
        // 如果配置文件存在，解析 YAML 格式
        // 为简化，这里先用 PropertyList（XML/Binary）格式
        // 后期可以引入 Yams 库支持纯 YAML

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
