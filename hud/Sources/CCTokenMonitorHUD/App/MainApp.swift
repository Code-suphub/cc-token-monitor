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
    private var configWindow: NSWindow?

    func start() {
        NSApp.setActivationPolicy(.accessory)

        let contentView = FloatingContentView(
            dataService: dataService,
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

        // 设置初始位置
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            let config = ConfigManager.shared.config
            let x = config.position?.x ?? (frame.origin.x + frame.width / 2 - 70)
            let y = config.position?.y ?? (frame.origin.y + frame.height / 2 - 50)
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)

        // 启动定时器
        startTimer()

        // 保存位置
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowMoved),
            name: NSWindow.didMoveNotification,
            object: window
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

    private func showConfig() {
        if configWindow == nil {
            let hostingView = NSHostingView(
                rootView: ConfigView(
                    dataService: dataService,
                    onBack: { [weak self] in
                        self?.configWindow?.close()
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
}

// MARK: - 悬浮窗内容视图

struct FloatingContentView: View {
    @ObservedObject var dataService: DataService
    var onShowConfig: () -> Void
    @State private var showDetail = false

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
            showDetail.toggle()
        }
        .sheet(isPresented: $showDetail) {
            DetailView(
                dataService: dataService,
                onShowConfig: onShowConfig
            )
        }
    }
}
