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

                # 过滤无效模型名
                if not model or model == "model" or model.startswith("<"):
                    continue

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

        :root {
            /* 背景色 - 深邃宇宙黑 */
            --bg-primary: #050508;
            --bg-secondary: #0a0a0f;
            --bg-tertiary: #0f0f16;

            /* 玻璃效果 */
            --glass-bg: rgba(16, 18, 30, 0.6);
            --glass-border: rgba(99, 102, 241, 0.1);
            --glass-border-hover: rgba(99, 102, 241, 0.3);
            --glass-blur: blur(20px) saturate(150%);

            /* 强调色 - 霓虹极光 */
            --accent-cyan: #22d3ee;
            --accent-violet: #a78bfa;
            --accent-fuchsia: #e879f9;
            --accent-emerald: #34d399;
            --accent-amber: #fbbf24;
            --accent-rose: #fb7185;
            --accent-indigo: #818cf8;
            --accent-teal: #2dd4bf;

            /* 渐变色 */
            --gradient-primary: linear-gradient(135deg, #22d3ee 0%, #818cf8 50%, #e879f9 100%);
            --gradient-border: linear-gradient(135deg, rgba(34, 211, 238, 0.5), rgba(168, 85, 247, 0.3), rgba(232, 121, 249, 0.5));
            --gradient-glow: radial-gradient(ellipse at center, rgba(34, 211, 238, 0.2) 0%, transparent 70%);

            /* 文字 */
            --text-primary: #f8fafc;
            --text-secondary: #94a3b8;
            --text-tertiary: #64748b;

            /* 阴影 */
            --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.4), 0 1px 3px rgba(0, 0, 0, 0.3);
            --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.5), 0 2px 4px -2px rgba(0, 0, 0, 0.4);
            --shadow-glow: 0 0 40px rgba(34, 211, 238, 0.2), 0 0 80px rgba(168, 85, 247, 0.1);
            --shadow-inner: inset 0 1px 1px rgba(255, 255, 255, 0.03);

            /* 间距 */
            --radius-sm: 8px;
            --radius-md: 12px;
            --radius-lg: 16px;
            --radius-xl: 24px;
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
            background:
                /* 顶部极光光晕 */
                radial-gradient(ellipse 100% 60% at 50% 0%, rgba(34, 211, 238, 0.12) 0%, transparent 50%),
                radial-gradient(ellipse 80% 40% at 20% 10%, rgba(168, 85, 247, 0.08) 0%, transparent 40%),
                radial-gradient(ellipse 80% 40% at 80% 20%, rgba(232, 121, 249, 0.06) 0%, transparent 40%),
                /* 底部反光 */
                radial-gradient(ellipse 100% 40% at 50% 100%, rgba(34, 211, 238, 0.05) 0%, transparent 40%),
                /* 主体深色背景 */
                linear-gradient(180deg, var(--bg-primary) 0%, var(--bg-secondary) 50%, var(--bg-tertiary) 100%);
            color: var(--text-primary);
            padding: 24px;
            min-height: 100vh;
            line-height: 1.6;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
            position: relative;
            overflow-x: hidden;
        }

        /* 动态网格背景 */
        body::before {
            content: '';
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background-image:
                linear-gradient(rgba(99, 102, 241, 0.03) 1px, transparent 1px),
                linear-gradient(90deg, rgba(99, 102, 241, 0.03) 1px, transparent 1px);
            background-size: 60px 60px;
            pointer-events: none;
            z-index: -1;
        }

        /* 流动光效动画 */
        @keyframes aurora {
            0%, 100% {
                opacity: 0.5;
                transform: translateX(-50%) translateY(-50%) rotate(0deg);
            }
            50% {
                opacity: 0.8;
                transform: translateX(-30%) translateY(-30%) rotate(180deg);
            }
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 0 16px;
        }

        /* 头部标题 - 精致渐变 */
        .header {
            text-align: center;
            margin-bottom: 40px;
            position: relative;
        }

        .header::before {
            content: '';
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: 300px;
            height: 100px;
            background: var(--gradient-glow);
            filter: blur(60px);
            pointer-events: none;
            z-index: -1;
        }

        h1 {
            font-size: 36px;
            font-weight: 700;
            letter-spacing: -0.03em;
            background: linear-gradient(135deg, #f1f5f9 0%, #38bdf8 50%, #818cf8 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            margin-bottom: 8px;
            position: relative;
        }

        .subtitle {
            color: var(--text-secondary);
            font-size: 14px;
            font-weight: 400;
            letter-spacing: 0.02em;
        }

        /* 按钮样式 - 玻璃拟态 */
        .back-btn {
            position: fixed;
            top: 24px;
            left: 24px;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 10px 18px;
            background: var(--glass-bg);
            backdrop-filter: var(--glass-blur);
            -webkit-backdrop-filter: var(--glass-blur);
            border: 1px solid var(--glass-border);
            border-radius: var(--radius-md);
            color: var(--text-secondary);
            font-size: 13px;
            font-weight: 500;
            text-decoration: none;
            cursor: pointer;
            transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
            box-shadow: var(--shadow-sm);
        }

        .back-btn::before {
            content: '←';
            font-size: 14px;
            transition: transform 0.25s ease;
        }

        .back-btn:hover {
            border-color: var(--glass-border-hover);
            color: var(--accent-cyan);
            transform: translateY(-2px);
            box-shadow: var(--shadow-md), 0 0 20px rgba(56, 189, 248, 0.15);
        }

        .back-btn:hover::before {
            transform: translateX(-3px);
        }

        .refresh-btn {
            position: fixed;
            top: 24px;
            right: 24px;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 10px 20px;
            background: linear-gradient(135deg, rgba(52, 211, 153, 0.15), rgba(52, 211, 153, 0.05));
            backdrop-filter: var(--glass-blur);
            -webkit-backdrop-filter: var(--glass-blur);
            border: 1px solid rgba(52, 211, 153, 0.25);
            border-radius: var(--radius-md);
            color: var(--accent-emerald);
            font-size: 13px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
            box-shadow: var(--shadow-sm);
        }

        .refresh-btn::before {
            content: '↻';
            font-size: 14px;
            display: inline-block;
            transition: transform 0.5s ease;
        }

        .refresh-btn:hover {
            background: linear-gradient(135deg, rgba(52, 211, 153, 0.25), rgba(52, 211, 153, 0.1));
            border-color: rgba(52, 211, 153, 0.4);
            transform: translateY(-2px);
            box-shadow: var(--shadow-md), 0 0 25px rgba(52, 211, 153, 0.2);
        }

        .refresh-btn:hover::before {
            transform: rotate(180deg);
        }

        /* 日期选择器 */
        .date-filter {
            display: flex;
            justify-content: center;
            margin-bottom: 32px;
        }

        .date-filter select {
            appearance: none;
            background: var(--glass-bg);
            backdrop-filter: var(--glass-blur);
            -webkit-backdrop-filter: var(--glass-blur);
            color: var(--text-primary);
            border: 1px solid var(--glass-border);
            padding: 12px 44px 12px 18px;
            border-radius: var(--radius-md);
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.25s ease;
            box-shadow: var(--shadow-sm), var(--shadow-inner);
            background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 24 24' fill='none' stroke='%2394a3b8' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='m6 9 6 6 6-6'/%3E%3C/svg%3E");
            background-repeat: no-repeat;
            background-position: right 14px center;
        }

        .date-filter select:hover {
            border-color: var(--glass-border-hover);
            background-color: rgba(20, 22, 35, 0.7);
        }

        .date-filter select:focus {
            outline: none;
            border-color: var(--accent-cyan);
            box-shadow: 0 0 0 3px rgba(56, 189, 248, 0.1), var(--shadow-inner);
        }

        /* 统计卡片网格 */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 20px;
            margin-bottom: 32px;
        }

        .stat-card {
            position: relative;
            padding: 28px 24px;
            background: var(--glass-bg);
            backdrop-filter: var(--glass-blur);
            -webkit-backdrop-filter: var(--glass-blur);
            border: 1px solid var(--glass-border);
            border-radius: var(--radius-lg);
            text-align: center;
            transition: all 0.35s cubic-bezier(0.4, 0, 0.2, 1);
            box-shadow: var(--shadow-sm), var(--shadow-inner);
            overflow: hidden;
        }

        /* 卡片顶部渐变线 */
        .stat-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 20%;
            right: 20%;
            height: 2px;
            background: var(--gradient-primary);
            opacity: 0;
            transition: all 0.35s ease;
            border-radius: 0 0 2px 2px;
        }

        /* 卡片悬停光效 */
        .stat-card::after {
            content: '';
            position: absolute;
            inset: 0;
            background: radial-gradient(600px circle at var(--mouse-x, 50%) var(--mouse-y, 50%), rgba(56, 189, 248, 0.06), transparent 40%);
            opacity: 0;
            transition: opacity 0.35s ease;
            pointer-events: none;
        }

        .stat-card:hover {
            transform: translateY(-4px) scale(1.01);
            border-color: var(--glass-border-hover);
            box-shadow: var(--shadow-md), var(--shadow-glow);
        }

        .stat-card:hover::before {
            opacity: 1;
            left: 10%;
            right: 10%;
        }

        .stat-card:hover::after {
            opacity: 1;
        }

        /* 卡片图标 */
        .stat-card .icon {
            width: 40px;
            height: 40px;
            margin: 0 auto 16px;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: var(--radius-md);
            background: rgba(56, 189, 248, 0.1);
            border: 1px solid rgba(56, 189, 248, 0.2);
            font-size: 18px;
            transition: all 0.35s ease;
        }

        .stat-card:nth-child(1) .icon { background: rgba(34, 211, 238, 0.12); border-color: rgba(34, 211, 238, 0.3); box-shadow: 0 0 20px rgba(34, 211, 238, 0.1); }
        .stat-card:nth-child(2) .icon { background: rgba(168, 85, 247, 0.12); border-color: rgba(168, 85, 247, 0.3); box-shadow: 0 0 20px rgba(168, 85, 247, 0.1); }
        .stat-card:nth-child(3) .icon { background: rgba(52, 211, 153, 0.12); border-color: rgba(52, 211, 153, 0.3); box-shadow: 0 0 20px rgba(52, 211, 153, 0.1); }
        .stat-card:nth-child(4) .icon { background: rgba(251, 191, 36, 0.12); border-color: rgba(251, 191, 36, 0.3); box-shadow: 0 0 20px rgba(251, 191, 36, 0.1); }
        .stat-card:nth-child(5) .icon { background: rgba(251, 113, 133, 0.12); border-color: rgba(251, 113, 133, 0.3); box-shadow: 0 0 20px rgba(251, 113, 133, 0.1); }

        .stat-card:hover .icon {
            transform: scale(1.1);
            box-shadow: 0 0 20px rgba(56, 189, 248, 0.2);
        }

        .stat-card h3 {
            color: var(--text-secondary);
            font-size: 12px;
            margin-bottom: 12px;
            text-transform: uppercase;
            letter-spacing: 1.5px;
            font-weight: 600;
        }

        .stat-card .value {
            font-family: 'SF Mono', 'JetBrains Mono', 'Fira Code', monospace;
            font-size: 28px;
            font-weight: 600;
            color: var(--text-primary);
            letter-spacing: -0.02em;
            line-height: 1.2;
        }

        .stat-card:nth-child(1) .value {
            background: linear-gradient(135deg, #22d3ee, #67e8f9);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            filter: drop-shadow(0 0 8px rgba(34, 211, 238, 0.3));
        }
        .stat-card:nth-child(2) .value {
            background: linear-gradient(135deg, #a78bfa, #c4b5fd);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            filter: drop-shadow(0 0 8px rgba(167, 139, 250, 0.3));
        }
        .stat-card:nth-child(3) .value {
            background: linear-gradient(135deg, #34d399, #6ee7b7);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            filter: drop-shadow(0 0 8px rgba(52, 211, 153, 0.3));
        }
        .stat-card:nth-child(4) .value {
            background: linear-gradient(135deg, #fbbf24, #fcd34d);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            filter: drop-shadow(0 0 8px rgba(251, 191, 36, 0.3));
        }
        .stat-card:nth-child(5) .value {
            background: linear-gradient(135deg, #fb7185, #fda4af);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            filter: drop-shadow(0 0 8px rgba(251, 113, 133, 0.3));
        }

        .stat-card .sub {
            font-size: 12px;
            color: var(--text-tertiary);
            margin-top: 8px;
            font-weight: 500;
            letter-spacing: 0.02em;
        }

        /* 图表区域 */
        .charts-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(420px, 1fr));
            gap: 24px;
            margin-bottom: 32px;
        }

        .chart-card {
            position: relative;
            padding: 28px;
            background: var(--glass-bg);
            backdrop-filter: var(--glass-blur);
            -webkit-backdrop-filter: var(--glass-blur);
            border: 1px solid var(--glass-border);
            border-radius: var(--radius-lg);
            transition: all 0.35s cubic-bezier(0.4, 0, 0.2, 1);
            box-shadow: var(--shadow-sm), var(--shadow-inner);
            overflow: hidden;
        }

        .chart-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 30%;
            right: 30%;
            height: 2px;
            background: var(--gradient-primary);
            opacity: 0;
            transition: all 0.35s ease;
        }

        .chart-card:hover {
            transform: translateY(-2px);
            border-color: var(--glass-border-hover);
            box-shadow: var(--shadow-md), var(--shadow-glow);
        }

        .chart-card:hover::before {
            opacity: 1;
            left: 15%;
            right: 15%;
        }

        .chart-card.full-width {
            grid-column: 1 / -1;
        }

        .chart-card h3 {
            color: var(--text-primary);
            margin-bottom: 24px;
            font-size: 15px;
            font-weight: 600;
            display: flex;
            align-items: center;
            gap: 10px;
            letter-spacing: -0.01em;
        }

        .chart-card h3 .icon {
            width: 32px;
            height: 32px;
            display: flex;
            align-items: center;
            justify-content: center;
            background: rgba(56, 189, 248, 0.1);
            border: 1px solid rgba(56, 189, 248, 0.2);
            border-radius: var(--radius-sm);
            font-size: 14px;
        }

        .chart-container {
            position: relative;
            height: 280px;
        }

        /* 数据表格 */
        .data-table-container {
            overflow: hidden;
        }

        table {
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            margin-top: 10px;
        }

        th, td {
            padding: 16px;
            text-align: left;
        }

        th {
            color: var(--text-tertiary);
            font-weight: 600;
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: 1.2px;
            border-bottom: 1px solid var(--glass-border);
        }

        td {
            font-size: 13px;
            color: var(--text-secondary);
            border-bottom: 1px solid rgba(148, 163, 184, 0.05);
            transition: all 0.2s ease;
        }

        tr:hover td {
            color: var(--text-primary);
            background: rgba(56, 189, 248, 0.04);
        }

        .session-link {
            color: var(--accent-cyan);
            text-decoration: none;
            cursor: pointer;
            font-weight: 500;
            transition: all 0.2s ease;
            position: relative;
        }

        .session-link::after {
            content: '';
            position: absolute;
            bottom: -2px;
            left: 0;
            width: 0;
            height: 1px;
            background: var(--accent-cyan);
            transition: width 0.3s ease;
            box-shadow: 0 0 10px var(--accent-cyan);
        }

        .session-link:hover {
            color: #7dd3fc;
        }

        .session-link:hover::after {
            width: 100%;
        }

        .model-tag {
            display: inline-flex;
            align-items: center;
            padding: 4px 10px;
            border-radius: 20px;
            font-size: 11px;
            font-weight: 600;
            letter-spacing: 0.3px;
            border: 1px solid;
            transition: all 0.2s ease;
        }

        .model-tag:hover {
            transform: scale(1.05);
        }

        .model-kimi {
            background: linear-gradient(135deg, rgba(34, 211, 238, 0.15), rgba(8, 145, 178, 0.08));
            color: #22d3ee;
            border-color: rgba(34, 211, 238, 0.35);
            box-shadow: 0 0 12px rgba(34, 211, 238, 0.15);
        }

        .model-claude {
            background: linear-gradient(135deg, rgba(168, 85, 247, 0.15), rgba(124, 58, 237, 0.08));
            color: #a78bfa;
            border-color: rgba(168, 85, 247, 0.35);
            box-shadow: 0 0 12px rgba(168, 85, 247, 0.15);
        }

        .model-gpt {
            background: linear-gradient(135deg, rgba(52, 211, 153, 0.15), rgba(5, 150, 105, 0.08));
            color: #34d399;
            border-color: rgba(52, 211, 153, 0.35);
            box-shadow: 0 0 12px rgba(52, 211, 153, 0.15);
        }

        .model-deepseek {
            background: linear-gradient(135deg, rgba(232, 121, 249, 0.15), rgba(192, 38, 211, 0.08));
            color: #e879f9;
            border-color: rgba(232, 121, 249, 0.35);
            box-shadow: 0 0 12px rgba(232, 121, 249, 0.15);
        }

        .model-gemini {
            background: linear-gradient(135deg, rgba(251, 191, 36, 0.15), rgba(217, 119, 6, 0.08));
            color: #fbbf24;
            border-color: rgba(251, 191, 36, 0.35);
            box-shadow: 0 0 12px rgba(251, 191, 36, 0.15);
        }

        .cost-positive {
            color: var(--accent-emerald);
            font-family: 'SF Mono', monospace;
            font-weight: 600;
        }

        .cache-tag {
            font-size: 10px;
            color: var(--text-tertiary);
            background: rgba(148, 163, 184, 0.12);
            padding: 3px 8px;
            border-radius: 4px;
            margin-left: 5px;
        }

        /* 动画 */
        @keyframes fadeInUp {
            from {
                opacity: 0;
                transform: translateY(20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        @keyframes shimmer {
            0% { background-position: -200% 0; }
            100% { background-position: 200% 0; }
        }

        @keyframes pulse-glow {
            0%, 100% { box-shadow: 0 0 20px rgba(56, 189, 248, 0.1); }
            50% { box-shadow: 0 0 40px rgba(56, 189, 248, 0.2); }
        }

        .stat-card, .chart-card {
            animation: fadeInUp 0.6s ease backwards;
        }

        .stat-card:nth-child(1) { animation-delay: 0.05s; }
        .stat-card:nth-child(2) { animation-delay: 0.1s; }
        .stat-card:nth-child(3) { animation-delay: 0.15s; }
        .stat-card:nth-child(4) { animation-delay: 0.2s; }
        .stat-card:nth-child(5) { animation-delay: 0.25s; }

        .chart-card:nth-child(1) { animation-delay: 0.3s; }
        .chart-card:nth-child(2) { animation-delay: 0.35s; }

        /* 响应式 */
        @media (max-width: 768px) {
            body { padding: 16px; }
            h1 { font-size: 28px; }
            .stats-grid { grid-template-columns: repeat(2, 1fr); }
            .charts-grid { grid-template-columns: 1fr; }
            .chart-container { height: 240px; }
        }
            margin-left: 5px;
            font-weight: 500;
        }

        /* Animations */
        @keyframes fadeInUp {
            from {
                opacity: 0;
                transform: translateY(20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        .stat-card {
            animation: fadeInUp 0.5s ease backwards;
        }

        .stat-card:nth-child(1) { animation-delay: 0.05s; }
        .stat-card:nth-child(2) { animation-delay: 0.1s; }
        .stat-card:nth-child(3) { animation-delay: 0.15s; }
        .stat-card:nth-child(4) { animation-delay: 0.2s; }
        .stat-card:nth-child(5) { animation-delay: 0.25s; }

        .chart-card {
            animation: fadeInUp 0.6s ease backwards;
            animation-delay: 0.3s;
        }

        @keyframes numberPulse {
            0%, 100% { transform: scale(1); }
            50% { transform: scale(1.02); }
        }

        .stat-card .value {
            animation: numberPulse 3s ease infinite;
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
                <div class="icon">⬇</div>
                <h3>输入 Tokens</h3>
                <div class="value" id="statInput">-</div>
                <div class="sub">Input</div>
            </div>
            <div class="stat-card">
                <div class="icon">⬆</div>
                <h3>输出 Tokens</h3>
                <div class="value" id="statOutput">-</div>
                <div class="sub">Output</div>
            </div>
            <div class="stat-card">
                <div class="icon">∑</div>
                <h3>总用量</h3>
                <div class="value" id="statTotal">-</div>
                <div class="sub">Total</div>
            </div>
            <div class="stat-card">
                <div class="icon">$</div>
                <h3>预估费用</h3>
                <div class="value" id="statCost">-</div>
                <div class="sub">USD</div>
            </div>
            <div class="stat-card">
                <div class="icon">◉</div>
                <h3>会话数</h3>
                <div class="value" id="statSessions">-</div>
                <div class="sub">Sessions</div>
            </div>
            {{EXTRA_STAT}}
        </div>

        {{TREND_CHART}}

        <div class="charts-grid">
            <div class="chart-card">
                <h3><span class="icon">◧</span>按模型统计</h3>
                <div class="chart-container">
                    <canvas id="modelChart"></canvas>
                </div>
            </div>
            <div class="chart-card">
                <h3><span class="icon">◨</span>按项目统计（Top 10）</h3>
                <div class="chart-container">
                    <canvas id="projectChart"></canvas>
                </div>
            </div>
        </div>

        {{SESSIONS_TABLE}}

        <div class="chart-card full-width">
            <h3><span class="icon">☰</span>详细数据</h3>
            <div class="data-table-container">
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

        // 模型饼图 - 霓虹渐变环形图
        function initModelChart() {
            const ctx = document.getElementById('modelChart').getContext('2d');
            const models = Object.entries(stats.models || {});

            // 霓虹渐变配色方案
            const gradientColors = [
                createRadialGradient(ctx, '#22d3ee', '#0891b2'),
                createRadialGradient(ctx, '#a78bfa', '#7c3aed'),
                createRadialGradient(ctx, '#e879f9', '#c026d3'),
                createRadialGradient(ctx, '#34d399', '#059669'),
                createRadialGradient(ctx, '#fbbf24', '#d97706'),
                createRadialGradient(ctx, '#fb7185', '#e11d48'),
                createRadialGradient(ctx, '#2dd4bf', '#0d9488'),
                createRadialGradient(ctx, '#818cf8', '#4f46e5'),
            ];

            const borderColors = [
                '#22d3ee', '#a78bfa', '#e879f9', '#34d399',
                '#fbbf24', '#fb7185', '#2dd4bf', '#818cf8'
            ];

            new Chart(ctx, {
                type: 'doughnut',
                data: {
                    labels: models.map(m => m[0]),
                    datasets: [{
                        data: models.map(m => m[1].input + m[1].output),
                        backgroundColor: gradientColors.slice(0, models.length),
                        borderColor: borderColors.slice(0, models.length),
                        borderWidth: 2,
                        hoverOffset: 15,
                        hoverBorderWidth: 3,
                        hoverBorderColor: '#ffffff',
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    cutout: '65%',
                    radius: '90%',
                    plugins: {
                        legend: {
                            position: 'bottom',
                            labels: {
                                color: '#94a3b8',
                                padding: 20,
                                font: { size: 12, family: '-apple-system, BlinkMacSystemFont, sans-serif' },
                                usePointStyle: true,
                                pointStyle: 'circle',
                                pointRadius: 6,
                            }
                        },
                        tooltip: {
                            backgroundColor: 'rgba(16, 18, 30, 0.9)',
                            titleColor: '#f8fafc',
                            bodyColor: '#94a3b8',
                            borderColor: 'rgba(99, 102, 241, 0.2)',
                            borderWidth: 1,
                            padding: 12,
                            cornerRadius: 8,
                            displayColors: true,
                            callbacks: {
                                label: function(context) {
                                    const label = context.label || '';
                                    const value = context.parsed || 0;
                                    const total = context.dataset.data.reduce((a, b) => a + b, 0);
                                    const percentage = ((value / total) * 100).toFixed(1);
                                    return `${label}: ${formatNum(value)} (${percentage}%)`;
                                }
                            }
                        }
                    },
                    animation: {
                        animateRotate: true,
                        animateScale: true,
                        duration: 1500,
                        easing: 'easeOutQuart'
                    }
                }
            });
        }

        // 创建径向渐变
        function createRadialGradient(ctx, color1, color2) {
            const gradient = ctx.createRadialGradient(150, 150, 0, 150, 150, 150);
            gradient.addColorStop(0, color1);
            gradient.addColorStop(1, color2);
            return gradient;
        }

        // 项目柱状图 - 霓虹渐变柱状图
        function initProjectChart() {
            const ctx = document.getElementById('projectChart').getContext('2d');
            const projects = Object.entries(stats.projects || {})
                .sort((a, b) => (b[1].input + b[1].output) - (a[1].input + a[1].output))
                .slice(0, 10);

            // 为每个柱子创建不同的霓虹渐变
            const barColors = projects.map((_, i) => {
                const gradients = [
                    { from: '#22d3ee', to: '#0891b2' },
                    { from: '#a78bfa', to: '#7c3aed' },
                    { from: '#e879f9', to: '#c026d3' },
                    { from: '#34d399', to: '#059669' },
                    { from: '#fbbf24', to: '#d97706' },
                    { from: '#fb7185', to: '#e11d48' },
                    { from: '#2dd4bf', to: '#0d9488' },
                    { from: '#818cf8', to: '#4f46e5' },
                    { from: '#c084fc', to: '#9333ea' },
                    { from: '#60a5fa', to: '#2563eb' },
                ];
                return createBarGradient(ctx, gradients[i % gradients.length].from, gradients[i % gradients.length].to);
            });

            new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: projects.map(p => {
                        const name = p[0].split('/').pop() || p[0];
                        return name.length > 12 ? name.slice(0, 12) + '...' : name;
                    }),
                    datasets: [{
                        label: 'Total Tokens',
                        data: projects.map(p => p[1].input + p[1].output),
                        backgroundColor: barColors,
                        borderRadius: 8,
                        borderSkipped: false,
                        barThickness: 24,
                        maxBarThickness: 32,
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { display: false },
                        tooltip: {
                            backgroundColor: 'rgba(16, 18, 30, 0.9)',
                            titleColor: '#f8fafc',
                            bodyColor: '#94a3b8',
                            borderColor: 'rgba(99, 102, 241, 0.2)',
                            borderWidth: 1,
                            padding: 12,
                            cornerRadius: 8,
                            callbacks: {
                                label: function(context) {
                                    return `Tokens: ${formatNum(context.parsed.y)}`;
                                }
                            }
                        }
                    },
                    scales: {
                        x: {
                            ticks: {
                                color: '#64748b',
                                font: { size: 10, family: '-apple-system, BlinkMacSystemFont, sans-serif' },
                                maxRotation: 45,
                                minRotation: 0,
                            },
                            grid: {
                                display: false,
                                drawBorder: false,
                            }
                        },
                        y: {
                            ticks: {
                                color: '#64748b',
                                font: { size: 11, family: '-apple-system, BlinkMacSystemFont, sans-serif' },
                                callback: function(value) {
                                    return formatNum(value);
                                }
                            },
                            grid: {
                                color: 'rgba(99, 102, 241, 0.06)',
                                drawBorder: false,
                            },
                            border: { display: false }
                        }
                    },
                    animation: {
                        duration: 1500,
                        easing: 'easeOutQuart'
                    },
                    interaction: {
                        mode: 'index',
                        intersect: false,
                    },
                }
            });
        }

        // 创建柱状图渐变
        function createBarGradient(ctx, color1, color2) {
            const gradient = ctx.createLinearGradient(0, 280, 0, 0);
            gradient.addColorStop(0, color2 + '80');  // 底部深色带透明度
            gradient.addColorStop(0.5, color1 + 'CC'); // 中间色
            gradient.addColorStop(1, color1);          // 顶部亮色
            return gradient;
        }

        // 创建径向渐变（用于饼图）
        function createRadialGradient(ctx, color1, color2) {
            const gradient = ctx.createRadialGradient(150, 150, 0, 150, 150, 150);
            gradient.addColorStop(0, color1);
            gradient.addColorStop(1, color2);
            return gradient;
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

        :root {
            --bg-primary: #050508;
            --bg-secondary: #0a0a0f;
            --bg-tertiary: #0f0f16;
            --bg-card: rgba(16, 18, 30, 0.6);
            --glass-border: rgba(99, 102, 241, 0.1);
            --glass-border-hover: rgba(99, 102, 241, 0.3);
            --text-primary: #f8fafc;
            --text-secondary: #94a3b8;
            --text-muted: #64748b;
            --accent-cyan: #22d3ee;
            --accent-violet: #a78bfa;
            --accent-fuchsia: #e879f9;
            --accent-emerald: #34d399;
            --accent-amber: #fbbf24;
            --accent-rose: #fb7185;
            --glass-blur: blur(20px) saturate(150%);
            --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.4), 0 1px 3px rgba(0, 0, 0, 0.3);
            --shadow-glow: 0 0 40px rgba(34, 211, 238, 0.2), 0 0 80px rgba(168, 85, 247, 0.1);
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background:
                radial-gradient(ellipse 100% 60% at 50% 0%, rgba(34, 211, 238, 0.1) 0%, transparent 50%),
                radial-gradient(ellipse 80% 40% at 20% 10%, rgba(168, 85, 247, 0.08) 0%, transparent 40%),
                radial-gradient(ellipse 80% 40% at 80% 20%, rgba(232, 121, 249, 0.06) 0%, transparent 40%),
                linear-gradient(180deg, var(--bg-primary) 0%, var(--bg-secondary) 50%, var(--bg-tertiary) 100%);
            color: var(--text-primary);
            padding: 20px;
            min-height: 100vh;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 {
            text-align: center;
            background: linear-gradient(135deg, var(--accent-cyan), var(--accent-violet), var(--accent-fuchsia));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            margin-bottom: 10px;
            font-size: 26px;
            font-weight: 700;
        }
        .subtitle {
            text-align: center;
            color: var(--text-secondary);
            font-size: 14px;
            margin-bottom: 30px;
        }
        .back-btn {
            position: fixed;
            top: 20px;
            left: 20px;
            background: var(--bg-card);
            backdrop-filter: var(--glass-blur);
            -webkit-backdrop-filter: var(--glass-blur);
            color: var(--text-secondary);
            border: 1px solid var(--glass-border);
            padding: 10px 20px;
            border-radius: 10px;
            cursor: pointer;
            font-size: 14px;
            text-decoration: none;
            transition: all 0.2s ease;
            box-shadow: var(--shadow-sm);
        }
        .back-btn:hover {
            background: rgba(34, 211, 238, 0.1);
            border-color: var(--glass-border-hover);
            color: var(--accent-cyan);
            transform: translateY(-1px);
            box-shadow: var(--shadow-glow);
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: var(--bg-card);
            backdrop-filter: var(--glass-blur);
            -webkit-backdrop-filter: var(--glass-blur);
            border: 1px solid var(--glass-border);
            border-radius: 14px;
            padding: 18px 15px;
            text-align: center;
            transition: all 0.3s ease;
            box-shadow: var(--shadow-sm);
        }
        .stat-card:hover {
            transform: translateY(-3px);
            border-color: var(--glass-border-hover);
            box-shadow: var(--shadow-glow);
        }
        .stat-card h3 {
            color: var(--text-secondary);
            font-size: 10px;
            margin-bottom: 10px;
            text-transform: uppercase;
            letter-spacing: 1px;
            font-weight: 600;
        }
        .stat-card .value {
            font-family: 'SF Mono', monospace;
            font-size: 24px;
            font-weight: 600;
            background: linear-gradient(135deg, var(--accent-cyan), var(--accent-violet));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            filter: drop-shadow(0 0 8px rgba(34, 211, 238, 0.3));
        }
        .stat-card .sub {
            font-size: 10px;
            color: var(--text-muted);
            margin-top: 5px;
        }
        .chart-card {
            background: var(--bg-card);
            backdrop-filter: var(--glass-blur);
            -webkit-backdrop-filter: var(--glass-blur);
            border: 1px solid var(--glass-border);
            border-radius: 16px;
            padding: 24px;
            margin-bottom: 20px;
            transition: all 0.3s ease;
            box-shadow: var(--shadow-sm);
        }
        .chart-card:hover {
            border-color: var(--glass-border-hover);
            box-shadow: var(--shadow-glow);
        }
        .chart-card h3 {
            color: var(--text-primary);
            margin-bottom: 15px;
            font-size: 16px;
            font-weight: 600;
        }
        .chart-container {
            position: relative;
            height: 350px;
        }
        .savings-box {
            background: linear-gradient(135deg, rgba(52, 211, 153, 0.15), rgba(5, 150, 105, 0.08));
            backdrop-filter: var(--glass-blur);
            -webkit-backdrop-filter: var(--glass-blur);
            border: 1px solid rgba(52, 211, 153, 0.25);
            border-radius: 12px;
            padding: 20px;
            margin-bottom: 20px;
            display: flex;
            justify-content: space-around;
            flex-wrap: wrap;
            box-shadow: 0 0 30px rgba(52, 211, 153, 0.1);
        }
        .savings-item {
            text-align: center;
        }
        .savings-item .label {
            font-size: 12px;
            color: var(--text-secondary);
            margin-bottom: 8px;
        }
        .savings-item .value {
            font-family: 'SF Mono', monospace;
            font-size: 26px;
            font-weight: 600;
            background: linear-gradient(135deg, var(--accent-emerald), #6ee7b7);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            filter: drop-shadow(0 0 8px rgba(52, 211, 153, 0.3));
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
        tr:hover { background: rgba(34, 211, 238, 0.04); }
        .cache-info {
            color: #22d3ee;
            text-shadow: 0 0 10px rgba(34, 211, 238, 0.3);
        }
        .cache-create-highlight {
            color: #a78bfa;
            font-weight: bold;
            text-shadow: 0 0 10px rgba(167, 139, 250, 0.3);
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
            color: #fb7185;
            font-weight: bold;
            cursor: help;
            position: relative;
            text-shadow: 0 0 10px rgba(251, 113, 133, 0.3);
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
            background: linear-gradient(135deg, rgba(34, 211, 238, 0.2), rgba(8, 145, 178, 0.1));
            color: #22d3ee;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 11px;
            border: 1px solid rgba(34, 211, 238, 0.2);
            box-shadow: 0 0 10px rgba(34, 211, 238, 0.1);
        }
        .cache-note {
            background: rgba(16, 18, 30, 0.5);
            border: 1px solid rgba(99, 102, 241, 0.1);
            border-radius: 8px;
            margin-bottom: 20px;
            font-size: 13px;
            color: #64748b;
            overflow: hidden;
            backdrop-filter: blur(10px);
        }
        .cache-note-header {
            padding: 12px 15px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: rgba(16, 18, 30, 0.6);
            transition: all 0.2s ease;
        }
        .cache-note-header:hover {
            background: rgba(34, 211, 238, 0.05);
        }
        .cache-note-header h4 {
            color: #f8fafc;
            margin: 0;
            font-size: 14px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .cache-note-toggle {
            color: #64748b;
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
            background: linear-gradient(135deg, #34d399, #6ee7b7);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            font-weight: bold;
            filter: drop-shadow(0 0 8px rgba(52, 211, 153, 0.3));
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
                        borderColor: '#fb7185',
                        backgroundColor: 'rgba(251, 113, 133, 0.15)',
                        borderWidth: 2,
                        fill: true,
                        tension: 0.4,
                        pointBackgroundColor: '#fb7185',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        pointRadius: 4,
                        pointHoverRadius: 6,
                    }, {
                        label: '有缓存花费（实际）',
                        data: costComparison.map(c => c.with_cache),
                        borderColor: '#34d399',
                        backgroundColor: 'rgba(52, 211, 153, 0.15)',
                        borderWidth: 2,
                        fill: true,
                        tension: 0.4,
                        pointBackgroundColor: '#34d399',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        pointRadius: 4,
                        pointHoverRadius: 6,
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: { intersect: false, mode: 'index' },
                    plugins: {
                        legend: {
                            labels: {
                                color: '#94a3b8',
                                font: { size: 12, family: '-apple-system, BlinkMacSystemFont, sans-serif' },
                                usePointStyle: true,
                                pointStyle: 'circle',
                                pointRadius: 6,
                            }
                        },
                        tooltip: {
                            backgroundColor: 'rgba(16, 18, 30, 0.9)',
                            titleColor: '#f8fafc',
                            bodyColor: '#94a3b8',
                            borderColor: 'rgba(99, 102, 241, 0.2)',
                            borderWidth: 1,
                            padding: 12,
                            cornerRadius: 8,
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
                        x: {
                            ticks: { color: '#64748b', font: { size: 11 } },
                            grid: { color: 'rgba(99, 102, 241, 0.06)', drawBorder: false },
                            border: { display: false }
                        },
                        y: {
                            ticks: { color: '#64748b', callback: v => '$' + v.toFixed(4), font: { size: 11 } },
                            grid: { color: 'rgba(99, 102, 241, 0.06)', drawBorder: false },
                            border: { display: false }
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
            // 趋势图 - 霓虹渐变曲线
            const trendCtx = document.getElementById('trendChart').getContext('2d');

            // 创建渐变填充
            const inputGradient = trendCtx.createLinearGradient(0, 0, 0, 400);
            inputGradient.addColorStop(0, 'rgba(34, 211, 238, 0.25)');
            inputGradient.addColorStop(1, 'rgba(34, 211, 238, 0.02)');

            const outputGradient = trendCtx.createLinearGradient(0, 0, 0, 400);
            outputGradient.addColorStop(0, 'rgba(167, 139, 250, 0.25)');
            outputGradient.addColorStop(1, 'rgba(167, 139, 250, 0.02)');

            new Chart(trendCtx, {
                type: 'line',
                data: {
                    labels: stats.trend.map(t => t.date.slice(5)),
                    datasets: [{
                        label: 'Input',
                        data: stats.trend.map(t => t.input),
                        borderColor: '#22d3ee',
                        backgroundColor: inputGradient,
                        borderWidth: 2,
                        fill: true,
                        tension: 0.4,
                        pointBackgroundColor: '#22d3ee',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        pointRadius: 3,
                        pointHoverRadius: 5,
                    }, {
                        label: 'Output',
                        data: stats.trend.map(t => t.output),
                        borderColor: '#a78bfa',
                        backgroundColor: outputGradient,
                        borderWidth: 2,
                        fill: true,
                        tension: 0.4,
                        pointBackgroundColor: '#a78bfa',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        pointRadius: 3,
                        pointHoverRadius: 5,
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: { intersect: false, mode: 'index' },
                    plugins: {
                        legend: {
                            position: 'top',
                            align: 'end',
                            labels: {
                                color: '#94a3b8',
                                font: { size: 12, family: '-apple-system, BlinkMacSystemFont, sans-serif' },
                                usePointStyle: true,
                                pointStyle: 'circle',
                                pointRadius: 6,
                                boxWidth: 8,
                            }
                        },
                        tooltip: {
                            backgroundColor: 'rgba(16, 18, 30, 0.9)',
                            titleColor: '#f8fafc',
                            bodyColor: '#94a3b8',
                            borderColor: 'rgba(99, 102, 241, 0.2)',
                            borderWidth: 1,
                            padding: 12,
                            cornerRadius: 8,
                        }
                    },
                    scales: {
                        x: {
                            ticks: { color: '#64748b', font: { size: 11 } },
                            grid: { color: 'rgba(99, 102, 241, 0.06)', drawBorder: false },
                            border: { display: false }
                        },
                        y: {
                            ticks: {
                                color: '#64748b',
                                callback: v => formatNum(v),
                                font: { size: 11 }
                            },
                            grid: { color: 'rgba(99, 102, 241, 0.06)', drawBorder: false },
                            border: { display: false }
                        }
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
