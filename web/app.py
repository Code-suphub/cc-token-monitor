#!/usr/bin/env python3
"""
Claude Code Token 监控 Web 界面
"""

import os
import sys
import json
from datetime import datetime, timedelta
from collections import defaultdict
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.parse

STATS_DIR = os.path.expanduser("~/.claude/token-stats")
PROJECTS_DIR = os.path.expanduser("~/.claude/projects")

def load_daily_data(target_date=None):
    """加载每日统计数据"""
    daily_dir = os.path.join(STATS_DIR, "daily")

    by_date = defaultdict(lambda: {
        'input': 0, 'output': 0, 'cache_create': 0, 'cache_read': 0,
        'sessions': {},  # session_id -> {project, model, input, output, cache_create, cache_read}
        'models': defaultdict(lambda: {'input': 0, 'output': 0}),
        'projects': defaultdict(lambda: {'input': 0, 'output': 0, 'sessions': set()})
    })

    if not os.path.exists(daily_dir):
        return by_date

    for filename in os.listdir(daily_dir):
        if not filename.endswith('.csv'):
            continue

        date = filename.replace('.csv', '')
        if target_date and date != target_date:
            continue

        filepath = os.path.join(daily_dir, filename)
        with open(filepath, 'r') as f:
            for line in f:
                parts = line.strip().split('|')
                if len(parts) < 7:
                    continue

                session_id, project, model = parts[0], parts[1], parts[2]
                try:
                    input_tok = int(parts[3])
                    output_tok = int(parts[4])
                    cache_create = int(parts[5])
                    cache_read = int(parts[6])
                except:
                    continue

                by_date[date]['input'] += input_tok
                by_date[date]['output'] += output_tok
                by_date[date]['cache_create'] += cache_create
                by_date[date]['cache_read'] += cache_read

                # 聚合会话数据
                if session_id not in by_date[date]['sessions']:
                    by_date[date]['sessions'][session_id] = {
                        'project': project,
                        'model': model,
                        'input': 0, 'output': 0,
                        'cache_create': 0, 'cache_read': 0
                    }
                by_date[date]['sessions'][session_id]['input'] += input_tok
                by_date[date]['sessions'][session_id]['output'] += output_tok
                by_date[date]['sessions'][session_id]['cache_create'] += cache_create
                by_date[date]['sessions'][session_id]['cache_read'] += cache_read

                by_date[date]['models'][model]['input'] += input_tok
                by_date[date]['models'][model]['output'] += output_tok
                by_date[date]['projects'][project]['input'] += input_tok
                by_date[date]['projects'][project]['output'] += output_tok
                by_date[date]['projects'][project]['sessions'].add(session_id)

    return by_date

