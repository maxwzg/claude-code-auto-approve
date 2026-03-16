#!/usr/bin/env bash
# post-process-compound-bash.sh - PostToolUse Hook
#
# 在 Bash 命令执行后自动检查未授权的子命令并添加到允许列表
#
# 这是真正的自动化：用户批准命令后，自动学习并添加未授权的子命令
#
# 依赖：jq, awk, stat, date

set -uo pipefail

# ---------------------------------------------------------------------------
# 依赖检查
# ---------------------------------------------------------------------------

# 定义脚本依赖的外部命令
declare -r SCRIPT_DEPENDS=(jq awk stat date)

# 检查依赖是否满足，返回 0 表示全部满足，1 表示有缺失
check_dependencies() {
  local missing=()
  for dep in "${SCRIPT_DEPENDS[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      missing+=("$dep")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    # 输出警告到 stderr（用户可见）
    echo "" >&2
    echo "⚠️  [post-process-compound-bash.sh] 依赖检查失败" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "缺失以下命令：" >&2
    for cmd in "${missing[@]}"; do
      printf "   ✗ %s\n" "$cmd" >&2
    done
    echo "" >&2
    echo "请安装缺失的依赖后重试：" >&2
    echo "   # Ubuntu/Debian" >&2
    echo "   sudo apt install jq gawk coreutils  # coreutils 包含 stat, date" >&2
    echo "" >&2
    echo "   # macOS" >&2
    echo "   brew install jq gawk coreutils" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 加载共享配置
# ---------------------------------------------------------------------------

script_dir="$(dirname "${BASH_SOURCE[0]}")"

# 加载命令列表配置（DANGEROUS_COMMANDS 和 is_dangerous 函数）
source "$script_dir/command-lists.sh"

# 读取标准输入（Claude Code 传入的工具执行结果）
input=$(cat)

# 依赖检查：缺失时静默退出（不影响主流程）
if ! check_dependencies; then
  exit 0
fi

# 解析工具信息
tool_name=$(jq -r '.tool_name // empty' <<< "$input" 2>/dev/null || true)
tool_exit_code=$(jq -r '.tool_result.exit_code // 0' <<< "$input" 2>/dev/null || echo "0")

# 只处理 Bash 工具
[[ "$tool_name" != "Bash" ]] && exit 0

# 查找最近的待处理命令文件（60秒内创建的）
pending_file=""
latest_time=0
current_time=$(date +%s)

for file in /tmp/claude-pending-commands-*.txt; do
  [[ ! -f "$file" ]] && continue

  file_time=$(stat -c %Y "$file" 2>/dev/null || echo "0")
  file_age=$((current_time - file_time))

  # 只考虑60秒内的文件
  if [[ $file_age -lt 60 ]] && [[ $file_time -gt $latest_time ]]; then
    latest_time=$file_time
    pending_file="$file"
  fi
done

# 如果没有待处理的命令，直接退出
if [[ -z "$pending_file" ]]; then
  exit 0
fi

# 读取未授权命令
mapfile -t unapproved < "$pending_file"
rm -f "$pending_file"  # 清理临时文件

if [[ ${#unapproved[@]} -eq 0 ]]; then
  exit 0
fi

# 命令成功执行，说明用户批准了
# 现在自动添加这些命令到允许列表
{
  echo "" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "✨ 自动学习：检测到新批准的命令" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "以下命令已执行，正在自动添加到允许列表：" >&2
  echo "" >&2

  local dangerous_cmds=()
  local safe_cmds=()

  # 分类：安全命令 vs 危险命令
  for cmd in "${unapproved[@]}"; do
    if is_dangerous "$cmd"; then
      dangerous_cmds+=("$cmd")
    else
      safe_cmds+=("$cmd")
    fi
  done

  # 自动添加安全命令
  for cmd in "${safe_cmds[@]}"; do
    cmd_name=$(echo "$cmd" | awk '{print $1}')

    # 调用添加工具
    if bash "$script_dir/add-to-allowlist.sh" "$cmd_name" 2>&1 | grep -q "已添加"; then
      echo "  ✓ $cmd_name" >&2
    fi
  done

  # 提示危险命令需要手动添加
  if [[ ${#dangerous_cmds[@]} -gt 0 ]]; then
    echo "" >&2
    echo "  ⚠️  以下危险命令已跳过自动添加：" >&2
    for i in "${!dangerous_cmds[@]}"; do
      local dangerous_cmd="${dangerous_cmds[$i]}"
      local dangerous_name
      dangerous_name=$(echo "$dangerous_cmd" | awk '{print $1}')
      printf "    %d. %s\n" "$((i+1))" "$dangerous_name" >&2
    done
    echo "" >&2
    echo "  💡 如需允许这些命令，请手动编辑 settings.local.json：" >&2
    echo "     例如：\"Bash($dangerous_name:*)\" 或 \"Bash($dangerous_name 具体参数)\"" >&2
    echo "" >&2
    echo "  ⚠️  注意：添加 \"Bash(rm:*)\" 将允许所有 rm 命令（包括 rm -rf /）" >&2
    echo "     建议使用具体参数限制，如：\"Bash(rm *.tmp)\"" >&2
  fi

  echo "" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  if [[ ${#safe_cmds[@]} -gt 0 ]]; then
    echo "✅ 已添加 ${#safe_cmds[@]} 个安全命令到允许列表" >&2
  fi
  if [[ ${#dangerous_cmds[@]} -gt 0 ]]; then
    echo "⚠️  已跳过 ${#dangerous_cmds[@]} 个危险命令" >&2
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "" >&2
}

exit 0
