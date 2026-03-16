import SwiftUI

/// L1 悬浮迷你窗
struct L1MiniWidget: View {
    @StateObject private var dataService = DataService()

    var body: some View {
        VStack(spacing: 6) {
            // 图标行
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.accentColor)
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(.green)
            }
            .font(.system(size: 12))

            // 数据行
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                // Tokens
                VStack(spacing: 1) {
                    Text(dataService.todayStats?.formattedTokens ?? "--")
                        .font(.system(size: 16, weight: .semibold))
                    Text("tokens")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }

                // Cost
                VStack(spacing: 1) {
                    Text("$" + (dataService.todayStats?.formattedCost ?? "--"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                    Text("cost")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }

            // 环比
            if let change = dataService.dayOverDayChange() {
                HStack(spacing: 2) {
                    Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                    Text("\(abs(change * 100), specifier: "%.0f")%")
                }
                .font(.system(size: 9))
                .foregroundColor(change >= 0 ? .red : .green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 120, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .onTapGesture {
            showL2()
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
        // L2 面板功能暂时禁用
        print("L2 panel tapped")
    }
}