def load_session_detail(session_id):
    """加载会话详细数据（从原始jsonl文件）"""
    # 查找会话文件
    session_file = None
    for root, dirs, files in os.walk(PROJECTS_DIR):
        for f in files:
            if f == f"{session_id}.jsonl":
                session_file = os.path.join(root, f)
                break
        if session_file:
            break

    if not session_file or not os.path.exists(session_file):
        return None

    # 按 message.id 分组，合并同一响应的 streaming 记录
    from collections import defaultdict
    resp_groups = defaultdict(list)

    try:
        with open(session_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    if data.get('type') != 'assistant':
                        continue
                    msg = data.get('message', {})
                    resp_id = msg.get('id', 'unknown')
                    resp_groups[resp_id].append(data)
                except:
                    continue
    except:
        pass

    # 合并同一响应的多条记录
    turns = []
    total_input = 0
    total_output = 0
    total_cache_create = 0
    total_cache_read = 0

    for resp_id, records in resp_groups.items():
        if not records:
            continue

        # 按时间排序，取第一条和最后一条
        records = sorted(records, key=lambda r: r.get('timestamp', ''))
        first = records[0]
        last = records[-1]

        msg = last.get('message', {})
        usage = msg.get('usage', {})
        if not usage:
            continue

        input_tokens = usage.get('input_tokens', 0)
        output_tokens = usage.get('output_tokens', 0)
        cache_create_tokens = usage.get('cache_creation_input_tokens', 0)
        cache_read_tokens = usage.get('cache_read_input_tokens', 0)

        total_input += input_tokens
        total_output += output_tokens
        total_cache_create += cache_create_tokens
        total_cache_read += cache_read_tokens

        # 合并 content，按 type 去重
        seen_types = set()
        content_types = []
        for r in records:
            for c in r.get('message', {}).get('content', []):
                ctype = c.get('type')
                if ctype and ctype not in seen_types:
                    seen_types.add(ctype)
                    content_types.append(ctype)

        stop_reason = msg.get('stop_reason')

        # 确定消息类型和状态
        msg_type = []
        msg_status = 'complete'

        has_thinking = 'thinking' in seen_types
        has_tool_use = 'tool_use' in seen_types
        has_text = 'text' in seen_types

        # 获取 text content 的实际长度（从最后一条记录）
        text_length = 0
        for c in msg.get('content', []):
            if c.get('type') == 'text':
                text_length += len(c.get('text', ''))

        is_empty_output = output_tokens == 0 and text_length == 0

        if has_tool_use:
            msg_type.append('tool_use')
            if not stop_reason and output_tokens == 0:
                msg_status = 'waiting'
        elif has_thinking:
            msg_type.append('thinking')
            if not stop_reason and output_tokens == 0:
                msg_status = 'thinking'
        elif has_text:
            msg_type.append('text')
            if is_empty_output:
                msg_status = 'empty'

        turns.append({
            'turn': len(turns) + 1,
            'model': msg.get('model', 'unknown'),
            'input': input_tokens,
            'output': output_tokens,
            'cache_create': cache_create_tokens,
            'cache_read': cache_read_tokens,
            'timestamp': first.get('timestamp', ''),
            'cumulative_input': total_input,
            'cumulative_output': total_output,
            'cumulative_total': total_input + total_output,
            'msg_type': msg_type,
            'msg_status': msg_status,
            'stop_reason': stop_reason
        })

    # 按时间排序并重新编号
    turns.sort(key=lambda t: t['timestamp'])
    for i, turn in enumerate(turns, 1):
        turn['turn'] = i
        # 重新计算累计值
        turn['cumulative_input'] = sum(t['input'] for t in turns[:i])
        turn['cumulative_output'] = sum(t['output'] for t in turns[:i])
        turn['cumulative_total'] = turn['cumulative_input'] + turn['cumulative_output']

    return {
        'session_id': session_id,
        'total_turns': len(turns),
        'total_input': total_input,
        'total_output': total_output,
        'total_cache_create': total_cache_create,
        'total_cache_read': total_cache_read,
        'turns': turns
    }

def get_price(model):
    """获取模型价格（每百万tokens）"""
    prices = {
        'kimi': {'input': 0.8, 'output': 0.8},
        'claude-opus': {'input': 15.0, 'output': 75.0},
        'claude-sonnet': {'input': 3.0, 'output': 15.0},
        'claude-haiku': {'input': 0.8, 'output': 4.0},
        'gpt-4o': {'input': 2.5, 'output': 10.0},
        'gpt-4': {'input': 30.0, 'output': 60.0},
        'gpt-3.5': {'input': 0.5, 'output': 1.5},
        'deepseek': {'input': 0.27, 'output': 1.1},
        'gemini-flash': {'input': 0.075, 'output': 0.3},
        'gemini-pro': {'input': 1.25, 'output': 5.0},
    }

    model_lower = model.lower()
    for key, price in prices.items():
        if key in model_lower:
            return price
    return {'input': 0.8, 'output': 0.8}  # 默认价格

def calculate_cost_with_cache(turns):
    """计算有缓存和无缓存的花费对比"""
    results = []
    cumulative_no_cache = 0
    cumulative_with_cache = 0

    for turn in turns:
        price = get_price(turn['model'])

        # Kimi/Claude 的缓存计费规则：
        # - input_tokens: 实际输入（不含缓存命中部分）
        # - cache_read_input_tokens: 命中缓存的部分，按折扣价计费
        # - 对于 Kimi，cache_read 已包含在计费中，且 API 返回的 input_tokens 是不含 cache_read 的

        # 无缓存场景：假设所有 tokens 都没有缓存优惠
        # 即 input + cache_read 都按正常 input 价格计算
        effective_input_no_cache = turn['input'] + turn['cache_read']
        no_cache_cost = (
            effective_input_no_cache * price['input'] +
            turn['output'] * price['output']
        ) / 1000000

        # 有缓存场景（实际）：
        # - input: 按正常价格
        # - cache_read: 按折扣价格（通常是正常价格的 10%）
        # 注意：对于 Kimi，API 返回的 input_tokens 已经排除了 cache_read
        cache_discount = 0.1  # 缓存命中通常只需支付 10% 的价格
        with_cache_cost = (
            turn['input'] * price['input'] +
            turn['cache_read'] * price['input'] * cache_discount +
            turn['output'] * price['output']
        ) / 1000000

        cumulative_no_cache += no_cache_cost
        cumulative_with_cache += with_cache_cost

        results.append({
            'turn': turn['turn'],
            'no_cache': round(cumulative_no_cache, 6),
            'with_cache': round(cumulative_with_cache, 6),
            'saved': round(cumulative_no_cache - cumulative_with_cache, 6),
            'saved_percent': round((cumulative_no_cache - cumulative_with_cache) / cumulative_no_cache * 100, 2) if cumulative_no_cache > 0 else 0
        })

    return results

def get_summary_stats():
    """获取汇总统计"""
    data = load_daily_data()

    total_input = sum(d['input'] for d in data.values())
    total_output = sum(d['output'] for d in data.values())
    total_cache_create = sum(d['cache_create'] for d in data.values())
    total_cache_read = sum(d['cache_read'] for d in data.values())

    all_sessions = set()
    all_models = defaultdict(lambda: {'input': 0, 'output': 0})
    all_projects = defaultdict(lambda: {'input': 0, 'output': 0})

    for date_data in data.values():
        all_sessions.update(date_data['sessions'].keys())
        for model, mdata in date_data['models'].items():
            all_models[model]['input'] += mdata['input']
            all_models[model]['output'] += mdata['output']
        for proj, pdata in date_data['projects'].items():
            all_projects[proj]['input'] += pdata['input']
            all_projects[proj]['output'] += pdata['output']

    sorted_dates = sorted(data.keys())
    trend = []
    for date in sorted_dates:
        d = data[date]
        trend.append({
            'date': date,
            'input': d['input'],
            'output': d['output'],
            'total': d['input'] + d['output'],
            'sessions': len(d['sessions'])
        })

    return {
        'total_input': total_input,
        'total_output': total_output,
        'total_cache_create': total_cache_create,
        'total_cache_read': total_cache_read,
        'total_tokens': total_input + total_output,
        'total_sessions': len(all_sessions),
        'total_days': len(data),
        'estimated_cost': round((total_input * 0.8 + total_output * 0.8) / 1000000, 4),
        'models': dict(all_models),
        'projects': dict(all_projects),
        'trend': trend[-30:]
    }

def get_date_stats(date_str):
    """获取指定日期的统计"""
    data = load_daily_data(date_str)
    if date_str not in data:
        return None

    d = data[date_str]
    sessions_list = []
    for sid, sdata in d['sessions'].items():
        sessions_list.append({
            'session_id': sid,
            'project': sdata['project'],
            'model': sdata['model'],
            'input': sdata['input'],
            'output': sdata['output'],
            'cache_create': sdata['cache_create'],
            'cache_read': sdata['cache_read'],
            'total': sdata['input'] + sdata['output']
        })

    sessions_list.sort(key=lambda x: x['total'], reverse=True)

    models_dict = {}
    for model_name, model_data in d['models'].items():
        models_dict[model_name] = dict(model_data)

    return {
        'date': date_str,
        'total_input': d['input'],
        'total_output': d['output'],
        'total_cache_create': d['cache_create'],
        'total_cache_read': d['cache_read'],
        'total_tokens': d['input'] + d['output'],
        'total_sessions': len(d['sessions']),
        'estimated_cost': round((d['input'] * 0.8 + d['output'] * 0.8) / 1000000, 4),
        'models': models_dict,
        'sessions': sessions_list
    }

# ==================== HTML 模板 ====================

INDEX_TEMPLATE = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Claude Code Token 监控</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #0d1117;
            color: #c9d1d9;
            padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 {
            text-align: center;
            color: #58a6ff;
            margin-bottom: 30px;
            font-size: 28px;
        }
        .back-btn {
            position: fixed;
            top: 20px;
            left: 20px;
            background: #21262d;
            color: #c9d1d9;
            border: 1px solid #30363d;
            padding: 10px 20px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            text-decoration: none;
        }
        .back-btn:hover { background: #30363d; }
        .refresh-btn {
            position: fixed;
            top: 20px;
            right: 20px;
            background: #238636;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
        }
        .refresh-btn:hover { background: #2ea043; }
        .date-filter {
            text-align: center;
            margin-bottom: 20px;
        }
        .date-filter select {
            background: #21262d;
            color: #c9d1d9;
            border: 1px solid #30363d;
            padding: 8px 15px;
            border-radius: 6px;
            font-size: 14px;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 12px;
            padding: 20px;
            text-align: center;
        }
        .stat-card h3 {
            color: #8b949e;
            font-size: 12px;
            margin-bottom: 10px;
            text-transform: uppercase;
        }
        .stat-card .value {
            font-size: 28px;
            font-weight: bold;
            color: #58a6ff;
        }
        .stat-card .sub {
            font-size: 11px;
            color: #6e7681;
            margin-top: 5px;
        }
        .charts-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .chart-card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 12px;
            padding: 20px;
        }
        .chart-card h3 {
            color: #c9d1d9;
            margin-bottom: 15px;
            font-size: 16px;
        }
        .chart-container {
            position: relative;
            height: 300px;
        }
        .full-width {
            grid-column: 1 / -1;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 10px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #30363d;
        }
        th {
            color: #8b949e;
            font-weight: 600;
            font-size: 11px;
            text-transform: uppercase;
        }
        td { font-size: 13px; }
        tr:hover { background: #21262d; }
        .session-link {
            color: #58a6ff;
            text-decoration: none;
            cursor: pointer;
        }
        .session-link:hover {
            text-decoration: underline;
        }
        .model-tag {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: bold;
        }
        .model-kimi { background: #388bfd33; color: #58a6ff; }
        .model-claude { background: #a371f733; color: #bc8cff; }
        .model-gpt { background: #3fb95033; color: #3fb950; }
        .cost-positive { color: #3fb950; }
        .cache-tag {
            font-size: 10px;
            color: #8b949e;
            background: #21262d;
            padding: 2px 6px;
            border-radius: 4px;
            margin-left: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>{{TITLE}}</h1>
        {{BACK_BUTTON}}
        <button class="refresh-btn" onclick="location.reload()">刷新数据</button>

        <div class="date-filter">
            <select id="dateSelect" onchange="filterByDate()">
                <option value="">全部日期</option>
            </select>
        </div>

        <div class="stats-grid">
            <div class="stat-card">
                <h3>输入 Tokens</h3>
                <div class="value" id="statInput">-</div>
                <div class="sub">Input</div>
            </div>
            <div class="stat-card">
                <h3>输出 Tokens</h3>
                <div class="value" id="statOutput">-</div>
                <div class="sub">Output</div>
            </div>
            <div class="stat-card">
                <h3>总用量</h3>
                <div class="value" id="statTotal">-</div>
                <div class="sub">Total</div>
            </div>
            <div class="stat-card">
                <h3>预估费用</h3>
                <div class="value" id="statCost">-</div>
                <div class="sub">USD</div>
            </div>
            <div class="stat-card">
                <h3>会话数</h3>
                <div class="value" id="statSessions">-</div>
                <div class="sub">Sessions</div>
            </div>
            {{EXTRA_STAT}}
        </div>

        {{TREND_CHART}}

        <div class="charts-grid">
            <div class="chart-card">
                <h3>按模型统计</h3>
                <div class="chart-container">
                    <canvas id="modelChart"></canvas>
                </div>
            </div>
            <div class="chart-card">
                <h3>按项目统计（Top 10）</h3>
                <div class="chart-container">
                    <canvas id="projectChart"></canvas>
                </div>
            </div>
        </div>

        {{SESSIONS_TABLE}}

        <div class="chart-card full-width">
            <h3>详细数据</h3>
            <table>
                <thead>
                    <tr>
                        <th>模型</th>
                        <th>输入 Tokens</th>
                        <th>输出 Tokens</th>
                        <th>总计</th>
                        <th>预估费用</th>
                    </tr>
                </thead>
                <tbody id="detailTable"></tbody>
            </table>
        </div>
    </div>

    <script>
        const stats = {{STATS_JSON}};
        const isSingleDate = {{IS_SINGLE_DATE}};

        function formatNum(num) {
            if (num >= 1000000) return (num / 1000000).toFixed(2) + 'M';
            if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
            return num.toString();
        }

        // 填充日期选择器
        const dateSelect = document.getElementById('dateSelect');
        const selectedDate = '{{SELECTED_DATE}}';

        // 加载所有可用日期
        fetch('/api/dates')
            .then(r => r.json())
            .then(dates => {
                dates.forEach(date => {
                    const opt = document.createElement('option');
                    opt.value = date;
                    opt.textContent = date;
                    if (date === selectedDate) {
                        opt.selected = true;
                    }
                    dateSelect.appendChild(opt);
                });
            });

        // 更新统计卡片
        document.getElementById('statInput').textContent = formatNum(stats.total_input || 0);
        document.getElementById('statOutput').textContent = formatNum(stats.total_output || 0);
        document.getElementById('statTotal').textContent = formatNum(stats.total_tokens || 0);
        document.getElementById('statCost').textContent = '$' + (stats.estimated_cost || 0).toFixed(4);
        document.getElementById('statSessions').textContent = formatNum(stats.total_sessions || 0);

        // 模型饼图
        function initModelChart() {
            const ctx = document.getElementById('modelChart').getContext('2d');
            const models = Object.entries(stats.models || {});
            new Chart(ctx, {
                type: 'doughnut',
                data: {
                    labels: models.map(m => m[0]),
                    datasets: [{
                        data: models.map(m => m[1].input + m[1].output),
                        backgroundColor: ['#58a6ff', '#a371f7', '#3fb950', '#f0883e', '#f85149', '#79c0ff']
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'bottom',
                            labels: { color: '#c9d1d9', padding: 20 }
                        }
                    }
                }
            });
        }

        // 项目柱状图
        function initProjectChart() {
            const ctx = document.getElementById('projectChart').getContext('2d');
            const projects = Object.entries(stats.projects || {})
                .sort((a, b) => (b[1].input + b[1].output) - (a[1].input + a[1].output))
                .slice(0, 10);
            new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: projects.map(p => {
                        const name = p[0].split('/').pop() || p[0];
                        return name.length > 15 ? name.slice(0, 15) + '...' : name;
                    }),
                    datasets: [{
                        label: 'Total Tokens',
                        data: projects.map(p => p[1].input + p[1].output),
                        backgroundColor: '#58a6ff'
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: { legend: { display: false } },
                    scales: {
                        x: { ticks: { color: '#8b949e' }, grid: { display: false } },
                        y: { ticks: { color: '#8b949e' }, grid: { color: '#30363d' } }
                    }
                }
            });
        }

        // 详细表格
        function initDetailTable() {
            const tbody = document.getElementById('detailTable');
            const models = Object.entries(stats.models || {});
            tbody.innerHTML = models.map(([name, data]) => {
                const total = data.input + data.output;
                const cost = ((data.input * 0.8 + data.output * 0.8) / 1000000).toFixed(4);
                let modelClass = 'model-claude';
                if (name.includes('kimi')) modelClass = 'model-kimi';
                else if (name.includes('gpt')) modelClass = 'model-gpt';
                return `<tr>
                    <td><span class="model-tag ${modelClass}">${name}</span></td>
                    <td>${formatNum(data.input)}</td>
                    <td>${formatNum(data.output)}</td>
                    <td>${formatNum(total)}</td>
                    <td class="cost-positive">$${cost}</td>
                </tr>`;
            }).join('');
        }

        // 趋势图（仅全部日期视图）
        {{TREND_CHART_SCRIPT}}

        function filterByDate() {
            const date = document.getElementById('dateSelect').value;
            if (date) {
                location.href = '/?date=' + date;
            } else {
                location.href = '/';
            }
        }

        initModelChart();
        initProjectChart();
        initDetailTable();
    </script>
</body>
</html>
'''

SESSION_TEMPLATE = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>会话详情 - {{SESSION_ID}}</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #0d1117;
            color: #c9d1d9;
            padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 {
            text-align: center;
            color: #58a6ff;
            margin-bottom: 10px;
            font-size: 24px;
        }
        .subtitle {
            text-align: center;
            color: #8b949e;
            font-size: 14px;
            margin-bottom: 30px;
        }
        .back-btn {
            position: fixed;
            top: 20px;
            left: 20px;
            background: #21262d;
            color: #c9d1d9;
            border: 1px solid #30363d;
            padding: 10px 20px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            text-decoration: none;
        }
        .back-btn:hover { background: #30363d; }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 12px;
            padding: 15px;
            text-align: center;
        }
        .stat-card h3 {
            color: #8b949e;
            font-size: 11px;
            margin-bottom: 8px;
            text-transform: uppercase;
        }
        .stat-card .value {
            font-size: 22px;
            font-weight: bold;
            color: #58a6ff;
        }
        .stat-card .sub {
            font-size: 10px;
            color: #6e7681;
            margin-top: 3px;
        }
        .chart-card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 12px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .chart-card h3 {
            color: #c9d1d9;
            margin-bottom: 15px;
            font-size: 16px;
        }
        .chart-container {
            position: relative;
            height: 350px;
        }
        .savings-box {
            background: #23863633;
            border: 1px solid #238636;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 20px;
            display: flex;
            justify-content: space-around;
            flex-wrap: wrap;
        }
        .savings-item {
            text-align: center;
        }
        .savings-item .label {
            font-size: 12px;
            color: #8b949e;
            margin-bottom: 5px;
        }
        .savings-item .value {
            font-size: 24px;
            font-weight: bold;
            color: #3fb950;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 10px;
        }
        th, td {
            padding: 10px;
            text-align: left;
            border-bottom: 1px solid #30363d;
            font-size: 12px;
        }
        th {
            color: #8b949e;
            font-weight: 600;
            font-size: 10px;
            text-transform: uppercase;
        }
        tr:hover { background: #21262d; }
        .cache-info {
            color: #58a6ff;
        }
        .cache-create-highlight {
            color: #a371f7;
            font-weight: bold;
        }
        .msg-type-thinking, .msg-type-tool, .msg-type-text, .msg-status-thinking, .msg-status-waiting {
            display: inline-block;
            padding: 1px 6px;
            border-radius: 4px;
            font-size: 10px;
            margin-left: 5px;
            cursor: help;
            position: relative;
        }
        .msg-type-thinking {
            background: #f0883e33;
            color: #f0883e;
        }
        .msg-type-tool {
            background: #3fb95033;
            color: #3fb950;
        }
        .msg-type-text {
            background: #58a6ff33;
            color: #58a6ff;
        }
        .msg-status-thinking {
            background: #f0883e22;
            color: #f0883e;
            font-style: italic;
        }
        .msg-status-waiting {
            background: #ffd70022;
            color: #ffd700;
            font-style: italic;
        }
        .msg-status-empty {
            display: inline-block;
            padding: 1px 6px;
            border-radius: 4px;
            font-size: 10px;
            background: #6e768122;
            color: #8b949e;
            font-style: italic;
            margin-left: 5px;
            cursor: help;
            position: relative;
        }
        /* Tooltip */
        .msg-type-thinking:hover::after,
        .msg-type-tool:hover::after,
        .msg-type-text:hover::after,
        .msg-status-thinking:hover::after,
        .msg-status-waiting:hover::after,
        .msg-status-empty:hover::after {
            content: attr(data-tooltip);
            position: absolute;
            bottom: 100%;
            left: 50%;
            transform: translateX(-50%);
            padding: 6px 10px;
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 6px;
            font-size: 11px;
            color: #c9d1d9;
            white-space: nowrap;
            z-index: 1000;
            margin-bottom: 5px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        }
        .msg-type-thinking:hover::before,
        .msg-type-tool:hover::before,
        .msg-type-text:hover::before,
        .msg-status-thinking:hover::before,
        .msg-status-waiting:hover::before,
        .msg-status-empty:hover::before {
            content: '';
            position: absolute;
            bottom: 100%;
            left: 50%;
            transform: translateX(-50%);
            border: 5px solid transparent;
            border-top-color: #30363d;
            margin-bottom: -5px;
            z-index: 1001;
        }
        .cache-high {
            color: #ff7b72;
            font-weight: bold;
            cursor: help;
            position: relative;
        }
        .cache-high:hover::after {
            content: attr(data-tooltip);
            position: absolute;
            bottom: 100%;
            left: 50%;
            transform: translateX(-50%);
            padding: 8px 12px;
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 6px;
            font-size: 11px;
            color: #c9d1d9;
            white-space: nowrap;
            z-index: 1000;
            margin-bottom: 5px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            font-weight: normal;
        }
        .cache-high:hover::before {
            content: '';
            position: absolute;
            bottom: 100%;
            left: 50%;
            transform: translateX(-50%);
            border: 5px solid transparent;
            border-top-color: #30363d;
            margin-bottom: -5px;
            z-index: 1001;
        }
        .turn-num {
            background: #58a6ff33;
            color: #58a6ff;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 11px;
        }
        .cache-note {
            background: #21262d;
            border: 1px solid #30363d;
            border-radius: 8px;
            margin-bottom: 20px;
            font-size: 13px;
            color: #8b949e;
            overflow: hidden;
        }
        .cache-note-header {
            padding: 12px 15px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: #1c2128;
            transition: background 0.2s;
        }
        .cache-note-header:hover {
            background: #262c36;
        }
        .cache-note-header h4 {
            color: #c9d1d9;
            margin: 0;
            font-size: 14px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .cache-note-toggle {
            color: #8b949e;
            font-size: 12px;
            transition: transform 0.3s;
        }
        .cache-note.expanded .cache-note-toggle {
            transform: rotate(180deg);
        }
        .cache-note-content {
            padding: 15px;
            display: none;
            line-height: 1.6;
        }
        .cache-note.expanded .cache-note-content {
            display: block;
        }
        .cache-hit-rate {
            color: #3fb950;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <a href="{{BACK_URL}}" class="back-btn">← 返回</a>
        <h1>会话详情</h1>
        <div class="subtitle" id="sessionSubtitle">{{SESSION_ID}}</div>

        <div class="cache-note" id="cacheNote">
            <div class="cache-note-header" onclick="toggleCacheNote()">
                <h4>ℹ️ 缓存机制说明</h4>
                <span class="cache-note-toggle">▼</span>
            </div>
            <div class="cache-note-content" id="cacheNoteContent">加载中...</div>
        </div>
        <script>
            function toggleCacheNote() {
                const note = document.getElementById('cacheNote');
                note.classList.toggle('expanded');
            }
        </script>

        <div class="stats-grid">
            <div class="stat-card">
                <h3>总输入 Tokens</h3>
                <div class="value" id="totalInput">-</div>
            </div>
            <div class="stat-card">
                <h3>总输出 Tokens</h3>
                <div class="value" id="totalOutput">-</div>
            </div>
            <div class="stat-card">
                <h3>Cache Read</h3>
                <div class="value" id="totalCacheRead">-</div>
                <div class="sub" id="cacheHitRate"></div>
            </div>
            <div class="stat-card">
                <h3>总轮数</h3>
                <div class="value" id="totalTurns">-</div>
            </div>
        </div>

        <div class="savings-box">
            <div class="savings-item">
                <div class="label">无缓存预估花费</div>
                <div class="value" id="noCacheCost">-</div>
            </div>
            <div class="savings-item">
                <div class="label">实际花费（有缓存）</div>
                <div class="value" id="withCacheCost">-</div>
            </div>
            <div class="savings-item">
                <div class="label">节省金额</div>
                <div class="value" id="savedCost">-</div>
            </div>
            <div class="savings-item">
                <div class="label">节省比例</div>
                <div class="value" id="savedPercent">-</div>
            </div>
        </div>

        <div class="chart-card">
            <h3>💰 花费对比曲线：缓存带来的成本节省</h3>
            <div class="chart-container">
                <canvas id="costChart"></canvas>
            </div>
        </div>

        <div class="chart-card">
            <h3>📊 每轮 Token 消耗详情</h3>
            <table>
                <thead>
                    <tr>
                        <th>轮次</th>
                        <th>模型</th>
                        <th>Input</th>
                        <th>Output</th>
                        <th>Cache Create</th>
                        <th>Cache Read</th>
                        <th>本轮累计</th>
                    </tr>
                </thead>
                <tbody id="turnsTable"></tbody>
            </table>
        </div>
    </div>

    <script>
        const sessionData = {{SESSION_JSON}};
        const costComparison = {{COST_COMPARISON_JSON}};

        function formatNum(num) {
            if (num >= 1000000) return (num / 1000000).toFixed(2) + 'M';
            if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
            return num.toString();
        }

        // 更新副标题
        const subtitleEl = document.getElementById('sessionSubtitle');
        subtitleEl.textContent = `${sessionData.session_id} | 共 ${sessionData.total_turns} 轮对话`;

        // 填充统计卡片
        document.getElementById('totalInput').textContent = formatNum(sessionData.total_input);
        document.getElementById('totalOutput').textContent = formatNum(sessionData.total_output);
        document.getElementById('totalCacheRead').textContent = formatNum(sessionData.total_cache_read);
        document.getElementById('totalTurns').textContent = sessionData.total_turns;

        // 如果有 Cache Create 数据，动态插入卡片
        const hasCacheCreate = sessionData.total_cache_create > 0;
        if (hasCacheCreate) {
            const statsGrid = document.querySelector('.stats-grid');
            const cacheCreateCard = document.createElement('div');
            cacheCreateCard.className = 'stat-card';
            cacheCreateCard.innerHTML = `
                <h3>Cache Create</h3>
                <div class="value" style="color:#a371f7">${formatNum(sessionData.total_cache_create)}</div>
            `;
            statsGrid.insertBefore(cacheCreateCard, statsGrid.children[2]);
        }

        // 计算缓存命中率
        const totalInputWithCache = sessionData.total_input + sessionData.total_cache_read;
        const cacheHitRate = totalInputWithCache > 0
            ? ((sessionData.total_cache_read / totalInputWithCache) * 100).toFixed(1)
            : 0;
        document.getElementById('cacheHitRate').textContent = cacheHitRate > 0 ? `命中率 ${cacheHitRate}%` : '';

        // 缓存说明
        const modelName = sessionData.turns[0]?.model || 'unknown';
        const cacheNoteContent = document.getElementById('cacheNoteContent');
        const hasAnyCacheCreate = sessionData.turns.some(t => t.cache_create > 0);

        // 检查是否有 Cache Read 异常高的情况
        const hasHighCacheRead = sessionData.turns.some(t => t.cache_read > t.input * 5 && t.cache_read > 10000);

        if (modelName.includes('kimi') || modelName.includes('Kimi')) {
            if (hasAnyCacheCreate) {
                // 罕见的 Kimi 有 Cache Create 数据的情况
                cacheNoteContent.innerHTML = `
                    <b>Kimi 模型缓存机制（检测到显式缓存标记）：</b><br>
                    • 本会话包含 <b>${formatNum(sessionData.total_cache_create)}</b> 个 Cache Create tokens<br>
                    • <b>Cache Create</b>：主动标记为缓存的 tokens（可能用于长上下文保持）<br>
                    • <b>Cache Read</b>：命中缓存的 tokens 数，按优惠价格计费${hasHighCacheRead ? '（⚠️ 标记行表示 Cache Read 包含完整对话历史）' : ''}<br>
                    • 缓存命中率：<span class="cache-hit-rate">${cacheHitRate}%</span>，节省约 $${(costComparison[costComparison.length-1]?.saved || 0).toFixed(4)}
                `;
            } else {
                cacheNoteContent.innerHTML = `
                    <b>Kimi 模型缓存机制：</b><br>
                    • Kimi API 采用<b>自动缓存</b>机制，系统会自动复用历史对话上下文<br>
                    • <b>Cache Read</b>：命中缓存的 tokens 数（${formatNum(sessionData.total_cache_read)}）${hasHighCacheRead ? '，⚠️ 标记行表示 Cache Read 超过 Input 的 5 倍，表示该轮从缓存读取了大量历史对话' : ''}<br>
                    • <b>Input</b>：本轮新增的输入 tokens | <b>Cache Read</b>：从缓存读取的历史 tokens<br>
                    • <b>Cache Create</b>：Kimi 通常不显示此项，由系统自动管理<br>
                    • 缓存命中率：<span class="cache-hit-rate">${cacheHitRate}%</span>，节省约 $${(costComparison[costComparison.length-1]?.saved || 0).toFixed(4)}
                `;
            }
        } else if (modelName.includes('claude') || modelName.includes('Claude')) {
            cacheNoteContent.innerHTML = `
                <b>Claude 模型缓存机制：</b><br>
                • Claude 支持显式缓存控制（<b>ephemeral</b> 5分钟 / <b>persisted</b> 1小时缓存标记）<br>
                • <b>Cache Create</b>：首次创建缓存的 tokens 数（${hasAnyCacheCreate ? formatNum(sessionData.total_cache_create) : '本会话无'}）<br>
                • <b>Cache Read</b>：命中缓存的 tokens 数，计费更便宜${hasHighCacheRead ? '<br>• ⚠️ 部分轮次 Cache Read 显著高于 Input，表示大量复用了缓存的历史上下文' : ''}<br>
                • 缓存命中率：<span class="cache-hit-rate">${cacheHitRate}%</span>${costComparison.length > 0 ? `，累计节省 $${(costComparison[costComparison.length-1]?.saved || 0).toFixed(4)}` : ''}
            `;
        } else {
            cacheNoteContent.innerHTML = `
                <b>模型：${modelName}</b><br>
                • ${hasAnyCacheCreate ? `<b>Cache Create</b>：${formatNum(sessionData.total_cache_create)} tokens<br>` : ''}
                • <b>Cache Read</b>：命中缓存的 tokens 数（${formatNum(sessionData.total_cache_read)}）${hasHighCacheRead ? '（⚠️ 部分行 Cache Read 包含完整历史）' : ''}<br>
                • <b>Input</b>：本轮新增输入 | <b>Cache Read</b>：历史缓存读取<br>
                • 缓存命中率：<span class="cache-hit-rate">${cacheHitRate}%</span>
            `;
        }

        // 填充节省统计
        if (costComparison.length > 0) {
            const last = costComparison[costComparison.length - 1];
            document.getElementById('noCacheCost').textContent = '$' + last.no_cache.toFixed(4);
            document.getElementById('withCacheCost').textContent = '$' + last.with_cache.toFixed(4);
            document.getElementById('savedCost').textContent = '$' + last.saved.toFixed(4);
            document.getElementById('savedPercent').textContent = last.saved_percent + '%';
        }

        // 花费对比曲线图
        function initCostChart() {
            const ctx = document.getElementById('costChart').getContext('2d');
            new Chart(ctx, {
                type: 'line',
                data: {
                    labels: costComparison.map(c => '轮 ' + c.turn),
                    datasets: [{
                        label: '无缓存花费',
                        data: costComparison.map(c => c.no_cache),
                        borderColor: '#f85149',
                        backgroundColor: '#f8514933',
                        fill: true,
                        tension: 0.3
                    }, {
                        label: '有缓存花费（实际）',
                        data: costComparison.map(c => c.with_cache),
                        borderColor: '#3fb950',
                        backgroundColor: '#3fb95033',
                        fill: true,
                        tension: 0.3
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: { intersect: false, mode: 'index' },
                    plugins: {
                        legend: {
                            labels: { color: '#c9d1d9', font: { size: 12 } }
                        },
                        tooltip: {
                            callbacks: {
                                afterLabel: function(context) {
                                    const idx = context.dataIndex;
                                    const data = costComparison[idx];
                                    return `节省: $${data.saved.toFixed(6)} (${data.saved_percent}%)`;
                                }
                            }
                        }
                    },
                    scales: {
                        x: { ticks: { color: '#8b949e' }, grid: { color: '#30363d' } },
                        y: {
                            ticks: { color: '#8b949e', callback: v => '$' + v.toFixed(4) },
                            grid: { color: '#30363d' }
                        }
                    }
                }
            });
        }

        // 填充轮次表格
        function initTurnsTable() {
            const tbody = document.getElementById('turnsTable');
            tbody.innerHTML = sessionData.turns.map(turn => {
                const hasCacheCreate = turn.cache_create > 0;
                const hasCacheRead = turn.cache_read > 0;
                const msgTypes = turn.msg_type || [];
                const msgStatus = turn.msg_status || 'complete';

                // 类型标签
                const typeBadges = msgTypes.map(t => {
                    if (t === 'thinking') return '<span class="msg-type-thinking" data-tooltip="模型的内部思考过程（reasoning）">思考</span>';
                    if (t === 'tool_use') return '<span class="msg-type-tool" data-tooltip="调用外部工具（如 Bash、Read 等）">工具</span>';
                    if (t === 'text') return '<span class="msg-type-text" data-tooltip="正常的文本回复">回复</span>';
                    return '';
                }).join(' ');

                // 状态标签（用于中间状态）
                let statusBadge = '';
                if (msgStatus === 'thinking') {
                    statusBadge = '<span class="msg-status-thinking" data-tooltip="正在生成思考过程，尚未输出结果">思考中...</span>';
                } else if (msgStatus === 'waiting') {
                    statusBadge = '<span class="msg-status-waiting" data-tooltip="已发起工具调用，等待执行结果">等待工具...</span>';
                } else if (msgStatus === 'empty') {
                    statusBadge = '<span class="msg-status-empty" data-tooltip="消息包含text类型但无实际输出内容（可能是预分配token或空消息）">空消息</span>';
                }

                // Cache Read 是否异常高（超过 input 的 5 倍且大于10000）
                const isCacheReadHigh = turn.cache_read > turn.input * 5 && turn.cache_read > 10000;

                // 构建 Cache Read 的 tooltip
                let cacheReadTooltip = '';
                if (isCacheReadHigh) {
                    cacheReadTooltip = `Cache Read (${formatNum(turn.cache_read)}) 包含了完整对话历史缓存，而 Input (${formatNum(turn.input)}) 只是本轮新增的 tokens`;
                }

                return `<tr>
                    <td><span class="turn-num">#${turn.turn}</span></td>
                    <td>${turn.model} ${typeBadges} ${statusBadge}</td>
                    <td>${formatNum(turn.input)}</td>
                    <td>${formatNum(turn.output)}</td>
                    <td class="${hasCacheCreate ? 'cache-create-highlight' : ''}">${hasCacheCreate ? formatNum(turn.cache_create) : '<span style="color:#6e7681">-</span>'}</td>
                    <td class="${hasCacheRead ? (isCacheReadHigh ? 'cache-high' : 'cache-info') : ''}"
                        ${isCacheReadHigh ? `data-tooltip="${cacheReadTooltip}" style="cursor: help;"` : ''}
                        >${hasCacheRead ? formatNum(turn.cache_read) + (isCacheReadHigh ? ' ⚠' : '') : '<span style="color:#6e7681">-</span>'}</td>
                    <td>${formatNum(turn.cumulative_total)}</td>
                </tr>`;
            }).join('');
        }

        initCostChart();
        initTurnsTable();
    </script>
</body>
</html>
'''

# ==================== HTTP 处理器 ====================

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        if path == '/' or path == '/index.html':
            self.handle_index(query)
        elif path == '/session':
            self.handle_session(query)
        elif path == '/api/dates':
            self.handle_api_dates()
        else:
            self.send_response(404)
            self.end_headers()

    def handle_index(self, query):
        """处理首页"""
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()

        target_date = query.get('date', [None])[0]

        if target_date:
            # 单日视图
            stats = get_date_stats(target_date)
            if not stats:
                stats = get_summary_stats()
                is_single_date = False
            else:
                is_single_date = True
        else:
            # 全部日期视图
            stats = get_summary_stats()
            is_single_date = False

        # 构建模板变量
        if is_single_date:
            title = f'Claude Code Token 监控 - {target_date}'
            back_button = ''
            extra_stat = ''
            trend_chart = ''
            trend_script = ''

            # 生成会话列表表格
            sessions_rows = ''
            for s in stats.get('sessions', []):
                sessions_rows += f'''<tr>
                    <td><a href="/session?id={s['session_id']}" class="session-link">{s['session_id'][:20]}...</a></td>
                    <td>{s['project']}</td>
                    <td>{s['model']}</td>
                    <td>{s['input']:,}</td>
                    <td>{s['output']:,}</td>
                    <td>{s['cache_read']:,}</td>
                    <td>{s['total']:,}</td>
                </tr>'''

            sessions_table = f'''
            <div class="chart-card full-width">
                <h3>📋 会话列表（按Token消耗排序）</h3>
                <table>
                    <thead>
                        <tr>
                            <th>会话ID</th>
                            <th>项目</th>
                            <th>模型</th>
                            <th>Input</th>
                            <th>Output</th>
                            <th>Cache Read</th>
                            <th>总计</th>
                        </tr>
                    </thead>
                    <tbody>{sessions_rows}</tbody>
                </table>
            </div>
            '''
        else:
            title = 'Claude Code Token 监控面板'
            back_button = ''
            extra_stat = '''
            <div class="stat-card">
                <h3>监控天数</h3>
                <div class="value" id="statTotalDays">-</div>
                <div class="sub">Days</div>
            </div>
            '''
            trend_chart = '''
            <div class="chart-card full-width">
                <h3>📈 Token 使用趋势（最近30天）</h3>
                <div class="chart-container">
                    <canvas id="trendChart"></canvas>
                </div>
            </div>
            '''
            trend_script = '''
            // 趋势图
            const trendCtx = document.getElementById('trendChart').getContext('2d');
            new Chart(trendCtx, {
                type: 'line',
                data: {
                    labels: stats.trend.map(t => t.date.slice(5)),
                    datasets: [{
                        label: 'Input',
                        data: stats.trend.map(t => t.input),
                        borderColor: '#58a6ff',
                        backgroundColor: '#58a6ff33',
                        fill: true,
                        tension: 0.4
                    }, {
                        label: 'Output',
                        data: stats.trend.map(t => t.output),
                        borderColor: '#a371f7',
                        backgroundColor: '#a371f733',
                        fill: true,
                        tension: 0.4
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: { intersect: false, mode: 'index' },
                    plugins: { legend: { labels: { color: '#c9d1d9' } } },
                    scales: {
                        x: { ticks: { color: '#8b949e' }, grid: { color: '#30363d' } },
                        y: { ticks: { color: '#8b949e' }, grid: { color: '#30363d' } }
                    }
                }
            });
            '''
            sessions_table = ''

        html = INDEX_TEMPLATE
        html = html.replace('{{TITLE}}', title)
        html = html.replace('{{BACK_BUTTON}}', back_button)
        html = html.replace('{{EXTRA_STAT}}', extra_stat)
        html = html.replace('{{TREND_CHART}}', trend_chart)
        html = html.replace('{{TREND_CHART_SCRIPT}}', trend_script)
        html = html.replace('{{SESSIONS_TABLE}}', sessions_table)
        html = html.replace('{{STATS_JSON}}', json.dumps(stats))
        html = html.replace('{{IS_SINGLE_DATE}}', 'true' if is_single_date else 'false')
        html = html.replace('{{SELECTED_DATE}}', target_date or '')

        self.wfile.write(html.encode())

    def handle_session(self, query):
        """处理会话详情页"""
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()

        session_id = query.get('id', [''])[0]
        if not session_id:
            self.wfile.write(b'Session ID required')
            return

        session_data = load_session_detail(session_id)
        if not session_data:
            self.wfile.write(f'Session not found: {session_id}'.encode())
            return

        cost_comparison = calculate_cost_with_cache(session_data['turns'])

        # 查找返回链接的日期
        back_url = '/'
        # 尝试从session文件修改时间推断日期
        for root, dirs, files in os.walk(PROJECTS_DIR):
            for f in files:
                if f == f"{session_id}.jsonl":
                    filepath = os.path.join(root, f)
                    try:
                        mtime = os.path.getmtime(filepath)
                        date_str = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d')
                        back_url = f'/?date={date_str}'
                    except:
                        pass
                    break

        html = SESSION_TEMPLATE
        html = html.replace('{{SESSION_ID}}', session_id)
        html = html.replace('{{TOTAL_TURNS}}', str(session_data['total_turns']))
        html = html.replace('{{BACK_URL}}', back_url)
        html = html.replace('{{SESSION_JSON}}', json.dumps(session_data))
        html = html.replace('{{COST_COMPARISON_JSON}}', json.dumps(cost_comparison))

        self.wfile.write(html.encode())

    def handle_api_dates(self):
        """API: 获取所有可用日期"""
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

        daily_dir = os.path.join(STATS_DIR, "daily")
        dates = []
        if os.path.exists(daily_dir):
            for f in os.listdir(daily_dir):
                if f.endswith('.csv'):
                    dates.append(f.replace('.csv', ''))
        dates.sort(reverse=True)

        self.wfile.write(json.dumps(dates).encode())

    def log_message(self, format, *args):
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {args[0]}")

def main():
    port = 8866
    if len(sys.argv) > 1:
        port = int(sys.argv[1])

    server = HTTPServer(('127.0.0.1', port), RequestHandler)
    print(f"\n🚀 Token 监控面板已启动!")
    print(f"📊 访问地址: http://127.0.0.1:{port}")
    print(f"📁 数据目录: {STATS_DIR}")
    print(f"\n按 Ctrl+C 停止服务\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n\n服务已停止")
        sys.exit(0)

if __name__ == '__main__':
    main()
