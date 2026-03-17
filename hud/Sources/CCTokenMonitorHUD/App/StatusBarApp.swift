import SwiftUI
import AppKit

/// 状态栏模式控制器
class StatusBarAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var dataService = DataService()
    private var timer: Timer?

    // 面板窗口
    private var detailWindow: NSWindow?
    private var configWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置为 accessory 模式（不显示 dock 图标）
        NSApp.setActivationPolicy(.accessory)

        // 创建状态栏项
        setupStatusBar()

        // 开始数据刷新
        startTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    // MARK: - Setup

    private var statusMenu: NSMenu!

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }

        // 初始设置
        updateStatusBarDisplay()

        // 创建菜单但不立即设置（避免拦截点击事件）
        statusMenu = createMenu()

        // 点击处理 - 使用 target/action 模式
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "今日统计", action: #selector(showDetail), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "刷新数据", action: #selector(refreshData), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "设置", action: #selector(showConfig), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        return menu
    }

    // MARK: - Timer

    private func startTimer() {
        let interval = ConfigManager.shared.config.refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { _ in
            self.dataService.refreshData()
            self.updateStatusBarDisplay()
        }
        dataService.refreshData()
    }

    // MARK: - Display Update

    private func updateStatusBarDisplay() {
        guard let button = statusItem.button else { return }

        let config = ConfigManager.shared.config
        let stats = dataService.todayStats

        switch config.statusBarDisplay {
        case .tokens:
            let text = stats?.formattedTokens ?? "--"
            button.title = text

        case .cost:
            let text = stats?.formattedCost ?? "--"
            button.title = "\(text)"

        case .both:
            // 两行显示效果：Tokens | Cost
            let tokens = stats?.formattedTokens ?? "--"
            let cost = stats?.formattedCost ?? "--"
            button.title = "\(tokens) | \(cost)"
        }

        // 设置字体
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }

    // MARK: - Actions

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        // 区分左右键
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            // 右键显示菜单
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            // 清除 menu 以便下次左键点击能正常触发 action
            statusItem.menu = nil
        } else {
            // 左键显示详情
            showDetail()
        }
    }

    @objc private func showDetail() {
        // 关闭配置窗口
        configWindow?.close()

        if detailWindow == nil {
            let hostingView = NSHostingView(
                rootView: DetailView(
                    dataService: dataService,
                    onShowConfig: { [weak self] in
                        self?.showConfig()
                    }
                )
            )

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Token Monitor"
            window.contentView = hostingView
            window.isReleasedWhenClosed = false
            window.center()

            detailWindow = window
        }

        detailWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showConfig() {
        // 关闭详情窗口
        detailWindow?.close()

        if configWindow == nil {
            let hostingView = NSHostingView(
                rootView: ConfigView(
                    dataService: dataService,
                    onBack: { [weak self] in
                        self?.configWindow?.close()
                        self?.showDetail()
                    }
                )
            )

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 450),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "设置"
            window.contentView = hostingView
            window.isReleasedWhenClosed = false
            window.center()

            configWindow = window
        }

        configWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refreshData() {
        dataService.refreshData()
        updateStatusBarDisplay()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
