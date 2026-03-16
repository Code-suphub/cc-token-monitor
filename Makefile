# CC Token Monitor Makefile

PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
CONFIGDIR = $(HOME)/.claude/token-stats/config

.PHONY: all install uninstall clean test lint

all: help

help:
	@echo "CC Token Monitor - Available targets:"
	@echo ""
	@echo "  make install      - Install to $(PREFIX) (default: /usr/local)"
	@echo "  make uninstall    - Remove from $(PREFIX)"
	@echo "  make link         - Create symlinks for development"
	@echo "  make test         - Run tests"
	@echo "  make lint         - Run shellcheck"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make release      - Create release package"
	@echo ""

install:
	@echo "Installing CC Token Monitor..."
	@install -d $(BINDIR)
	@install -d $(CONFIGDIR)
	@install -m 755 bin/cc-token-monitor $(BINDIR)/
	@install -m 755 bin/cc-token-web $(BINDIR)/ 2>/dev/null || true
	@install -m 755 bin/cc-token-web-stop $(BINDIR)/ 2>/dev/null || true
	@install -m 644 config/prices.json $(CONFIGDIR)/
	@echo "✓ Installation complete!"
	@echo ""
	@echo "Add to your shell profile:"
	@echo '  alias cctok="cc-token-monitor"'
	@echo '  alias cctoday="cc-token-monitor today"'
	@echo ""
	@echo "Or run: make aliases >> ~/.zshrc"

uninstall:
	@echo "Uninstalling CC Token Monitor..."
	@rm -f $(BINDIR)/cc-token-monitor
	@rm -f $(BINDIR)/cc-token-web
	@rm -f $(BINDIR)/cc-token-web-stop
	@echo "✓ Uninstallation complete!"
	@echo "Note: Data in ~/.claude/token-stats/ was not removed"

link:
	@echo "Creating symlinks for development..."
	@ln -sf $(PWD)/bin/cc-token-monitor ~/.local/bin/cc-token-monitor
	@ln -sf $(PWD)/bin/cc-token-web ~/.local/bin/cc-token-web 2>/dev/null || true
	@ln -sf $(PWD)/bin/cc-token-web-stop ~/.local/bin/cc-token-web-stop 2>/dev/null || true
	@echo "✓ Symlinks created!"

aliases:
	@echo '# CC Token Monitor Aliases'
	@echo 'alias cctok="cc-token-monitor"'
	@echo 'alias cctoday="cc-token-monitor today"'
	@echo 'alias ccsum="cc-token-monitor summary"'
	@echo 'alias ccsessions="cc-token-monitor sessions"'
	@echo 'alias ccsess="cc-token-monitor sessions"'
	@echo 'alias ccproj="cc-token-monitor project"'
	@echo 'alias ccconfig="cc-token-monitor config"'
	@echo 'alias ccprice="cc-token-monitor price"'
	@echo 'alias ccweb="cc-token-web"'
	@echo 'alias ccweb-stop="cc-token-web-stop"'
	@echo 'alias cchud="cc-token-monitor hud"'
	@echo 'alias cchud-stop="cc-token-monitor hud-stop"'

# HUD (macOS Swift 悬浮窗)
hud-build:
	@echo "Building CC Token Monitor HUD..."
	@cd hud && swift build -c release
	@echo "✓ HUD build complete: hud/.build/release/cc-token-monitor-hud"

hud-install: hud-build
	@echo "Installing HUD..."
	@install -m 755 hud/.build/release/cc-token-monitor-hud $(BINDIR)/
	@echo "✓ HUD installed! Run: cc-token-monitor-hud"

hud-run:
	@cd hud && swift run

hud-clean:
	@cd hud && rm -rf .build/

test:
	@echo "Running tests..."
	@bash test/run_tests.sh

lint:
	@echo "Running shellcheck..."
	@shellcheck bin/cc-token-monitor || echo "shellcheck not installed, skipping"
	@shellcheck bin/cc-token-web 2>/dev/null || true

clean:
	@echo "Cleaning..."
	@rm -rf dist/
	@rm -f *.tar.gz

release:
	@echo "Creating release package..."
	@mkdir -p dist/cc-token-monitor-$(VERSION)
	@cp -r bin config web docs install.sh Makefile README.md LICENSE dist/cc-token-monitor-$(VERSION)/
	@tar -czf dist/cc-token-monitor-$(VERSION).tar.gz -C dist cc-token-monitor-$(VERSION)
	@echo "✓ Release created: dist/cc-token-monitor-$(VERSION).tar.gz"

.DEFAULT_GOAL := help
