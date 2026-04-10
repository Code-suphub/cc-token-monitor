import SwiftUI
import os.log

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

// MARK: - 日志工具

/// 文件日志工具
class FileLogger {
    static let shared = FileLogger()
    private let logFile: URL
    private let dateFormatter: DateFormatter

    init() {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/token-stats")
        logFile = logDir.appendingPathComponent("hud-debug.log")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // 创建目录
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        // 写入启动标记
        log("=== HUD Started ===")
    }

    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"

        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                    _ = fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }

        // 同时输出到控制台
        print(message)
    }
}

// MARK: - 屏幕位置计算工具

/// 屏幕位置工具类 - 处理多屏幕场景下的窗口位置
class ScreenPositionUtility {
    /// 计算窗口在屏幕上的相对位置比例
    /// 返回 (xRatio, yRatio) 其中 0,0 是左下角，1,1 是右上角
    static func calculateRelativePosition(windowFrame: CGRect, screen: NSScreen) -> (x: Double, y: Double) {
        let screenFrame = screen.frame
        let windowCenterX = windowFrame.midX
        let windowCenterY = windowFrame.midY

        // 计算相对于屏幕的位置比例
        let xRatio = (windowCenterX - screenFrame.minX) / screenFrame.width
        let yRatio = (windowCenterY - screenFrame.minY) / screenFrame.height

        return (x: max(0, min(1, xRatio)), y: max(0, min(1, yRatio)))
    }

    /// 根据相对位置比例计算目标屏幕上的绝对位置
    static func calculateAbsolutePosition(
        relativeX: Double,
        relativeY: Double,
        windowSize: CGSize,
        targetScreen: NSScreen
    ) -> NSPoint {
        let screenFrame = targetScreen.frame

        // 计算目标屏幕上的中心点
        let targetCenterX = screenFrame.minX + screenFrame.width * relativeX
        let targetCenterY = screenFrame.minY + screenFrame.height * relativeY

        // 计算窗口原点（左下角）
        let originX = targetCenterX - windowSize.width / 2
        let originY = targetCenterY - windowSize.height / 2

        return NSPoint(x: originX, y: originY)
    }

    /// 将窗口位置限制在屏幕范围内
    static func constrainWindowToScreen(windowSize: CGSize, screen: NSScreen, margin: CGFloat = 8) -> NSPoint {
        let screenFrame = screen.visibleFrame

        // 默认放在右上角
        let x = screenFrame.maxX - windowSize.width - margin
        let y = screenFrame.maxY - windowSize.height - margin

        return NSPoint(x: x, y: y)
    }

