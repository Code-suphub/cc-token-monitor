# Contributing to CC Token Monitor

感谢你对 CC Token Monitor 的兴趣！我们欢迎各种形式的贡献。

## 如何贡献

### 报告问题

如果你发现了 bug 或有功能建议，请通过 GitHub Issues 提交：

1. 检查是否已有类似 issue
2. 创建新 issue，提供详细信息：
   - 操作系统和版本
   - 复现步骤
   - 期望行为 vs 实际行为
   - 错误日志（如果有）

### 提交代码

1. **Fork** 本仓库
2. **创建分支** (`git checkout -b feature/amazing-feature`)
3. **提交更改** (`git commit -m 'Add amazing feature'`)
4. **推送分支** (`git push origin feature/amazing-feature`)
5. 创建 **Pull Request**

### 代码规范

- 使用一致的代码风格
- 添加适当的注释
- 确保脚本在 zsh 和 bash 下都能运行
- 更新相关文档

### 开发环境设置

```bash
# Fork 并克隆仓库
git clone https://github.com/YOUR_USERNAME/cc-token-monitor.git
cd cc-token-monitor

# 创建开发链接
make link

# 测试你的修改
cc-token-monitor-dev today
```

### 添加新模型价格

编辑 `config/prices.json`，添加新模型：

```json
{
  "models": {
    "new-model-name": {
      "input": 1.0,
      "output": 2.0,
      "provider": "provider-name"
    }
  }
}
```

### 测试

运行测试（如果有）：

```bash
make test
```

### 文档

- 更新 README.md 如果需要
- 添加代码注释
- 更新 CHANGELOG.md

## 行为准则

- 尊重所有参与者
- 欢迎新手，耐心解答问题
- 专注于建设性的讨论

## 许可证

通过贡献代码，你同意你的贡献将在 MIT 许可证下发布。
