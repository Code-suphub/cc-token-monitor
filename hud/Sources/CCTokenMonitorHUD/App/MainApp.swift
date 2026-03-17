import SwiftUI

/// 统一的应用入口
@main
struct CCTokenMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// 应用委托 - 根据配置启动对应模式
class AppDelegate: NSObject, NSApplicationDelegate {
    private var floatingApp: FloatingWindowController?
    private var statusBarApp: StatusBarAppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = ConfigManager.shared.config

        switch config.displayMode {
        case .floating:
            // 启动悬浮窗模式
            floatingApp = FloatingWindowController()
            floatingApp?.start()
        case .statusBar:
            // 启动状态栏模式
            statusBarApp = StatusBarAppDelegate()
            statusBarApp?.applicationDidFinishLaunching(notification)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarApp?.applicationWillTerminate(notification)
    }
}

// MARK: - 悬浮窗模式控制器

class FloatingWindowController: NSObject {
    private var window: NSWindow?
    private var dataService = DataService()
    private var timer: Timer?
    private var detailWindow: NSWindow?
    private var configWindow: NSWindow?
    private var isShowingDialog = false  // 是否正在显示弹窗，用于禁用自动关闭

    func start() {
        NSApp.setActivationPolicy(.accessory)

        let contentView = FloatingContentView(
            dataService: dataService,
            onShowDetail: { [weak self] in
                self?.showDetail()
            },
            onShowConfig: { [weak self] in
                self?.showConfig()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // 设置初始位置 - 使用主屏幕中心
        // 优先使用 screens.first（主屏幕），因为 main 可能返回外接显示器
        let targetScreen = NSScreen.screens.first ?? NSScreen.main
        if let screen = targetScreen {
            let frame = screen.frame
            // macOS 坐标系：原点在左下角，y向上增长
            // 计算屏幕中心（考虑多显示器偏移）
            let centerX = frame.origin.x + frame.width / 2
            let centerY = frame.origin.y + frame.height / 2

            // 窗口大小 140x100，计算左下角原点位置
            let defaultX = centerX - 70
            let defaultY = centerY - 50

            // 如果有保存的位置，检查是否在屏幕范围内
            let config = ConfigManager.shared.config
            let x: CGFloat
            let y: CGFloat

            if let savedPos = config.position {
                // 确保位置在当前屏幕范围内
                x = max(frame.minX, min(savedPos.x, frame.maxX - 140))
                y = max(frame.minY, min(savedPos.y, frame.maxY - 100))
            } else {
                x = defaultX
                y = defaultY
            }

            window.setFrameOrigin(NSPoint(x: x, y: y))
            print("[HUD] Screen: \(frame), Window: (\(x), \(y)), Center: (\(centerX), \(centerY))")
        }

        self.window = window

        // 确保窗口显示
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }

        // 启动定时器
        startTimer()

        // 保存位置
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowMoved),
            name: NSWindow.didMoveNotification,
            object: window
        )

