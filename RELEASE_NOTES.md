移除默认百度统计脚本，消除控制台权限策略告警

```bash
docker pull mobufan/fan-imagehost:latest
```
```bash
docker pull mobufan/fan-imagehost:v0.0.4
```

```bash
docker pull ghcr.io/meimolihan/fan-imagehost:latest
```
```bash
docker pull ghcr.io/meimolihan/fan-imagehost:v0.0.4
```

## 一键脚本安装
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/fan-imagehost/main/scripts/install.sh)" -p 8083 -d /var/lib/fan-imagehost
```

## 一键脚本卸载
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/fan-imagehost/main/scripts/uninstall.sh)" -y --purge
```
