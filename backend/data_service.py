"""
数据服务模块 - 负责加载和统计 Token 数据
"""
import os
import json
from datetime import datetime
from collections import defaultdict
from config import STATS_DIR, PROJECTS_DIR
from utils.pricing import estimate_cost


def load_daily_data(target_date=None):
    """加载每日统计数据"""
    daily_dir = os.path.join(STATS_DIR, "daily")

    by_date = defaultdict(lambda: {
        'input': 0, 'output': 0, 'cache_create': 0, 'cache_read': 0,
        'sessions': {},
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
        _parse_daily_file(filepath, by_date[date])

    return by_date


def _parse_daily_file(filepath, data):
    """解析单个日期的 CSV 文件"""
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
            except (ValueError, IndexError):
                continue

            # 更新统计数据
            data['input'] += input_tok
            data['output'] += output_tok
            data['cache_create'] += cache_create
            data['cache_read'] += cache_read

            # 聚合会话数据
            _update_session(data['sessions'], session_id, project, model,
                          input_tok, output_tok, cache_create, cache_read)

            # 聚合模型数据
            data['models'][model]['input'] += input_tok
            data['models'][model]['output'] += output_tok

            # 聚合项目数据
            data['projects'][project]['input'] += input_tok
            data['projects'][project]['output'] += output_tok
            data['projects'][project]['sessions'].add(session_id)


def _update_session(sessions, session_id, project, model,
                   input_tok, output_tok, cache_create, cache_read):
    """更新会话数据"""
    if session_id not in sessions:
        sessions[session_id] = {
            'project': project,
            'model': model,
            'input': 0, 'output': 0,
            'cache_create': 0, 'cache_read': 0
        }
    sessions[session_id]['input'] += input_tok
    sessions[session_id]['output'] += output_tok
    sessions[session_id]['cache_create'] += cache_create
    sessions[session_id]['cache_read'] += cache_read


def load_session_detail(session_id: str) -> dict:
    """加载会话详细数据（从原始 jsonl 文件）"""
    session_file = _find_session_file(session_id)
    if not session_file:
        return None

    return _parse_session_file(session_file)


def _find_session_file(session_id: str) -> str:
    """查找会话文件路径"""
    for root, dirs, files in os.walk(PROJECTS_DIR):
        for f in files:
            if f == f"{session_id}.jsonl":
                return os.path.join(root, f)
    return None


def _parse_session_file(filepath: str) -> dict:
    """解析会话 JSONL 文件"""
    resp_groups = defaultdict(list)

    try:
        with open(filepath, 'r') as f:
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
                except json.JSONDecodeError:
                    continue
    except (IOError, OSError):
        pass

    return _merge_response_records(resp_groups)


def _merge_response_records(resp_groups: dict) -> dict:
    """合并同一响应的多条 streaming 记录"""
    turns = []
    total_input = total_output = total_cache_create = total_cache_read = 0

    for resp_id, records in resp_groups.items():
        if not records:
            continue

        records = sorted(records, key=lambda r: r.get('timestamp', ''))
        first, last = records[0], records[-1]

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

        msg_type, msg_status = _analyze_message_type(records, msg)

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
            'stop_reason': msg.get('stop_reason')
        })

    # 重新计算累计值
    _recalculate_cumulative(turns)

    return {
        'session_id': list(resp_groups.keys())[0] if resp_groups else 'unknown',
        'total_turns': len(turns),
        'total_input': total_input,
        'total_output': total_output,
        'total_cache_create': total_cache_create,
        'total_cache_read': total_cache_read,
        'turns': turns
    }


def _analyze_message_type(records: list, last_msg: dict) -> tuple:
    """分析消息类型和状态"""
    seen_types = set()
    for r in records:
        for c in r.get('message', {}).get('content', []):
            ctype = c.get('type')
            if ctype:
                seen_types.add(ctype)

    msg_type = []
    msg_status = 'complete'

    has_thinking = 'thinking' in seen_types
    has_tool_use = 'tool_use' in seen_types
    has_text = 'text' in seen_types
    stop_reason = last_msg.get('stop_reason')

    # 计算 text 长度
    text_length = sum(
        len(c.get('text', ''))
        for c in last_msg.get('content', [])
        if c.get('type') == 'text'
    )

    output_tokens = last_msg.get('usage', {}).get('output_tokens', 0)
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

    return msg_type, msg_status


def _recalculate_cumulative(turns: list):
    """重新计算累计值"""
    turns.sort(key=lambda t: t['timestamp'])
    for i, turn in enumerate(turns, 1):
        turn['turn'] = i
        turn['cumulative_input'] = sum(t['input'] for t in turns[:i])
        turn['cumulative_output'] = sum(t['output'] for t in turns[:i])
        turn['cumulative_total'] = turn['cumulative_input'] + turn['cumulative_output']


def get_summary_stats() -> dict:
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
    trend = [
        {
            'date': date,
            'input': data[date]['input'],
            'output': data[date]['output'],
            'total': data[date]['input'] + data[date]['output'],
            'sessions': len(data[date]['sessions'])
        }
        for date in sorted_dates
    ]

    return {
        'total_input': total_input,
        'total_output': total_output,
        'total_cache_create': total_cache_create,
        'total_cache_read': total_cache_read,
        'total_tokens': total_input + total_output,
        'total_sessions': len(all_sessions),
        'total_days': len(data),
        'estimated_cost': estimate_cost(total_input, total_output),
        'models': dict(all_models),
        'projects': dict(all_projects),
        'trend': trend[-30:]
    }


def get_date_stats(date_str: str) -> dict:
    """获取指定日期的统计"""
    data = load_daily_data(date_str)
    if date_str not in data:
        return None

    d = data[date_str]

    sessions_list = [
        {
            'session_id': sid,
            'project': sdata['project'],
            'model': sdata['model'],
            'input': sdata['input'],
            'output': sdata['output'],
            'cache_create': sdata['cache_create'],
            'cache_read': sdata['cache_read'],
            'total': sdata['input'] + sdata['output']
        }
        for sid, sdata in d['sessions'].items()
    ]
    sessions_list.sort(key=lambda x: x['total'], reverse=True)

    return {
        'date': date_str,
        'total_input': d['input'],
        'total_output': d['output'],
        'total_cache_create': d['cache_create'],
        'total_cache_read': d['cache_read'],
        'total_tokens': d['input'] + d['output'],
        'total_sessions': len(d['sessions']),
        'estimated_cost': estimate_cost(d['input'], d['output']),
        'models': dict(d['models']),
        'sessions': sessions_list
    }


def get_available_dates() -> list:
    """获取所有可用日期列表"""
    daily_dir = os.path.join(STATS_DIR, "daily")
    if not os.path.exists(daily_dir):
        return []

    dates = [
        f.replace('.csv', '')
        for f in os.listdir(daily_dir)
        if f.endswith('.csv')
    ]
    dates.sort(reverse=True)
    return dates
