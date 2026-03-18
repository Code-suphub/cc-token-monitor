import SwiftUI
import Charts

/// 菜单栏下拉面板 - Glassmorphism 设计
struct MenuBarPanel: View {
    @ObservedObject var dataService: DataService
    @Environment(\.dismiss) var dismiss
    var onShowConfig: (() -> Void)? = nil

    // 配色方案
    private let accentColor = Color(hex: "58a6ff")
    private let purpleColor = Color(hex: "a371f7")
    private let greenColor = Color(hex: "3fb950")
    private let redColor = Color(hex: "f85149")
    private let amberColor = Color(hex: "f0883e")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            headerView

            Divider()
                .background(Color.white.opacity(0.08))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    todayStatsView

                    Divider()
                        .background(Color.white.opacity(0.06))

                    trendView

                    Divider()
                        .background(Color.white.opacity(0.06))

                    modelStatsView

                    Divider()
                        .background(Color.white.opacity(0.06))

                    sessionView
                }
                .padding(16)
            }
        }
        .frame(width: 320, height: 520)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "1e2330").opacity(0.95),
                                    Color(hex: "14161f").opacity(0.98)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.4),
                            purpleColor.opacity(0.2),
                            accentColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(
            color: accentColor.opacity(0.12),
            radius: 20,
            x: 0,
            y: 8
        )
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentColor, purpleColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("Token Monitor")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            // 设置按钮
            if let onShowConfig = onShowConfig {
                Button(action: onShowConfig) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("设置")
            }

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "1a1d29").opacity(0.9),
                    Color(hex: "151821").opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var todayStatsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundColor(accentColor)
                Text("今日")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.3)
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dataService.todayStats?.formattedTokens ?? "--")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .fontDesign(.monospaced)
                        .foregroundColor(.white)
                    Text("tokens")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("$" + (dataService.todayStats?.formattedCost ?? "--"))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .fontDesign(.monospaced)
                        .foregroundColor(greenColor)
                    Text("cost")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }

    private var trendView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 11))
                    .foregroundColor(purpleColor)
                Text("近7天趋势")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.3)
            }

            if dataService.recentStats.count >= 2 {
                Chart(dataService.recentStats) { stat in
                    BarMark(
                        x: .value("日期", String(stat.date.suffix(5))),
                        y: .value("Tokens", stat.totalTokens)
                    )
                    .foregroundStyle(
                        stat.date == dataService.todayStats?.date
                            ? LinearGradient(
                                colors: [accentColor, purpleColor],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                            : LinearGradient(
                                colors: [accentColor.opacity(0.4), accentColor.opacity(0.2)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                    )
                    .cornerRadius(4)
                }
                .frame(height: 100)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(formatNumber(intValue))
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let strValue = value.as(String.self) {
                                Text(strValue)
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                    }
                }
            } else {
                Text("数据不足")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(height: 100)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var modelStatsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11))
                    .foregroundColor(amberColor)
                Text("模型分布")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.3)
            }

            let models = dataService.todayModelStats()
            if models.isEmpty {
                Text("暂无数据")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            } else {
                VStack(spacing: 6) {
                    ForEach(models.prefix(5)) { model in
                        HStack {
                            Text(model.name)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                            Spacer()
                            Text(model.formattedTokens)
                                .font(.system(size: 12, design: .rounded))
                                .fontDesign(.monospaced)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
            }
        }
    }

    private var sessionView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11))
                    .foregroundColor(amberColor)
                Text("今日会话")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.3)
            }

            Spacer()

            Text("\(dataService.todayStats?.sessions ?? 0) 个")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .fontDesign(.monospaced)
                .foregroundColor(.white)
        }
    }
}
