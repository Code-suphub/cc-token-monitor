import AppKit

/// macOS 桌面应用委托
class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var backendManager: BackendManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置为普通应用模式（显示 dock 图标）
        NSApp.setActivationPolicy(.regular)

        // 启动 Python 后端
        backendManager = BackendManager()
        backendManager?.start()

        // 创建主窗口（传入已启动的 backendManager）
        setupMainWindow()

        // 设置菜单
        setupMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        backendManager?.stop()
    }

    // MARK: - Window Setup

    private func setupMainWindow() {
        let contentView = WebViewContainer(backendManager: backendManager!)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CC Token Monitor"
        window.contentView = contentView
        window.minSize = NSSize(width: 800, height: 600)
        window.center()
        window.isReleasedWhenClosed = false

        // 从配置恢复窗口位置
        restoreWindowPosition(window)

        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreWindowPosition(_ window: NSWindow) {
        if let pos = ConfigManager.shared.windowPosition {
            window.setFrameOrigin(NSPoint(x: pos.x, y: pos.y))
        }
    }

    // MARK: - Menu Setup

    private func setupMenu() {
        let mainMenu = NSMenu()

        // 应用菜单
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(NSMenuItem(title: "关于 CC Token Monitor", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "设置...", action: #selector(showPreferences), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // 窗口菜单
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: "全屏", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f"))

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Actions

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showPreferences() {
        mainWindow?.makeKeyAndOrderFront(nil)
    }
}
