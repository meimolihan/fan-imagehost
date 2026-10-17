#!/usr/bin/env bash
#
# fan-imagehost 内置 CLI 管理命令
# 由 scripts/install.sh 安装到 /usr/local/bin/fan-imagehost
#
# 用法:
#   fan-imagehost status                     查看运行状态
#   fan-imagehost start|stop|restart         启动 / 停止 / 重启 systemd 服务
#   fan-imagehost credentials                查看登录用户名
#   fan-imagehost version                    查看版本号
#   fan-imagehost uninstall [-y] [--purge]   卸载（透传给卸载脚本）
#   fan-imagehost help                       显示帮助

set -uo pipefail

APP_NAME="fan-imagehost"
APP_DIR="/var/lib/fan-imagehost"
DATA_DIR="/var/lib/fan-imagehost/data"
DEFAULT_PORT=8083
CONFIG_FILE="/etc/fan-imagehost.conf"
SERVICE_FILE="/etc/systemd/system/fan-imagehost.service"
UNINSTALL_SCRIPT="${APP_DIR}/scripts/uninstall.sh"

# 颜色
gl_hui=$'\033[38;5;59m'; gl_hong=$'\033[38;5;9m'; gl_lv=$'\033[38;5;10m'
gl_huang=$'\033[38;5;11m'; gl_lan=$'\033[38;5;32m'; gl_bai=$'\033[38;5;15m'
gl_zi=$'\033[38;5;13m'; gl_bufan=$'\033[38;5;14m'; reset=$'\033[0m'

read_config() {
  [ -f "${CONFIG_FILE}" ] || return 0
  while IFS='=' read -r KEY VALUE; do
    KEY=$(printf '%s' "$KEY" | tr -d ' ')
    VALUE=$(printf '%s' "$VALUE" | tr -d '\r')
    case "${KEY}" in
      APP_DIR) [ -n "$VALUE" ] && APP_DIR="$VALUE" ;;
      DATA_DIR) [ -n "$VALUE" ] && DATA_DIR="$VALUE" ;;
      PORT) [ -n "$VALUE" ] && PORT="$VALUE" ;;
      BACKUP_DIR) [ -n "$VALUE" ] && BACKUP_DIR="$VALUE" ;;
    esac
  done < "${CONFIG_FILE}"
}

read_config
PORT="${PORT:-$DEFAULT_PORT}"
BACKUP_DIR="${BACKUP_DIR:-${APP_DIR}/backup}"

have_systemd() { command -v systemctl >/dev/null 2>&1 && [ -f "${SERVICE_FILE}" ]; }

get_version() {
  if [ -f "${APP_DIR}/package.json" ]; then
    local v
    v=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "${APP_DIR}/package.json" | head -n1 | sed -E 's/.*"([^"]+)"$/\1/')
    [ -n "${v}" ] && { echo "${v}"; return; }
  fi
  if [ -f "${APP_DIR}/app/base.php" ]; then
    local v
    v=$(grep -oE "APP_VERSION',[[:space:]]*'[^']+'" "${APP_DIR}/app/base.php" | head -n1 | sed -E "s/.*'([^']+)'$/\1/")
    [ -n "${v}" ] && { echo "${v}"; return; }
  fi
  echo "unknown"
}

find_pids() {
  local d pid cmdline
  for d in /proc/[0-9]*; do
    [ -d "$d" ] || continue
    pid="${d#/proc/}"
    cmdline=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
    case "$cmdline" in
      *"${APP_DIR}/router.php"*|*"-t ${APP_DIR}"*) echo "$pid" ;;
    esac
  done
}

get_ip() {
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -n "${ip}" ] && echo "${ip}" || echo "127.0.0.1"
}

