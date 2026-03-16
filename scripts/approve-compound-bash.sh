#!/usr/bin/env bash
# shellcheck shell=bash
# approve-compound-bash — Claude Code 的 PreToolUse hook
#
# 当复合 Bash 命令（管道、链式、子shell 等）的每个子命令都匹配允许列表
# 且不匹配拒绝列表时，自动批准该命令。主动拒绝包含拒绝段的复合命令。
# 对于未知命令，回退到 Claude Code 的原生提示。
#
# 详细文档请参阅 README.md。
#
# 依赖：bash 4.3+, shfmt, jq

set -uo pipefail

# ---------------------------------------------------------------------------
# 依赖检查
# ---------------------------------------------------------------------------

# 定义脚本依赖的外部命令
declare -r SCRIPT_DEPENDS=(jq shfmt)

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
    echo "⚠️  [approve-compound-bash.sh] 依赖检查失败" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "缺失以下命令：" >&2
    for cmd in "${missing[@]}"; do
      printf "   ✗ %s\n" "$cmd" >&2
    done
    echo "" >&2
    echo "请安装缺失的依赖后重试：" >&2
    echo "   # Ubuntu/Debian" >&2
    echo "   sudo apt install jq" >&2
    echo "   curl -sS https://webinstall.dev/shfmt | bash  # 安装 shfmt" >&2
    echo "" >&2
    echo "   # macOS" >&2
    echo "   brew install jq shfmt" >&2
    echo "" >&2
    echo "   # 或使用 Go 安装 shfmt" >&2
    echo "   go install mvdan.cc/sh/v3/cmd/shfmt@latest" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    return 1
  fi
  return 0
}

DEBUG=false
readonly ALLOW_JSON='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'

debug() { if $DEBUG; then printf '[approve-compound] %s\n' "$*" >&2; fi; }
approve() { printf '%s\n' "$ALLOW_JSON"; exit 0; }
deny() {
  jq -n --arg msg "$1" '{
    hookSpecificOutput: {hookEventName:"PreToolUse", permissionDecision:"deny"},
    systemMessage: $msg
  }' >&2
  exit 2
}

# ---------------------------------------------------------------------------
# 权限加载（单次遍历所有设置文件）
# ---------------------------------------------------------------------------

find_git_root() {
  local toplevel git_dir git_common_dir
  toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || return
  git_dir=$(git rev-parse --git-dir 2>/dev/null)
  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  if [[ "$git_dir" != "$git_common_dir" ]]; then
    dirname "$git_common_dir"
  else
    printf '%s\n' "$toplevel"
  fi
}

# ---------------------------------------------------------------------------
# 加载共享配置
# ---------------------------------------------------------------------------

# 获取脚本目录
script_dir="$(dirname "${BASH_SOURCE[0]}")"

# 加载命令列表配置（BUILTIN_SAFE_COMMANDS）
source "$script_dir/command-lists.sh"

# 填充调用者的 allowed_prefixes 和 denied_prefixes 数组
load_prefixes() {
  local git_root
  git_root=$(find_git_root 2>/dev/null || true)

  # 使用内置安全命令初始化
  allowed_prefixes=("${BUILTIN_SAFE_COMMANDS[@]}")

  local files=(
    "$HOME/.claude/settings.json"
    "$HOME/.claude/settings.local.json"
  )
  if [[ -n "$git_root" ]]; then
    files+=("$git_root/.claude/settings.json" "$git_root/.claude/settings.local.json")
  else
    files+=(".claude/settings.json" ".claude/settings.local.json")
  fi

  # 内联的 jq 过滤器（从 extract_prefixes.jq 提取）
  local jq_filter='
def extract_prefix: sub("^Bash\\("; "") | sub("( \\*|\\*|:\\*)\\)$"; "") | sub("\\)$"; "");
(.permissions.allow[]? // empty | select(startswith("Bash(")) | "allow:" + extract_prefix),
(.permissions.deny[]?  // empty | select(startswith("Bash(")) | "deny:"  + extract_prefix)
'

  local line
  while IFS= read -r line; do
    # 去除 Windows CR 字符
    line="${line%$'\r'}"
    case "$line" in
      allow:*) allowed_prefixes+=("${line#allow:}") ;;
      deny:*)  denied_prefixes+=("${line#deny:}") ;;
    esac
  done < <(
    for file in "${files[@]}"; do
      [[ -f "$file" ]] || continue
      debug "Reading prefixes from: $file"
      jq -r "$jq_filter" "$file" 2>/dev/null || true
    done | sort -u
  )
}

