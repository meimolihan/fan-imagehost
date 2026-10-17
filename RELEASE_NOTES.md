修复 Docker 镜像安装环境检测（upload.php 可执行权限与 /i 可写）

```bash
docker pull mobufan/fan-imagehost:latest
```
```bash
docker pull mobufan/fan-imagehost:v0.0.2
```

```bash
docker pull ghcr.io/meimolihan/fan-imagehost:latest
```
```bash
docker pull ghcr.io/meimolihan/fan-imagehost:v0.0.2
```

## 一键脚本安装
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/fan-imagehost/main/scripts/install.sh)" -p 8083 -d /var/lib/fan-imagehost
```

## 一键脚本卸载
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/fan-imagehost/main/scripts/uninstall.sh)" -y --purge
```
