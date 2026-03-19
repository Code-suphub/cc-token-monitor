import SwiftUI

/// 悬浮迷你窗 - Glassmorphism 设计
struct FloatingWidget: View {
    @StateObject private var dataService = DataService()
    @State private var isPressed = false

    // 配色方案
    private let accentColor = Color(hex: "58a6ff")
    private let greenColor = Color(hex: "3fb950")
    private let redColor = Color(hex: "f85149")
    private let amberColor = Color(hex: "f0883e")

    var body: some View {
        VStack(spacing: 8) {
            // 图标行
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor, Color(hex: "79c0ff")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [greenColor, Color(hex: "56d364")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .font(.system(size: 14, weight: .medium))

            // 数据行
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                // Tokens
                VStack(spacing: 2) {
                    Text(dataService.todayStats?.formattedTokens ?? "--")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .fontDesign(.monospaced)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white, Color.white.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("TOKENS")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(0.5)
                }

                // Cost
                VStack(spacing: 2) {
                    Text("$" + (dataService.todayStats?.formattedCost ?? "--"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .fontDesign(.monospaced)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [greenColor, Color(hex: "56d364")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("COST")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(0.5)
                }
            }

            // 环比指示器
            if let change = dataService.dayOverDayChange() {
                HStack(spacing: 3) {
                    Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(abs(change * 100), specifier: "%.0f")%")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                }
                .foregroundColor(change >= 0 ? redColor : greenColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill((change >= 0 ? redColor : greenColor).opacity(0.15))
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 130, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "1a1e2e").opacity(1.0),
                            Color(hex: "131620").opacity(1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(0.3),
            radius: 6,
            x: 0,
            y: 3
        )
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onTapGesture {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                showL2()
            }
        }
        .contextMenu {
            Button("打开详细面板") {
                showL2()
            }

            Divider()

            Button("刷新数据") {
                dataService.refreshData()
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            dataService.startTimer(interval: 30)
        }
        .onDisappear {
            dataService.stopTimer()
        }
    }

    private func showL2() {
        // L2 面板功能
        print("L2 panel tapped")
    }
}
