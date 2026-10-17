#!/usr/bin/env bash
#
# fan-imagehost - 简单图床 安装脚本
# 将图床程序安装为 systemd 服务（PHP 内置服务器 php -S 运行）。
# 可重复执行，升级等同于重新安装（覆盖程序并重启服务，数据目录保留）。
#
# Usage:
#   交互式安装（将提示端口与数据目录）:
#     bash scripts/install.sh
#   参数静默安装（-p 端口 / -d 数据目录 / -s 源码目录）:
#     bash scripts/install.sh -p 8083 -d /var/lib/fan-imagehost/data /data/fan-imagehost.repo
#     bash scripts/install.sh -p 8083 -d /var/lib/fan-imagehost/data -s /tmp/fan-imagehost
#   预编译发布包安装（无需 git）:
#     bash scripts/install.sh -p 8083 -b
#     默认已优先使用发布包（auto）；不指定 -s 且本地无源码时自动下载发布包
#   国内网络可用镜像仓库:
#     FAN_IMAGEHOST_REPO=https://ghfast.top/https://github.com/meimolihan/fan-imagehost.git bash scripts/install.sh -y
#
# 固定约定: 程序默认安装目录 /var/lib/fan-imagehost
#   标准安装命令: bash scripts/install.sh -p 端口号 -d /var/lib/fan-imagehost -y

set -euo pipefail

# ================== terminal colors ==================
list_color_init() {
    export gl_hui=$'\033[38;5;59m'
    export gl_hong=$'\033[38;5;9m'
    export gl_lv=$'\033[38;5;10m'
    export gl_huang=$'\033[38;5;11m'
    export gl_lan=$'\033[38;5;32m'
    export gl_bai=$'\033[38;5;15m'
    export gl_zi=$'\033[38;5;13m'
    export gl_bufan=$'\033[38;5;14m'
    export reset=$'\033[0m'
}
list_color_init

sep_line() {
  printf '%s' "$gl_bufan"
  printf '—%.0s' {1..32}
  printf '%s\n' "$reset"
}

section() {
  printf "  %s %s\n" "${gl_zi}▶${reset}" "$1"
}

ok() {
  printf "  %s %s\n" "${gl_lv}>>>${reset}" "$1"
}

skip() {
  printf "  %s %s\n" "${gl_hui}--${reset}" "$1"
}

warn() {
  printf "  %s %s\n" "${gl_huang}[提示]${reset}" "$1"
}

print_banner() {
  local z="$gl_zi" r="$reset" b="$gl_bai" l="$gl_lan"
  printf '%s\n' \
    "" \
    "  ${z}┌─────────────────────────────────────────┐${r}" \
    "  ${z}│${r}   ${b}fan-imagehost${r}  ${l}简单图床 · 安装${r}      ${z}│${r}" \
    "  ${z}└─────────────────────────────────────────┘${r}" \
    ""
}

error() { printf "  %s %s\n" "${gl_hong}[错误]${reset}" "$1" >&2; exit 1; }

# ================== customize me ==================
APP_NAME="fan-imagehost"
DEFAULT_PORT=8083
APP_DIR="/var/lib/${APP_NAME}"
DEFAULT_DATA_DIR="${APP_DIR}/data"
CONFIG_FILE="/etc/${APP_NAME}.conf"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
CLI_BIN="/usr/local/bin/${APP_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
DEFAULT_SRC_DIR="${SCRIPT_DIR}/.."
GITHUB_REPO="https://github.com/meimolihan/fan-imagehost.git"
GITHUB_BIN_REPO="meimolihan/fan-imagehost"
RELEASE_ASSET="fan-imagehost.tar.gz"
PHP_REQUIRED_EXTS="fileinfo gd mbstring zip openssl iconv curl exif"

# ================== GitHub 下载加速镜像 ==================
# 原始 GitHub 地址超时/失败时，按下列顺序依次尝试（末尾必须带斜杠）
GITHUB_MIRRORS=(
  "https://ghfast.top/"
  "https://ghproxy.net/"
  "https://gh.xxooo.cf/"
  "https://v6.gh-proxy.org/"
  "https://githubproxy.cc/"
)
# v6.gh-proxy.org 为纯 IPv6 代理：本机未配置 IPv6 地址时剔除，避免每次空等超时
if [ ! -s /proc/net/if_inet6 ]; then
  _no_v6=()
  for _m in "${GITHUB_MIRRORS[@]}"; do
    case "${_m}" in
      *v6.gh-proxy.org*) continue ;;
    esac
    _no_v6+=("${_m}")
  done
  GITHUB_MIRRORS=("${_no_v6[@]}")
fi

# 根据原始 GitHub URL 生成候选地址列表：原始地址优先，然后依次套用各镜像
make_url_candidates() {
  local github_url="$1"
  local p
  printf '%s\n' "$github_url"
  for p in "${GITHUB_MIRRORS[@]}"; do
    printf '%s\n' "${p}${github_url}"
  done
}
# ==========================================================

# 经 curl|bash 远程执行时，SCRIPT_DIR 指向 bash 抽取的临时目录，本地源码仓库
# 需按常见目录回退探测（当前目录 / 上一级目录 / 上级的上级），否则会误判"无本地源码"。
resolve_local_src() {
  local candidates=(
    "${SCRIPT_DIR:-}/.."
    "$(pwd)"
    "$(pwd)/.."
    "$(dirname "$(pwd)")"
    "$(dirname "$(dirname "$(pwd)")")"
  )
  for c in "${candidates[@]}"; do
    if [ -f "${c}/index.php" ] && [ -f "${c}/app/function.php" ] && [ -f "${c}/config/config.php" ]; then
      printf '%s' "${c}"
      return 0
    fi
  done
  return 1
}

