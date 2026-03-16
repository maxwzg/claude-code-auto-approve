# CLAUDE.md

此文件为 Claude Code (claude.ai/code) 在此代码库中工作时提供指导。

## 项目概述

这是 `claude-code-auto-approve` - 一个 Claude Code Plugin，用于智能 Bash 命令自动批准。

## Plugin 功能

- **PreToolUse Hook**: 自动批准复合 Bash 命令（管道、链式、子shell 等）
- **PostToolUse Hook**: 自动学习用户批准的新命令并添加到允许列表
- **安全检查**: 区分安全命令和危险命令，保护系统安全
- **依赖检查**: 自动检测所需依赖（jq, shfmt 等），缺失时优雅降级

## 项目结构

```
claude-code-auto-approve/
├── .claude-plugin/              # Plugin 元数据
│   ├── plugin.json              # Plugin 清单和 Hook 配置
│   └── marketplace.json         # Marketplace 发布配置
│
├── scripts/                      # 可执行脚本
│   ├── approve-compound-bash.sh         # PreToolUse Hook
│   ├── post-process-compound-bash.sh    # PostToolUse Hook
│   ├── add-to-allowlist.sh              # 辅助工具
│   └── command-lists.sh                 # 共享配置
│
├── commands/                     # Claude Code 命令文档
│   └── allowlist.md             # /allowlist 命令
│
├── .claude/                      # 示例配置
│   └── settings.example.json
│
├── 文档/
│   ├── README.md                # 用户文档
│   ├── QUICKSTART.md            # 快速入门
│   ├── DEVELOPMENT.md           # 开发指南
│   ├── STRUCTURE.md             # 架构说明
│   └── CHANGELOG.md             # 变更日志
│
├── test-plugin.sh               # 测试脚本
└── LICENSE                      # MIT 许可证
```

## 开发和测试

### 本地测试 Plugin

```bash
# 方法 1: 使用 --plugin-dir
claude --plugin-dir .

# 方法 2: 调试模式
claude --debug --plugin-dir .

# 方法 3: 运行测试脚本
bash test-plugin.sh
```

### 安装 Plugin

```bash
# 用户级别（推荐）
claude plugin install . --scope user

# 项目级别
claude plugin install . --scope project

# 本地级别
claude plugin install . --scope local
```

## 核心脚本说明

### approve-compound-bash.sh (PreToolUse Hook)

**功能**: 在 Bash 命令执行前自动批准

**依赖**: jq, shfmt

**工作流程**:
1. 解析复合命令为单个子命令
2. 检查每个子命令是否在允许列表
3. 全部允许 → 自动批准
4. 包含拒绝 → 主动拒绝
5. 部分未知 → 回退到原生提示

### post-process-compound-bash.sh (PostToolUse Hook)

**功能**: 在 Bash 命令执行后自动学习

**依赖**: jq, awk, stat, date

**工作流程**:
1. 检测用户批准的新命令
2. 分类为安全命令和危险命令
3. 自动添加安全命令到允许列表
4. 提示手动添加危险命令

### command-lists.sh

**功能**: 共享配置文件

**内容**:
- `DANGEROUS_COMMANDS` - 危险命令列表（不会自动学习）
- `BUILTIN_SAFE_COMMANDS` - 内置安全命令列表
- `is_dangerous()` - 危险命令检查函数
- `is_builtin_safe()` - 安全命令检查函数

## 环境变量

- `${CLAUDE_PLUGIN_ROOT}` - Plugin 安装目录的绝对路径
- `${CLAUDE_PROJECT_DIR}` - 当前项目目录的绝对路径
- `DEBUG` - 启用调试输出（可选）

## 配置文件

Plugin 读取权限配置的顺序：

1. `~/.claude/settings.json` (用户级)
2. `~/.claude/settings.local.json` (用户本地)
3. `.claude/settings.json` (项目级)
4. `.claude/settings.local.json` (项目本地)

权限格式：
```json
{
  "permissions": {
    "allow": [
      "Bash(git status)",
      "Bash(npm install)"
    ],
    "deny": [
      "Bash(rm *)",
      "Bash(sudo *)"
    ]
  }
}
```

## 依赖管理

Plugin 需要以下系统工具：

**必需**:
- `bash` 4.3+
- `jq` - JSON 处理
- `shfmt` - Shell 解析

**标准工具**:
- `awk`, `stat`, `date`

**安装依赖**:
```bash
# Ubuntu/Debian
sudo apt install jq shfmt gawk coreutils

# macOS
brew install jq shfmt
```

## 调试

### 启用调试模式

```bash
# 方法 1: 环境变量
DEBUG=1 claude --plugin-dir .

# 方法 2: Claude Code 调试
claude --debug --plugin-dir .
```

### 查看详细信息

调试模式会显示：
- Plugin 加载详情
- Hook 注册信息
- 脚本执行日志
- 依赖检查结果

## 版本管理

遵循语义版本控制：

- **MAJOR**: 破坏性更改
- **MINOR**: 新功能（向后兼容）
- **PATCH**: 错误修复（向后兼容）

## 发布

### 更新版本

1. 更新 `.claude-plugin/plugin.json` 中的 `version`
2. 更新 `CHANGELOG.md`
3. 创建 git tag
4. 发布到 Marketplace

### 测试清单

- [ ] 运行 `bash test-plugin.sh`
- [ ] 本地测试所有功能
- [ ] 验证文档完整性
- [ ] 检查依赖兼容性

## 相关资源

- [Claude Code Plugin 文档](https://code.claude.com/docs/zh-CN/plugins-reference)
- [Hooks 文档](https://code.claude.com/docs/zh-CN/hooks)
- [Plugin 开发最佳实践](https://code.claude.com/docs/zh-CN/plugin-development)

## 当前状态

- **版本**: 1.0.0
- **状态**: ✅ 完成并验证
- **最后更新**: 2026-03-16