    /// 找到包含给定点的屏幕，如果没有则返回主屏幕
    static func screenContaining(point: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                return screen
            }
        }
        return nil
    }

    /// 保存窗口位置（包含相对坐标和屏幕标识）
    static func saveWindowPosition(windowFrame: CGRect, for screen: NSScreen?, isUserAction: Bool = true) {
        guard let screen = screen ?? NSScreen.main else { return }

        let relativePos = calculateRelativePosition(windowFrame: windowFrame, screen: screen)
        let screenID = getScreenIdentifier(screen)

        ConfigManager.shared.savePositionWithContext(
            x: windowFrame.origin.x,
            y: windowFrame.origin.y,
            relativeX: relativePos.x,
            relativeY: relativePos.y,
            screenID: screenID,
            isUserAction: isUserAction
        )
    }

    /// 恢复窗口位置
    static func restoreWindowPosition(
        windowSize: CGSize,
        defaultScreen: NSScreen
    ) -> NSPoint {
        let config = ConfigManager.shared.config

        // 如果有保存的上下文信息，优先使用相对位置
        if let posContext = config.positionContext,
           let savedScreenID = posContext.screenID {

            // 尝试找到原来的屏幕
            if let originalScreen = findScreen(by: savedScreenID) {
                // 原屏幕还在，使用保存的相对位置
                return calculateAbsolutePosition(
                    relativeX: posContext.relativeX,
                    relativeY: posContext.relativeY,
                    windowSize: windowSize,
                    targetScreen: originalScreen
                )
            }

            // 尝试最佳匹配
            if let matchedScreen = findBestMatchingScreen(savedID: savedScreenID) {
                return calculateAbsolutePosition(
                    relativeX: posContext.relativeX,
                    relativeY: posContext.relativeY,
                    windowSize: windowSize,
                    targetScreen: matchedScreen
                )
            }

            // 原屏幕不在，使用相对位置应用到默认屏幕
            // 这样可以保持"右上角还在右上角"
            return calculateAbsolutePosition(
                relativeX: posContext.relativeX,
                relativeY: posContext.relativeY,
                windowSize: windowSize,
                targetScreen: defaultScreen
            )
        }

        // 旧版配置兼容：直接返回保存的坐标
        if let savedPos = config.position {
            // 检查是否在可见屏幕范围内
            let point = NSPoint(x: savedPos.x, y: savedPos.y)
            if screenContaining(point: point) != nil {
                // 位置有效，直接使用
                return point
            }
            // 位置不在任何屏幕上，尝试映射到默认屏幕
            if let originalScreen = NSScreen.screens.first(where: {
                $0.frame.contains(NSPoint(x: savedPos.x, y: savedPos.y))
            }) {
                let windowFrame = CGRect(origin: point, size: windowSize)
                let relativePos = calculateRelativePosition(windowFrame: windowFrame, screen: originalScreen)
                return calculateAbsolutePosition(
                    relativeX: relativePos.x,
                    relativeY: relativePos.y,
                    windowSize: windowSize,
                    targetScreen: defaultScreen
                )
            }
        }

        // 默认：右上角
        return constrainWindowToScreen(windowSize: windowSize, screen: defaultScreen)
    }

    /// 获取屏幕唯一标识（使用更稳定的属性）
    static func getScreenIdentifier(_ screen: NSScreen) -> String {
        // 组合多个属性来识别屏幕，更稳定
        // 包括：分辨率、DPI、名称
        let frame = screen.frame
        let backingScale = screen.backingScaleFactor
        let name = screen.localizedName.replacingOccurrences(of: "-", with: "_")

        // 使用 # 作为分隔符，因为屏幕名称中可能包含 -
        let id = "\(name)#\(Int(frame.width))x\(Int(frame.height))#\(backingScale)"

        // 对于外接显示器，尝试使用更稳定的标识
        // 注意：frame.origin 会在屏幕排列改变时变化，不作为主要标识
        return id
    }

    /// 查找最佳匹配的屏幕（支持部分匹配）
    static func findBestMatchingScreen(savedID: String) -> NSScreen? {
        // 首先尝试精确匹配
        if let exact = findScreen(by: savedID) {
            return exact
        }

        // 检查是否是旧格式 ID (如 "1512x982@0,0" 或 "1920x1080@1512,0")
        if savedID.contains("@") {
            // 旧格式: "WIDTHxHEIGHT@X,Y" 或 "WIDTHxHEIGHT@X,Y-HIDPI"
            // 提取分辨率部分 (在 @ 之前的部分)
            let resolutionPart = savedID.split(separator: "@").first
            if let resolution = resolutionPart {
                let savedRes = String(resolution) // "1512x982"

                for screen in NSScreen.screens {
                    let currentID = getScreenIdentifier(screen)
                    let currentParts = currentID.split(separator: "#")

                    if currentParts.count >= 2 {
                        let currentResolution = String(currentParts[1]) // "1512x982"

                        if currentResolution == savedRes {
                            return screen
                        }
                    }
                }
            }
            return nil
        }

        // 解析新格式的ID (name#resolution#scale)
        let parts = savedID.split(separator: "#")
        guard parts.count >= 2 else {
            return nil
        }

        let savedName = String(parts[0])
        let savedResolution = String(parts[1])

        // 尝试按名称和分辨率匹配（忽略位置）
        for screen in NSScreen.screens {
            let currentID = getScreenIdentifier(screen)
            let currentParts = currentID.split(separator: "#")

            if currentParts.count >= 2 {
                let currentName = String(currentParts[0])
                let currentResolution = String(currentParts[1])

                // 名称和分辨率都匹配
                if currentName == savedName && currentResolution == savedResolution {
                    return screen
                }
            }
        }

        return nil
    }

    /// 根据标识查找屏幕
    static func findScreen(by identifier: String) -> NSScreen? {
        for screen in NSScreen.screens {
            if getScreenIdentifier(screen) == identifier {
                return screen
            }
        }
        return nil
    }
}

// MARK: - 悬浮窗模式控制器

class FloatingWindowController: NSObject {
    private var window: NSWindow?
    private var dataService = DataService()
    private var timer: Timer?
    private var detailWindow: NSWindow?
    private var configWindow: NSWindow?
    private var isShowingDialog = false