        // 监听窗口失去焦点，关闭详情面板
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )

        // 监听弹窗状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDialogNotification(_:)),
            name: NSNotification.Name("DisableAutoClose"),
            object: nil
        )
    }

    private func startTimer() {
        let interval = ConfigManager.shared.config.refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { _ in
            self.dataService.refreshData()
        }
        dataService.refreshData()
    }

    @objc private func windowMoved() {
        guard let frame = window?.frame else { return }
        ConfigManager.shared.savePosition(x: frame.origin.x, y: frame.origin.y)
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        // 如果正在显示弹窗，不关闭窗口
        if isShowingDialog {
            return
        }

        // 当面板窗口失去焦点时关闭它们
        if let resignedWindow = notification.object as? NSWindow {
            // 如果是面板窗口失去焦点，直接关闭
            if resignedWindow == detailWindow || resignedWindow == configWindow {
                DispatchQueue.main.async {
                    resignedWindow.close()
                }
                return
            }

            // 如果主悬浮窗失去焦点，关闭所有面板
            if resignedWindow == window {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    if self?.window?.isKeyWindow == false {
                        self?.detailWindow?.close()
                        self?.configWindow?.close()
                    }
                }
            }
        }
    }

    @objc private func handleDialogNotification(_ notification: Notification) {
        if let disable = notification.object as? Bool {
            isShowingDialog = disable
        }
    }

    /// 处理外部点击 - 当点击发生在面板外部时关闭面板
    func handleOutsideClick() {
        // 如果面板打开，检查是否需要关闭
        if let detailWindow = detailWindow, detailWindow.isVisible {
            // 如果点击不在面板内，关闭面板
            if !detailWindow.isKeyWindow {
                detailWindow.close()
            }
        }
        if let configWindow = configWindow, configWindow.isVisible {
            if !configWindow.isKeyWindow {
                configWindow.close()
            }
        }
    }

    /// 计算窗口显示位置（在悬浮窗下方）
    private func calculateWindowPosition(for popupWindow: NSWindow) -> NSPoint {
        guard let parentWindow = window else {
            return NSPoint(x: 0, y: 0)
        }

        let parentFrame = parentWindow.frame
        let popupSize = popupWindow.frame.size

        // 计算位置：悬浮窗下方居中
        let x = parentFrame.midX - popupSize.width / 2
        let y = parentFrame.minY - popupSize.height - 4 // 4pt 间距

        // 确保不超出屏幕边界
        guard let screen = parentWindow.screen ?? NSScreen.main else {
            return NSPoint(x: x, y: y)
        }

        let screenFrame = screen.visibleFrame
        var finalX = x
        var finalY = y

        // 右边界检查
        if finalX + popupSize.width > screenFrame.maxX {
            finalX = screenFrame.maxX - popupSize.width - 8
        }

        // 左边界检查
        if finalX < screenFrame.minX {
            finalX = screenFrame.minX + 8
        }

        // 下边界检查（如果下方空间不足，显示在悬浮窗上方）
        if finalY < screenFrame.minY {
            finalY = parentFrame.maxY + 4
        }

        return NSPoint(x: finalX, y: finalY)
    }

    private func showDetail() {
        // 关闭配置窗口
        configWindow?.close()

        // 如果详情窗口已存在，直接关闭（切换行为）
        if let detailWindow = detailWindow, detailWindow.isVisible {
            detailWindow.close()
            return
        }

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
        window.level = .floating + 1 // 确保在悬浮窗之上

        // 设置窗口委托，监听关闭事件
        window.delegate = self

        detailWindow = window

        // 计算并设置窗口位置
        let position = calculateWindowPosition(for: window)
        window.setFrameOrigin(position)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showConfig() {
        // 关闭详情窗口
        detailWindow?.close()

        // 如果配置窗口已存在，直接关闭
        if let configWindow = configWindow, configWindow.isVisible {
            configWindow.close()
            return
        }

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
        window.level = .floating + 1
        window.delegate = self

        configWindow = window

        // 计算并设置窗口位置
        let position = calculateWindowPosition(for: window)
        window.setFrameOrigin(position)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 窗口委托

extension FloatingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 窗口关闭时的清理
    }
}

// MARK: - 悬浮窗内容视图

struct FloatingContentView: View {
    @ObservedObject var dataService: DataService
    var onShowDetail: () -> Void
    var onShowConfig: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Tokens 行
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 10))
                Text(dataService.todayStats?.formattedTokens ?? "--")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text("tokens")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }

            // Cost 行
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 10))
                Text("$" + (dataService.todayStats?.formattedCost ?? "--"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.green)
                    .lineLimit(1)
                Text("cost")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }

            // 环比
            if let change = dataService.dayOverDayChange() {
                HStack(spacing: 2) {
                    Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8))
                    Text("\(abs(change * 100), specifier: "%.0f")%")
                        .font(.system(size: 8))
                }
                .foregroundColor(change >= 0 ? .red : .green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 140, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .onTapGesture {
            onShowDetail()
        }
        .contextMenu {
            Button("打开详情") {
                onShowDetail()
            }
            Button("设置") {
                onShowConfig()
            }
            Divider()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
