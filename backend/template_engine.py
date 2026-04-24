"""
简易模板引擎模块
"""
import os
from config import TEMPLATE_DIR


def load_template(name: str) -> str:
    """加载模板文件"""
    template_path = os.path.join(TEMPLATE_DIR, name)
    try:
        with open(template_path, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return f"<!-- Template not found: {name} -->"


def render_template(name: str, **kwargs) -> str:
    """渲染模板，替换 {{VAR}} 变量"""
    template = load_template(name)
    for key, value in kwargs.items():
        placeholder = '{{' + key + '}}'
        template = template.replace(placeholder, str(value))
    return template