    // 多屏幕位置跟踪
    private var lastKnownScreenID: String?  // 上次窗口所在的屏幕ID
    private var currentScreenID: String?    // 当前窗口所在的屏幕ID
    private var wasRelocatedToMainScreen = false  // 是否曾经被移动到主屏幕（用于判断是否自动回原屏幕）
    private var lastKnownScreenCount = 0    // 上次已知的屏幕数量（用于检测屏幕连接/断开）
    private var isSystemRelocation = false  // 标记是否正在进行系统强制迁移（屏幕断开时）
    private var systemRelocationUntil: Date? = nil  // 系统迁移冷却期截止时间

    // 定时保存位置，确保屏幕变化被记录
    private var savePositionTimer: Timer?

    func start() {
        NSApp.setActivationPolicy(.accessory)

        FileLogger.shared.log("[HUD] Starting floating window...")

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

        // 使用新的位置恢复逻辑
        let windowSize = CGSize(width: 140, height: 100)
        let targetScreen = NSScreen.screens.first ?? NSScreen.main
        if let screen = targetScreen {
            let position = ScreenPositionUtility.restoreWindowPosition(
                windowSize: windowSize,
                defaultScreen: screen
            )
            window.setFrameOrigin(position)

            // 初始化屏幕跟踪
            let screenID = ScreenPositionUtility.getScreenIdentifier(screen)
            currentScreenID = screenID
            lastKnownScreenID = screenID
            lastKnownScreenCount = NSScreen.screens.count
            FileLogger.shared.log("[HUD] Initial screen: \(screenID.components(separatedBy: "#").first ?? "unknown") (screens: \(lastKnownScreenCount))")
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

        // 启动位置保存定时器（每2秒保存一次位置，确保屏幕变化被记录）
        startSavePositionTimer()

        // 监听窗口失去焦点
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

        // 监听屏幕参数变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        FileLogger.shared.log("[HUD] Setup complete")
    }

    private func startSavePositionTimer() {
        // 每2秒检查并保存位置
        savePositionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkAndSavePosition()
        }
    }

    private func checkAndSavePosition() {
        guard let window = window else { return }

        let currentScreenCount = NSScreen.screens.count

        // 检测屏幕数量变化（连接/断开显示器）
        if lastKnownScreenCount > 0 && currentScreenCount != lastKnownScreenCount {
            FileLogger.shared.log("[Screen] Screen count changed: \(lastKnownScreenCount) -> \(currentScreenCount)")

            // 屏幕增加了，不要重置冷却期！让冷却期自然结束或由 handleScreenChange 处理
            if currentScreenCount > lastKnownScreenCount {
                FileLogger.shared.log("[Screen] Screen connected, waiting for screenParametersChanged")
            } else {
                // 屏幕减少了，标记系统强制迁移即将发生
                isSystemRelocation = true
                // 设置冷却期：5秒内不检测位置变化（防止误判为用户移动）
                systemRelocationUntil = Date().addingTimeInterval(5.0)
                FileLogger.shared.log("[Screen] Screen disconnected, marking system relocation (cooldown 5s)")
            }

            lastKnownScreenCount = currentScreenCount
            return
        }

        lastKnownScreenCount = currentScreenCount

        // 检查是否在系统迁移冷却期内
        if let cooldown = systemRelocationUntil, Date() < cooldown {
            // 仍在冷却期内，只保存位置但不检测屏幕切换
            let windowCenter = window.frame.center
            for screen in NSScreen.screens {
                if screen.frame.contains(windowCenter) {
                    ScreenPositionUtility.saveWindowPosition(windowFrame: window.frame, for: screen, isUserAction: false)
                    // 静默更新 currentScreenID，不记录日志
                    currentScreenID = ScreenPositionUtility.getScreenIdentifier(screen)
                    lastKnownScreenID = currentScreenID
                    break
                }
            }
            return
        } else if systemRelocationUntil != nil {
            // 冷却期结束
            systemRelocationUntil = nil
            isSystemRelocation = false
            FileLogger.shared.log("[Screen] System relocation cooldown ended")
        }

        // 找到窗口实际所在的屏幕
        let windowCenter = window.frame.center
        var actualScreen: NSScreen?

        for screen in NSScreen.screens {
            if screen.frame.contains(windowCenter) {
                actualScreen = screen
                break
            }
        }

        guard let screen = actualScreen else { return }

        let screenID = ScreenPositionUtility.getScreenIdentifier(screen)

        // 如果屏幕变化了，更新保存并记录日志
        if screenID != currentScreenID {
            let screenName = screenID.components(separatedBy: "#").first ?? "unknown"
            let prevName = currentScreenID?.components(separatedBy: "#").first ?? "nil"

            // 检查是否是系统强制迁移（屏幕断开导致）
            if isSystemRelocation {
                FileLogger.shared.log("[Screen] System relocated window from '\(prevName)' to '\(screenName)' (preserving preferredScreenID)")
                // 系统强制迁移，不更新 preferredScreenID
                ScreenPositionUtility.saveWindowPosition(windowFrame: window.frame, for: screen, isUserAction: false)
                isSystemRelocation = false  // 重置标志
            } else {
                FileLogger.shared.log("[Screen] User moved window from '\(prevName)' to '\(screenName)'")
                // 用户主动拖动导致的屏幕切换，更新 preferredScreenID
                ScreenPositionUtility.saveWindowPosition(windowFrame: window.frame, for: screen, isUserAction: true)
            }

            currentScreenID = screenID
            lastKnownScreenID = screenID
        } else {
            // 屏幕没变，只更新位置（不记录日志，不更新 preferredScreenID）
            ScreenPositionUtility.saveWindowPosition(windowFrame: window.frame, for: screen, isUserAction: false)
        }
    }

    private func startTimer() {
        let interval = ConfigManager.shared.config.refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { _ in
            self.dataService.refreshData()
        }
        dataService.refreshData()
    }

    @objc private func windowMoved() {
        guard let window = window,
              let screen = window.screen else { return }

        // 保存窗口位置
        ScreenPositionUtility.saveWindowPosition(windowFrame: window.frame, for: screen)

        // 更新当前屏幕跟踪
        currentScreenID = ScreenPositionUtility.getScreenIdentifier(screen)
        lastKnownScreenID = currentScreenID
    }

    @objc private func screenParametersChanged() {
        FileLogger.shared.log("[Screen] Screen configuration changed, screens: \(NSScreen.screens.count)")

        guard window != nil else { return }

        // 延迟执行，给系统时间完成屏幕配置
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.handleScreenChange()
        }
    }

