# CC Token Monitor

Claude Code Token 监控工具 - 追踪你的 AI 编程助手使用情况和费用。

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)

## 功能特性

- 实时监控 Claude Code 对话 Token 使用情况
- 支持 30+ 种主流 AI 模型价格计算
- 多维度统计：按日期、模型、项目、会话分组
- Web 可视化界面，图表展示使用趋势
- 可自定义价格配置
- 导出 CSV 报告
- 自动归档历史数据

## 支持的模型

| 提供商 | 模型 | 价格 (Input/Output per 1M) |
|--------|------|---------------------------|
| Anthropic | Claude Opus | $15.0 / $75.0 |
| Anthropic | Claude Sonnet | $3.0 / $15.0 |
| Anthropic | Claude Haiku | $0.8 / $4.0 |
| Moonshot | Kimi K2.5 | $0.8 / $0.8 |
| OpenAI | GPT-4o | $2.5 / $10.0 |
| OpenAI | GPT-4o-mini | $0.15 / $0.6 |
| DeepSeek | DeepSeek V3 | $0.27 / $1.1 |
| Google | Gemini 2.0 Flash | $0.075 / $0.3 |
| Alibaba | Qwen Max | $0.5 / $1.0 |
| ... | ... | ... |

完整列表见 [config/prices.json](config/prices.json)

## 安装

### 方式一：Homebrew（推荐 macOS）

```bash
# 添加 tap
brew tap Code-suphub/cc-token-monitor https://github.com/Code-suphub/cc-token-monitor

# 安装
brew install cc-token-monitor
```

### 方式二：手动安装

```bash
# 克隆仓库
git clone https://github.com/Code-suphub/cc-token-monitor.git
cd cc-token-monitor

# 安装
make install

# 或使用 install 脚本
./install.sh
```

### 方式三：直接下载

```bash
curl -fsSL https://raw.githubusercontent.com/Code-suphub/cc-token-monitor/main/install.sh | bash
```

## 使用方法

### 快速开始

```bash
# 初始化数据（扫描现有会话）
cc-token-monitor once

# 查看今日统计
cctoday

# 启动 Web 界面
ccweb
```

### CLI 命令

```bash
# 基础命令
cc-token-monitor today                    # 今日统计
cctoken-monitor date 2026-03-13          # 指定日期统计
cctoken-monitor sessions                 # 会话明细
cctoken-monitor project                  # 按项目汇总
cctoken-monitor summary                  # 历史汇总

# 配置相关
cc-token-monitor config                  # 查看价格配置
cc-token-monitor price kimi-for-coding   # 查询模型价格

# 导出和监控
cc-token-monitor export                  # 导出 CSV 报告
cc-token-monitor watch                   # 实时监控

# Web 界面
ccweb                                    # 启动 Web 界面 (端口 8866)
ccweb-stop                               # 停止 Web 界面
```

### 快捷别名

```bash
cctok           # 等同于 cc-token-monitor
cctoday         # 今日统计
ccsum           # 历史汇总
ccsessions      # 会话明细
ccproj          # 项目汇总
ccconfig        # 查看配置
ccprice         # 查询价格
```

## 配置

### 自定义模型价格

编辑配置文件：

```bash
~/.claude/token-stats/config/prices.json
```

示例配置：

```json
{
  "default": {
    "input": 0.8,
    "output": 0.8
  },
  "models": {
    "my-custom-model": {
      "input": 1.0,
      "output": 2.0,
      "provider": "custom"
    }
  }
}
```

### 环境变量

```bash
export CC_TOKEN_STATS_DIR="~/.cc-token-stats"  # 自定义数据目录
export CC_TOKEN_WEB_PORT=8866                   # Web 界面端口
```

## Web 界面

启动后访问 `http://localhost:8866`

![Web Interface](docs/screenshot.png)

功能：
- 实时统计卡片
- Token 使用趋势图
- 模型分布饼图
- 项目使用柱状图
- 详细数据表格

## 项目结构

```
cc-token-monitor/
├── bin/
│   ├── cc-token-monitor      # 主 CLI 脚本
│   ├── cc-token-web          # Web 服务脚本
│   └── cc-token-web-stop     # 停止 Web 服务
├── config/
│   └── prices.json           # 模型价格配置
├── lib/
│   └── utils.sh              # 工具函数库
├── web/
│   └── app.py                # Web 服务端
├── docs/
│   └── screenshot.png        # 截图
├── install.sh                # 安装脚本
├── Makefile                  # 构建脚本
├── README.md                 # 本文件
└── LICENSE                   # MIT 许可证
```

## 开发

### 本地开发

```bash
# 克隆仓库
git clone https://github.com/Code-suphub/cc-token-monitor.git
cd cc-token-monitor

# 创建符号链接进行测试
ln -sf $(pwd)/bin/cc-token-monitor ~/.local/bin/cc-token-monitor-dev

# 修改代码后测试
cc-token-monitor-dev today
```

### 贡献代码

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

## 路线图

- [ ] 支持更多 IDE（Cursor、Windsurf 等）
- [ ] 添加数据可视化图表导出
- [ ] 支持多用户/团队统计
- [ ] 添加预算告警功能
- [ ] 集成 Slack/Discord 通知
- [ ] 支持 SQLite 数据存储
- [ ] RESTful API

## 常见问题

**Q: 支持哪些操作系统？**

A: 目前主要支持 macOS 和 Linux。Windows 支持正在计划中。

**Q: 数据存储在哪里？**

A: 默认存储在 `~/.claude/token-stats/`，包含会话数据和每日汇总。

**Q: 如何清除历史数据？**

A: 删除数据目录：`rm -rf ~/.claude/token-stats/`

**Q: 费用计算准确吗？**

A: 基于官方 API 价格估算，实际费用可能因折扣、缓存等略有差异。

## 许可证

[MIT](LICENSE) © 2026 Your Name

## 致谢

感谢所有贡献者和用户的支持！

---

如果这个项目对你有帮助，请给个 ⭐️ Star！
