import SwiftUI

/// 设置面板 - Glassmorphism 设计
struct SettingsPanel: View {
    @ObservedObject var configManager = ConfigManager.shared
    @ObservedObject var dataService: DataService
    var onBack: () -> Void

    @State private var showRestartAlert = false

    // 配色方案
    private let accentColor = Color(hex: "58a6ff")
    private let purpleColor = Color(hex: "a371f7")
    private let greenColor = Color(hex: "3fb950")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack(spacing: 12) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("设置")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                // 占位保持平衡
                Text("返回")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0)
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

            // 配置内容
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // 显示模式
                    configSection("显示模式", icon: "display", color: accentColor) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("", selection: displayModeBinding) {
                                Text("悬浮窗")
                                    .foregroundColor(.white)
                                    .tag(DisplayMode.floating)
                                Text("状态栏")
                                    .foregroundColor(.white)
                                    .tag(DisplayMode.statusBar)
                            }
                            .pickerStyle(.segmented)
                            .colorMultiply(accentColor)
                            .environment(\.colorScheme, .dark)

                            Text(displayModeDescription)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.top, 4)
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.06))

                    // 状态栏显示内容（只在状态栏模式下有效）
                    configSection("状态栏显示", icon: "textformat", color: purpleColor) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("内容", selection: statusBarDisplayBinding) {
                                Text("Tokens").foregroundColor(.white).tag(StatusBarDisplay.tokens)
                                Text("Cost").foregroundColor(.white).tag(StatusBarDisplay.cost)
                                Text("两者").foregroundColor(.white).tag(StatusBarDisplay.both)
                            }
                            .pickerStyle(.segmented)
                            .environment(\.colorScheme, .dark)

                            Picker("格式", selection: statusBarDetailLevelBinding) {
                                Text("简洁 (T/C)").foregroundColor(.white).tag(StatusBarDetailLevel.simple)
                                Text("详细 (I/O/C)").foregroundColor(.white).tag(StatusBarDetailLevel.detailed)
                            }
                            .pickerStyle(.segmented)
                            .environment(\.colorScheme, .dark)

                            Text(statusBarDisplayDescription)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.top, 4)
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.06))

                    // 刷新间隔
                    configSection("刷新间隔", icon: "arrow.clockwise", color: greenColor) {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: refreshIntervalBinding) {
                                Text("10秒").foregroundColor(.white).tag(10)
                                Text("30秒").foregroundColor(.white).tag(30)
                                Text("1分钟").foregroundColor(.white).tag(60)
                                Text("5分钟").foregroundColor(.white).tag(300)
                            }
                            .pickerStyle(.segmented)
                            .environment(\.colorScheme, .dark)
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.06))

                    // 悬浮窗选项（只在悬浮窗模式下有效）
                    configSection("悬浮窗选项", icon: "eye", color: accentColor) {
                        VStack(alignment: .leading, spacing: 10) {
                            CustomToggle("显示 Tokens", isOn: showTokensBinding)
                            CustomToggle("显示 Cost", isOn: showCostBinding)
                            CustomToggle("显示环比", isOn: showComparisonBinding)
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.06))

                    // 数据
                    configSection("数据", icon: "externaldrive", color: purpleColor) {
                        VStack(alignment: .leading, spacing: 10) {
                            ActionButton("刷新数据", icon: "arrow.clockwise") {
                                dataService.refreshData()
                            }

                            ActionButton("重新统计", icon: "arrow.counterclockwise") {
                                dataService.rescanAll()
                            }

                            ActionButton("打开数据目录", icon: "folder") {
                                openDataDirectory()
                            }
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.06))

                    // 关于
                    configSection("关于", icon: "info.circle", color: greenColor) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CC Token Monitor HUD")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Text("版本 1.1.0")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // 底部提示
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(accentColor)
                Text("显示模式更改需要重启应用生效")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
        .frame(width: 300, height: 480)
        .background(
            RoundedRectangle(cornerRadius: 20)
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
            color: .black.opacity(0.3),
            radius: 8,
            x: 0,
            y: 4
        )
        .confirmationDialog("需要重启", isPresented: $showRestartAlert, titleVisibility: .visible) {
            Button("立即重启") {
                restartApp()
            }
            Button("稍后手动重启", role: .cancel) {}
        } message: {
            Text("显示模式已更改，需要重启应用才能生效。")
        }
    }

    /// 重启应用
    private func restartApp() {
        // 获取当前可执行文件路径
        guard let executablePath = Bundle.main.executablePath else {
            print("Failed to get executable path")
            NSApplication.shared.terminate(nil)
            return
        }

        // 获取当前进程名
        let processName = (executablePath as NSString).lastPathComponent

        // 创建一个后台任务来重启应用
        // 1. 先杀掉所有同名进程（包括当前进程）
        // 2. 等待进程完全退出
        // 3. 然后启动新进程
        let script = """
        (
            sleep 0.3
            # 杀掉所有 HUD 进程（包括当前进程）
            pgrep -x "\(processName)" | xargs kill -9 2>/dev/null || true
            sleep 0.5
            # 确保所有进程都被杀掉
            pgrep -x "\(processName)" | xargs kill -9 2>/dev/null || true
            sleep 0.2
            # 启动新进程
            nohup "\(executablePath)" > /dev/null 2>&1 &
        ) &
        """

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]

        do {
            try task.run()
        } catch {
            print("Failed to restart: \(error)")
        }

        // 立即退出当前应用（让后台脚本来清理和重启）
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Bindings

    private var displayModeBinding: Binding<DisplayMode> {
        Binding(
            get: { configManager.config.displayMode },
            set: { newValue in
                configManager.update { $0.displayMode = newValue }
                // 禁用窗口自动关闭，避免弹窗被关闭
                NotificationCenter.default.post(name: .init("DisableAutoClose"), object: true)
                // 延迟显示弹窗，避免与 Picker 动画冲突
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showRestartAlert = true
                    // 5秒后自动重新启用自动关闭（防止弹窗异常未关闭时一直禁用）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        NotificationCenter.default.post(name: .init("DisableAutoClose"), object: false)
                    }
                }
            }
        )
    }

    private var statusBarDisplayBinding: Binding<StatusBarDisplay> {
        Binding(
            get: { configManager.config.statusBarDisplay },
            set: { newValue in
                configManager.update { $0.statusBarDisplay = newValue }
            }
        )
    }

    private var statusBarDetailLevelBinding: Binding<StatusBarDetailLevel> {
        Binding(
            get: { configManager.config.statusBarDetailLevel },
            set: { newValue in
                configManager.update { $0.statusBarDetailLevel = newValue }
            }
        )
    }

    private var refreshIntervalBinding: Binding<Int> {
        Binding(
            get: { configManager.config.refreshInterval },
            set: { newValue in
                configManager.update { $0.refreshInterval = newValue }
            }
        )
    }

    private var showTokensBinding: Binding<Bool> {
        Binding(
            get: { configManager.config.showTokens },
            set: { newValue in
                configManager.update { $0.showTokens = newValue }
            }
        )
    }

    private var showCostBinding: Binding<Bool> {
        Binding(
            get: { configManager.config.showCost },
            set: { newValue in
                configManager.update { $0.showCost = newValue }
            }
        )
    }

    private var showComparisonBinding: Binding<Bool> {
        Binding(
            get: { configManager.config.showComparison },
            set: { newValue in
                configManager.update { $0.showComparison = newValue }
            }
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func configSection(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .tracking(0.3)
            }
            content()
        }
    }

    private var displayModeDescription: String {
        switch configManager.config.displayMode {
        case .floating:
            return "悬浮窗：在屏幕显示可移动的浮动窗口"
        case .statusBar:
            return "状态栏：在菜单栏显示简洁信息"
        }
    }

    private var statusBarDisplayDescription: String {
        let display = configManager.config.statusBarDisplay
        let detail = configManager.config.statusBarDetailLevel

        switch (display, detail) {
        case (.tokens, .simple):
            return "示例：T:49.4M（显示总 tokens）"
        case (.tokens, .detailed):
            return "示例：I:45M O:4.4M（显示 input/output 细分）"
        case (.cost, _):
            return "示例：C:39.53（只显示预估成本）"
        case (.both, .simple):
            return "示例：T:49.4M C:39.53"
        case (.both, .detailed):
            return "示例：I:45M O:4.4M C:39.53"
        }
    }

    private func openDataDirectory() {
        let dataDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/token-stats")
        NSWorkspace.shared.open(dataDir)
    }
}
