#!/usr/bin/env bash
# Smart10u · 酷态科 10 号 Ultra 本地 BLE 面板 · macOS 一键安装
#
#   curl -fsSL https://raw.githubusercontent.com/sdlyingyong/Smart10u/main/install.sh | bash
#
# 可覆盖：
#   CUKTECH_INSTALL_DIR  安装目录（默认 ~/.smart10u）
#   CUKTECH_PORT         Web 端口（默认 8199）
#   CUKTECH_SKIP_START=1 只安装不启动
set -euo pipefail

REPO="https://github.com/sdlyingyong/smart10u"
TARBALL="$REPO/archive/refs/heads/main.tar.gz"
APP_NAME="Smart10u"
PORT="${CUKTECH_PORT:-8199}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "只支持 macOS。Linux 请直接用上游项目的 Docker 部署。"

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/ha_server.py" ] && [ -f "$SCRIPT_DIR/pyproject.toml" ]; then
  INSTALL_DIR="$SCRIPT_DIR"
  info "使用当前目录：$INSTALL_DIR"
else
  INSTALL_DIR="${CUKTECH_INSTALL_DIR:-$HOME/.smart10u}"
  info "下载 Smart10u 到：$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  TMP="$(mktemp -t smart10u)"
  curl -fL --retry 2 --max-time 180 "$TARBALL" -o "$TMP" || die "下载失败：检查网络，或先 git clone 再运行 ./install.sh"
  tar -xzf "$TMP" -C "$INSTALL_DIR" --strip-components=1
  rm -f "$TMP"
fi

# app 要落在 Launchpad / Spotlight 会扫的目录，而不是安装目录。
# 之前建在 ~/.smart10u/ 这种隐藏目录里，结果是：Finder 里看不见、启动台没有、
# Spotlight 也搜不到（隐藏目录不建索引），只能靠命令行 open 才能起来。
APP_DIR=""
if [ -w /Applications ]; then
  APP_DIR="/Applications"
elif mkdir -p "$HOME/Applications" 2>/dev/null; then
  APP_DIR="$HOME/Applications"
else
  APP_DIR="$INSTALL_DIR"
  warn "没有可写的 Applications 目录，app 留在 $INSTALL_DIR（启动台里可能看不到）"
fi
[ -n "$APP_DIR" ] || die "无法确定 app 安装目录"
APP="$APP_DIR/$APP_NAME.app"
# 覆盖旧版本前先确认目标确实是一个 app bundle（或指向它的软链接），
# 避免路径异常时误删别的东西。
if [ -L "$APP" ]; then
  rm -f "$APP"
elif [ -d "$APP" ] && [ -f "$APP/Contents/Info.plist" ]; then
  info "覆盖已有的 $APP"
  rm -rf "$APP"
fi

PY=""
for c in python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v "$c" >/dev/null 2>&1 &&
     "$c" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    PY="$c"; break
  fi
done
[ -n "$PY" ] || die "需要 Python 3.10+：brew install python@3.12"

info "准备 Python 虚拟环境"
[ -x "$INSTALL_DIR/.venv/bin/python" ] || "$PY" -m venv "$INSTALL_DIR/.venv"
VPY="$INSTALL_DIR/.venv/bin/python"
"$VPY" -m pip install -q --upgrade pip >/dev/null 2>&1 || true
if ! "$VPY" -m pip install -q -e "$INSTALL_DIR" >/dev/null 2>&1; then
  warn "PyPI 直连失败，改用清华镜像"
  "$VPY" -m pip install -q -i https://pypi.tuna.tsinghua.edu.cn/simple -e "$INSTALL_DIR"
fi

info "生成本地配置（仅监听 127.0.0.1，MQTT 默认关闭）"
if [ ! -f "$INSTALL_DIR/config.yaml" ]; then
  cp "$INSTALL_DIR/config.yaml.example" "$INSTALL_DIR/config.yaml"
  "$VPY" - "$INSTALL_DIR/config.yaml" <<'PY'
import sys
import yaml

path = sys.argv[1]
with open(path) as f:
    cfg = yaml.safe_load(f) or {}
cfg.setdefault("ble", {})
cfg.setdefault("mqtt", {})["enabled"] = False
cfg.setdefault("server", {})["host"] = "127.0.0.1"
with open(path, "w") as f:
    yaml.safe_dump(cfg, f, allow_unicode=True, sort_keys=False)
