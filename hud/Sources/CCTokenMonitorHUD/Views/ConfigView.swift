import SwiftUI

/// 配置面板视图
struct ConfigView: View {
    @ObservedObject var configManager = ConfigManager.shared
    @ObservedObject var dataService: DataService
    var onBack: () -> Void

    @State private var showRestartAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                }

                Spacer()

                Text("设置")
                    .font(.headline)

                Spacer()

                // 占位保持平衡
                Text("返回")
                    .opacity(0)
            }
            .padding(.horizontal)
            .padding(.top)

            Divider()

            // 配置内容
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 显示模式
                    section("显示模式") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: displayModeBinding) {
                                Text("悬浮窗").tag(DisplayMode.floating)
                                Text("状态栏").tag(DisplayMode.statusBar)
                            }
                            .pickerStyle(.segmented)

                            Text(displayModeDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }

                    Divider()

                    // 状态栏显示内容（只在状态栏模式下有效）
                    section("状态栏显示") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: statusBarDisplayBinding) {
                                Text("Tokens").tag(StatusBarDisplay.tokens)
                                Text("Cost").tag(StatusBarDisplay.cost)
                                Text("两者").tag(StatusBarDisplay.both)
                            }
                            .pickerStyle(.segmented)

                            Text("选择状态栏中显示的内容")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }

                    Divider()

                    // 刷新间隔
                    section("刷新间隔") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: refreshIntervalBinding) {
                                Text("10秒").tag(10)
                                Text("30秒").tag(30)
                                Text("1分钟").tag(60)
                                Text("5分钟").tag(300)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    Divider()

                    // 悬浮窗选项（只在悬浮窗模式下有效）
                    section("悬浮窗选项") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("显示 Tokens", isOn: showTokensBinding)
                            Toggle("显示 Cost", isOn: showCostBinding)
                            Toggle("显示环比", isOn: showComparisonBinding)
                        }
                    }

                    Divider()

                    // 数据
                    section("数据") {
                        VStack(alignment: .leading, spacing: 12) {
                            Button("刷新数据") {
                                dataService.refreshData()
                            }

                            Button("打开数据目录") {
                                openDataDirectory()
                            }
                        }
                    }

                    Divider()

                    // 关于
                    section("关于") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CC Token Monitor HUD")
                                .font(.headline)
                            Text("版本 1.1.0")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            // 底部提示
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("显示模式更改需要重启应用生效")
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(width: 300, height: 450)
        .alert("需要重启", isPresented: $showRestartAlert) {
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

        // 创建一个后台任务来重启应用
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [
            "-c",
            "sleep 1 && \"\(executablePath)\" &"
        ]

        do {
            try task.run()
        } catch {
            print("Failed to restart: \(error)")
        }

        // 退出当前应用
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Bindings

    private var displayModeBinding: Binding<DisplayMode> {
        Binding(
            get: { configManager.config.displayMode },
            set: { newValue in
                configManager.update { $0.displayMode = newValue }
                showRestartAlert = true
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
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
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

    private func openDataDirectory() {
        let dataDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/token-stats")
        NSWorkspace.shared.open(dataDir)
    }
}
