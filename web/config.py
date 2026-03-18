"""
CC Token Monitor Web - 配置模块
"""
import os

# 基础路径
WEB_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_DIR = os.path.join(WEB_DIR, 'templates')
STATIC_DIR = os.path.join(WEB_DIR, 'static')

# 数据路径
STATS_DIR = os.path.expanduser("~/.claude/token-stats")
PROJECTS_DIR = os.path.expanduser("~/.claude/projects")

# 服务器默认配置
DEFAULT_PORT = 8866
DEFAULT_HOST = '127.0.0.1'
