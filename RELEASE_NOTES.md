修复全新安装无法登录（SHA256 密码存储）与 Docker 登录跳转（output_buffering）

```bash
docker pull mobufan/fan-imagehost:latest
```
```bash
docker pull mobufan/fan-imagehost:v0.0.3
```

```bash
docker pull ghcr.io/meimolihan/fan-imagehost:latest
```
```bash
docker pull ghcr.io/meimolihan/fan-imagehost:v0.0.3
```

## 一键脚本安装
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/fan-imagehost/main/scripts/install.sh)" -p 8083 -d /var/lib/fan-imagehost
```

## 一键脚本卸载
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/fan-imagehost/main/scripts/uninstall.sh)" -y --purge
```