# ---------------------------------------------------------------------------
# 命令检测和解析（shfmt AST -> 通过 jq 提取单个命令）
# ---------------------------------------------------------------------------

# 如果命令需要复合解析（包含可能隐藏子命令的 shell 元字符：
# 管道、链式、分号、命令替换、进程替换、反引号），返回 0。
needs_compound_parse() {
  # shellcheck disable=SC2016  # $( 是字面模式，不是展开
  [[ "$1" == *['|&;`']* || "$1" == *'$('* || "$1" == *'<('* || "$1" == *'>('* ]]
}

# read 在分隔符前的 EOF 时返回 1；|| true 防止在 pipefail 下退出
read -r -d '' SHFMT_AST_FILTER << 'JQEOF' || true
def get_part_value:
  if (type == "object" | not) then ""
  elif .Type == "Lit" then .Value // ""
  elif .Type == "DblQuoted" then
    "\"" + ([.Parts[]? | get_part_value] | join("")) + "\""
  elif .Type == "SglQuoted" then
    "'" + (.Value // "") + "'"
  elif .Type == "ParamExp" then
    "$" + (.Param.Value // "")
  elif .Type == "CmdSubst" then "$(..)"
  else ""
  end;

def find_cmd_substs:
  if type == "object" then
    if .Type == "CmdSubst" or .Type == "ProcSubst" then .
    elif .Type == "DblQuoted" then .Parts[]? | find_cmd_substs
    elif .Type == "ParamExp" then
      (.Exp?.Word | find_cmd_substs),
      (.Repl?.Orig | find_cmd_substs),
      (.Repl?.With | find_cmd_substs)
    elif .Parts then .Parts[]? | find_cmd_substs
    else empty
    end
  elif type == "array" then .[] | find_cmd_substs
  else empty
  end;

def get_arg_value:
  [.Parts[]? | get_part_value] | join("");

def get_command_string:
  if .Type == "CallExpr" and .Args then
    [.Args[] | get_arg_value] | map(select(length > 0)) | join(" ")
  else empty
  end;

def extract_commands:
  if type == "object" then
    if .Type == "CallExpr" then
      get_command_string,
      (.Args[]? | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Assigns[]?.Value | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Assigns[]?.Array?.Elems[]?.Value | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Redirs[]?.Word | find_cmd_substs | .Stmts[]? | extract_commands)
    elif .Type == "BinaryCmd" then
      (.X | extract_commands), (.Y | extract_commands)
    elif .Type == "Subshell" or .Type == "Block" then
      (.Stmts[]? | extract_commands)
    elif .Type == "CmdSubst" then
      (.Stmts[]? | extract_commands)
    elif .Type == "IfClause" then
      (.Cond[]? | extract_commands),
      (.Then[]? | extract_commands),
      (.Else | extract_commands)
    elif .Type == "WhileClause" or .Type == "UntilClause" then
      (.Cond[]? | extract_commands), (.Do[]? | extract_commands)
    elif .Type == "ForClause" then
      (.Loop.Items[]? | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Do[]? | extract_commands)
    elif .Type == "CaseClause" then
      (.Items[]?.Stmts[]? | extract_commands)
    elif .Type == "DeclClause" then
      (.Args[]?.Value | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Args[]?.Array?.Elems[]?.Value | find_cmd_substs | .Stmts[]? | extract_commands)
    elif .Cmd then
      (.Cmd | extract_commands),
      (.Redirs[]?.Word | find_cmd_substs | .Stmts[]? | extract_commands)
    elif .Stmts then
      (.Stmts[] | extract_commands)
    else
      (.[] | extract_commands)
    end
  elif type == "array" then
    (.[] | extract_commands)
  else empty
  end;

extract_commands | select(length > 0)
JQEOF
readonly SHFMT_AST_FILTER

# 将复合命令解析为单个命令（NUL 分隔）
parse_compound() {
  local cmd="$1"

  # 规范化 shfmt 无法解析的 [[ \! $x =~ ]] 模式
  if [[ "$cmd" == *"=~"* ]]; then
    cmd=$(sed -E 's/\[\[[[:space:]]*\\?![[:space:]]+(.+)[[:space:]]+=~/! [[ \1 =~/g' <<< "$cmd")
  fi

  local ast
  if ! ast=$(shfmt -ln bash -tojson <<< "$cmd" 2>/dev/null); then
    debug "shfmt parse failed"
    return 1
  fi

  local raw_commands
  raw_commands=$(jq -r "$SHFMT_AST_FILTER" <<< "$ast" 2>/dev/null) || return 1

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # 去除 Windows CR 字符
    line="${line%$'\r'}"
    # 递归展开 bash -c / sh -c
    if [[ "$line" =~ ^(env[[:space:]]+)?(/[^[:space:]]*/)?((ba)?sh)[[:space:]]+-c[[:space:]]*[\'\"](.*)[\'\"]$ ]]; then
      debug "Recursing into shell -c: ${BASH_REMATCH[5]}"
      if ! parse_compound "${BASH_REMATCH[5]}"; then
        # 内部解析失败 — 按原样发出包装器，以便对照允许/拒绝列表检查
        # （很可能回退）
        printf '%s\0' "$line"
      fi
    else
      printf '%s\0' "$line"
    fi
  done <<< "$raw_commands"
}

# ---------------------------------------------------------------------------
# 权限匹配
# ---------------------------------------------------------------------------

# 去除前导环境变量赋值（VAR=val cmd ...）并输出候选数组。
# 兼容 bash 3.2：通过全局变量传递结果
strip_env_vars() {
  local full_command="$1"
  local result_var="$2"
  local stripped="$full_command"

  while [[ "$stripped" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*) ]]; do
    stripped="${BASH_REMATCH[1]}"
  done

  # 构建数组并赋值给调用者
  eval "$result_var=(\"\$full_command\")"
  [[ "$stripped" != "$full_command" ]] && eval "$result_var+=(\"\$stripped\")"
}

# 检查命令是否匹配给定列表中的任何前缀。
# 兼容 bash 3.2：通过 eval 访问数组
matches_prefix_list() {
  local full_command="$1"
  local list_name="$2"
  local label="${3:-}"

  # 获取数组长度
  local list_length
  eval "list_length=\${#$list_name[@]}"
  [[ $list_length -eq 0 ]] && return 1

  local -a candidates=()
  strip_env_vars "$full_command" candidates

  debug "matches_prefix_list: checking '$full_command' against $list_length prefixes (label=$label)"
  local cmd prefix i
  for cmd in "${candidates[@]}"; do
    for ((i=0; i<list_length; i++)); do
      eval "prefix=\${$list_name[i]}"
      debug "  Testing: cmd='$cmd' prefix='$prefix'"
      if [[ "$cmd" == "$prefix" ]] || [[ "$cmd" == "$prefix "* ]] || [[ "$cmd" == "$prefix/"* ]]; then
        debug "MATCH ($label): '$cmd' -> '$prefix'"
        return 0
      fi
    done
  done
  return 1
}

# 根据拒绝和允许列表检查单个命令。
# 返回：0=允许，1=不允许（拒绝或未知）
is_allowed() {
  local cmd="$1"
  debug "Checking command: '$cmd'"
  if matches_prefix_list "$cmd" denied_prefixes "deny"; then
    debug "Command denied: '$cmd'"
    return 1
  fi
  if matches_prefix_list "$cmd" allowed_prefixes "allow"; then
    debug "Command allowed: '$cmd'"
    return 0
  fi
  debug "Command unknown (not in allow or deny): '$cmd'"
  return 1
}

# 检查给定数组中的所有命令。仅当每个命令都被允许时返回 0。
# 兼容 bash 3.2：通过 eval 访问数组
all_allowed() {
  local cmds_name="$1"
  local cmds_length cmd i

  eval "cmds_length=\${#$cmds_name[@]}"
  for ((i=0; i<cmds_length; i++)); do
    eval "cmd=\${$cmds_name[i]}"
    [[ -z "$cmd" ]] && continue
    if ! is_allowed "$cmd"; then
      debug "Not all commands approved"
      return 1
    fi
  done
  return 0
}

# 检查给定数组中是否有任何命令匹配拒绝列表。
# 兼容 bash 3.2：通过 eval 访问数组
any_denied() {
  local cmds_name="$1"
  [[ ${#denied_prefixes[@]} -eq 0 ]] && return 1

  local cmds_length cmd i
  eval "cmds_length=\${#$cmds_name[@]}"
  for ((i=0; i<cmds_length; i++)); do
    eval "cmd=\${$cmds_name[i]}"
    [[ -z "$cmd" ]] && continue
    if matches_prefix_list "$cmd" denied_prefixes "deny"; then
      debug "Denied segment found: $cmd"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# 主函数
# ---------------------------------------------------------------------------

main() {
  local permissions_json="" deny_json="" mode="hook"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --debug) DEBUG=true; shift ;;
      --permissions) permissions_json="$2"; shift 2 ;;
      --deny) deny_json="$2"; shift 2 ;;
      parse) mode="parse"; shift ;;
      *) shift ;;
    esac
  done

  # 依赖检查：缺失时回退到原生权限提示（exit 0）
  if ! check_dependencies; then
    debug "Dependencies missing, falling through to native prompt"
    exit 0
  fi

  # 解析模式：从 stdin（纯文本）提取命令，每行一个
  if [[ "$mode" == "parse" ]]; then
    local cmd
    cmd=$(cat)
    [[ -z "$cmd" ]] && exit 0
    if ! needs_compound_parse "$cmd"; then
      printf '%s\n' "$cmd"
    else
      # 兼容 bash 3.2：使用 while 循环替代 mapfile
      parse_compound "$cmd" | while IFS= read -r -d '' c; do
        [[ -n "$c" ]] && printf '%s\n' "$c"
      done
    fi
    exit 0
  fi

  # 守卫：读取 hook 输入
  local input command
  input=$(cat)
  command=$(jq -r '.tool_input.command // empty' <<< "$input")
  [[ -z "$command" ]] && exit 0

  debug "Command: $command"

  # 加载权限（从设置文件，或从 --permissions/--deny 用于测试）
  local -a allowed_prefixes=() denied_prefixes=()
  if [[ -n "$permissions_json" ]]; then
    local line
    while IFS= read -r line; do
      [[ -n "$line" ]] && allowed_prefixes+=("$line")
    done < <(jq -r '.[] | sub("^Bash\\("; "") | sub("( \\*|\\*|:\\*)\\)$"; "") | sub("\\)$"; "")' <<< "$permissions_json" 2>/dev/null)
    if [[ -n "$deny_json" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && denied_prefixes+=("$line")
      done < <(jq -r '.[] | sub("^Bash\\("; "") | sub("( \\*|\\*|:\\*)\\)$"; "") | sub("\\)$"; "")' <<< "$deny_json" 2>/dev/null)
    fi
  else
    load_prefixes
  fi
  debug "Loaded ${#allowed_prefixes[@]} allow, ${#denied_prefixes[@]} deny prefixes"
  [[ ${#allowed_prefixes[@]} -eq 0 ]] && exit 0

  # 简单命令 — 直接检查，无需 shfmt 解析
  if ! needs_compound_parse "$command"; then
    debug "Simple command"
    is_allowed "$command" && approve
    exit 0
  fi

  # 复合命令 — 解析为段并逐个检查
  debug "Compound command"
  local -a extracted_commands=()

  # 兼容 bash 3.2：使用临时文件和循环替代 mapfile
  local tmp_file
  tmp_file=$(mktemp)
  parse_compound "$command" > "$tmp_file"

  # 读取 NUL 分隔的命令到数组
  local line_num=0
  while IFS= read -r -d '' line; do
    [[ -n "$line" ]] && extracted_commands[$line_num]="$line"
    ((line_num++))
  done < "$tmp_file"
  rm -f "$tmp_file"

  # 解析失败或空结果 — 回退到提示（不要自动批准
  # 可能包含危险子命令的无法解析的命令）
  [[ ${#extracted_commands[@]} -eq 0 ]] && exit 0

  all_allowed extracted_commands && approve

  # 未全部批准：主动拒绝如果任何段在拒绝列表中
  any_denied extracted_commands && deny "Compound command contains a denied sub-command"

  # 收集未授权的命令并输出（供用户批准后的处理使用）
  local -a unapproved=()
  for cmd in "${extracted_commands[@]}"; do
    [[ -z "$cmd" ]] && continue
    if ! is_allowed "$cmd"; then
      unapproved+=("$cmd")
    fi
  done

  if [[ ${#unapproved[@]} -gt 0 ]]; then
    # 输出特殊标记到 stderr，包含未授权命令列表（用 \x1f 分隔）
    printf '\n__UNAPPROVED_COMMANDS__:%s\n' "$(IFS=$'\x1f'; echo "${unapproved[*]}")" >&2

    # **关键： 保存到临时文件，供 PostToolUse hook 使用**
    local pending_file="/tmp/claude-pending-commands-$$.txt"
    printf '%s\n' "$(IFS=$'\n'; echo "${unapproved[*]}")" > "$pending_file"
    debug "Saved pending commands to: $pending_file"
  fi

  # 回退到原生权限提示
  exit 0
}

main "$@"
