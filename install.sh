#!/usr/bin/env bash
# Installer and Chinese UI: MIT. LibreSpeed itself retains its upstream license.
set -Eeuo pipefail
umask 022

VERSION=1.1.6
PORT=8080
BASE=/opt/librespeed-oneclick
UNIT=/etc/systemd/system/librespeed-oneclick.service
SERVICE=librespeed-oneclick
UNINSTALL=false
log() { printf '\n%s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'HELP'
用法：sudo bash install.sh [--port 8080] [--version 1.1.6]
      sudo bash install.sh --uninstall
支持：使用 systemd 的 Linux，x86_64 / ARM64。
默认使用已验证的 LibreSpeed Go 1.1.6。重复执行会重新部署并应用指定端口。
HELP
}
while (($#)); do
  case "$1" in
    --port|--version)
      (($# >= 2)) || die "$1 缺少参数"
      if [[ $1 == --port ]]; then PORT=$2; else VERSION=${2#v}; fi
      shift 2 ;;
    --uninstall) UNINSTALL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done
[[ $PORT =~ ^[0-9]{1,5}$ ]] || die '端口必须为数字'
PORT=$((10#$PORT))
((PORT >= 1024 && PORT <= 65535)) || die '端口范围为 1024–65535'
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die '版本格式应为 1.1.6'
[[ $(uname -s) == Linux ]] || die '请在 Linux VPS 上运行'
((EUID == 0)) || die '请使用 root 或 sudo 运行'
command -v systemctl >/dev/null && [[ -d /run/systemd/system ]] || die '需要正在运行的 systemd'

# Refuse to overwrite/delete files that are not owned by this installer.
if [[ -e $BASE || -L $BASE ]]; then
  [[ -d $BASE && ! -L $BASE && -f $BASE/.oneclick-managed ]] || die "$BASE 已存在，且不是本脚本管理的目录"
fi
if [[ -e $UNIT || -L $UNIT ]]; then
  [[ ! -L $UNIT ]] && grep -qx '# Managed by librespeed-oneclick' "$UNIT" || die "$UNIT 已存在，且不是本脚本管理的服务"
elif systemctl cat "$SERVICE" >/dev/null 2>&1; then
  die '存在同名服务，请先处理后再安装'
fi
if $UNINSTALL; then
  if [[ ! -e $BASE && ! -e $UNIT ]]; then log '未发现本脚本安装的服务。'; exit 0; fi
  systemctl disable --now "$SERVICE" 2>/dev/null || true
  rm -f "$UNIT"
  rm -rf -- "$BASE"
  systemctl daemon-reload
  log '已卸载 LibreSpeed Oneclick；其他服务不受影响。'
  exit 0
fi

case $(uname -m) in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die '目前支持 x86_64 和 ARM64' ;;
esac
for cmd in curl tar sha256sum awk ss; do
  command -v "$cmd" >/dev/null || die "缺少 $cmd。Debian/Ubuntu 请先执行：apt-get update && apt-get install -y curl ca-certificates tar coreutils iproute2"
done
LISTENERS=$(ss -H -lntp "sport = :$PORT")
if [[ -n $LISTENERS ]]; then
  OWN_PID=$(systemctl show "$SERVICE" -p MainPID --value 2>/dev/null || true)
  [[ ${OWN_PID:-0} != 0 && $LISTENERS == *"pid=$OWN_PID,"* ]] || die "端口 $PORT 已被占用，请用 --port 指定其他端口"
fi

TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
trap 'printf "安装失败。可用 journalctl -u librespeed-oneclick -n 30 查看服务日志。\n" >&2' ERR
ASSET="speedtest-go_${VERSION}_linux_${ARCH}.tar.gz"
RELEASE="https://github.com/librespeed/speedtest-go/releases/download/v$VERSION"
download() { curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 180 "$1" -o "$2"; }
log "下载 LibreSpeed Go $VERSION ($ARCH) 并验证 SHA256…"
download "$RELEASE/$ASSET" "$TMP/$ASSET"
download "$RELEASE/checksums.txt" "$TMP/checksums.txt"
HASH=$(awk -v file="$ASSET" '$2 == file {print $1}' "$TMP/checksums.txt")
[[ $HASH =~ ^[0-9a-fA-F]{64}$ ]] || die '官方校验清单中找不到对应文件'
(cd "$TMP" && printf '%s  %s\n' "$HASH" "$ASSET" | sha256sum -c -)
mkdir "$TMP/binary" "$TMP/source"
tar -xzf "$TMP/$ASSET" -C "$TMP/binary"
download "https://codeload.github.com/librespeed/speedtest-go/tar.gz/refs/tags/v$VERSION" "$TMP/source.tar.gz"
tar -xzf "$TMP/source.tar.gz" -C "$TMP/source" --strip-components=1
[[ -x $TMP/binary/speedtest-backend && -f $TMP/source/web/assets/speedtest.js && -f $TMP/source/web/assets/speedtest_worker.js ]] || die '上游发布目录结构发生变化，停止安装'

# Finish staging downloads before changing the running service.
mkdir -p "$BASE"
touch "$BASE/.oneclick-managed"
STAGE=$(mktemp -d "$BASE/release-${VERSION}.XXXXXX")
chmod 755 "$BASE" "$STAGE"
install -m 755 "$TMP/binary/speedtest-backend" "$STAGE/speedtest-backend"
cp -R "$TMP/source/web/assets" "$STAGE/assets"
cp "$TMP/binary/LICENSE" "$STAGE/LICENSE.librespeed"
find "$STAGE/assets" -type d -exec chmod 755 {} +
find "$STAGE/assets" -type f -exec chmod 644 {} +
cat > "$STAGE/assets/index.html" <<'HTML'
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>VPS 连接测速 · LibreSpeed</title>
<style>
:root{color-scheme:light}*{box-sizing:border-box}body{margin:0;background:#f5f7fb;color:#18243b;font-family:system-ui,sans-serif}main{max-width:780px;margin:8vh auto;padding:28px}h1{font-size:32px;margin-bottom:8px}p{color:#526079;line-height:1.8}.cards{display:grid;grid-template-columns:repeat(2,1fr);gap:16px;margin:28px 0}.card{background:white;border:1px solid #e3e8f0;border-radius:18px;padding:24px}.label{color:#526079}.value{display:block;font-size:40px;font-weight:650;margin:12px 0 4px}.unit{font-size:14px;color:#526079}button{border:0;border-radius:12px;background:#245cdb;color:white;padding:15px 30px;font-size:17px;cursor:pointer}button:focus-visible{outline:3px solid #8dabee;outline-offset:4px}#status{min-height:28px}footer{margin-top:32px;font-size:13px}a{color:#245cdb}@media(max-width:480px){main{padding:20px;margin:3vh auto}.card{padding:18px}.value{font-size:32px}}
</style>
<script src="speedtest.js"></script>
</head>
<body><main>
<h1>VPS 连接测速</h1><p>测量你的设备与 <strong id="server"></strong> 之间的连接速度。</p>
<div class="cards">
<div class="card"><span class="label">下载 · VPS → 本地</span><span class="value" id="download">—</span><span class="unit">Mbps</span></div>
<div class="card"><span class="label">上传 · 本地 → VPS</span><span class="value" id="upload">—</span><span class="unit">Mbps</span></div>
<div class="card"><span class="label">延迟</span><span class="value" id="ping">—</span><span class="unit">ms</span></div>
<div class="card"><span class="label">抖动</span><span class="value" id="jitter">—</span><span class="unit">ms</span></div>
</div>
<button id="start" type="button">开始测速</button><p id="status" role="status" aria-live="polite">准备就绪</p>
<p>Mbps ÷ 8 ≈ MB/s，例如 100 Mbps ≈ 12.5 MB/s。<br>测直连速度时，请关闭代理 / VPN，暂停其他下载。测速会消耗 VPS 流量。</p>
<footer>Powered by <a href="https://github.com/librespeed/speedtest-go">LibreSpeed</a> · 未启用测速记录</footer>
</main><script>
const el=id=>document.getElementById(id);
el('server').textContent=location.host;
const speedtest=new Speedtest();
speedtest.setParameter('telemetry_level','disabled');
speedtest.setParameter('getIp_ispInfo',false);
const format=value=>value!==''&&Number.isFinite(Number(value))?Number(value).toFixed(2):'—';
speedtest.onupdate=data=>{
  el('download').textContent=format(data.dlStatus);
  el('upload').textContent=format(data.ulStatus);
  el('ping').textContent=format(data.pingStatus);
  el('jitter').textContent=format(data.jitterStatus);
  el('status').textContent=({0:'正在连接…',1:'正在测试下载…',2:'正在测试延迟…',3:'正在测试上传…',4:'测速完成',5:'已停止'})[data.testState]||'正在测速…';
};
speedtest.onend=aborted=>{el('start').textContent='重新测速';el('status').textContent=aborted?'已停止':'测速完成';};
el('start').onclick=()=>{
  if(speedtest.getState()===3){speedtest.abort();return;}
  for(const id of ['download','upload','ping','jitter'])el(id).textContent='—';
  el('start').textContent='停止测速';el('status').textContent='正在连接…';
  try{speedtest.start();}catch(error){el('status').textContent='启动失败，请刷新页面重试';el('start').textContent='重新测速';}
};
</script></body></html>
HTML
cat > "$TMP/settings.toml" <<CONFIG
bind_address=""
listen_port=$PORT
proxyprotocol_port=0
server_lat=1
server_lng=1
ipinfo_api_key=""
assets_path="$BASE/current/assets"
statistics_password=""
redact_ip_addresses=true
database_type="none"
enable_tls=false
enable_http2=false
CONFIG
cat > "$TMP/service" <<SERVICEFILE
# Managed by librespeed-oneclick
[Unit]
Description=LibreSpeed Oneclick browser speed test
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
DynamicUser=yes
WorkingDirectory=$BASE
ExecStart=$BASE/current/speedtest-backend -c $BASE/settings.toml
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes

[Install]
WantedBy=multi-user.target
SERVICEFILE
OLD_TARGET=$(readlink "$BASE/current" 2>/dev/null || true)
if [[ -e $BASE/current && ! -L $BASE/current ]]; then die "$BASE/current 不是符号链接，停止安装"; fi
[[ ! -f $BASE/settings.toml ]] || cp "$BASE/settings.toml" "$TMP/old-settings.toml"
[[ ! -f $UNIT ]] || cp "$UNIT" "$TMP/old-service"
rollback() {
  log '新部署验证失败，回滚…'
  systemctl stop "$SERVICE" || true
  if [[ -n $OLD_TARGET ]]; then
    ln -sfn "$OLD_TARGET" "$BASE/current"
    cp "$TMP/old-settings.toml" "$BASE/settings.toml"
    cp "$TMP/old-service" "$UNIT"
    systemctl daemon-reload
    systemctl restart "$SERVICE" || true
  else
    systemctl disable "$SERVICE" 2>/dev/null || true
    rm -f "$UNIT" "$BASE/current" "$BASE/settings.toml"
    systemctl daemon-reload
  fi
  rm -rf -- "$STAGE"
}
ln -sfn "$STAGE" "$BASE/current"
install -m 644 "$TMP/settings.toml" "$BASE/settings.toml"
install -m 644 "$TMP/service" "$UNIT"
if ! systemctl daemon-reload || ! systemctl enable "$SERVICE" || ! systemctl restart "$SERVICE"; then
  rollback; die '服务启动失败'
fi
READY=false
for ((i=0;i<20;i++)); do
  if curl -fsS --noproxy '*' --max-time 2 "http://127.0.0.1:$PORT/" -o "$TMP/page" && grep -q 'VPS 连接测速' "$TMP/page" && curl -fsS --noproxy '*' --max-time 2 "http://127.0.0.1:$PORT/backend/empty.php" -o /dev/null; then READY=true; break; fi
  sleep 1
done
if ! $READY; then
  journalctl -u "$SERVICE" -n 20 --no-pager >&2 || true
  rollback; die '服务未通过健康检查'
fi
log "安装完成！浏览器打开：http://<VPS 公网 IP>:$PORT/"
log "请在服务商安全组/系统防火墙中放行 TCP $PORT。本脚本不会自动修改防火墙。"
log "查看状态：systemctl status $SERVICE"
log '重复部署会保留旧版本目录，卸载时统一移除。'
