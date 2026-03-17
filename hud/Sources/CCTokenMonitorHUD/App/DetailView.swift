import SwiftUI
import Charts

struct DetailView: View {
    @ObservedObject var dataService: DataService
    @Environment(\.dismiss) var dismiss
    var onShowConfig: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            Divider()
            todayStatsView
            Divider()
            trendView
            Divider()
            modelStatsView
            Divider()
            sessionView
            Spacer()
        }
        .padding()
        .frame(width: 320, height: 520)
    }

    private var headerView: some View {
        HStack {
            Text("Token Monitor")
                .font(.headline)
            Spacer()

            // 设置按钮
            if let onShowConfig = onShowConfig {
                Button(action: onShowConfig) {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("设置")
            }

            Button("关闭") {
                dismiss()
            }
        }
    }

    private var todayStatsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📅 今日")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                VStack(alignment: .leading) {
                    Text(dataService.todayStats?.formattedTokens ?? "--")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("$" + (dataService.todayStats?.formattedCost ?? "--"))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    Text("cost")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var trendView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📊 近7天趋势")
                .font(.caption)
                .foregroundColor(.secondary)

            if dataService.recentStats.count >= 2 {
                Chart(dataService.recentStats) { stat in
                    BarMark(
                        x: .value("日期", String(stat.date.suffix(5))),
                        y: .value("Tokens", stat.totalTokens)
                    )
                    .foregroundStyle(
                        stat.date == dataService.todayStats?.date
                            ? Color.accentColor
                            : Color.accentColor.opacity(0.5)
                    )
                    .cornerRadius(4)
                }
                .frame(height: 120)
            } else {
                Text("数据不足")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 120)
            }
        }
    }

    private var modelStatsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🤖 模型分布")
                .font(.caption)
                .foregroundColor(.secondary)

            let models = dataService.todayModelStats()
            if models.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(models.prefix(5)) { model in
                        HStack {
                            Text(model.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(model.formattedTokens)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var sessionView: some View {
        HStack {
            Text("💬 今日会话")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(dataService.todayStats?.sessions ?? 0) 个")
                .font(.caption)
        }
    }
}
