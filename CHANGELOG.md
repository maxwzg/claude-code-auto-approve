# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-16

### Added
- 初始版本发布
- PreToolUse hook 支持复合 Bash 命令自动批准
- PostToolUse hook 支持自动学习批准的命令
- 内置安全命令列表
- 危险命令检测和拒绝
- 自动添加安全命令到允许列表
- 完整的依赖检查和错误处理
- 调试模式支持
- 跨平台支持（Linux, macOS, Windows Git Bash）

### Security
- 默认拒绝所有危险命令
- 自动检测并拒绝包含危险子命令的复合命令
- 区分安全命令和危险命令的自动学习策略

[1.0.0]: https://github.com/maxwzg/claude-code-auto-approve/releases/tag/v1.0.0
