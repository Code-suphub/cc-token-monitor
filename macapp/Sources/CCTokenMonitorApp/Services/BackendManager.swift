import Foundation

/// Python 后端进程管理器
class BackendManager {
    private var process: Process?
    private var outputPipe: Pipe?
    private var isRunning = false
    private let logFile: URL

    var onBackendReady: (() -> Void)?
    var onBackendError: ((String) -> Void)?

    init() {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/token-stats")
        logFile = logDir.appendingPathComponent("macapp-error.log")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    /// 启动 Python 后端服务
    func start() {
        // 如果已经在运行，先停止
        stop()

        // 清理可能占用 8866 端口的旧进程（等一等确保进程退出）
        cleanupPort(8866)
        Thread.sleep(forTimeInterval: 0.5)

        // 获取 backend 路径
        guard let backendPath = findBackendPath() else {
            onBackendError?("找不到 backend 目录")
            return
        }

        // 构建启动命令
        let scriptPath = "\(backendPath)/app.py"
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            onBackendError?("找不到 app.py: \(scriptPath)")
            return
        }

        writeLog("启动 Python: \(scriptPath)")

        // 使用 launchd 或直接启动 Python
        // 这里用直接启动方式，简单直接
        launchPythonBackend(scriptPath: scriptPath)
    }

    /// 清理占用指定端口的进程
    private func cleanupPort(_ port: Int) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-ti:\(port)"]

        let outputPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()

            let data = outputPipe.fileHandleForReading.availableData
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                // 有进程占用，杀掉它们
                let pids = output.split(separator: "\n").map { String($0) }
                for pid in pids {
                    let killProc = Process()
                    killProc.executableURL = URL(fileURLWithPath: "/bin/kill")
                    killProc.arguments = ["-9", pid]
                    try? killProc.run()
                }
                writeLog("已清理占用端口 \(port) 的进程: \(output)")
            }
        } catch {
            // 忽略错误
        }
    }

    /// 停止后端服务
    func stop() {
        if let process = process, process.isRunning {
            process.terminate()
        }
        process = nil
        isRunning = false
    }

    /// 查找 backend 目录
    private func findBackendPath() -> String? {
        // 获取应用所在目录（开发时是项目根目录，打包后是 app bundle 目录）
        let exePath = Bundle.main.executablePath ?? ""
        let appDir = (exePath as NSString).deletingLastPathComponent // macapp/Contents/MacOS
        let contentsDir = (appDir as NSString).deletingLastPathComponent // macapp/Contents
        let bundleDir = (contentsDir as NSString).deletingLastPathComponent // macapp

        // 开发时：bundleDir 是 macapp，上级是项目根目录
        // 打包后：bundleDir 是 app bundle，上级是 Contents，上上级是 bundle

        // 尝试多种路径
        let possiblePaths = [
            "\(bundleDir)/../../backend",  // 从 bundle 上级找
            "\(bundleDir)/../backend",      // 从 Contents 上级找
            "\(bundleDir)/backend",        // 相对 bundle
            "/Users/bilibili/data/projects/cc-token-monitor/backend"  // 直接路径（开发用）
        ]

        for path in possiblePaths {
            let fullPath = (path as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: "\(fullPath)/app.py") {
                return fullPath
            }
        }

        return nil
    }

    /// 启动 Python 后端
    private func launchPythonBackend(scriptPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [scriptPath, "8866"]

        // 设置工作目录
        let workDir = (scriptPath as NSString).deletingLastPathComponent
        proc.currentDirectoryURL = URL(fileURLWithPath: workDir)

        do {
            try proc.run()
            process = proc

            // 直接用端口检测判断启动成功，不再依赖输出解析
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkBackendAndNotify()
            }
        } catch {
            onBackendError?("启动 Python 失败: \(error.localizedDescription)")
        }
    }

    /// 检查后端是否就绪
    private func checkBackendAndNotify() {
        if checkPort(8866) {
            isRunning = true
            onBackendReady?()
        } else {
            // 每 0.5 秒检查一次，最多 15 秒
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, !self.isRunning else { return }

                if self.checkPort(8866) {
                    self.isRunning = true
                    self.onBackendReady?()
                } else {
                    // 继续检查
                    self.checkBackendAndNotify()
                }
            }
        }
    }

    /// 写入日志
    private func writeLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
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
        print(message)
    }

    /// 检查端口是否可用
    private func checkPort(_ port: Int) -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)")!
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 1

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                // 任何非连接错误的响应都认为服务已启动
                success = (httpResponse.statusCode >= 200 && httpResponse.statusCode < 600)
            }
            semaphore.signal()
        }
        task.resume()

        _ = semaphore.wait(timeout: .now() + 1)
        return success
    }
}