cmd_status() {
  echo -e "${gl_zi}>>> ${APP_NAME} 运行状态${gl_bai}"
  echo -e "${gl_bufan}————————————————————————————————————————————————${gl_bai}"

  local mode="未运行" pid="" uptime_s="" mem="" status="inactive"
  if have_systemd && systemctl is-active --quiet "${APP_NAME}" 2>/dev/null; then
    mode="systemd 服务"
    status="active"
    pid=$(systemctl show -p MainPID --value "${APP_NAME}" 2>/dev/null)
    uptime_s=$(systemctl show -p ActiveEnterTimestamp --value "${APP_NAME}" 2>/dev/null)
  else
    pid=$(find_pids | head -n1)
    [ -n "${pid}" ] && { mode="直接运行进程"; status="active"; }
  fi

  local status_text
  case "${status}" in
    active) status_text="${gl_lv}运行中${reset}" ;;
    *) status_text="${gl_hong}已停止${reset}" ;;
  esac

  printf "  %-14s%s\n" "${gl_hui}运行方式：${reset}" "${gl_lan}${mode}${reset}"
  printf "  %-14s%s\n" "${gl_hui}运行状态：${reset}" "${status_text}"
  [ -n "${pid}" ] && [ "${pid}" != "0" ] && printf "  %-14s%s\n" "${gl_hui}进程 PID：${reset}" "${gl_bufan}${pid}${reset}"

  if [ -n "${pid}" ] && [ -d "/proc/${pid}" ]; then
    local start_ticks clk hz etime
    start_ticks=$(awk '{print $22}' "/proc/${pid}/stat" 2>/dev/null)
    clk=$(getconf CLK_TCK 2>/dev/null || echo 100)
    if [ -n "${start_ticks}" ] && [ -r "/proc/uptime" ]; then
      local up now
      up=$(awk '{print int($1)}' /proc/uptime)
      now=$((up - start_ticks / clk))
      if [ "${now}" -ge 0 ]; then
        local d=$((now/86400)) h=$(((now%86400)/3600)) m=$(((now%3600)/60)) s=$((now%60))
        printf "  %-14s%s\n" "${gl_hui}运行时长：${reset}" "${gl_bai}${d}天 ${h}时 ${m}分 ${s}秒${reset}"
      fi
    fi
    local rss
    rss=$(awk '/VmRSS/{print $2" "$3}' "/proc/${pid}/status" 2>/dev/null)
    [ -n "${rss}" ] && printf "  %-14s%s\n" "${gl_hui}内存占用：${reset}" "${gl_bai}${rss}${reset}"
  fi

  printf "  %-14s%s\n" "${gl_hui}版本：${reset}" "${gl_lv}$(get_version)${reset}"
  local ip; ip=$(get_ip)
  printf "  %-14s%s\n" "${gl_hui}访问地址：${reset}" "${gl_bai}http://${ip}:${PORT}${reset}"
  printf "  %-14s%s\n" "${gl_hui}程序目录：${reset}" "${gl_bai}${APP_DIR}${reset}"
  printf "  %-14s%s\n" "${gl_hui}数据目录：${reset}" "${gl_bai}${DATA_DIR}${reset}"
  printf "  %-14s%s\n" "${gl_hui}备份目录：${reset}" "${gl_bai}${BACKUP_DIR}${reset}"
  echo -e "${gl_bufan}————————————————————————————————————————————————${gl_bai}"
}

require_root() {
  [ "$(id -u)" = "0" ] || { echo -e "${gl_hong}ERROR: 需要 root 权限（sudo ${APP_NAME} $1）${reset}" >&2; exit 1; }
}

cmd_service() {
  local action="$1"
  require_root "${action}"
  if ! have_systemd; then
    echo -e "${gl_hong}ERROR: 未找到 systemd 服务 ${SERVICE_FILE}${reset}" >&2
    exit 1
  fi
  systemctl "${action}" "${APP_NAME}"
}

cmd_credentials() {
  local user="" conf="${DATA_DIR}/config/config.php"
  if [ -f "${conf}" ]; then
    user=$(grep -oE "'user'[[:space:]]*=>[[:space:]]*'[^']*'" "${conf}" | head -n1 | sed -E "s/.*'([^']*)'$/\1/")
  fi
  echo -e "${gl_zi}>>> ${APP_NAME} 登录信息${gl_bai}"
  echo -e "${gl_bufan}————————————————————————————————————————————————${gl_bai}"
  printf "  %-14s%s\n" "${gl_hui}用户名：${reset}" "${gl_bai}${user:-admin}${reset}"
  printf "  %-14s%s\n" "${gl_hui}密码：${reset}" "${gl_huang}出于安全考虑不提供明文密码；首次安装默认 admin@123，请登录后及时修改${reset}"
  printf "  %-14s%s\n" "${gl_hui}登录地址：${reset}" "${gl_bai}http://$(get_ip):${PORT}/admin/${reset}"
  echo -e "${gl_bufan}————————————————————————————————————————————————${gl_bai}"
}

cmd_version() {
  echo -e "${gl_zi}>>> ${APP_NAME} 版本：${gl_lv}$(get_version)${reset}"
}

cmd_help() {
  echo -e "${gl_zi}>>> ${APP_NAME} 管理命令${gl_bai}"
  echo -e "${gl_bufan}————————————————————————————————————————————————${gl_bai}"
  printf "  %-42s %s\n" "fan-imagehost status" "查看运行方式、PID、端口、访问地址、运行时长、路径"
  printf "  %-42s %s\n" "fan-imagehost credentials" "查看登录用户名"
  printf "  %-42s %s\n" "fan-imagehost start|stop|restart" "启动 / 停止 / 重启 systemd 服务"
  printf "  %-42s %s\n" "fan-imagehost version" "查看版本号"
  printf "  %-42s %s\n" "fan-imagehost uninstall [-y] [--purge|--keep-data]" "卸载服务与程序，可选删除数据目录"
  printf "  %-42s %s\n" "fan-imagehost help" "显示本帮助"
  echo -e "${gl_bufan}————————————————————————————————————————————————${gl_bai}"
}

ACTION="${1:-help}"
shift || true

case "${ACTION}" in
  status) cmd_status ;;
  start|stop|restart) cmd_service "${ACTION}" ;;
  credentials) cmd_credentials ;;
  version|-v|--version) cmd_version ;;
  uninstall)
    require_root "uninstall"
    if [ -f "${UNINSTALL_SCRIPT}" ]; then
      exec bash "${UNINSTALL_SCRIPT}" "$@"
    else
      echo -e "${gl_hong}ERROR: 未找到卸载脚本 ${UNINSTALL_SCRIPT}${reset}" >&2
      exit 1
    fi
    ;;
  help|-h|--help) cmd_help ;;
  *) echo -e "${gl_hong}未知命令: ${ACTION}${reset}"; cmd_help; exit 1 ;;
esac