is_valid_src() {
  [ -f "$1/index.php" ] && [ -f "$1/app/function.php" ] && [ -f "$1/config/config.php" ]
}
# ==================================================

PORT=""
DATA_DIR=""
SRC_DIR=""
SRC_DIR_EXPLICIT=0
BINARY_MODE="auto"
INSTALL_YES=0

# ---- bootstrap: support `bash -c "$(curl ...)" -p ... -d ...` ----
case "$0" in
  -*) set -- "$0" "$@" ;;
esac

# ---- parse command-line args (silent install) ----
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p|--port)
      shift
      [ -n "${1:-}" ] || error "缺少 -p/--port 的值"
      PORT="$1"
      ;;
    -d|--data)
      shift
      [ -n "${1:-}" ] || error "缺少 -d/--data 的值"
      DATA_DIR="$1"
      ;;
    -s|--src)
      shift
      [ -n "${1:-}" ] || error "缺少 -s/--src 的值"
      SRC_DIR="$1"
      SRC_DIR_EXPLICIT=1
      ;;
    -b|--binary)
      BINARY_MODE="force"
      ;;
    -y|--yes)
      INSTALL_YES=1
      ;;
    -h|--help)
      printf "%s\n" "${gl_lan}fan-imagehost${reset} - ${gl_bai}简单图床（无数据库 PHP 图床）安装脚本${reset}"
      printf "  %-13s %s\n" "${gl_bai}用法:${reset}" "bash scripts/install.sh [-p PORT] [-d DATA_DIR] [-s SRC] [-b] [-y]"
      printf "  %-13s %s\n" "${gl_bai}-p, --port${reset}" "监听端口（默认 ${gl_lan}${DEFAULT_PORT}${reset}）"
      printf "  %-13s %s\n" "${gl_bai}-d, --data${reset}" "数据目录（默认 ${gl_lan}${DEFAULT_DATA_DIR}${reset}，存放 config 与上传图片）"
      printf "  %-13s %s\n" "${gl_bai}-s, --src${reset}" "源码仓库路径（默认 ${gl_lan}${DEFAULT_SRC_DIR}${reset}）"
      printf "  %-13s %s\n" "${gl_bai}-b, --binary${reset}" "强制使用预编译发布包安装（无需 git）"
      printf "  %-13s %s\n" "${gl_bai}-y, --yes${reset}" "免交互，未指定项全部使用默认值"
      printf "  %-13s %s\n" "${gl_bai}-h, --help${reset}" "显示本帮助"
      printf "%s\n" "${gl_hui}指定任意参数即进入静默安装；不带参数则为交互式安装。${reset}"
      printf "%s\n" "${gl_hui}默认优先下载 GitHub Releases 发布包（无需 git）；可用 FAN_IMAGEHOST_VERSION 指定版本号（默认 latest）。${reset}"
      printf "%s\n" "${gl_hui}未指定 -b 且本地存在源码仓库（含 -s 显式指定）时，仍按源码安装。${reset}"
      printf "%s\n" "${gl_hui}国内网络可设 FAN_IMAGEHOST_REPO 自定义仓库或镜像地址，如 FAN_IMAGEHOST_REPO=https://ghfast.top/https://github.com/meimolihan/fan-imagehost.git${reset}"
      printf "%s\n" "${gl_hui}首次安装默认管理员账号 admin / admin@123，可用 FAN_IMAGEHOST_ADMIN_USER、FAN_IMAGEHOST_ADMIN_PASSWORD 覆盖。${reset}"
      exit 0
      ;;
    *)
      error "未知参数: $1（使用 -h 查看帮助）"
      ;;
  esac
  shift
done

# ---- firewall: automatically open the listen port ----
FW_OPENED="n"
open_firewall_port() {
  local PORT="$1"
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    if ! firewall-cmd --query-port="${PORT}/tcp" >/dev/null 2>&1; then
      firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    ok "已通过 ${gl_bai}firewalld${reset} 开放端口 ${gl_lan}${PORT}/tcp${reset}"
    FW_OPENED="y"
    return 0
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    if ! ufw status 2>/dev/null | grep -q "${PORT}/tcp"; then
      ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
    fi
    ok "已通过 ${gl_bai}ufw${reset} 开放端口 ${gl_lan}${PORT}/tcp${reset}"
    FW_OPENED="y"
    return 0
  fi

  if command -v iptables >/dev/null 2>&1; then
    if iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1; then
      ok "端口 ${gl_lan}${PORT}/tcp${reset} 已在 iptables 中放行"
      FW_OPENED="y"
      return 0
    fi
    if iptables -L INPUT -n 2>/dev/null | grep -qE 'policy (DROP|REJECT)|REJECT|DROP'; then
      if iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1; then
        ok "已通过 ${gl_bai}iptables${reset} 开放端口 ${gl_lan}${PORT}/tcp${reset}"
        FW_OPENED="y"
        return 0
      fi
    fi
  fi
  printf "  %s %s\n" "${gl_huang}[提示]${reset}" "未检测到活跃的防火墙（firewalld/ufw/iptables），跳过端口开放。"
}

