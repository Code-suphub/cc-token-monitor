import Foundation

/// 窗口位置配置
struct WindowPosition: Codable {
    var x: Double
    var y: Double
}

/// 配置管理器（从 HUD 简化）
class ConfigManager {
    static let shared = ConfigManager()

    private let configPath: URL
    private var configData: [String: Any] = [:]

    var windowPosition: WindowPosition? {
        get {
            guard let x = configData["windowX"] as? Double,
                  let y = configData["windowY"] as? Double else { return nil }
            return WindowPosition(x: x, y: y)
        }
        set {
            if let pos = newValue {
                configData["windowX"] = pos.x
                configData["windowY"] = pos.y
            } else {
                configData.removeValue(forKey: "windowX")
                configData.removeValue(forKey: "windowY")
            }
            save()
        }
    }

    init() {
        let statsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/token-stats")
        configPath = statsDir.appendingPathComponent("macapp-config.json")

        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: configPath.path) else { return }
        do {
            let data = try Data(contentsOf: configPath)
            configData = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            print("加载配置失败: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONSerialization.data(withJSONObject: configData)
            try data.write(to: configPath)
        } catch {
            print("保存配置失败: \(error)")
        }
    }
}
