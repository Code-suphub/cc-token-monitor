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

    // 位置上下文（包含相对坐标，用于多屏幕场景）
    var positionContext: PositionContext?

    struct Position: Codable {
        var x: Double
        var y: Double
    }

    struct PositionContext: Codable {
        var x: Double
        var y: Double
        var relativeX: Double  // 0-1, 相对于屏幕宽度的比例
        var relativeY: Double  // 0-1, 相对于屏幕高度的比例
        var screenID: String?  // 当前屏幕标识
        var preferredScreenID: String?  // 用户偏好的屏幕（用于多屏幕自动迁移）
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
        // 发送配置变更通知
        NotificationCenter.default.post(name: .init("ConfigDidChange"), object: nil)
    }

    /// 保存位置（兼容旧版）
    func savePosition(x: Double, y: Double) {
        config.position = HUDConfig.Position(x: x, y: y)
        saveConfig()
    }

    /// 保存位置（包含相对坐标和屏幕上下文）
    func savePositionWithContext(x: Double, y: Double, relativeX: Double, relativeY: Double, screenID: String?, isUserAction: Bool = true) {
        config.position = HUDConfig.Position(x: x, y: y)

        // 保留之前的 preferredScreenID（如果是自动迁移，不覆盖用户偏好）
        let previousPreferred = config.positionContext?.preferredScreenID

        // 如果是用户主动移动，更新 preferredScreenID
        let newPreferredScreenID = isUserAction ? screenID : previousPreferred

        // 系统强制迁移时，保持原有的相对坐标不变
        let finalRelativeX = isUserAction ? relativeX : (config.positionContext?.relativeX ?? relativeX)
        let finalRelativeY = isUserAction ? relativeY : (config.positionContext?.relativeY ?? relativeY)

        config.positionContext = HUDConfig.PositionContext(
            x: x,
            y: y,
            relativeX: finalRelativeX,
            relativeY: finalRelativeY,
            screenID: screenID,
            preferredScreenID: newPreferredScreenID
        )
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
