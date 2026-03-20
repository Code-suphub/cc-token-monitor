import Foundation
import Combine

/// 数据服务，负责读取 token 统计数据
class DataService: ObservableObject {
    @Published var todayStats: DailyStats?
    @Published var recentStats: [DailyStats] = []
    @Published var isLoading: Bool = false
    @Published var lastError: Error?

    private var timer: Timer?
    private let monthlyDir: URL

    init() {
        monthlyDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/token-stats/monthly")

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

    /// 全量重新统计（调用 CLI）
    func rescanAll() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", "cc-token-monitor rescan"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                // 完成后刷新数据
                DispatchQueue.main.async {
                    self?.refreshData()
                    self?.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastError = error
                    self?.isLoading = false
                }
            }
        }
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

    /// 获取指定日期按模型统计的数据
    func modelStats(for dateString: String) -> [ModelStats] {
        return loadModelStats(for: dateString)
    }

    /// 加载今日统计数据
    private func loadTodayStats() -> DailyStats? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())

        return loadStats(for: todayString)
    }

    /// 加载指定日期的统计数据（从月文件中筛选）
    private func loadStats(for dateString: String) -> DailyStats? {
        // 从日期提取年月
        let month = String(dateString.prefix(7))  // "2026-03"
        let fileURL = monthlyDir.appendingPathComponent("\(month).csv")

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
            // 新格式: date|session|project|model|input|output|cache_create|cache_read
            guard parts.count >= 8 else { continue }

            // 只统计指定日期的数据
            if parts[0] != dateString { continue }

            let sessionId = parts[1]
            sessions.insert(sessionId)

            if let input = Int(parts[4]),
               let output = Int(parts[5]),
               let cacheCreate = Int(parts[6]),
               let cacheRead = Int(parts[7]) {
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

    /// 加载近 N 天数据（包括无数据的日期，显示为0）
    private func loadRecentStats(days: Int) -> [DailyStats] {
        var stats: [DailyStats] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for i in 0..<days {
            guard let date = Calendar.current.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let dateString = formatter.string(from: date)

            // 如果有数据就加载，没有则返回0值的统计
            if let stat = loadStats(for: dateString) {
                stats.append(stat)
            } else {
                stats.append(DailyStats(
                    date: dateString,
                    inputTokens: 0,
                    outputTokens: 0,
                    cacheCreateTokens: 0,
                    cacheReadTokens: 0,
                    sessions: 0
                ))
            }
        }

        return stats.reversed()  // 日期从早到晚
    }

    /// 加载指定日期按模型统计的数据（从月文件中筛选）
    private func loadModelStats(for dateString: String) -> [ModelStats] {
        // 从日期提取年月
        let month = String(dateString.prefix(7))  // "2026-03"
        let fileURL = monthlyDir.appendingPathComponent("\(month).csv")

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        // 按模型聚合数据
        var modelData: [String: (input: Int, output: Int)] = [:]

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: "|")
            // 新格式: date|session|project|model|input|output|cache_create|cache_read
            guard parts.count >= 8 else { continue }

            // 只统计指定日期的数据
            if parts[0] != dateString { continue }

            let model = parts[3] // model 在第4列

            // 过滤无效模型名
            guard !model.isEmpty,
                  model != "model",
                  !model.hasPrefix("<") else { continue }

            if let input = Int(parts[4]),
               let output = Int(parts[5]) {
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
