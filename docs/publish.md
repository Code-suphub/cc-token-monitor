# 发布指南

本文档说明如何发布 CC Token Monitor 的新版本，并更新 Homebrew Formula。

## 目录

- [快速发布流程](#快速发布流程)
- [详细步骤](#详细步骤)
- [注意事项](#注意事项)
- [常见问题](#常见问题)

---

## 快速发布流程

```bash
# 1. 确保所有改动已提交
git status

# 2. 打版本标签（例如 v1.0.1）
git tag v1.0.1
git push origin v1.0.1

# 3. 等待 GitHub 生成 release 包，然后获取 SHA256
curl -sL https://github.com/Code-suphub/cc-token-monitor/archive/refs/tags/v1.0.1.tar.gz | shasum -a 256

# 4. 更新 Formula/cc-token-monitor.rb 中的版本号和 SHA256
# 5. 提交并推送更新
git add Formula/cc-token-monitor.rb
git commit -m "Update formula to v1.0.1"
git push
```

---

## 详细步骤

### 步骤 1：准备发布

确保所有改动都已经完成并通过测试：

```bash
# 检查当前状态
git status
git diff

# 确保所有文件已提交
git add .
git commit -m "Prepare for v1.0.1 release"
```

### 步骤 2：创建版本标签

```bash
# 本地打标签
git tag v1.0.1

# 推送标签到 GitHub
git push origin v1.0.1
```

**注意**：标签一旦推送，GitHub 会自动生成 `v1.0.1.tar.gz` 压缩包。

### 步骤 3：计算 SHA256

标签推送后，需要等待几秒让 GitHub 生成压缩包，然后计算 SHA256：

```bash
curl -sL https://github.com/Code-suphub/cc-token-monitor/archive/refs/tags/v1.0.1.tar.gz | shasum -a 256
```

输出示例：
```
c2d5d41de7f8011ba3de53a6328db38e857a3d788ce7bed417fa260f4ef52ffe  -
```

复制前面的 SHA256 值（忽略后面的 `-`）。

### 步骤 4：更新 Formula

编辑 `Formula/cc-token-monitor.rb` 文件，更新以下字段：

```ruby
class CcTokenMonitor < Formula
  desc "Monitor Claude Code token usage and costs"
  homepage "https://github.com/Code-suphub/cc-token-monitor"
  url "https://github.com/Code-suphub/cc-token-monitor/archive/refs/tags/v1.0.1.tar.gz"  # ← 修改版本号
  sha256 "c2d5d41de7f8011ba3de53a6328db38e857a3d788ce7bed417fa260f4ef52ffe"              # ← 修改 SHA256
  license "MIT"
  # ...
end
```

### 步骤 5：提交 Formula 更新

```bash
git add Formula/cc-token-monitor.rb
git commit -m "Update formula to v1.0.1"
git push
```

---

## 注意事项

### 1. 版本号规范

- 遵循 [Semantic Versioning](https://semver.org/)：MAJOR.MINOR.PATCH
- Git 标签必须以 `v` 开头，例如：`v1.0.0`、`v1.2.3`
- Formula 中的 `url` 必须与标签名完全匹配

### 2. SHA256 计算时机

**必须在推送标签之后**才能计算 SHA256，因为：

- 推送标签前：GitHub 尚未生成 tar.gz 包，curl 会返回 404
- 推送标签后：GitHub 自动生成压缩包，此时才能计算正确的 SHA256

### 3. 为什么不能先改 Formula 再打标签？

因为 SHA256 是根据 tar.gz 包的内容计算的，而 tar.gz 包又包含了整个仓库的代码，包括 Formula 文件本身。如果先修改 Formula，再打标签，会导致 SHA256 不匹配。

正确的顺序是：
1. 代码准备就绪
2. 打标签并推送
3. 基于标签生成的 tar.gz 计算 SHA256
4. 更新 Formula 中的 SHA256
5. 推送 Formula 更新

### 4. 快速验证 Formula

更新 Formula 后，可以本地测试：

```bash
# 进入 Formula 所在目录
cd /path/to/cc-token-monitor

# 使用 brew 本地安装测试
brew install --build-from-source ./Formula/cc-token-monitor.rb

# 如果已经安装过，先卸载再测试
brew uninstall cc-token-monitor
brew install --build-from-source ./Formula/cc-token-monitor.rb

# 运行测试
cctoken-monitor --version
```

---

## 常见问题

### Q: 用户安装时提示 SHA256 不匹配？

**原因**：Formula 中的 SHA256 与实际的 tar.gz 包不匹配。

**解决**：
1. 重新计算正确的 SHA256：
   ```bash
   curl -sL https://github.com/Code-suphub/cc-token-monitor/archive/refs/tags/vX.X.X.tar.gz | shasum -a 256
   ```
2. 更新 Formula 中的 SHA256
3. 重新提交推送

### Q: 如何撤销一个错误的标签？

如果标签打错了，可以删除并重建：

```bash
# 删除本地标签
git tag -d v1.0.1

# 删除远程标签
git push origin --delete v1.0.1

# 重新打标签（确保代码已更新）
git tag v1.0.1
git push origin v1.0.1
```

### Q: 可以跳过某些小版本的 Formula 更新吗？

可以。Formula 中的版本号不一定要连续，只需要确保 `url` 和 `sha256` 与用户要安装的版本对应即可。

例如：
- v1.0.0 有 Formula 更新
- v1.0.1 只是文档修复，不需要更新 Formula
- v1.0.2 有功能更新，需要更新 Formula

### Q: 如何测试 Formula 是否正确？

```bash
# 1. 语法检查
brew style Formula/cc-token-monitor.rb

# 2. 本地安装测试
brew install --build-from-source Formula/cc-token-monitor.rb

# 3. 运行测试
brew test Formula/cc-token-monitor.rb

# 4. 审计检查
brew audit --new-formula Formula/cc-token-monitor.rb
```

---

## 发布检查清单

发布新版本前，使用以下检查清单确保没有遗漏：

- [ ] 所有代码改动已完成并提交
- [ ] 版本号遵循 SemVer 规范（例如 v1.0.1）
- [ ] 已创建并推送 Git 标签
- [ ] 已计算新版本的 SHA256
- [ ] 已更新 Formula 中的 `url` 和 `sha256`
- [ ] 已提交并推送 Formula 更新
- [ ] 已本地测试 Formula 可以正常安装
- [ ] 已更新 CHANGELOG.md
- [ ] 已更新 README.md 中的版本号（如有）

---

## 附录：自动化脚本

可以创建一个辅助脚本简化发布流程：

```bash
#!/bin/bash
# publish.sh - 发布新版本

set -e

VERSION=$1

if [ -z "$VERSION" ]; then
    echo "Usage: ./publish.sh v1.0.1"
    exit 1
fi

echo "🚀 Publishing $VERSION..."

# 1. 检查是否有未提交的改动
if [ -n "$(git status --porcelain)" ]; then
    echo "❌ 有未提交的改动，请先提交"
    git status
    exit 1
fi

# 2. 创建并推送标签
echo "📌 Creating tag..."
git tag $VERSION
git push origin $VERSION

# 3. 等待 GitHub 生成压缩包
echo "⏳ Waiting for GitHub to generate archive..."
sleep 5

# 4. 计算 SHA256
echo "🔐 Calculating SHA256..."
SHA256=$(curl -sL https://github.com/Code-suphub/cc-token-monitor/archive/refs/tags/${VERSION}.tar.gz | shasum -a 256 | cut -d' ' -f1)
echo "SHA256: $SHA256"

# 5. 更新 Formula
echo "📝 Updating Formula..."
sed -i '' "s|url \"https://github.com/Code-suphub/cc-token-monitor/archive/refs/tags/.*\.tar\.gz\"|url \"https://github.com/Code-suphub/cc-token-monitor/archive/refs/tags/${VERSION}.tar.gz\"|" Formula/cc-token-monitor.rb
sed -i '' "s|sha256 \"[^\"]*\"|sha256 \"$SHA256\"|" Formula/cc-token-monitor.rb

# 6. 提交 Formula 更新
git add Formula/cc-token-monitor.rb
git commit -m "Update formula to ${VERSION}"
git push

echo "✅ Published $VERSION successfully!"
echo ""
echo "Users can now install with:"
echo "  brew tap Code-suphub/cc-token-monitor"
echo "  brew install cc-token-monitor"
```

使用方式：

```bash
chmod +x publish.sh
./publish.sh v1.0.1
```

---

**如有其他问题，请参考 Homebrew 官方文档：**
- https://docs.brew.sh/Formula-Cookbook
- https://docs.brew.sh/Taps
