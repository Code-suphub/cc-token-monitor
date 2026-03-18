# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

CC Token Monitor 是一个 Claude Code Token 监控工具，用于追踪 AI 编程助手的使用情况和费用。

- **主要语言**: Shell (zsh)、Swift、Python
- **平台**: macOS (主要)、Linux
- **仓库结构**: 混合架构项目（CLI Shell 脚本 + Swift 悬浮窗 + Python Web 服务）

## 常用命令

### 安装与构建

```bash
# 安装 CLI 工具
make install

# 创建开发符号链接
make link

# 运行代码检查
make lint

# 构建并安装 HUD (macOS Swift 悬浮窗)
make hud-build
make hud-install
```

### 本地开发

```bash
# 开发模式运行 CLI
ln -sf $(pwd)/bin/cc-token-monitor ~/.local/bin/cc-token-monitor-dev
cc-token-monitor-dev today

# 开发模式运行 HUD
make hud-run

# 手动运行 Web 服务
python3 web/app.py 8866
```

## 项目架构

### 数据流架构

```
~/.claude/projects/*/*.jsonl (Claude Code 会话文件)
           ↓
   bin/cc-token-monitor (process_file 函数)
           ↓
   CSV 转换: ~/.claude/token-stats/daily/YYYY-MM-DD.csv
           ↓
   ┌─────────┬─────────┬─────────┐
   ↓         ↓         ↓         ↓
 CLI 显示   HUD 悬浮窗  Web 界面  导出 CSV
```

### 核心组件

#### 1. CLI 工具 (`bin/cc-token-monitor`)

主入口脚本，使用 zsh 编写，主要功能:

- `process_file()`: 解析 `~/.claude/projects/*/*.jsonl` 文件，提取 assistant 消息的 usage 数据
- 按日期分组存储到 `~/.claude/token-stats/daily/YYYY-MM-DD.csv`
- CSV 格式: `session_id|project|model|input_tokens|output_tokens|cache_create|cache_read`

关键命令:
- `cc-token-monitor once` - 初始化扫描所有会话
- `cc-token-monitor today` - 显示今日统计
- `cc-token-monitor watch` - 实时监控（需要 fswatch）
- `cc-token-monitor hud` - 启动悬浮窗（仅 macOS）

#### 2. Swift HUD 悬浮窗 (`hud/`)

macOS 专用实时监控悬浮窗应用。

- **技术栈**: Swift 5.9+, SwiftUI, Swift Charts
- **最低系统要求**: macOS 13+
- **构建输出**: `hud/.build/release/cc-token-monitor-hud`
- **源码结构**:
  - `App/`: MainApp.swift (菜单栏应用)、StatusBarApp.swift
  - `Views/`: FloatingPanel.swift, FloatingWidget.swift, MenuBarPanel.swift, SettingsPanel.swift
  - `Services/`: DataService.swift (读取 CSV 数据)
  - `Models/`: DailyStats.swift, HUDConfig.swift

#### 3. Python Web 服务 (`web/app.py`)

基于 http.server 的轻量级 Web 界面。

- **端口**: 默认 8866
- **启动**: `cc-token-web` 或 `python3 web/app.py 8866`
- **功能**: 统计卡片、趋势图、模型分布饼图、项目柱状图

### 配置文件

- **模型价格**: `config/prices.json` (安装后复制到 `~/.claude/token-stats/config/prices.json`)
  - 支持 30+ 模型价格配置
  - 格式: `{"models": {"model-name": {"input": X, "output": Y, "provider": "Z"}}}`
  - 默认价格: `{"default": {"input": 0.8, "output": 0.8}}`

### 数据存储

```
~/.claude/token-stats/
├── daily/              # 按日期汇总的 CSV 文件
│   └── YYYY-MM-DD.csv
├── sessions/           # 会话级别的原始记录
│   └── {session_id}.csv
├── archives/           # 归档数据
└── config/
    └── prices.json     # 用户价格配置
```

## 重要实现细节

### Token 数据解析逻辑

主脚本通过解析 Claude Code 生成的 `.jsonl` 会话文件提取 Token 使用数据:

```zsh
# 关键解析命令 (位于 process_file 函数)
grep '"type":"assistant"' | jq -r '
  select(.message.usage) |
  (.timestamp | split("T")[0]) as $date |
  select(.message.model | test("^(synthetic|model|)$"; "i") | not) |
  "\($date)|\($sid)|\($project)|\(.message.model)|\(.message.usage.input_tokens)|\(.message.usage.output_tokens)|\(.message.usage.cache_creation_input_tokens // 0)|\(.message.usage.cache_read_input_tokens // 0)"
'
```

### 价格计算

费用计算使用 bc 进行精确浮点运算:

```zsh
cost=$(echo "scale=6; ($input_tokens * $input_price + $output_tokens * $output_price) / 1000000" | bc)
```

### HUD 数据读取

DataService.swift 直接读取 `~/.claude/token-stats/daily/` 目录下的 CSV 文件:

```swift
let statsDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/token-stats/daily")
```

刷新间隔: 默认 30 秒 (`refresh_interval` 可配置)

## 快捷别名

建议添加到 `~/.zshrc`:

```bash
alias cctok="cc-token-monitor"
alias cctoday="cc-token-monitor today"
alias ccsum="cc-token-monitor summary"
alias ccsessions="cc-token-monitor sessions"
alias ccsess="cc-token-monitor sessions"
alias ccproj="cc-token-monitor project"
alias ccconfig="cc-token-monitor config"
alias ccprice="cc-token-monitor price"
alias ccweb="cc-token-web"
alias ccweb-stop="cc-token-web-stop"
alias cchud="cc-token-monitor hud"
alias cchud-stop="cc-token-monitor hud-stop"
```

## 开发注意事项

1. **Shell 兼容性**: 主脚本使用 zsh，但需避免过于特殊的语法以保证 bash 兼容性
2. **模型名称过滤**: 解析时需过滤无效模型名 (`model`, `<synthetic>`, 空字符串等)
3. **HUD 仅 macOS**: Swift HUD 组件使用 Swift Charts (macOS 13+) 和 SwiftUI
4. **Web 无依赖**: Python Web 服务使用标准库，无第三方依赖
5. **数据目录**: 所有数据存储在用户 home 目录下的 `~/.claude/token-stats/`
