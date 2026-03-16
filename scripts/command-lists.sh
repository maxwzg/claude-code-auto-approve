#!/usr/bin/env bash
# command-lists.sh - 命令安全配置中心
#
# 集中定义所有安全相关的命令列表
# 供 PreToolUse 和 PostToolUse hooks 共享使用
#
# 用法：source "$script_dir/command-lists.sh"
# 或：  . "$script_dir/command-lists.sh"

# ---------------------------------------------------------------------------
# 防护：防止直接执行此配置文件
# ---------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "⚠️  错误：此配置文件应该被 source，而不是直接执行" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "" >&2
  echo "正确用法：" >&2
  echo "  source $0" >&2
  echo "  或" >&2
  echo "  . $0" >&2
  echo "" >&2
  echo "此文件定义了以下配置：" >&2
  echo "  • DANGEROUS_COMMANDS - 危险命令列表" >&2
  echo "  • BUILTIN_SAFE_COMMANDS - 安全命令列表" >&2
  echo "  • is_dangerous() - 危险命令检查函数" >&2
  echo "  • is_builtin_safe() - 安全命令检查函数" >&2
  echo "" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 危险命令定义
# ---------------------------------------------------------------------------

# 危险命令列表 - 不会自动学习，需要手动添加到配置文件
# 分类标准：极高风险 > 高风险 > 中等风险
readonly DANGEROUS_COMMANDS=(
  # ===== 极高风险 - Shell 解释器 =====
  bash            # Bash 解释器（可执行任意命令）
  sh              # POSIX shell（可执行任意命令）
  zsh             # Zsh 解释器（可执行任意命令）
  dash            # Debian ash（可执行任意命令）
  fish            # Fish shell（可执行任意命令）
  command         # 命令执行器（可绕过函数和别名保护）
  builtin         # 内置命令执行器（可执行 shell 内置命令）

  # ===== 极高风险 - 文件删除和权限提升 =====
  rm              # 文件删除（可能导致数据丢失）
  rmdir           # 目录删除
  sudo            # 权限提升（完全控制）
  shred           # 安全删除（覆盖数据，不可恢复）

  # ===== 极高风险 - 权限修改 =====
  chmod           # 权限修改
  chown           # 所有者修改
  chgrp           # 组修改

  # ===== 极高风险 - 磁盘和分区 =====
  dd              # 磁盘复制（可能覆盖整个磁盘）
  mkfs            # 格式化（清除所有数据）
  fdisk           # 分区操作
  parted          # 分区工具
  mount           # 挂载文件系统
  umount          # 卸载文件系统

  # ===== 极高风险 - 系统启动 =====
  grub-install    # 安装引导加载器
  update-grub     # 更新引导配置
  efibootmgr      # UEFI 引导管理

  # ===== 极高风险 - 系统控制 =====
  shutdown        # 关机
  reboot          # 重启
  poweroff        # 关机
  halt            # 停机
  init            # 运行级别切换

  # ===== 高风险 - 进程管理 =====
  kill            # 进程终止
  pkill           # 批量终止进程
  killall         # 按名称终止进程

  # ===== 高风险 - 防火墙 =====
  iptables        # 防火墙规则
  ufw             # 防火墙配置

  # ===== 高风险 - 系统服务 =====
  systemctl       # systemd 服务管理
  service         # 传统服务管理

  # ===== 高风险 - 包管理器 =====
  apt             # Debian/Ubuntu 包管理
  apt-get         # Debian/Ubuntu 包管理
  dpkg            # Debian 包管理
  yum             # RHEL/CentOS 包管理
  dnf             # Fedora 包管理
  pacman          # Arch Linux 包管理

  # ===== 高风险 - 定时任务 =====
  crontab         # 定时任务
  at              # 定时任务

  # ===== 高风险 - 用户管理 =====
  userdel         # 删除用户
  usermod         # 修改用户

  # ===== 中等风险 - 网络（瑞士军刀型工具）=====
  curl            # 数据传输工具（可下载恶意内容、数据泄露）
  wget            # 文件下载工具（可下载恶意内容）
  nc              # netcat（网络瑞士军刀）
  ncat            # netcat 现代版
  socat           # 高级网络工具

  # ===== 中等风险 - 远程操作 =====
  ssh             # SSH 远程登录
  scp             # SSH 远程复制
  rsync           # 远程同步

  # ===== 中等风险 - 用户组管理 =====
  groupdel        # 删除组
)

# ---------------------------------------------------------------------------
# 内置安全命令定义
# ---------------------------------------------------------------------------

# 内置安全命令列表（可被配置文件覆盖/扩展）
# 这些命令被认为是安全的，可以自动批准
declare -a BUILTIN_SAFE_COMMANDS=(
  # 文件系统导航
  "pwd"
  "cd"
  "ls"
  "dir"

  # 文件查看（只读）
  "cat"
  "head"
  "tail"
  "less"
  "more"
  "wc"

  # 文本处理（无副作用的纯处理命令）
  "echo"
  "printf"
  "grep"
  # "sed"   # ❌ 已移除：-i 参数可修改文件
  # "awk"   # ❌ 已移除：system() 函数可执行任意命令
  "sort"
  "uniq"
  "cut"
  "tr"
  "nl"
  "tac"
  "rev"
  "fmt"
  "comm"
  "cmp"
  "numfmt"
  "tsort"
  "pr"

  # 条件和流程控制
  "test"
  "["
  "[["
  "read"
  "true"
  "false"

  # 文件操作（安全子集）
  "find"      # 保留：开发中太常用
  "locate"
  "xargs"     # 保留：开发中太常用

  # 系统信息（只读）
  "date"
  "whoami"
  "id"
  "uname"
  "hostname"
  "getconf"
  # "env"   # ❌ 已移除：可能泄露环境变量中的敏感信息

  # 其他安全工具
  "tee"       # 保留：开发中太常用
  "basename"
  "dirname"
  "realpath"
  "readlink"
  "seq"
  "yes"
  "expr"
  "bc"
  "sleep"
  "time"
)

# ---------------------------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------------------------

# 检查命令是否为危险命令
# 参数：$1 - 命令字符串
# 返回：0=危险，1=安全
is_dangerous() {
  local cmd="$1"
  local cmd_name
  cmd_name=$(echo "$cmd" | awk '{print $1}')

  for dangerous in "${DANGEROUS_COMMANDS[@]}"; do
    [[ "$cmd_name" == "$dangerous" ]] && return 0
  done
  return 1
}

# 检查命令是否在安全列表中
# 参数：$1 - 命令字符串
# 返回：0=安全，1=不在列表中
is_builtin_safe() {
  local cmd="$1"
  local cmd_name
  cmd_name=$(echo "$cmd" | awk '{print $1}')

  for safe in "${BUILTIN_SAFE_COMMANDS[@]}"; do
    [[ "$cmd_name" == "$safe" ]] && return 0
  done
  return 1
}
