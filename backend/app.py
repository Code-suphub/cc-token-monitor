#!/usr/bin/env python3
"""
Claude Code Token 监控 Web 界面
主入口 - 只负责 HTTP 处理和路由
"""

import sys
import json
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.parse

from config import DEFAULT_HOST, DEFAULT_PORT, STATIC_DIR, PROJECTS_DIR, FRONTEND_DIR
from template_engine import render_template
from data_service import load_session_detail, get_summary_stats, get_date_stats, get_available_dates
from utils.pricing import calculate_cost_with_cache


class RequestHandler(BaseHTTPRequestHandler):
    """HTTP 请求处理器"""

    def do_GET(self):
        """处理 GET 请求"""
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        routes = {
            '/': self.handle_index,
            '/index.html': self.handle_index,
            '/session': self.handle_session,
            '/api/dates': self.handle_api_dates,
        }

        if path in routes:
            routes[path](query)
        elif path.startswith('/static/'):
            self.handle_static(path)
        else:
            self.send_response(404)
            self.end_headers()

    def handle_static(self, path: str):
        """处理静态文件请求"""
        import os
        from config import STATIC_DIR

        relative_path = path[len('/static/'):]
        safe_path = os.path.normpath(relative_path)

        if safe_path.startswith('..'):
            self.send_response(403)
            self.end_headers()
            return

        file_path = os.path.join(STATIC_DIR, safe_path)

        if not os.path.exists(file_path) or not os.path.isfile(file_path):
            self.send_response(404)
            self.end_headers()
            return

        # MIME 类型映射
        mime_types = {
            '.css': 'text/css',
            '.js': 'application/javascript',
            '.png': 'image/png',
            '.jpg': 'image/jpeg',
            '.jpeg': 'image/jpeg',
            '.svg': 'image/svg+xml',
            '.json': 'application/json',
        }
        ext = os.path.splitext(file_path)[1].lower()
        content_type = mime_types.get(ext, 'text/plain')

        try:
            with open(file_path, 'rb') as f:
                content = f.read()
            self._send_response(200, content, content_type)
        except Exception as e:
            self._send_response(500, f"Error: {str(e)}".encode())

    def handle_index(self, query: dict):
        """处理首页"""
        target_date = query.get('date', [None])[0]

        if target_date:
            stats = get_date_stats(target_date)
            is_single_date = True
            if not stats:
                stats = get_summary_stats()
                is_single_date = False
        else:
            stats = get_summary_stats()
            is_single_date = False

        html = render_template('index.html',
            TITLE=f'Claude Code Token 监控 - {target_date}' if is_single_date else 'Claude Code Token 监控面板',
            STATS_JSON=json.dumps(stats),
            IS_SINGLE_DATE='true' if is_single_date else 'false',
            SELECTED_DATE=target_date or ''
        )

        self._send_response(200, html.encode())

    def handle_session(self, query: dict):
        """处理会话详情页"""
        session_id = query.get('id', [''])[0]

        if not session_id:
            self._send_response(400, b'Session ID required')
            return

        session_data = load_session_detail(session_id)
        if not session_data:
            self._send_response(404, f'Session not found: {session_id}'.encode())
            return

        cost_comparison = calculate_cost_with_cache(session_data['turns'])
        back_url = self._get_back_url(session_id)

        html = render_template('session.html',
            SESSION_ID=session_id,
            BACK_URL=back_url,
            SESSION_JSON=json.dumps(session_data),
            COST_COMPARISON_JSON=json.dumps(cost_comparison)
        )

        self._send_response(200, html.encode())

    def _get_back_url(self, session_id: str) -> str:
        """根据会话文件修改时间推断返回链接"""
        import os
        from config import PROJECTS_DIR

        for root, dirs, files in os.walk(PROJECTS_DIR):
            for f in files:
                if f == f"{session_id}.jsonl":
                    filepath = os.path.join(root, f)
                    try:
                        mtime = os.path.getmtime(filepath)
                        date_str = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d')
                        return f'/?date={date_str}'
                    except (OSError, IOError):
                        pass
                    break
        return '/'

    def handle_api_dates(self, query: dict):
        """API: 获取所有可用日期"""
        dates = get_available_dates()
        self._send_response(200, json.dumps(dates).encode(), 'application/json')

    def _send_response(self, code: int, content: bytes, content_type: str = 'text/html'):
        """发送 HTTP 响应"""
        self.send_response(code)
        self.send_header('Content-type', content_type)
        self.send_header('Content-Length', len(content))
        self.end_headers()
        self.wfile.write(content)

    def log_message(self, format, *args):
        """自定义日志格式"""
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {args[0]}")


def main():
    """主入口"""
    port = DEFAULT_PORT
    if len(sys.argv) > 1:
        port = int(sys.argv[1])

    server = HTTPServer((DEFAULT_HOST, port), RequestHandler)

    print(f"\n🚀 Token 监控面板已启动!")
    print(f"📊 访问地址: http://{DEFAULT_HOST}:{port}")
    print(f"📁 前端资源: {FRONTEND_DIR}")
    print(f"\n按 Ctrl+C 停止服务\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n\n服务已停止")
        sys.exit(0)


if __name__ == '__main__':
    main()