[ "$(id -u)" != "0" ] && error "请以 root 身份运行（例如 sudo bash scripts/install.sh）"

print_banner
sep_line
section "安装信息"
printf "  %-14s %s\n" "${gl_lan}系统${reset}" "$(uname -s) $(uname -m)"
printf "  %-14s %s\n" "${gl_lan}程序${reset}" "${gl_bai}${APP_NAME}${reset}"
sep_line

# ---- PHP 运行时检查（尝试自动安装缺失的运行环境）----
PHP_BIN=""
EXT_MISSING=""

check_php_exts() {
  local ext list=""
  for ext in ${PHP_REQUIRED_EXTS}; do
    if ! "${PHP_BIN}" -m 2>/dev/null | grep -qi "^${ext}$"; then
      list="${list} ${ext}"
    fi
  done
  EXT_MISSING="${list# }"
  [ -z "${EXT_MISSING}" ]
}

install_php_runtime() {
  printf "  %s\n" "${gl_huang}[提示]${reset} 未检测到可用的 PHP（或缺少扩展），尝试自动安装 ..."
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -qq php-cli php-gd php-mbstring php-zip php-curl php-xml php-exif >/dev/null 2>&1 || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y php-cli php-gd php-mbstring php-zip php-curl php-xml php-exif >/dev/null 2>&1 || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y php-cli php-gd php-mbstring php-zip php-curl php-xml php-exif >/dev/null 2>&1 || true
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache php81 php81-cli php81-gd php81-mbstring php81-zip php81-curl php81-fileinfo php81-iconv php81-openssl php81-exif >/dev/null 2>&1 || true
  else
    return 1
  fi
  PHP_BIN="$(command -v php || true)"
  [ -n "${PHP_BIN}" ]
}

section "运行环境"
PHP_BIN="$(command -v php || true)"
if [ -z "${PHP_BIN}" ] || ! check_php_exts; then
  install_php_runtime || true
fi
if [ -z "${PHP_BIN}" ]; then
  error "未检测到 PHP，请先安装 PHP（要求 >= 5.6）及扩展：${PHP_REQUIRED_EXTS}"
fi
if ! check_php_exts; then
  php_ver="$("${PHP_BIN}" -r 'echo PHP_VERSION;' 2>/dev/null || echo '?')"
  error "PHP 缺少必要扩展: ${EXT_MISSING}（当前 ${php_ver}）。请安装对应扩展后重试。"
fi
ok "PHP ${gl_bai}$("${PHP_BIN}" -r 'echo PHP_VERSION;' 2>/dev/null)${reset} / 扩展齐全（${PHP_REQUIRED_EXTS}）"

# ---- 安装方式判定：发布包优先，可回退源码 ----
INSTALL_METHOD="source"
BIN_VER=""
local_src="$(resolve_local_src)" || true
if [ "${BINARY_MODE}" = "force" ]; then
  INSTALL_METHOD="binary"
elif [ "${SRC_DIR_EXPLICIT}" = "1" ]; then
  INSTALL_METHOD="source"
elif [ -n "${local_src}" ] && is_valid_src "${local_src}"; then
  INSTALL_METHOD="source"
elif [ -z "${PORT}" ] && [ "${INSTALL_YES}" != "1" ] && [ -t 0 ]; then
  read -r -p "${gl_bai}安装方式${reset}: ${gl_hui}[1] 预编译发布包 [2] 源码安装 [默认: 1]${reset} " METHOD_CHOICE
  case "${METHOD_CHOICE}" in
    2|2*) INSTALL_METHOD="source" ;;
    *) INSTALL_METHOD="binary" ;;
  esac
else
  INSTALL_METHOD="binary"
fi

if [ "${INSTALL_METHOD}" = "binary" ]; then
  ok "安装方式：${gl_lan}预编译发布包${reset}（无需 git）"
else
  ok "安装方式：${gl_lan}源码安装${reset}"
fi

