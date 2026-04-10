#!/bin/bash
# CC Token Monitor HUD 开发启动脚本

set -e

echo "🚀 CC Token Monitor HUD 开发启动"
echo "=================================="

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 1. 检查并关闭已有进程
echo ""
echo "📋 检查现有进程..."
PID=$(pgrep -f "cc-token-monitor-hud" || true)
if [ -n "$PID" ]; then
    echo "   发现运行中的 HUD 进程 (PID: $PID)，正在关闭..."
    kill "$PID" 2>/dev/null || kill -9 "$PID" 2>/dev/null || true
    sleep 1
    echo "   ✓ 已关闭"
else
    echo "   没有运行中的 HUD 进程"
fi

# 清除旧日志
echo ""
echo "🧹 清除旧日志..."
rm -f ~/.claude/token-stats/hud-debug.log
echo "   ✓ 已清除"

# 2. 构建项目
echo ""
echo "🔨 构建 HUD (开发模式)..."
cd hud
swift build 2>&1 | while read line; do
    echo "   $line"
done

# 检查构建结果
if [ ! -f ".build/debug/cc-token-monitor-hud" ]; then
    echo "❌ 构建失败！"
    exit 1
fi

echo "   ✓ 构建成功"

# 3. 启动 HUD（前台运行，显示日志）
echo ""
echo "▶️  启动 HUD..."
echo ""
echo "📋 日志输出（按 Ctrl+C 停止）："
echo "=================================="
./.build/debug/cc-token-monitor-hud
