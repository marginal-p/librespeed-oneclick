# LibreSpeed 一键部署

在 Linux VPS 上部署中文浏览器测速页面，测量**本地设备与这台 VPS 之间**的下载、上传速度、HTTP 延迟和抖动。无需 Docker、Nginx、PHP 或数据库。

使用 [LibreSpeed Go](https://github.com/librespeed/speedtest-go) 官方二进制及前端，默认固定为已验证的 **v1.1.6**，下载后核对官方 SHA256 校验清单。

## 一键安装

在 VPS 的 SSH 终端中执行：

```bash
curl -fL https://raw.githubusercontent.com/marginal-p/librespeed-oneclick/main/install.sh -o /tmp/librespeed-install.sh && sudo bash /tmp/librespeed-install.sh
```

若已登录 root，可以省略 `sudo`。完成后，在自己的电脑或手机浏览器打开：

```text
http://你的VPS公网IP:8080/
```

点击「开始测速」。**下载是 VPS → 本地，上传是本地 → VPS。** Mbps ÷ 8 ≈ MB/s，例如 100 Mbps ≈ 12.5 MB/s。

## 系统要求

- Linux，正在使用 systemd；CPU 为 x86_64 或 ARM64。
- root 或 sudo 权限；支持 DynamicUser 的 systemd（235+）。
- 已安装 Bash、curl、CA 证书、tar、coreutils、iproute2 等常用工具。
- 能够访问 GitHub、GitHub Releases 和 codeload.github.com。

Debian / Ubuntu 缺少依赖时：

```bash
sudo apt-get update && sudo apt-get install -y curl ca-certificates tar coreutils iproute2
```

脚本不会升级系统或自动修改软件源。旧系统若提示软件包 404，请先修复系统软件源。

## 更换端口与版本

```bash
sudo bash /tmp/librespeed-install.sh --port 8090
sudo bash /tmp/librespeed-install.sh --version 1.1.6 --port 8090
```

端口支持 1024–65535；占用时会停止安装。重复执行会部署新版本并重新生成配置，应用本次指定的端口（不指定时回到 8080）。其他上游版本需要自行验证兼容性。

## 运维与卸载

```bash
sudo systemctl status librespeed-oneclick
sudo systemctl restart librespeed-oneclick
sudo journalctl -u librespeed-oneclick -n 50 --no-pager
sudo bash /tmp/librespeed-install.sh --uninstall
```

程序目录：`/opt/librespeed-oneclick`。配置文件：`/opt/librespeed-oneclick/settings.toml`。服务文件：`/etc/systemd/system/librespeed-oneclick.service`。

自动开机启动，使用 systemd 动态普通用户运行。服务启动或健康检查失败时，脚本会尝试恢复上次部署。旧版本目录保留用于排查，卸载会删除本脚本的程序、配置、所有旧版本和服务；不会卸载其他 LibreSpeed 实例。

## 使用说明

- 放行安全组与系统防火墙中的测速端口 TCP 8080（或你选择的端口）。脚本只验证服务器本机访问，公网可达性还需浏览器确认。
- 默认监听所有网卡，通过 HTTP 提供公开测速页面；知道地址的任何人均可测速。每次测速会消耗 VPS 流量。
- 测直连速度时关闭代理 / VPN，暂停其他下载；开启代理后，测量的是经过代理的连接。
- 不记录测速结果，不启用统计数据库，中文首页不查询第三方 ISP 信息。
- 延迟是浏览器 HTTP 请求延迟，并非 ICMP ping；结果受本地 Wi-Fi、运营商路由、浏览器和 VPS 带宽影响。
- 若希望使用 HTTPS，可在外部反向代理中配置有效证书，并关闭缓存、压缩及请求缓冲，允许至少 20 MB 的上传请求体。

## 许可证

本仓库的安装脚本和自编中文首页使用 [MIT License](LICENSE)。下载的 LibreSpeed 程序与前端保留其 [LGPL-3.0 上游许可证](https://github.com/librespeed/speedtest-go/blob/v1.1.6/LICENSE)，安装目录保留上游许可证文件。本项目不是 LibreSpeed 官方项目。
