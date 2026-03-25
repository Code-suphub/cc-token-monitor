"""
价格计算工具模块
"""
import json
import os

# 内置兜底价格（每百万 tokens）
MODEL_PRICES = {
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

DEFAULT_PRICE = {'input': 0.8, 'output': 0.8}
CACHE_DISCOUNT = 0.1  # 缓存命中按 10% 价格计费

_prices_json_cache = None


def _load_prices_json() -> dict | None:
    """读取 ~/.claude/token-stats/config/prices.json（优先于内置价格）"""
    global _prices_json_cache
    if _prices_json_cache is not None:
        return _prices_json_cache
    config_path = os.path.expanduser('~/.claude/token-stats/config/prices.json')
    if os.path.exists(config_path):
        try:
            with open(config_path) as f:
                _prices_json_cache = json.load(f)
                return _prices_json_cache
        except Exception:
            pass
    return None


def get_price(model: str) -> dict:
    """获取模型价格（每百万 tokens）。优先读取 prices.json，再回退内置列表"""
    model_lower = model.lower()

    config = _load_prices_json()
    if config:
        # 解析别名：先检查 aliases 字段
        aliases = config.get('aliases', {})
        if model_lower in aliases:
            model_lower = aliases[model_lower].lower()

        models = config.get('models', {})
        default = config.get('default', DEFAULT_PRICE)
        cache_read_mult = config.get('cache_discount', {}).get('read_multiplier', CACHE_DISCOUNT)

        # 精确匹配
        if model_lower in models:
            entry = models[model_lower]
            return {
                'input': entry.get('input', default.get('input', 0.8)),
                'output': entry.get('output', default.get('output', 0.8)),
                'cache_read_multiplier': cache_read_mult,
            }
        # 前缀匹配：模型名以某个 key 开头
        for key, entry in models.items():
            if model_lower.startswith(key):
                return {
                    'input': entry.get('input', default.get('input', 0.8)),
                    'output': entry.get('output', default.get('output', 0.8)),
                    'cache_read_multiplier': cache_read_mult,
                }
        # 子串匹配（兜底）
        for key, entry in models.items():
            if key in model_lower:
                return {
                    'input': entry.get('input', default.get('input', 0.8)),
                    'output': entry.get('output', default.get('output', 0.8)),
                    'cache_read_multiplier': cache_read_mult,
                }
        # 未命中，使用 JSON 中的 default
        return {'input': default.get('input', 0.8), 'output': default.get('output', 0.8),
                'cache_read_multiplier': cache_read_mult}

    # prices.json 不存在，回退内置列表
    for key, price in MODEL_PRICES.items():
        if key in model_lower:
            return price
    return DEFAULT_PRICE


def calculate_cost(input_tokens: int, output_tokens: int, model: str) -> float:
    """计算单次调用的费用"""
    price = get_price(model)
    return (input_tokens * price['input'] + output_tokens * price['output']) / 1000000


def calculate_cost_with_cache(turns: list) -> list:
    """
    计算有缓存和无缓存的花费对比

    Args:
        turns: 包含 input, output, cache_read, model 的轮次列表

    Returns:
        每轮的累计花费对比数据
    """
    results = []
    cumulative_no_cache = 0
    cumulative_with_cache = 0

    for turn in turns:
        price = get_price(turn['model'])

        # 无缓存场景：假设所有 tokens 都没有缓存优惠
        effective_input_no_cache = turn['input'] + turn['cache_read']
        no_cache_cost = (
            effective_input_no_cache * price['input'] +
            turn['output'] * price['output']
        ) / 1000000

        # 有缓存场景（实际）
        cache_discount = price.get('cache_read_multiplier', CACHE_DISCOUNT)
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
            'saved_percent': round(
                (cumulative_no_cache - cumulative_with_cache) / cumulative_no_cache * 100, 2
            ) if cumulative_no_cache > 0 else 0
        })

    return results


def estimate_cost(input_tokens: int, output_tokens: int, price_per_m: float = 0.8) -> float:
    """使用默认价格估算费用"""
    return round((input_tokens * price_per_m + output_tokens * price_per_m) / 1000000, 4)
