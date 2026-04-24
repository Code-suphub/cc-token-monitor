import AppKit
import WebKit

/// WebView 容器视图
class WebViewContainer: NSView {
    private var webView: WKWebView!
    private var backendManager: BackendManager
    private var progressIndicator: NSProgressIndicator?
    private var retryButton: NSButton?
    private var statusLabel: NSTextField?

    var onBackendReady: (() -> Void)?

    init(backendManager: BackendManager) {
        self.backendManager = backendManager
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // 创建进度指示器
        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        progress.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progress)
        progressIndicator = progress

        // 创建状态标签
        let label = NSTextField(labelWithString: "正在启动服务...")
        label.font = NSFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        statusLabel = label

        NSLayoutConstraint.activate([
            progress.centerXAnchor.constraint(equalTo: centerXAnchor),
            progress.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),

            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 16)
        ])

        // 设置后端回调
        backendManager.onBackendReady = { [weak self] in
            DispatchQueue.main.async {
                self?.loadWebInterface()
            }
        }
        backendManager.onBackendError = { [weak self] error in
            DispatchQueue.main.async {
                self?.showError(error)
            }
        }
    }

    private func loadWebInterface() {
        // 隐藏加载状态
        progressIndicator?.stopAnimation(nil)
        progressIndicator?.isHidden = true
        statusLabel?.isHidden = true
        retryButton?.isHidden = true

        // 创建 WKWebView
        let config = WKWebViewConfiguration()
        if #available(macOS 11.0, *) {
            config.websiteDataStore = .default()
        }

        webView = WKWebView(frame: bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)

        // 加载 Web 界面
        let url = URL(string: "http://127.0.0.1:8866")!
        let request = URLRequest(url: url)
        webView.load(request)

        onBackendReady?()
    }

    private func showError(_ error: String) {
        progressIndicator?.stopAnimation(nil)
        statusLabel?.stringValue = "启动失败"
        statusLabel?.textColor = .systemRed
    }
}
