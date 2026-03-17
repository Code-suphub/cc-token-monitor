import Foundation

/// 单日统计数据
struct DailyStats: Codable, Identifiable {
    var id = UUID()
    let date: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreateTokens: Int
    let cacheReadTokens: Int
    let sessions: Int

    var totalTokens: Int {
        inputTokens + outputTokens
    }

    /// 计算预估成本（USD）
    var totalCost: Double {
        // 复用 web 的定价逻辑，默认 $0.8/M tokens
        let pricePerM: Double = 0.8
        return Double(totalTokens) * pricePerM / 1_000_000
    }

    /// 格式化后的 tokens 显示（如 23.5K）
    var formattedTokens: String {
        formatNumber(totalTokens)
    }

    /// 格式化后的成本显示
    var formattedCost: String {
        String(format: "%.2f", totalCost)
    }
}

/// 项目级别的统计
struct ProjectStats: Identifiable {
    let id = UUID()
    let name: String
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens
    }
}

/// 模型级别的统计
struct ModelStats: Identifiable {
    let id = UUID()
    let name: String
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens
    }

    var formattedTokens: String {
        formatNumber(totalTokens)
    }
}

/// 格式化数字为 K/M 格式
func formatNumber(_ num: Int) -> String {
    if num >= 1_000_000 {
        return String(format: "%.1fM", Double(num) / 1_000_000)
    } else if num >= 1_000 {
        return String(format: "%.1fK", Double(num) / 1_000)
    } else {
        return String(num)
    }
}