PY
else
  info "保留已有 config.yaml（不覆盖凭据）"
fi

info "构建 $APP_NAME.app（声明蓝牙用途，避免 macOS TCC 直接终止进程）"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIdentifier</key><string>local.smart10u.bridge</string>
  <key>CFBundleName</key><string>Smart10u</string>
  <key>CFBundleDisplayName</key><string>Smart10u</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>2.0.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>连接并读取附近的酷态科充电器功率数据</string>
  <key>NSBluetoothPeripheralUsageDescription</key><string>连接并读取附近的酷态科充电器功率数据</string>
  <key>NSBluetoothUsageDescription</key><string>连接并读取附近的酷态科充电器功率数据</string>
</dict>
</plist>
PLIST

if [ -f "$INSTALL_DIR/assets/AppIcon.icns" ]; then
  cp "$INSTALL_DIR/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
  warn "缺少 assets/AppIcon.icns，应用图标将退回系统默认"
fi

cat > "$APP/Contents/MacOS/launcher" <<LAUNCH
#!/bin/bash
# Smart10u 启动器
#   双击：服务已在跑 → 只把面板叫出来；未在跑 → 起服务，就绪后自动打开面板
#   --silent：只起服务不弹面板（给开机自启用）
APP_DIR="$INSTALL_DIR"
PORT=$PORT
URL="http://127.0.0.1:\$PORT/"
HEALTH="http://127.0.0.1:\$PORT/api/health"
SILENT=0

cd "\$APP_DIR" || exit 1

# --noproxy '*' 不能省：系统若注入 http_proxy，localhost 会被绕去代理然后超时
probe_health() { curl -fsS --noproxy '*' --max-time 2 "\$HEALTH" >/dev/null 2>&1; }

if [ "\$1" = "--silent" ] || [ "\$1" = "-s" ]; then
  SILENT=1
fi

# 已在运行就不再起第二个进程（会抢 BLE 和端口），只打开面板
if probe_health; then
  [ "\$SILENT" = "1" ] || open "\$URL"
  exit 0
fi

# 就绪后自动打开面板。必须放后台：下面 exec 会把当前进程换成服务本体。
# 只等 /api/health 通，不等 BLE 认证（还要几秒）——让界面先出来，
# 连接进度由面板自己显示（页头徽标会走 扫描中 / 连接中 / 认证中）。
if [ "\$SILENT" = "0" ]; then
  (
    for i in {1..90}; do
      sleep 1
      if probe_health; then
        open "\$URL"
        exit 0
      fi
    done
  ) &
fi

exec "$VPY" -u "\$APP_DIR/ha_server.py" >> "\$APP_DIR/server.console.log" 2>&1
LAUNCH
chmod +x "$APP/Contents/MacOS/launcher"
codesign -s - -f --deep "$APP" >/dev/null 2>&1 || warn "ad-hoc 签名失败，通常仍可运行"

if [ "${CUKTECH_SKIP_START:-0}" = "1" ]; then
  info "已跳过启动（CUKTECH_SKIP_START=1）"
  exit 0
fi

if pgrep -f "$INSTALL_DIR/ha_server.py" >/dev/null 2>&1; then
  info "停止已在运行的服务"
  pkill -f "$INSTALL_DIR/ha_server.py" || true
  sleep 2
fi

info "启动服务"
open "$APP" || die "启动失败：请在桌面会话中运行，或手动双击 $APP"

for _ in $(seq 1 30); do
  if curl -fsS --noproxy '*' --max-time 2 "http://127.0.0.1:$PORT/api/status" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

cat <<EOF

安装完成。

以后就用这个 app：$APP
  双击它 —— 服务没在跑就起服务并等就绪，已经在跑就直接把面板叫出来。
  已经放在上面这个位置，启动台 / Finder 里都能直接找到。

第一次还要做 3 件事：
  1. 若弹出「$APP_NAME 想使用蓝牙」，点“允许”；
     没弹窗就去 系统设置 → 隐私与安全性 → 蓝牙 里打开 $APP_NAME。
  2. 打开 http://127.0.0.1:$PORT/config.html
     点「小米云自动获取」→ 用米家 App 扫码 → 勾选充电头 → 保存并重启。
  3. 彻底退出米家 App（BLE 同一时间只允许一个连接）。

面板    http://127.0.0.1:$PORT/
应用    $APP
配置    $INSTALL_DIR/config.yaml
日志    $INSTALL_DIR/server.console.log
EOF
