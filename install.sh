#!/bin/bash
# CC Token Monitor 安装脚本

set -e

REPO_URL="https://github.com/yourusername/cc-token-monitor"
INSTALL_DIR="/usr/local"
BIN_DIR="$INSTALL_DIR/bin"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         CC Token Monitor Installer                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

check_dependencies() {
    echo "Checking dependencies..."

    # 检查 jq
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Warning: jq is not installed${NC}"
        echo "jq is required for JSON processing."
        echo ""
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "Install with: brew install jq"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "Install with: sudo apt-get install jq  # Debian/Ubuntu"
            echo "             sudo yum install jq      # RHEL/CentOS"
        fi
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    echo -e "${GREEN}✓ Dependencies check passed${NC}"
}

install_binaries() {
    echo ""
    echo "Installing binaries..."

    # 创建目录
    mkdir -p "$BIN_DIR"
    mkdir -p "$HOME/.claude/token-stats/config"

    # 下载或复制二进制文件
    if [[ -f "bin/cc-token-monitor" ]]; then
        # 本地安装
        cp bin/cc-token-monitor "$BIN_DIR/"
        cp bin/cc-token-web "$BIN_DIR/" 2>/dev/null || true
        cp bin/cc-token-web-stop "$BIN_DIR/" 2>/dev/null || true
    else
        # 远程安装
        echo "Downloading from $REPO_URL..."
        curl -fsSL "$REPO_URL/releases/latest/download/cc-token-monitor" -o "$BIN_DIR/cc-token-monitor"
        chmod +x "$BIN_DIR/cc-token-monitor"
    fi

    # 复制配置文件
    if [[ -f "config/prices.json" ]]; then
        cp config/prices.json "$HOME/.claude/token-stats/config/"
    fi

    echo -e "${GREEN}✓ Binaries installed to $BIN_DIR${NC}"
}

setup_aliases() {
    echo ""
    echo "Setting up shell aliases..."

    local SHELL_RC=""
    if [[ "$SHELL" == */zsh ]]; then
        SHELL_RC="$HOME/.zshrc"
    elif [[ "$SHELL" == */bash ]]; then
        SHELL_RC="$HOME/.bashrc"
    fi

    if [[ -n "$SHELL_RC" ]]; then
        echo ""
        echo "Add the following aliases to your shell profile?"
        echo "  File: $SHELL_RC"
        echo ""
        echo "  cctok -> cc-token-monitor"
        echo "  cctoday -> cc-token-monitor today"
        echo "  ccsum -> cc-token-monitor summary"
        echo "  ..."
        echo ""
        read -p "Add aliases? (Y/n) " -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            cat >> "$SHELL_RC" << 'EOF'

# CC Token Monitor Aliases
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
EOF
            echo -e "${GREEN}✓ Aliases added to $SHELL_RC${NC}"
            echo -e "${CYAN}Run 'source $SHELL_RC' to apply changes${NC}"
        fi
    fi
}

print_footer() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              Installation Complete!                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Quick Start:"
    echo "  cc-token-monitor once     # Initialize data"
    echo "  cc-token-monitor today    # View today's stats"
    echo "  cc-token-monitor config   # View configuration"
    echo "  ccweb                     # Start web interface"
    echo ""
    echo "Documentation: https://github.com/yourusername/cc-token-monitor#readme"
    echo ""
}

main() {
    print_header
    check_dependencies
    install_binaries
    setup_aliases
    print_footer
}

# 如果直接运行脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
