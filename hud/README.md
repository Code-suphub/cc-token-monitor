# CC Token Monitor HUD

macOS 悬浮窗实时监控工具，显示今日 Token 用量和 Cost 花销。

## 功能

- **L1 悬浮窗**: 120×80pt 迷你窗口，显示今日 Tokens / Cost / 环比
- **L2 详细面板**: 点击展开，显示7天趋势图 + 今日会话数
- **自动刷新**: 每30秒自动刷新数据
- **位置记忆**: 拖动后自动保存位置
- **菜单栏控制**: 通过菜单栏图标控制显示/隐藏

## 安装

```bash
# 构建发布版本
swift build -c release

# 复制到 PATH
cp .build/release/cc-token-monitor-hud /usr/local/bin/

# 启动
cc-token-monitor-hud
```

## 使用

| 操作 | 说明 |
|------|------|
| 点击悬浮窗 | 展开/收起详细面板 |
| 右键悬浮窗 | 显示上下文菜单 |
| 拖动悬浮窗 | 移动位置（自动保存） |
| 菜单栏图标 | 控制显示/隐藏、刷新、退出 |

## 配置文件

配置文件位置：`~/.cc-token-monitor/hud-config.yaml`

```yaml
hud:
  width: 120
  height: 80
  corner_radius: 12
  opacity: 0.95
  show_tokens: true
  show_cost: true
  refresh_interval: 30
```

## 开发

```bash
# 调试构建
swift build

# 运行
.build/debug/cc-token-monitor-hud
```

## 技术栈

- Swift 5.9+
- SwiftUI
- Swift Charts (macOS 13+)
