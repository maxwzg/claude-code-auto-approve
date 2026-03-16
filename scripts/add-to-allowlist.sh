#!/usr/bin/env bash
# add-to-allowlist - 将命令添加到 settings.local.json 的允许列表
#
# 用法：
#   add-to-allowlist "command1" "command2" ...
#
# 会自动将命令添加到 permissions.allow 列表中
#
# 依赖：jq, awk

set -uo pipefail

# ---------------------------------------------------------------------------
# 依赖检查
# ---------------------------------------------------------------------------

# 定义脚本依赖的外部命令
declare -r SCRIPT_DEPENDS=(jq awk)

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
    echo "⚠️  [add-to-allowlist.sh] 依赖检查失败" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "缺失以下命令：" >&2
    for cmd in "${missing[@]}"; do
      printf "   ✗ %s\n" "$cmd" >&2
    done
    echo "" >&2
    echo "请安装缺失的依赖后重试：" >&2
    echo "   # Ubuntu/Debian" >&2
    echo "   sudo apt install jq gawk" >&2
    echo "" >&2
    echo "   # macOS" >&2
    echo "   brew install jq gawk" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    return 1
  fi
  return 0
}

script_dir="$(dirname "${BASH_SOURCE[0]}")"
settings_file="$script_dir/../settings.local.json"

# 添加命令到允许列表
add_commands() {
  local -a commands=("$@")

  # 确保配置文件存在
  if [[ ! -f "$settings_file" ]]; then
    echo '{"permissions":{"allow":[],"deny":[],"ask":[]}}' > "$settings_file"
  fi

  # 先提取并标准化所有命令名称
  local -a cmd_names=()
  for cmd in "${commands[@]}"; do
    local cmd_name
    # 提取命令名和子命令（前两个词，适用于 git/add/subcommand 类命令）
    # 如果是 git/npm/pnpm 等带子命令的，保留前两个词
    local first_word
    first_word=$(echo "$cmd" | awk '{print $1}')

    case "$first_word" in
      git|npm|pnpm|yarn|docker|kubectl)
        # 带子命令的工具：保留前两个词
        cmd_name=$(echo "$cmd" | awk '{print $1, $2}')
        ;;
      *)
        # 普通命令：只保留第一个词
        cmd_name="$first_word"
        ;;
    esac

    cmd_names+=("$cmd_name")
  done

  # 去重
  local -a unique_cmd_names=()
  local -A seen=()
  for cmd_name in "${cmd_names[@]}"; do
    [[ -z "$cmd_name" ]] && continue
    [[ -v "seen[$cmd_name]" ]] && continue
    seen["$cmd_name"]=1
    unique_cmd_names+=("$cmd_name")
  done

  # 为每个唯一命令添加到允许列表
  for cmd_name in "${unique_cmd_names[@]}"; do
    # 检查是否已存在
    if jq -e --arg cmd "Bash($cmd_name:*)" '.permissions.allow | any(. == $cmd)' "$settings_file" >/dev/null 2>&1; then
      echo "✓ $cmd_name 已在允许列表中，跳过"
      continue
    fi

    # 添加到允许列表
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg cmd "Bash($cmd_name:*)" '.permissions.allow += [$cmd]' "$settings_file" > "$tmp_file" && mv "$tmp_file" "$settings_file"

    echo "✓ 已添加: $cmd_name"
  done

  echo ""
  echo "配置文件已更新: $settings_file"
}

main() {
  if [[ $# -eq 0 ]]; then
    echo "用法: add-to-allowlist <command1> [command2] ..."
    exit 1
  fi

  # 依赖检查：缺失时报错退出
  if ! check_dependencies; then
    exit 1
  fi

  add_commands "$@"
}

main "$@"