# ---- 下载并解压预编译发布包 ----
install_binary() {
  local tag="${FAN_IMAGEHOST_VERSION:-latest}" url_path="" tmp="" url="" extracted=""
  if [ "${tag}" = "latest" ]; then
    url_path="releases/latest/download/${RELEASE_ASSET}"
  else
    case "${tag}" in v*) ;; *) tag="v${tag}" ;; esac
    url_path="releases/download/${tag}/${RELEASE_ASSET}"
  fi
  BIN_VER="${tag}"
  ok "下载预编译发布包 ${gl_bai}${RELEASE_ASSET}${reset}（版本 ${gl_lan}${tag}${reset}）"

  if command -v curl >/dev/null 2>&1; then
    DL_CURL="y"
  elif command -v wget >/dev/null 2>&1; then
    DL_CURL="n"
  else
    printf "  %s\n" "${gl_huang}[警告]${reset} 未检测到 curl/wget，无法下载发布包。"
    return 1
  fi

  tmp="$(mktemp)"; hdr="${tmp}.hdr"
  local candidates=()
  mapfile -t candidates < <(make_url_candidates "https://github.com/${GITHUB_BIN_REPO}/${url_path}")

  for url in "${candidates[@]}"; do
    skip "尝试下载 ${gl_bai}${url}${reset}"
    rm -f "${tmp}" "${hdr}"
    DL_FAIL="n"
    if [ "${DL_CURL}" = "y" ]; then
      if command -v timeout >/dev/null 2>&1; then
        timeout 120 curl -fsSL --connect-timeout 10 --max-time 120 -o "${tmp}" -D "${hdr}" "${url}" 2>/dev/null || DL_FAIL="y"
      else
        curl -fsSL --connect-timeout 10 --max-time 120 -o "${tmp}" -D "${hdr}" "${url}" 2>/dev/null || DL_FAIL="y"
      fi
    else
      wget -qO "${tmp}" --timeout=120 --tries=1 "${url}" 2>/dev/null || DL_FAIL="y"
    fi

    if [ "${DL_FAIL}" = "y" ] || [ ! -s "${tmp}" ]; then
      printf "  %s\n" "${gl_huang}[警告]${reset}" "下载失败：${url}"
      continue
    fi

    # 大小核对
    if [ "${DL_CURL}" = "y" ] && [ -f "${hdr}" ]; then
      expected="$(grep -i '^content-length:' "${hdr}" | tail -n 1 | tr -d '\r' | awk '{print $2}')"
      actual="$(stat -c%s "${tmp}" 2>/dev/null || echo 0)"
      if [ -n "${expected}" ] && [ "${actual}" != "${expected}" ]; then
        printf "  %s\n" "${gl_huang}[警告]${reset} 文件不完整（${actual}/${expected} 字节），跳过该源。"
        continue
      fi
    fi

    # 校验为 gzip 包（magic 1f 8b）
    magic="$(head -c2 "${tmp}" | od -An -tx1 | tr -d ' \n')"
    if [ "${magic}" != "1f8b" ]; then
      printf "  %s\n" "${gl_huang}[警告]${reset} 下载内容不是有效的 gzip 包，跳过该源。"
      continue
    fi

    BIN_TMP_ROOT="$(mktemp -d)"
    if tar -xzf "${tmp}" -C "${BIN_TMP_ROOT}" 2>/dev/null && [ -f "${BIN_TMP_ROOT}/index.php" ]; then
      mkdir -p "${APP_DIR}/scripts"
      rm -f "${tmp}" "${hdr}"
      ok "发布包已就绪（${gl_bai}${BIN_TMP_ROOT}${reset}）"
      BIN_SRC_DIR="${BIN_TMP_ROOT}"
      return 0
    fi
    printf "  %s\n" "${gl_huang}[警告]${reset}" "发布包解压失败或内容异常：${url}"
    rm -rf "${BIN_TMP_ROOT}"
    rm -f "${tmp}" "${hdr}"
  done
  rm -f "${tmp}" "${hdr}"
  printf "  %s\n" "${gl_huang}[警告]${reset} 所有源均下载失败/校验未通过，回退源码安装。"
  return 1
}

# ---- silent install detection ----
SILENT="n"
if [ -n "${PORT}" ]; then
  case "${PORT}" in
    ''|*[!0-9]*) error "PORT 无效（需为 1‑65535 的数字）: ${PORT}" ;;
    *) [ "${PORT}" -ge 1 ] && [ "${PORT}" -le 65535 ] || error "PORT 超出范围（1‑65535）: ${PORT}" ;;
  esac
  SILENT="y"
fi
[ -n "${DATA_DIR}" ] && SILENT="y"
[ -n "${SRC_DIR}" ] && SILENT="y"
[ ! -t 0 ] && SILENT="y"

