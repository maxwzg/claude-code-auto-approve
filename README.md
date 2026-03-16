# Claude Code Auto Approve Plugin

**自动批准 Bash 复合命令的 Claude Code Plugin**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](https://github.com/maxwzg/claude-code-auto-approve/releases)
[![CHANGELOG](https://img.shields.io/badge/changelog-📝-orange.svg)](CHANGELOG.md)
[![Based on](https://img.shields.io/badge/based_on-oryband--claude--code--auto--approve-informational.svg)](https://github.com/oryband/claude-code-auto-approve)

> 💡 本项目基于 [oryband/claude-code-auto-approve](https://github.com/oryband/claude-code-auto-approve) 进行改进和扩展，感谢原作者的杰出工作。

## 核心功能

### 🎯 解决的问题

Claude Code 的原生权限系统将 `Bash(cmd *)` 权限与**完整命令字符串**进行匹配。这意味着：

```bash
# 即使你已允许 Bash(ls *) 和 Bash(grep *)
ls | grep foo        # ❌ 仍然会提示你批准

# 即使你已允许 Bash(git status) 和 Bash(head)
git log | head -n 10  # ❌ 仍然会提示你批准

# 即使你已允许 Bash(npm install) 和 Bash(npm test)
npm install && npm test  # ❌ 仍然会提示你批准
```

### ✅ 我们的解决方案

这个 Plugin 会**解析复合命令**并**检查每个子命令**：

```bash
ls | grep foo        # ✅ 自动批准（两个子命令都已允许）

git log | head -n 10  # ✅ 自动批准（两个子命令都已允许）

npm install && npm test  # ✅ 自动批准（两个子命令都已允许）

cat file.txt | grep pattern | sort | uniq  # ✅ 自动批准（4个子命令都已允许）
```

### 🔍 支持的复合命令类型

- **管道命令**: `cmd1 | cmd2 | cmd3`
- **链式命令**: `cmd1 && cmd2 || cmd3`
- **顺序命令**: `cmd1; cmd2; cmd3`
- **子shell**: `(cd /tmp && ls)`
- **命令替换**: `$(date)` 和 `` `date` ``
- **进程替换**: `diff <(sort a) <(sort b)`
- **条件语句**: `if ...; then ...; fi`
- **循环语句**: `for i in ...; do ...; done`
- **bash -c**: `bash -c 'echo hello'`

### 🤖 自动学习新命令

执行新命令后，Plugin 会自动将其添加到允许列表：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✨ 自动学习：检测到新批准的命令
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
以下命令已执行，正在自动添加到允许列表：

  ✓ npm
  ✓ git status

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 已添加 2 个安全命令到允许列表
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 🔒 安全保护

- **危险命令拒绝**: 自动拒绝包含 `rm`、`sudo`、`dd` 等危险操作的复合命令
- **安全命令分类**: 智能区分安全命令和危险命令
- **失败回退**: 无法解析的命令回退到 Claude Code 原生提示

## 快速开始

### 第一步：安装依赖

#### Linux (Ubuntu/Debian)

```bash
sudo apt install jq shfmt gawk coreutils
```

#### Linux (Fedora/RHEL)

```bash
sudo dnf install jq shfmt gawk coreutils
```

#### macOS

```bash
brew install jq shfmt
```

#### Windows

需要 **Git Bash** 或 **WSL** 环境（推荐 WSL2）：

**使用 WSL2（推荐）**：
```bash
# 在 WSL 中安装
sudo apt install jq shfmt gawk coreutils
```

**使用 Git Bash**：

1. 安装 [Scoop](https://scoop.sh) 或 [Chocolatey](https://chocolatey.org)

**Scoop**：
```powershell
scoop bucket add extras
scoop install jq shfmt
```

**Chocolatey**：
```powershell
choco install jq shfmt
```

**手动下载**：
- jq: https://stedolan.github.io/jq/download/
- shfmt: `go install mvdan.cc/sh/v3/cmd/shfmt@latest` 或下载二进制文件

**验证安装**：
```bash
# 在 Git Bash 或 WSL 中
which jq shfmt
jq --version
shfmt --version
```

**Windows 注意事项**：

- ⚠️ **路径问题**：Git Bash 和 WSL 使用 Unix 风格路径（`/c/Users/...`），Plugin 会自动处理
- ⚠️ **权限问题**：可能需要以管理员身份运行 Git Bash 或 WSL
- ⚠️ **性能考虑**：Git Bash 性能可能不如 WSL，推荐使用 WSL2
- ✅ **最佳实践**：在 WSL2 中使用 Claude Code 和 Plugin 以获得最佳体验

### 第二步：安装插件

```bash
# 从 GitHub 安装（推荐）
claude plugin install https://github.com/maxwzg/claude-code-auto-approve --scope user

# 或本地安装
cd /path/to/claude-code-auto-approve
claude plugin install . --scope user
```

### 第三步：体验自动批准

安装后，尝试这些复合命令：

```bash
# 管道命令
ls -la | grep pattern | sort

# 链式命令
cd /tmp && ls && pwd

# 命令替换
echo "Current dir: $(pwd)"

# 复合条件
[ -f file.txt ] && cat file.txt || echo "File not found"
```

**所有命令都会自动批准**，无需每次手动确认！

## 工作原理

### 核心机制

#### 1. 命令分类

**简单命令**（不包含 shell 元字符）：
```bash
ls -la              # 快速路径，直接检查
cat file.txt        # 快速路径，直接检查
```

**复合命令**（包含 shell 元字符）：
```bash
ls | grep foo       # 解析路径，提取子命令
cd /tmp && ls       # 解析路径，提取子命令
```

#### 2. 解析流程

```
复合命令输入
    ↓
shfmt 解析为 JSON AST
    ↓
jq 提取所有子命令
    ↓
┌─────────────┐
│ 逐个检查权限  │
└─────────────┘
    ↓
┌──────────┬──────────┬──────────┐
│ 全部允许  │ 包含拒绝  │ 未知/失败  │
└──────────┴──────────┴──────────┘
    ↓           ↓           ↓
 自动批准    主动拒绝    回退提示
```

#### 3. 安全保证

- ✅ **完全分析**: 只批准能完全解析和理解的命令
- ✅ **失败回退**: 任何不确定的情况都回退到原生提示
- ✅ **危险拒绝**: 主动拒绝包含危险子命令的复合命令
- ✅ **透明可审计**: 使用 bash + shfmt + jq，所有逻辑可见

### 技术实现

采用 **bash + shfmt + jq** 技术栈：

- **shfmt**: 将 bash 命令解析为 JSON AST
- **jq**: 从 AST 中提取所有子命令
- **bash**: 协调整个流程和权限检查

选择这个技术栈的原因：
- **透明性**: 所有逻辑都在源代码中，可审查
- **可维护性**: 使用标准工具，避免黑盒二进制
- **性能**: 简单命令走快速路径，复合命令才解析
- **兼容性**: 支持 bash 4.3+，跨平台工作

## 配置说明

### 权限配置

插件读取以下配置文件（按优先级）：

1. `~/.claude/settings.json` - 用户全局配置
2. `~/.claude/settings.local.json` - 用户本地配置
3. `.claude/settings.json` - 项目配置
4. `.claude/settings.local.json` - 项目本地配置

### 配置示例

```json
{
  "permissions": {
    "allow": [
      "Bash(ls)",
      "Bash(cat)",
      "Bash(grep *)",
      "Bash(git status)",
      "Bash(git commit *)",
      "Bash(npm install)"
    ],
    "deny": [
      "Bash(rm *)",
      "Bash(sudo *)",
      "Bash(dd *)"
    ]
  }
}
```

### 权限格式

- `Bash(cmd)` - 精确匹配
- `Bash(cmd *)` - 匹配任意参数
- `Bash(cmd:*)` - 匹配子命令

## 内置命令分类

### 🟢 安全命令（自动批准）

文件系统导航、查看、文本处理等基础命令会自动批准：

```bash
ls, cd, pwd, cat, head, tail, grep, sort, uniq, cut, tr
find, xargs, tee, basename, dirname
date, whoami, id, uname, hostname
```

### 🔴 危险命令（不会自动学习）

以下命令需要手动添加到允许列表：

```bash
# 系统控制
rm, sudo, dd, mkfs, fdisk, shutdown, reboot

# 权限修改
chmod, chown, chgrp

# 进程管理
kill, pkill, killall

# 服务管理
systemctl, service

# 网络工具
curl, wget, ssh, scp
```

## 调试和故障排除

### 启用调试模式

```bash
# 临时启用
DEBUG=1 claude

# 或在配置中启用
{
  "debug": true
}
```

### 常见问题

**Q: 为什么有些复合命令还是提示我？**

A: 检查以下几点：
1. 所有子命令是否都在允许列表中
2. 是否包含危险命令
3. 启用调试模式查看详细日志

**Q: 如何允许危险命令？**

A: 手动编辑配置文件，添加具体权限：

```json
{
  "permissions": {
    "allow": [
      "Bash(rm *.tmp)",           // 只允许删除 .tmp 文件
      "Bash(sudo apt install)"    // 只允许安装包
    ]
  }
}
```

**Q: 插件会批准它不能理解的命令吗？**

A: 不会。任何无法完全解析或分析的命令都会回退到 Claude Code 的原生提示。

## 项目结构

```
claude-code-auto-approve/
├── .claude-plugin/
│   ├── plugin.json              # Plugin 清单和 Hook 配置
│   └── marketplace.json         # Marketplace 发布配置
├── scripts/
│   ├── approve-compound-bash.sh         # PreToolUse Hook - 命令前检查
│   ├── post-process-compound-bash.sh    # PostToolUse Hook - 命令后学习
│   ├── add-to-allowlist.sh              # 辅助工具 - 添加命令
│   └── command-lists.sh                 # 安全/危险命令列表
├── commands/
│   └── allowlist.md             # /allowlist 命令文档
└── README.md
```

## 版本管理

遵循语义版本控制：

- **MAJOR**：破坏性更改
- **MINOR**：新功能（向后兼容）
- **PATCH**：错误修复（向后兼容）

📝 **查看详细的版本更新记录：** [CHANGELOG.md](CHANGELOG.md)

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 作者

**Wu Zhi Gang**

## 致谢

### 原项目

本项目的核心功能基于 [oryband/claude-code-auto-approve](https://github.com/oryband/claude-code-auto-approve)（MIT 许可证），感谢原作者 **oryband** 的杰出工作。

原项目提供了优秀的复合命令解析方案，使用 bash + shfmt + jq 的组合实现了：
- 智能的命令解析和子命令提取
- 允许列表和拒绝列表支持
- 透明且可审计的实现

### 我们的改进

在原项目基础上，我们添加了以下特性：

1. **Plugin 架构**：封装为标准的 Claude Code Plugin
2. **自动学习系统**：PostToolUse Hook 实现命令自动学习
3. **安全分类**：危险命令检测和安全命令自动添加
4. **完整文档**：用户友好的文档和快速入门指南
5. **依赖管理**：自动检测和优雅降级
6. **Marketplace 支持**：便于分发和更新的配置

### 设计理念

我们保留了原项目的核心设计理念：
- ✅ **透明性**：使用 bash 脚本和标准工具，避免不透明的二进制文件
- ✅ **可审计性**：所有逻辑都在源代码中，便于审查和修改
- ✅ **安全性**：失败时回退到原生提示，从不批准无法完全分析的命令
- ✅ **性能**：简单命令走快速路径，避免不必要的解析开销

### 相关链接

- [原项目](https://github.com/oryband/claude-code-auto-approve) - 核心解析逻辑
- [Claude Code 文档](https://code.claude.com/docs)
- [Plugin 文档](https://code.claude.com/docs/zh-CN/plugins-reference)
