# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-13

### Added
- Initial release of CC Token Monitor
- Real-time token usage monitoring for Claude Code
- Support for 30+ AI models with configurable pricing:
  - Anthropic: Claude Opus, Sonnet, Haiku
  - Moonshot: Kimi K2.5, Kimi for Coding
  - OpenAI: GPT-4o, GPT-4, GPT-3.5-turbo
  - DeepSeek: V3, R1, Chat, Coder
  - Google: Gemini 2.0 Flash, Gemini 2.0 Pro
  - Alibaba: Qwen Max, Plus, Turbo
  - Meta: Llama 3.3, Llama 3.1
  - Mistral: Mixtral 8x22b, 8x7b
  - And more...
- Multi-dimensional statistics:
  - By date
  - By model
  - By project
  - By session
- Web visualization interface with Chart.js
- CSV export functionality
- Customizable price configuration via JSON
- Shell aliases for quick access
- GitHub Actions for automated releases
- MIT License

### Features
- CLI tool for terminal usage
- Web dashboard for visual statistics
- Cron-friendly for scheduled updates
- Data persistence in CSV format
- Cost estimation in USD

[1.0.0]: https://github.com/yourusername/cc-token-monitor/releases/tag/v1.0.0