section "配置参数"
# port prompt
if [ -z "${PORT}" ]; then
  if [ "$INSTALL_YES" = "1" ] || [ ! -t 0 ]; then
    PORT="${DEFAULT_PORT}"
  else
    while :; do
      read -r -p "${gl_bai}请输入监听端口${reset} ${gl_hui}[默认: ${DEFAULT_PORT}]${reset}: " PORT
      PORT="${PORT:-$DEFAULT_PORT}"
      case "$PORT" in
        ''|*[!0-9]*) printf "  %s\n" "${gl_huang}端口无效，请重新输入。${reset}" ;;
        *)
          if [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then break; fi
          printf "  %s\n" "${gl_huang}端口超出范围（1‑65535），请重新输入。${reset}"
          ;;
      esac
    done
  fi
else
  printf "  %-14s %s\n" "${gl_lan}监听端口${reset}" "${gl_bai}${PORT}${reset}（参数指定）"
fi
PORT="${PORT:-$DEFAULT_PORT}"

# data dir prompt
if [ -z "${DATA_DIR}" ]; then
  if [ "$INSTALL_YES" = "1" ] || [ ! -t 0 ]; then
    DATA_DIR="${DEFAULT_DATA_DIR}"
  else
    read -r -p "${gl_bai}请输入数据目录${reset} ${gl_hui}[默认: ${DEFAULT_DATA_DIR}]${reset}: " DATA_DIR
    DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"
  fi
else
  printf "  %-14s %s\n" "${gl_lan}数据目录${reset}" "${gl_bai}${DATA_DIR}${reset}（参数指定）"
fi

# 数据目录不得与安装目录相同，否则 config/i 软链会自引用（环形），自动纠正为 data 子目录
if [ "${DATA_DIR}" = "${APP_DIR}" ] || [ "${DATA_DIR}" = "${APP_DIR}/" ]; then
  printf "  %s\n" "${gl_huang}[提示]${reset} 数据目录不能与安装目录相同，已自动使用 ${gl_bai}${APP_DIR}/data${reset}"
  DATA_DIR="${APP_DIR}/data"
fi
DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"

# 安装程序获取
BIN_SRC_DIR=""
if [ "${INSTALL_METHOD}" = "binary" ]; then
  if ! install_binary; then
    if [ "${BINARY_MODE}" = "force" ]; then
      error "发布包安装失败（-b 强制发布包模式），可用 -s 指定源码目录重新安装"
    fi
    printf "  %s\n" "${gl_huang}[警告]${reset} 预编译发布包获取失败，回退为源码安装。"
    INSTALL_METHOD="source"
  fi
fi

if [ "${INSTALL_METHOD}" = "source" ]; then
  SRC_DIR="${SRC_DIR:-$DEFAULT_SRC_DIR}"
  if ! is_valid_src "${SRC_DIR}"; then
    if [ "${SRC_DIR_EXPLICIT}" != "1" ]; then
      DISCOVERED_SRC="$(resolve_local_src)" || true
      if [ -n "${DISCOVERED_SRC:-}" ]; then
        ok "已从仓库目录发现本地源码 ${gl_bai}${DISCOVERED_SRC}${reset}"
        SRC_DIR="${DISCOVERED_SRC}"
      fi
    fi
  fi
  if ! is_valid_src "${SRC_DIR}"; then
    if [ "${SRC_DIR_EXPLICIT}" = "1" ]; then
      error "未找到源码仓库 ${SRC_DIR}（-s 显式指定，需包含 index.php 与 app/ 目录）"
    fi
    ok "本地无源码仓库，尝试获取源码（可用环境变量 FAN_IMAGEHOST_REPO 自定义仓库地址）"
    TMP_ROOT="$(mktemp -d)"
    TMP_SRC="${TMP_ROOT}/fan-imagehost"

    REPO_CANDIDATES=()
    [ -n "${FAN_IMAGEHOST_REPO:-}" ] && REPO_CANDIDATES+=("${FAN_IMAGEHOST_REPO}")
    while IFS= read -r u; do
      REPO_CANDIDATES+=("$u")
    done < <(make_url_candidates "${GITHUB_REPO}")

    FETCHED="n"
    if command -v timeout >/dev/null 2>&1; then CLONE_TIMEOUT="timeout 90"; else CLONE_TIMEOUT=""; fi

    if command -v git >/dev/null 2>&1; then
      for repo in "${REPO_CANDIDATES[@]}"; do
        [ -n "${repo}" ] || continue
        skip "尝试 git clone ${gl_bai}${repo}${reset}"
        if ${CLONE_TIMEOUT} git clone --depth=1 "${repo}" "${TMP_SRC}" 2>"${TMP_ROOT}/clone.err"; then
          FETCHED="y"
          break
        fi
        printf "  %s %s\n" "${gl_huang}[警告]${reset}" "克隆失败：$(tail -n 1 "${TMP_ROOT}/clone.err" 2>/dev/null)"
        rm -rf "${TMP_SRC}"
      done
    else
      printf "  %s %s\n" "${gl_huang}[警告]${reset}" "未检测到 git，跳过 git clone，改用源码压缩包"
    fi

    # 回退：下载源码压缩包并解压
    if [ "${FETCHED}" != "y" ]; then
      ARCHIVE_URLS=()
      while IFS= read -r u; do
        ARCHIVE_URLS+=("$u")
      done < <(make_url_candidates "https://github.com/meimolihan/fan-imagehost/archive/refs/heads/main.tar.gz")
      ARCHIVE_URLS+=("https://codeload.github.com/meimolihan/fan-imagehost/tar.gz/refs/heads/main")

      if command -v curl >/dev/null 2>&1; then
        DL_CMD="curl -fsSL --connect-timeout 10 --max-time 120"
      elif command -v wget >/dev/null 2>&1; then
        DL_CMD="wget -qO- --timeout=120 --tries=1"
      else
        DL_CMD=""
      fi
      for url in "${ARCHIVE_URLS[@]}"; do
        [ -n "${url}" ] || continue
        [ -n "${DL_CMD}" ] || break
        skip "尝试下载源码包 ${gl_bai}${url}${reset}"
        TMP_TGZ="${TMP_ROOT}/src.tar.gz"
        if ${DL_CMD} "${url}" > "${TMP_TGZ}" 2>/dev/null \
          && tar -xzf "${TMP_TGZ}" -C "${TMP_ROOT}" 2>/dev/null; then
          EXTRACTED="$(find "${TMP_ROOT}" -maxdepth 1 -type d -name 'fan-imagehost-*' -print -quit 2>/dev/null)"
          if [ -n "${EXTRACTED}" ]; then
            mv "${EXTRACTED}" "${TMP_SRC}"
            FETCHED="y"
            break
          fi
        fi
        printf "  %s %s\n" "${gl_huang}[警告]${reset}" "下载失败：${url}"
        rm -f "${TMP_TGZ}"
      done
    fi

    [ "${FETCHED}" = "y" ] || error "获取源码仓库失败，请检查服务器网络，或使用 -s 指定本地源码目录"
    SRC_DIR="${TMP_SRC}"
    ok "已获取源码仓库"
  fi
fi

if command -v systemctl >/dev/null 2>&1; then
  USE_SYSTEMD="y"
else
  USE_SYSTEMD="n"
  printf "  %s\n" "${gl_huang}[警告]${reset} 未检测到 systemd（容器或受限环境）。"
  printf "  %s\n" "${gl_hui}    已回退为后台运行模式，重启或崩溃后服务不会自动恢复。${reset}"
fi

sep_line
section "安装程序"
ok "正在安装 ${gl_bai}${APP_NAME}${reset} 程序 ${gl_hong}.${gl_huang}.${gl_lv}.${gl_bai}"

# 拷贝程序文件到安装目录（排除开发/文档/仓库元数据）
copy_app() {
  local src="$1"
  mkdir -p "${APP_DIR}"
  # 清理旧程序文件（保留数据目录、运维脚本与备份目录）
  find "${APP_DIR}" -mindepth 1 -maxdepth 1 \
    ! -name 'data' ! -name 'scripts' ! -name 'backup' \
    -exec rm -rf {} + 2>/dev/null || true
  tar -C "${src}" \
    --exclude='./.git' --exclude='./.github' --exclude='./docs' \
    --exclude='./node_modules' --exclude='./scripts' \
    --exclude='./docker' --exclude='./Dockerfile' \
    --exclude='./docker-compose.yml' --exclude='./.dockerignore' \
    -cf - . | tar -C "${APP_DIR}" -xf -
}

DEPLOY_SRC=""
if [ "${INSTALL_METHOD}" = "binary" ]; then
  DEPLOY_SRC="${BIN_SRC_DIR}"
  ok "使用预编译发布包：${gl_bai}${RELEASE_ASSET}${reset}（版本 ${gl_lan}${BIN_VER}${reset}）"
else
  DEPLOY_SRC="${SRC_DIR}"
  ok "使用源码目录：${gl_bai}${SRC_DIR}${reset}"
fi

is_valid_src "${DEPLOY_SRC}" || error "程序文件不完整：${DEPLOY_SRC}（需包含 index.php 与 app/ 目录）"
copy_app "${DEPLOY_SRC}"
ok "已拷贝程序文件至 ${gl_bai}${APP_DIR}${reset}"

# 部署运维脚本（备份/还原/卸载/路由器/CLI）
mkdir -p "${APP_DIR}/scripts"
if [ "${INSTALL_METHOD}" = "source" ] && [ -d "${SRC_DIR}/scripts" ]; then
  cp -rf "${SRC_DIR}/scripts/." "${APP_DIR}/scripts/"
elif [ -d "${SCRIPT_DIR}" ]; then
  cp -f "${SCRIPT_DIR}/fan-imagehost_backup.sh" "${APP_DIR}/scripts/" 2>/dev/null || true
  cp -f "${SCRIPT_DIR}/fan-imagehost_recover.sh" "${APP_DIR}/scripts/" 2>/dev/null || true
  cp -f "${SCRIPT_DIR}/uninstall.sh" "${APP_DIR}/scripts/" 2>/dev/null || true
  cp -f "${SCRIPT_DIR}/fan-imagehost-cli.sh" "${APP_DIR}/scripts/" 2>/dev/null || true
  cp -f "${SCRIPT_DIR}/router.php" "${APP_DIR}/scripts/" 2>/dev/null || true
fi

# 从远端拉取单个脚本（走加速镜像，并校验内容特征）
fetch_remote_script() {
  local name="$1" dest="$2" marker="$3" url_tmp=""
  [ -s "${dest}" ] && return 0
  url_tmp="$(mktemp)"
  local cands=()
  mapfile -t cands < <(make_url_candidates "https://raw.githubusercontent.com/${GITHUB_BIN_REPO}/main/scripts/${name}")
  local u
  for u in "${cands[@]}"; do
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --connect-timeout 10 --max-time 60 "${u}" > "${url_tmp}" 2>/dev/null || { rm -f "${url_tmp}"; continue; }
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "${url_tmp}" --timeout=60 --tries=1 "${u}" 2>/dev/null || { rm -f "${url_tmp}"; continue; }
    else
      break
    fi
    if [ -s "${url_tmp}" ] && grep -q "${marker}" "${url_tmp}"; then
      mv -f "${url_tmp}" "${dest}"
      return 0
    fi
    rm -f "${url_tmp}"
  done
  rm -f "${url_tmp}"
  return 1
}

# 预编译发布包场景下脚本可能缺失，尝试从远端补下
fetch_remote_script fan-imagehost_backup.sh  "${APP_DIR}/scripts/fan-imagehost_backup.sh"  '#!/bin/bash' || true
fetch_remote_script fan-imagehost_recover.sh "${APP_DIR}/scripts/fan-imagehost_recover.sh" '#!/bin/bash' || true
fetch_remote_script uninstall.sh             "${APP_DIR}/scripts/uninstall.sh"             '#!/usr/bin/env bash' || true
fetch_remote_script fan-imagehost-cli.sh     "${APP_DIR}/scripts/fan-imagehost-cli.sh"     '#!/usr/bin/env bash' || true
fetch_remote_script router.php               "${APP_DIR}/router.php"                       '<?php' || true
chmod +x "${APP_DIR}"/scripts/*.sh 2>/dev/null || true

# 路由器（php -S 运行方式下拦截内部目录）；本地有则优先用本地
if [ ! -f "${APP_DIR}/router.php" ] && [ -f "${APP_DIR}/scripts/router.php" ]; then
  cp -f "${APP_DIR}/scripts/router.php" "${APP_DIR}/router.php"
fi
if [ ! -f "${APP_DIR}/router.php" ] && [ -f "${SCRIPT_DIR}/router.php" ]; then
  cp -f "${SCRIPT_DIR}/router.php" "${APP_DIR}/router.php" 2>/dev/null || true
fi
if [ ! -f "${APP_DIR}/router.php" ]; then
  warn "未获取到 router.php，php -S 将以根目录直接运行（建议手动放置以增强安全性）。"
fi
ok "已部署运维脚本至 ${gl_bai}${APP_DIR}/scripts${reset}"

# 数据目录 & 软链接（数据与程序分离，便于备份/还原）
mkdir -p "${DATA_DIR}" "${DATA_DIR}/config" "${DATA_DIR}/i"
if [ ! -f "${DATA_DIR}/config/config.php" ] && [ -f "${APP_DIR}/config/config.php" ]; then
  cp -rf "${APP_DIR}/config/." "${DATA_DIR}/config/"
fi
if [ ! -f "${DATA_DIR}/i/index.html" ] && [ -f "${APP_DIR}/i/index.html" ]; then
  cp -rf "${APP_DIR}/i/." "${DATA_DIR}/i/"
fi
rm -rf "${APP_DIR}/config" "${APP_DIR}/i"
ln -sfn "${DATA_DIR}/config" "${APP_DIR}/config"
ln -sfn "${DATA_DIR}/i" "${APP_DIR}/i"
chmod 700 "${DATA_DIR}"
ok "数据目录 ${gl_lan}${DATA_DIR}${reset} 已就绪（config 与 i $( [ "${DATA_DIR}" = "${APP_DIR}/data" ] && echo "即为数据目录" || echo "软链至数据目录" )）"

# 首次安装：自动完成初始化（写入站点域名与管理员账号，生成 install.lock）
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "${IP}" ] && IP="<服务器IP>"
ADMIN_USER="${FAN_IMAGEHOST_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${FAN_IMAGEHOST_ADMIN_PASSWORD:-admin@123}"
SITE_URL="${FAN_IMAGEHOST_DOMAIN:-http://${IP}:${PORT}}"

AUTOINSTALLED="n"
if [ ! -f "${DATA_DIR}/config/install.lock" ]; then
  AUTO_PHP="$(mktemp)"
  cat > "${AUTO_PHP}" <<'PHP'
<?php
$root = $argv[1];
$url  = $argv[2];
$user = $argv[3];
$pass = $argv[4];
require $root . '/app/function.php';
$config['domain']   = $url;
$config['imgurl']   = $url;
$config['user']     = $user;
$config['password'] = password_hash($pass, PASSWORD_DEFAULT);
cache_write(APP_ROOT . '/config/config.php', $config);
file_put_contents(APP_ROOT . '/config/install.lock', '安装程序锁定文件。');
echo "ok";
PHP
  if "${PHP_BIN}" "${AUTO_PHP}" "${APP_DIR}" "${SITE_URL}" "${ADMIN_USER}" "${ADMIN_PASSWORD}" >/dev/null 2>&1; then
    AUTOINSTALLED="y"
    ok "已自动完成初始化：站点地址 ${gl_bai}${SITE_URL}${reset}"
  else
    warn "自动初始化未成功，请打开 http://${IP}:${PORT}/install/ 按向导完成安装。"
  fi
  rm -f "${AUTO_PHP}"
else
  skip "检测到已安装（install.lock 存在），保留原有配置。"
fi

# 安装记录
mkdir -p "$(dirname "${CONFIG_FILE}")"
cat > "${CONFIG_FILE}" <<EOF
# ${APP_NAME} 安装记录（由 install.sh 生成，请勿手动修改）
APP_DIR=${APP_DIR}
PORT=${PORT}
DATA_DIR=${DATA_DIR}
BACKUP_DIR=${APP_DIR}/backup
INSTALL_METHOD=${INSTALL_METHOD}
PHP_BIN=${PHP_BIN}
VERSION=${BIN_VER}
EOF
chmod 0644 "${CONFIG_FILE}"
ok "已写入安装记录 ${gl_bai}${CONFIG_FILE}${reset}"

# 安装内置 CLI 命令
mkdir -p "$(dirname "${CLI_BIN}")"
if [ -f "${APP_DIR}/scripts/fan-imagehost-cli.sh" ]; then
  cp -f "${APP_DIR}/scripts/fan-imagehost-cli.sh" "${CLI_BIN}"
elif [ -f "${SCRIPT_DIR}/fan-imagehost-cli.sh" ]; then
  cp -f "${SCRIPT_DIR}/fan-imagehost-cli.sh" "${CLI_BIN}"
fi
if [ -f "${CLI_BIN}" ]; then
  chmod +x "${CLI_BIN}"
  ok "已安装命令 ${gl_bai}${CLI_BIN}${reset}（运行 ${gl_bai}${APP_NAME} help${reset} 查看用法）"
else
  warn "未找到 CLI 模板，跳过命令安装。"
fi

sep_line
section "启动服务"
if [ "${USE_SYSTEMD}" = "y" ]; then
  if [ -f "${APP_DIR}/router.php" ]; then
    EXEC_START="${PHP_BIN} -S 0.0.0.0:${PORT} -t ${APP_DIR} ${APP_DIR}/router.php"
  else
    EXEC_START="${PHP_BIN} -S 0.0.0.0:${PORT} -t ${APP_DIR}"
  fi
  cat > "${SERVICE_FILE}" <<UNIT
[Unit]
Description=${APP_NAME} - 简单图床（无数据库 PHP 图床）
After=network-online.target local-fs.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_START}
WorkingDirectory=${APP_DIR}
Environment=TZ=Asia/Shanghai
Restart=on-failure
RestartSec=3
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable "${APP_NAME}" >/dev/null 2>&1 || true
  systemctl restart "${APP_NAME}"
  sleep 3
  if systemctl is-active "${APP_NAME}" >/dev/null 2>&1; then
    ok "${gl_bai}${APP_NAME}${reset} 服务已启动。"
    systemctl status "${APP_NAME}" --no-pager || true
  else
    printf "  %s\n" "${gl_hong}[错误]${reset} 服务启动失败，请检查：${gl_bai}journalctl -u ${APP_NAME} -n 50${reset}" >&2
    exit 1
  fi
else
  if command -v pgrep >/dev/null 2>&1 && pgrep -f "${APP_DIR}" >/dev/null 2>&1; then
    printf "  %s\n" "${gl_huang}[警告]${reset} 检测到 ${APP_NAME} 进程可能已在运行"
  else
    if [ -f "${APP_DIR}/router.php" ]; then
      nohup "${PHP_BIN}" -S "0.0.0.0:${PORT}" -t "${APP_DIR}" "${APP_DIR}/router.php" >> "${DATA_DIR}/${APP_NAME}.log" 2>&1 &
    else
      nohup "${PHP_BIN}" -S "0.0.0.0:${PORT}" -t "${APP_DIR}" >> "${DATA_DIR}/${APP_NAME}.log" 2>&1 &
    fi
    ok "${APP_NAME} 已在后台启动，pid: ${gl_bai}$!${reset}"
  fi
fi

print_credentials() {
  local conf="${DATA_DIR}/config/config.php" user=""
  [ -f "${conf}" ] && user=$(grep -oE "'user'[[:space:]]*=>[[:space:]]*'[^']*'" "${conf}" | head -n1 | sed -E "s/.*'([^']*)'$/\1/")
  printf "  %s\n" "${gl_lv}✔ 登录信息${reset}"
  printf "  %-14s %s\n" "${gl_lan}用户名${reset}" "${gl_bai}${user:-$ADMIN_USER}${reset}"
  if [ "${AUTOINSTALLED}" = "y" ]; then
    printf "  %-14s %s\n" "${gl_lan}密码${reset}" "${gl_bai}${ADMIN_PASSWORD}${reset}"
  else
    printf "  %-14s %s\n" "${gl_lan}密码${reset}" "${gl_hui}已安装，请使用原管理员密码${reset}"
  fi
}

open_firewall_port "${PORT}"
if [ "${FW_OPENED}" = "y" ]; then
  FW_STATUS="${gl_lv}已开放 ${PORT}/tcp${reset}"
else
  FW_STATUS="${gl_huang}未检测到活跃防火墙，已跳过${reset}"
fi

if [ "${INSTALL_METHOD}" = "binary" ]; then
  METHOD_LABEL="预编译发布包 ${BIN_VER#v}"
else
  METHOD_LABEL="源码安装"
fi

sep_line
if [ "${USE_SYSTEMD}" = "y" ]; then
  printf "  %s\n" "${gl_lv}✔ ${APP_NAME} 安装成功！${reset}"
  printf "  %-14s %s\n" "${gl_lan}访问地址${reset}" "${gl_bai}http://${IP}:${PORT}${reset}"
  printf "  %-14s %s\n" "${gl_lan}后台地址${reset}" "${gl_bai}http://${IP}:${PORT}/admin/${reset}"
  printf "  %-14s %s\n" "${gl_lan}数据目录${reset}" "${gl_bai}${DATA_DIR}${reset}"
  printf "  %-14s %s\n" "${gl_lan}程序目录${reset}" "${gl_bai}${APP_DIR}${reset}"
  printf "  %-14s %s\n" "${gl_lan}安装方式${reset}" "${gl_bai}${METHOD_LABEL}${reset}"
  printf "  %-14s %s\n" "${gl_lan}防火墙状态${reset}" "$FW_STATUS"
  printf "  %-14s %s\n" "${gl_lan}运行模式${reset}" "${gl_bai}systemd 服务（php -S）${reset}"
  printf "  %-14s %s\n" "${gl_lan}服务命令${reset}" "${gl_hui}systemctl status ${APP_NAME}${reset}"
  printf "  %-14s %s\n" "${gl_lan}升级方式${reset}" "${gl_hui}重新执行 scripts/install.sh（数据自动保留）${reset}"
else
  printf "  %s\n" "${gl_lv}✔ ${APP_NAME} 安装成功！${reset} ${gl_huang}（后台运行模式）${reset}"
  printf "  %-14s %s\n" "${gl_lan}访问地址${reset}" "${gl_bai}http://${IP}:${PORT}${reset}"
  printf "  %-14s %s\n" "${gl_lan}数据目录${reset}" "${gl_bai}${DATA_DIR}${reset}"
  printf "  %-14s %s\n" "${gl_lan}程序目录${reset}" "${gl_bai}${APP_DIR}${reset}"
  printf "  %-14s %s\n" "${gl_lan}安装方式${reset}" "${gl_bai}${METHOD_LABEL}${reset}"
  printf "  %s\n" "  ${gl_huang}注意：${reset}后台运行模式在系统重启后不会自动恢复。"
fi

skip "读取登录信息 ..."
print_credentials
sep_line
