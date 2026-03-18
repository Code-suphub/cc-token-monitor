import Foundation
import Combine

/// 数据服务，负责读取 token 统计数据
class DataService: ObservableObject {
    @Published var todayStats: DailyStats?
    @Published var recentStats: [DailyStats] = []
    @Published var isLoading: Bool = false
    @Published var lastError: Error?

    private var timer: Timer?
    private let statsDir: URL

    init() {
        statsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/token-stats/daily")

        // 立即加载一次
        refreshData()
    }

    /// 开始定时刷新
    func startTimer(interval: TimeInterval = 30) {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshData()
        }
    }

    /// 停止定时刷新
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 刷新数据
    func refreshData() {
        isLoading = true
        defer { isLoading = false }

        // 加载今日数据
        todayStats = loadTodayStats()

        // 加载近7天数据
        recentStats = loadRecentStats(days: 7)
    }

    /// 获取今日按模型统计的数据
    func todayModelStats() -> [ModelStats] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())

        return loadModelStats(for: todayString)
    }

    /// 加载今日统计数据
    private func loadTodayStats() -> DailyStats? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())

        return loadStats(for: todayString)
    }

    /// 加载指定日期的统计数据
    private func loadStats(for dateString: String) -> DailyStats? {
        let fileURL = statsDir.appendingPathComponent("\(dateString).csv")

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        var inputTokens = 0
        var outputTokens = 0
        var cacheCreateTokens = 0
        var cacheReadTokens = 0
        var sessions = Set<String>()

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 7 else { continue }

            let sessionId = parts[0]
            sessions.insert(sessionId)

            if let input = Int(parts[3]),
               let output = Int(parts[4]),
               let cacheCreate = Int(parts[5]),
               let cacheRead = Int(parts[6]) {
                inputTokens += input
                outputTokens += output
                cacheCreateTokens += cacheCreate
                cacheReadTokens += cacheRead
            }
        }

        return DailyStats(
            date: dateString,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreateTokens: cacheCreateTokens,
            cacheReadTokens: cacheReadTokens,
            sessions: sessions.count
        )
    }

    /// 加载近 N 天数据
    private func loadRecentStats(days: Int) -> [DailyStats] {
        var stats: [DailyStats] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for i in 0..<days {
            guard let date = Calendar.current.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let dateString = formatter.string(from: date)

            if let stat = loadStats(for: dateString) {
                stats.append(stat)
            }
        }

        return stats.reversed()  // 日期从早到晚
    }

    /// 加载指定日期按模型统计的数据
    private func loadModelStats(for dateString: String) -> [ModelStats] {
        let fileURL = statsDir.appendingPathComponent("\(dateString).csv")

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        // 按模型聚合数据
        var modelData: [String: (input: Int, output: Int)] = [:]

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 7 else { continue }

            let model = parts[2] // model 在第3列

            // 过滤无效模型名
            guard !model.isEmpty,
                  model != "model",
                  !model.hasPrefix("<") else { continue }

            if let input = Int(parts[3]),
               let output = Int(parts[4]) {
                if var existing = modelData[model] {
                    existing.input += input
                    existing.output += output
                    modelData[model] = existing
                } else {
                    modelData[model] = (input: input, output: output)
                }
            }
        }

        // 转换为 ModelStats 数组，按总 tokens 排序
        return modelData.map { (model, data) in
            ModelStats(name: model, inputTokens: data.input, outputTokens: data.output)
        }.sorted { $0.totalTokens > $1.totalTokens }
    }

    /// 计算环比变化
    func dayOverDayChange() -> Double? {
        guard let today = todayStats,
              let yesterday = recentStats.dropLast().last else {
            return nil
        }

        guard yesterday.totalTokens > 0 else { return 0 }

        let change = Double(today.totalTokens - yesterday.totalTokens) / Double(yesterday.totalTokens)
        return change
    }
}
