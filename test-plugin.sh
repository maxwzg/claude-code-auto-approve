#!/usr/bin/env bash
# test-plugin.sh - 测试 Plugin 是否正确配置

set -e

echo "=========================================="
echo "Claude Code Auto Approve Plugin 测试"
echo "=========================================="
echo ""

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Plugin 根目录: $PLUGIN_ROOT"
echo ""

# 1. 检查文件结构
echo "1. 检查文件结构..."
required_files=(
    ".claude-plugin/plugin.json"
    "hooks/approve-compound-bash.sh"
    "hooks/post-process-compound-bash.sh"
    "hooks/add-to-allowlist.sh"
    "hooks/command-lists.sh"
)

for file in "${required_files[@]}"; do
    if [[ -f "$PLUGIN_ROOT/$file" ]]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file (缺失)"
        exit 1
    fi
done
echo ""

# 2. 验证 plugin.json 语法
echo "2. 验证 plugin.json 语法..."
if command -v jq &>/dev/null; then
    if jq empty "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null; then
        echo "  ✓ plugin.json 语法正确"
    else
        echo "  ✗ plugin.json 语法错误"
        exit 1
    fi
else
    echo "  ⚠ jq 未安装，跳过 JSON 验证"
fi
echo ""

# 3. 检查脚本权限
echo "3. 检查脚本权限..."
scripts=(
    "hooks/approve-compound-bash.sh"
    "hooks/post-process-compound-bash.sh"
    "hooks/add-to-allowlist.sh"
)

for script in "${scripts[@]}"; do
    if [[ -x "$PLUGIN_ROOT/$script" ]]; then
        echo "  ✓ $script (可执行)"
    else
        echo "  ⚠ $script (不可执行)"
        echo "    运行: chmod +x $script"
    fi
done
echo ""

# 4. 检查依赖
echo "4. 检查系统依赖..."
dependencies=(jq shfmt awk stat date)
missing_deps=()

for dep in "${dependencies[@]}"; do
    if command -v "$dep" &>/dev/null; then
        echo "  ✓ $dep"
    else
        echo "  ✗ $dep (缺失)"
        missing_deps+=("$dep")
    fi
done
echo ""

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo "⚠️  缺失依赖，插件可能无法正常工作"
    echo ""
    echo "安装方法："
    echo "  Ubuntu/Debian:"
    echo "    sudo apt install jq shfmt gawk coreutils"
    echo ""
    echo "  macOS:"
    echo "    brew install jq shfmt"
    echo ""
fi

# 5. 测试 Hook 脚本语法
echo "5. 测试 Hook 脚本语法..."
if bash -n "$PLUGIN_ROOT/hooks/approve-compound-bash.sh" 2>/dev/null; then
    echo "  ✓ approve-compound-bash.sh 语法正确"
else
    echo "  ✗ approve-compound-bash.sh 语法错误"
    exit 1
fi

if bash -n "$PLUGIN_ROOT/hooks/post-process-compound-bash.sh" 2>/dev/null; then
    echo "  ✓ post-process-compound-bash.sh 语法正确"
else
    echo "  ✗ post-process-compound-bash.sh 语法错误"
    exit 1
fi

if bash -n "$PLUGIN_ROOT/hooks/add-to-allowlist.sh" 2>/dev/null; then
    echo "  ✓ add-to-allowlist.sh 语法正确"
else
    echo "  ✗ add-to-allowlist.sh 语法错误"
    exit 1
fi
echo ""

# 6. 测试命令解析功能
echo "6. 测试命令解析功能..."
test_commands=(
    "ls -la"
    "cat file.txt | grep test"
    "cd /tmp && ls && pwd"
)

for cmd in "${test_commands[@]}"; do
    echo "  测试: $cmd"
    if echo "$cmd" | bash "$PLUGIN_ROOT/hooks/approve-compound-bash.sh" parse &>/dev/null; then
        echo "    ✓ 解析成功"
    else
        echo "    ✗ 解析失败"
    fi
done
echo ""

# 总结
echo "=========================================="
echo "测试完成！"
echo "=========================================="
echo ""

if [[ ${#missing_deps[@]} -eq 0 ]]; then
    echo "✓ 所有检查通过，插件已准备就绪！"
    echo ""
    echo "开始使用："
    echo "  cd $PLUGIN_ROOT"
    echo "  claude --plugin-dir ."
else
    echo "⚠️  请先安装缺失的依赖"
fi
