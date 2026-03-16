import SwiftUI
import Charts

/// L2 详细面板
struct L2DetailPanel: View {
    @StateObject private var dataService = DataService()
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("CC Token Monitor")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // 今日概览
                    todaySection

                    Divider()

                    // 7天趋势图
                    trendSection

                    Divider()

                    // 会话数
                    sessionSection
                }
                .padding()
            }

            Divider()

            // 底部按钮
            HStack {
                Button("打开完整界面") {
                    openWebInterface()
                }

                Spacer()

                Button("设置") {
                    // TODO: 打开设置面板
                }
            }
            .padding()
        }
        .frame(width: 280, height: 400)
    }

    // MARK: - 今日概览
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📅 今天")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(dataService.todayStats?.formattedTokens ?? "--")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("tokens")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("$")
                            .font(.caption)
                        Text(dataService.todayStats?.formattedCost ?? "--")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                // 环比指示器
                if let change = dataService.dayOverDayChange() {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(change >= 0 ? .red : .green)
                        Text("较昨日")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(abs(change * 100), specifier: "%.0f")%")
                            .font(.caption)
                            .foregroundColor(change >= 0 ? .red : .green)
                    }
                }
            }
        }
    }

    // MARK: - 趋势图
    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📊 近7天趋势")
                .font(.caption)
                .foregroundColor(.secondary)

            if dataService.recentStats.count >= 2 {
                Chart(dataService.recentStats) { stat in
                    BarMark(
                        x: .value("日期", String(stat.date.suffix(5))), // MM-dd
                        y: .value("Tokens", stat.totalTokens)
                    )
                    .foregroundStyle(
                        stat.date == dataService.todayStats?.date
                            ? Color.accentColor
                            : Color.accentColor.opacity(0.5)
                    )
                    .cornerRadius(4)
                }
                .frame(height: 100)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(formatNumber(intValue))
                                    .font(.caption2)
                            }
                        }
                    }
                }

                // 平均值
                let avg = dataService.recentStats.map(\.totalTokens).reduce(0, +) / dataService.recentStats.count
                HStack {
                    Text("平均:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatNumber(avg) + "/天")
                        .font(.caption)
                }
            } else {
                Text("数据不足")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 100)
            }
        }
    }

    // MARK: - 会话数
    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💬 今日会话")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("\(dataService.todayStats?.sessions ?? 0)")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("个会话")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
    }

    private func openWebInterface() {
        // 启动 web 服务并打开浏览器
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["http://localhost:8080"]
        try? task.run()
    }
}

// Preview removed for compilation
