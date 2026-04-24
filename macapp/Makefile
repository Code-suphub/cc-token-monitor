.PHONY: all build run clean install dev backend-start

# 构建 macapp
build:
	swift build --configuration release

# 开发模式构建
dev:
	swift build

# 运行
run:
	swift run

# 清理
clean:
	swift package clean

# 安装（需要先构建）
install: build
	cp .build/release/cc-token-monitor-app /Applications/

# 启动后端（单独运行 Python）
backend-start:
	cd ../backend && python3 app.py 8866

# 重启后端（关闭已存在的）
backend-restart:
	@lsof -ti:8866 | xargs kill -9 2>/dev/null || true
	cd ../backend && python3 app.py 8866 &

# 当前状态
status:
	@lsof -ti:8866 | head -1 && echo "Backend is running on port 8866" || echo "Backend is not running"
