#!/bin/sh
# fan-imagehost 容器入口脚本
# 数据与程序分离：程序固化在镜像 /var/www/html，可变数据（config + i）落到数据卷。
# 首次启动时从镜像内置的默认文件初始化数据目录，随后以软链挂回程序目录。
set -e

APP_DIR="/var/www/html"
DATA_DIR="${FAN_IMAGEHOST_DATA_DIR:-/var/lib/fan-imagehost}"

mkdir -p "${DATA_DIR}/config" "${DATA_DIR}/i"

if [ ! -f "${DATA_DIR}/config/config.php" ]; then
  echo "[fan-imagehost] 初始化配置目录 -> ${DATA_DIR}/config"
  cp -a "${APP_DIR}/config/." "${DATA_DIR}/config/" 2>/dev/null || true
fi

if [ ! -f "${DATA_DIR}/i/index.html" ]; then
  echo "[fan-imagehost] 初始化上传目录 -> ${DATA_DIR}/i"
  cp -a "${APP_DIR}/i/." "${DATA_DIR}/i/" 2>/dev/null || true
fi

# 用数据目录软链替换程序内置目录，实现数据与程序分离（便于备份/还原）
rm -rf "${APP_DIR}/config" "${APP_DIR}/i"
ln -sfn "${DATA_DIR}/config" "${APP_DIR}/config"
ln -sfn "${DATA_DIR}/i" "${APP_DIR}/i"

# 内核 fs.protected_symlinks：进程用户须与目录属主一致，否则无法跟随软链
# 基础镜像 /var/www/html 为 1777(sticky)，且软链由 root 创建，故需去掉 sticky 并把软链属主改为 www-data
chmod 755 "${APP_DIR}"
chown -h www-data:www-data "${APP_DIR}/config" "${APP_DIR}/i"

chown -R www-data:www-data "${DATA_DIR}"

# 允许以参数覆盖默认命令
if [ "${1#-}" != "$1" ]; then
  set -- apache2-foreground "$@"
fi

exec "$@"
