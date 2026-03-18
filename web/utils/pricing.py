"""
价格计算工具模块
"""

# 模型价格配置（每百万 tokens）
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


def get_price(model: str) -> dict:
    """获取模型价格（每百万 tokens）"""
    model_lower = model.lower()
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
        with_cache_cost = (
            turn['input'] * price['input'] +
            turn['cache_read'] * price['input'] * CACHE_DISCOUNT +
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
