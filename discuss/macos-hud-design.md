# CC Token Monitor macOS 悬浮窗设计文档

## 1. 概述

为 CC Token Monitor 增加 macOS 原生悬浮窗（Head-up Display, HUD），提供轻量级实时监控能力。

## 2. 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                     CC Token Monitor HUD                    │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   L1 HUD    │───→│   L2 面板   │───→│  Web 全界面  │     │
│  │  悬浮迷你窗  │    │  7天趋势详情 │    │ (现有 web)   │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         ↑                                                   │
│  ┌─────────────┐    ┌─────────────┐                        │
│  │  DataService │←──│ Python Bridge │←── ~/.claude/token-stats │
│  │  (Swift)     │    │ (Process)    │                        │
│  └─────────────┘    └─────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

## 3. 技术栈

- **语言**: Swift 5.9+
- **UI 框架**: SwiftUI
- **最低系统**: macOS 12.0 (Monterey)
- **架构**: Swift Package Manager 项目

## 4. 功能设计

### 4.1 三种形态（配置项）

| 形态 | 优先级 | 说明 |
|------|--------|------|
| **A. 悬浮窗 (HUD)** | P0 | 可拖动的小型悬浮面板，始终置顶 |
| **B. 菜单栏 (Menu Bar)** | P1 | 菜单栏图标+下拉面板（配置项占位） |
| **C. 边缘停靠 (Dock)** | P1 | 屏幕边缘固定面板（配置项占位） |

默认形态：**A. 悬浮窗**

### 4.2 层级设计

#### L1 - 悬浮迷你窗（始终显示）

```
┌─────────────────┐
│  📊    💰       │  ← 图标行
│  23.5K  $0.45   │  ← 今日 Tokens / Cost
│  ─────────────  │
│  ↑ 环比 +12%    │  ← 对比昨日（可选显示）
└─────────────────┘
   尺寸: 120 x 80 pt
   圆角: 12 pt
   阴影: 系统默认
```

**显示内容组合:**
- 今日总 Tokens (input + output)
- 今日预估 Cost (USD)
- 环比变化指示器（红/绿箭头）

**交互:**
- 拖拽：按住标题栏/空白处拖动位置
- 点击：展开 L2 详细面板
- 右击：显示上下文菜单

#### L2 - 详细面板（点击展开）

```
┌─────────────────────────┐
│  CC Token Monitor    [×] │
├─────────────────────────┤
│  📅 今天                │
│  ┌─────┐ Tokens: 23.5K │
│  │ 趋势 │ Cost:   $0.45 │
│  │ 图表 │ Sessions: 12  │
│  └─────┘                │
├─────────────────────────┤
│  📊 近7天               │
│  [迷你柱状图]            │
│  平均: 18K/天           │
├─────────────────────────┤
│  📁 今日项目 Top3       │
│  1. project-a    15.2K  │
│  2. project-b     8.3K  │
│  3. project-c     0.1K  │
├─────────────────────────┤
│  [打开完整界面] [设置]   │
└─────────────────────────┘
   尺寸: 280 x 400 pt
   动画: 从 L1 展开 (scale + fade)
```

#### L3 - Web 全界面

点击 L2 的「打开完整界面」跳转浏览器访问 `http://localhost:PORT`

### 4.3 数据刷新

- **频率**: 每 30 秒自动刷新
- **触发**: 定时器 + 检测到文件变化时
- **策略**: 增量读取，只读今日数据文件

### 4.4 配置项

```swift
struct HUDConfig: Codable {
    // 形态选择（P0 只实现 HUD）
    var displayMode: DisplayMode = .hud
    enum DisplayMode: String, Codable {
        case hud        // 悬浮窗
        case menuBar    // 菜单栏（占位）
        case dock       // 边缘停靠（占位）
    }

    // L1 显示配置
    var showTokens: Bool = true
    var showCost: Bool = true
    var showComparison: Bool = true  // 环比
    var currency: String = "USD"     // USD/CNY

    // 外观
    var opacity: Double = 0.95       // 背景透明度
    var cornerRadius: Double = 12
    var fontSize: FontSize = .medium
    enum FontSize: String, Codable {
        case small, medium, large
    }

    // 行为
    var refreshInterval: Int = 30    // 秒
    var autoStart: Bool = false      // 开机自启
    var snapToEdges: Bool = true     // 靠近边缘时吸附
    var hideWhenInactive: Bool = false  // 失去焦点时隐藏

    // 位置记忆
    var lastPosition: CGPoint?       // 上次关闭时的位置
}
```

## 5. UI 设计规范

### 5.1 颜色方案（跟随系统）

**Light Mode:**
- 背景: `NSColor.windowBackgroundColor` (带透明度 0.95)
- 文字: `NSColor.label`
- 次要文字: `NSColor.secondaryLabel`
- 正向（节省）: `#28C840`
- 负向（增长）: `#FF453A`

**Dark Mode:**
- 背景: `NSColor.controlBackgroundColor` (带透明度 0.95)
- 其余跟随系统动态颜色

### 5.2 字体规范

| 元素 | 字体 | 大小 | 字重 |
|------|------|------|------|
| 主数值 | SF Pro Display | 16pt | Semibold |
| 单位 | SF Pro Text | 10pt | Regular |
| 标签 | SF Pro Text | 9pt | Medium |
| 次要信息 | SF Pro Text | 11pt | Regular |

### 5.3 动画规范

- L1 → L2 展开: `scale(0.8→1.0) + opacity(0→1)`, duration 0.2s, ease-out
- 数据更新: `opacity flash`, duration 0.15s
- 拖拽释放: `spring animation` 吸附到边缘

