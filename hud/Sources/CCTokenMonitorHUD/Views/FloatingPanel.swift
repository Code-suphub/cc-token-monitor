import SwiftUI
import Charts

/// 悬浮详细面板 - Glassmorphism 设计（备用）
struct FloatingPanel: View {
    @StateObject private var dataService = DataService()
    let onClose: () -> Void

    // 配色方案
    private let accentColor = Color(hex: "58a6ff")
    private let purpleColor = Color(hex: "a371f7")
    private let greenColor = Color(hex: "3fb950")
    private let redColor = Color(hex: "f85149")
    private let amberColor = Color(hex: "f0883e")

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
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
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.4))
                        .contentShape(Circle())
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

            Divider()
                .background(Color.white.opacity(0.08))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // 今日概览
                    todaySection

                    Divider()
                        .background(Color.white.opacity(0.06))

                    // 7天趋势图
                    trendSection

                    Divider()
                        .background(Color.white.opacity(0.06))

                    // 会话数
                    sessionSection
                }
                .padding(16)
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // 底部按钮
            HStack(spacing: 12) {
                Button(action: openWebInterface) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                            .font(.system(size: 11))
                        Text("Web")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.15))
                    )
                    .foregroundColor(accentColor)
                    .overlay(
                        Capsule()
                            .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {}) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        Text("设置")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "151821").opacity(0.95),
                        Color(hex: "1a1d29").opacity(0.9)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(width: 300, height: 420)
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
        .shadow(
            color: .black.opacity(0.4),
            radius: 12,
            x: 0,
            y: 4
        )
    }

    // MARK: - 今日概览
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundColor(accentColor)
                Text("今日概览")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.3)
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(dataService.todayStats?.formattedTokens ?? "--")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .fontDesign(.monospaced)
                            .foregroundColor(.white)
                        Text("tokens")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("$")
                            .font(.system(size: 11))
                            .foregroundColor(greenColor)
                        Text(dataService.todayStats?.formattedCost ?? "--")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .fontDesign(.monospaced)
                            .foregroundColor(greenColor)
                    }
                }

                Spacer()

                // 环比指示器
                if let change = dataService.dayOverDayChange() {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 3) {
                            Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(abs(change * 100), specifier: "%.0f")%")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(change >= 0 ? redColor : greenColor)

                        Text("较昨日")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill((change >= 0 ? redColor : greenColor).opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder((change >= 0 ? redColor : greenColor).opacity(0.25), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - 趋势图
    private var trendSection: some View {
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
                    .cornerRadius(3)
                }
                .frame(height: 90)
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

                HStack(spacing: 4) {
                    Text("平均")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                    Text(formatNumber(dataService.recentStats.map(\.totalTokens).reduce(0, +) / dataService.recentStats.count) + "/天")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .fontDesign(.monospaced)
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                Text("数据不足")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(height: 90)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - 会话数
    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11))
                    .foregroundColor(amberColor)
                Text("今日会话")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.3)
            }

            HStack(spacing: 8) {
                Text("\(dataService.todayStats?.sessions ?? 0)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .fontDesign(.monospaced)
                    .foregroundColor(.white)
                Text("个会话")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()
            }
        }
    }

    private func openWebInterface() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["http://localhost:8080"]
        try? task.run()
    }
}

// Preview removed for compilation