    private func handleScreenChange() {
        guard let window = window else { return }

        let config = ConfigManager.shared.config
        let windowSize = window.frame.size
        let windowCenter = window.frame.center

        // 调试日志
        let preferredID = config.positionContext?.preferredScreenID ?? "nil"
        let currentID = config.positionContext?.screenID ?? "nil"
        FileLogger.shared.log("[ScreenChange] preferredScreenID: \(preferredID), screenID: \(currentID)")
        FileLogger.shared.log("[ScreenChange] Available screens: \(NSScreen.screens.map { ScreenPositionUtility.getScreenIdentifier($0).components(separatedBy: "#").first! })")

        // 优先使用 preferredScreenID（用户最后主动放置的屏幕）
        // 如果 preferredScreenID 不存在，回退到当前的 screenID
        let targetScreenID = config.positionContext?.preferredScreenID ?? config.positionContext?.screenID

        // 先检查窗口当前在哪个屏幕上
        var currentScreen: NSScreen?
        for screen in NSScreen.screens {
            if screen.frame.contains(windowCenter) {
                currentScreen = screen
                break
            }
        }

        FileLogger.shared.log("[ScreenChange] Window currently on screen: \(currentScreen.map { ScreenPositionUtility.getScreenIdentifier($0).components(separatedBy: "#").first! } ?? "nil")")

        // 情况1: 检查目标屏幕（用户偏好的屏幕）是否重新连接
        if let preferredID = targetScreenID {
            FileLogger.shared.log("[ScreenChange] Looking for target screen: \(preferredID)")

            // 使用最佳匹配查找（支持位置变化后的屏幕重连）
            if let targetScreen = ScreenPositionUtility.findBestMatchingScreen(savedID: preferredID) {
                let targetName = preferredID.components(separatedBy: "#").first ?? "unknown"
                FileLogger.shared.log("[ScreenChange] Found target screen: \(targetName)")

                // 目标屏幕存在，检查窗口是否已经在该屏幕上
                let isOnTargetScreen = targetScreen.frame.contains(windowCenter)
                FileLogger.shared.log("[ScreenChange] isOnTargetScreen: \(isOnTargetScreen)")

                if !isOnTargetScreen {
                    // 窗口不在目标屏幕上，移回目标屏幕的相对位置
                    if let posContext = config.positionContext {
                        let newPosition = ScreenPositionUtility.calculateAbsolutePosition(
                            relativeX: posContext.relativeX,
                            relativeY: posContext.relativeY,
                            windowSize: windowSize,
                            targetScreen: targetScreen
                        )

                        FileLogger.shared.log("[ScreenChange] Target screen frame: \(targetScreen.frame)")
                        FileLogger.shared.log("[ScreenChange] Calculated position: (\(Int(newPosition.x)), \(Int(newPosition.y))) for relative (\(String(format: "%.2f", posContext.relativeX)), \(String(format: "%.2f", posContext.relativeY)))")

                        // 直接设置位置，不使用动画，确保立即生效
                        window.setFrameOrigin(newPosition)

                        FileLogger.shared.log("[Screen] Moved window back to preferred screen '\(targetName)' at (\(Int(newPosition.x)), \(Int(newPosition.y)))")

                        // 验证移动是否成功
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                            let actualCenter = window.frame.center
                            let isOnTarget = targetScreen.frame.contains(actualCenter)
                            FileLogger.shared.log("[Screen] Verification: window at (\(Int(actualCenter.x)), \(Int(actualCenter.y))), on target screen: \(isOnTarget)")
                        }

                        // 更新当前屏幕跟踪，但不更新 preferredScreenID（因为是自动迁移）
                        let newScreenID = ScreenPositionUtility.getScreenIdentifier(targetScreen)
                        currentScreenID = newScreenID
                        lastKnownScreenID = newScreenID

                        // 保存位置
                        let targetFrame = CGRect(origin: newPosition, size: windowSize)
                        ScreenPositionUtility.saveWindowPosition(windowFrame: targetFrame, for: targetScreen, isUserAction: false)

                        // 设置冷却期，防止 checkAndSavePosition 误判为用户移动
                        systemRelocationUntil = Date().addingTimeInterval(3.0)
                        isSystemRelocation = false
                    }
                } else {
                    FileLogger.shared.log("[ScreenChange] Already on target screen, no action needed")
                }

                return
            } else {
                FileLogger.shared.log("[ScreenChange] Target screen not found!")
            }
        } else {
            FileLogger.shared.log("[ScreenChange] No targetScreenID set!")
        }

        // 情况2: 目标屏幕未连接，检查窗口是否还在可见屏幕上
        if currentScreen == nil {
            if let mainScreen = NSScreen.screens.first {
                let newPosition = ScreenPositionUtility.restoreWindowPosition(
                    windowSize: windowSize,
                    defaultScreen: mainScreen
                )

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    window.animator().setFrameOrigin(newPosition)
                }

                FileLogger.shared.log("[Screen] Relocated window to main screen (preferred display disconnected)")

                // 更新当前屏幕，但不更新 preferredScreenID
                let mainScreenID = ScreenPositionUtility.getScreenIdentifier(mainScreen)
                currentScreenID = mainScreenID
                lastKnownScreenID = mainScreenID

                // 使用目标位置创建临时 frame 来保存
                let targetFrame = CGRect(origin: newPosition, size: windowSize)
                ScreenPositionUtility.saveWindowPosition(windowFrame: targetFrame, for: mainScreen, isUserAction: false)

                // 设置冷却期
                systemRelocationUntil = Date().addingTimeInterval(3.0)
                isSystemRelocation = false
            }
        }
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        if isShowingDialog {
            return
        }

        if let resignedWindow = notification.object as? NSWindow {
            if resignedWindow == detailWindow || resignedWindow == configWindow {
                DispatchQueue.main.async {
                    resignedWindow.close()
                }
                return
            }

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

    /// 处理外部点击
    func handleOutsideClick() {
        if let detailWindow = detailWindow, detailWindow.isVisible {
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

        let x = parentFrame.midX - popupSize.width / 2
        let y = parentFrame.minY - popupSize.height - 4

        guard let screen = parentWindow.screen ?? NSScreen.main else {
            return NSPoint(x: x, y: y)
        }

        let screenFrame = screen.visibleFrame
        var finalX = x
        var finalY = y

        if finalX + popupSize.width > screenFrame.maxX {
            finalX = screenFrame.maxX - popupSize.width - 8
        }

        if finalX < screenFrame.minX {
            finalX = screenFrame.minX + 8
        }

        if finalY < screenFrame.minY {
            finalY = parentFrame.maxY + 4
        }

        return NSPoint(x: finalX, y: finalY)
    }

    private func showDetail() {
        configWindow?.close()

        if let detailWindow = detailWindow, detailWindow.isVisible {
            detailWindow.close()
            return
        }

        let hostingView = NSHostingView(
            rootView: MenuBarPanel(
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
        window.level = .floating + 1
        window.delegate = self

        detailWindow = window

        let position = calculateWindowPosition(for: window)
        window.setFrameOrigin(position)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showConfig() {
        detailWindow?.close()

        if let configWindow = configWindow, configWindow.isVisible {
            configWindow.close()
            return
        }

        let hostingView = NSHostingView(
            rootView: SettingsPanel(
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

// MARK: - 辅助扩展

extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
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
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
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