## 6. 项目结构

```
cc-token-monitor-hud/
├── Package.swift
├── Sources/
│   ├── CCTokenMonitorHUD/
│   │   ├── App/
│   │   │   ├── CCTokenMonitorHUDApp.swift      # App 入口
│   │   │   └── AppDelegate.swift               # 生命周期
│   │   ├── Views/
│   │   │   ├── L1MiniWidget.swift              # 悬浮迷你窗
│   │   │   ├── L2DetailPanel.swift             # 详细面板
│   │   │   ├── TokenChartView.swift            # 趋势图表
│   │   │   └── SettingsView.swift              # 设置界面
│   │   ├── Models/
│   │   │   ├── TokenData.swift                 # 数据模型
│   │   │   ├── HUDConfig.swift                 # 配置模型
│   │   │   └── DailyStats.swift                # 统计模型
│   │   ├── Services/
│   │   │   ├── DataService.swift               # 数据读取服务
│   │   │   ├── PythonBridge.swift              # Python 桥接
│   │   │   └── ConfigManager.swift             # 配置管理
│   │   └── Utils/
│   │       ├── WindowManager.swift             # 窗口管理
│   │       ├── AutoStartHelper.swift           # 开机自启
│   │       └── Formatters.swift                # 格式化工具
│   └── PythonBridge/
│       └── read_stats.py                       # Python 数据读取脚本
├── Resources/
│   ├── Assets.xcassets/
│   └── Info.plist
└── Tests/
```

## 7. 核心类设计

### 7.1 DataService

```swift
class DataService: ObservableObject {
    @Published var todayStats: DailyStats?
    @Published var recentStats: [DailyStats]?
    @Published var isLoading: Bool = false

    func refreshData()
    func startTimer(interval: TimeInterval)
    func stopTimer()
}
```

### 7.2 WindowManager

```swift
class WindowManager {
    static let shared = WindowManager()

    func showL1Widget()
    func showL2Panel()
    func hideL2Panel()
    func savePosition(_ point: CGPoint)
    func restorePosition() -> CGPoint?
}
```

### 7.3 L1MiniWidget (SwiftUI)

```swift
struct L1MiniWidget: View {
    @ObservedObject var dataService: DataService
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            // 图标行
            HStack {
                Image(systemName: "chart.bar.fill")
                Image(systemName: "dollarsign.circle.fill")
            }
            .font(.system(size: 12))

            // 数据行
            HStack(spacing: 12) {
                TokenView(value: todayStats?.totalTokens)
                CostView(value: todayStats?.totalCost)
            }

            // 环比
            if showComparison {
                ComparisonView(change: todayStats?.dayOverDayChange)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .onTapGesture { isExpanded.toggle() }
        .gesture(dragGesture)
    }
}
```

## 8. 与现有系统集成

### 8.1 数据读取

复用现有的 `~/.claude/token-stats/daily/` CSV 文件：

```swift
// Swift 直接读取 CSV，无需启动 Python 服务
func loadTodayStats() -> DailyStats? {
    let csvPath = "~/.claude/token-stats/daily/\(today).csv"
    // 解析 CSV 文件
}
```

### 8.2 CLI 集成

在现有的 `cc-token-monitor` 命令中添加：

```bash
cc-token-monitor hud start    # 启动悬浮窗
cc-token-monitor hud stop     # 关闭悬浮窗
cc-token-monitor hud config   # 打开配置
```

## 9. 安装与分发

### 9.1 构建

```bash
cd hud/
swift build -c release
```

### 9.2 安装

- 打包为 `.app` 放入 `/Applications/`
- 或作为 CLI 工具的一部分安装在 `/usr/local/bin/`

### 9.3 开机自启

使用 `SMLoginItemSetEnabled` 或 `LaunchAgent` 实现：

```swift
// 注册 LaunchAgent
~/Library/LaunchAgents/com.cc-token-monitor.hud.plist
```

## 10. 迭代计划

| 阶段 | 内容 | 预计时间 |
|------|------|----------|
| P0 | 基础悬浮窗 L1 + L2 + 数据读取 | 2-3 天 |
| P1 | 设置界面 + 配置持久化 + 开机自启 | 1-2 天 |
| P2 | 菜单栏模式 + 边缘停靠模式 | 2 天 |
| P3 | 优化动画 + 性能调优 + 签名公证 | 1-2 天 |

## 11. 设计决策确认

| 问题 | 决策 |
|------|------|
| L1 尺寸 | 固定 120x80pt，不可用户调整，后期通过 `config.yaml` 调整 |
| L2 图表 | 使用 Swift Charts (macOS 13+)，视觉效果更好 |
| Cost 计算 | 复用 web 的定价逻辑 |
| 多显示器 | P0 先不支持，MVP 优先单显示器 |
| L2 收起 | 支持点击外部自动收起 L2 |

## 12. 配置文件设计

```yaml
# ~/.cc-token-monitor/hud-config.yaml
hud:
  # L1 尺寸（固定，不可 UI 调整，需重启生效）
  width: 120
  height: 80
  corner_radius: 12
  opacity: 0.95

  # 显示内容
  show_tokens: true
  show_cost: true
  show_comparison: true
  currency: USD  # USD/CNY

  # 行为
  refresh_interval: 30
  auto_start: false
  snap_to_edges: true
  auto_hide_l2: true  # 点击外部自动收起 L2

  # 位置（自动记忆）
  position:
    x: 100
    y: 100
    # screen: "Built-in Retina Display"  # P1 多显示器时启用
```

---

设计已确认，开始 P0 阶段实现。
