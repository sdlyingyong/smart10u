# Smart10u

酷态科 10 号 Ultra（AD1204U）本地 BLE 控制面板 · macOS 一键部署

实时查看四个接口的功率 / 电压 / 电流、识别充电协议、画功率曲线，切换场景模式、控制端口。全程本地蓝牙直连，不经过米家云。

> 非官方项目，与 CUKTECH 酷态科、小米无关联。设备型号 AD1204U，米家型号 `njcuk.fitting.ad1204`，固件 `2.1.2_0073` 实测通过。

![macOS](https://img.shields.io/badge/macOS-13%2B-black) ![Python](https://img.shields.io/badge/Python-3.10%2B-blue) ![License](https://img.shields.io/badge/license-MIT-green)

## 一句话安装

```bash
curl -fsSL https://raw.githubusercontent.com/sdlyingyong/smart10u/main/install.sh | bash
```

装到 `~/.smart10u`，自动建虚拟环境、生成带蓝牙用途声明的 `CuktechBridge.app`、启动服务。

也可以先 clone 再装：

```bash
git clone https://github.com/sdlyingyong/smart10u.git && cd Smart10u && ./install.sh
```

换目录或端口：

```bash
CUKTECH_INSTALL_DIR="$HOME/Apps/smart10u" CUKTECH_PORT=18199 ./install.sh
```

## 装完 3 步

1. **允许蓝牙**：首次启动若弹出「CuktechBridge 想使用蓝牙」，点允许；没弹窗就去 系统设置 → 隐私与安全性 → 蓝牙 打开它。
2. **扫码绑定**：打开 <http://127.0.0.1:8199/config.html> → 「小米云自动获取」→ 米家 App 扫码 → 勾选充电头 → 保存并重启。
3. **退出米家 App**：BLE 同一时间只允许一个连接，App 开着会把桥接挤掉。

之后面板在 <http://127.0.0.1:8199/>。

## 功能

- 四口实时 W / V / A，协议识别 PD / PPS / QC / SCP / UFCS / idle
- 总功率曲线：30 分钟 / 1 小时 / 2 小时 / 24 小时
- 场景模式：AI 智能 / 数码生态 / 极速单充 / 均衡输出
- 端口开关、协议开关、倒计时关闭、充电量限额（Wh 积分到阈值断电）
- SQLite 历史采样、充电会话、能量统计、CSV 导出
- 可选 MQTT，接 Home Assistant / 小爱同学（巴法云）
- 六套主题、手机版页面

## 为什么必须本地蓝牙

这台充电头是米家 **BLE 即用即连**设备，不是 Wi-Fi 设备：

- 实时功率不上米家云，云端没有可轮询的属性；
- 没做蓝牙网关子设备，多模网关 / 中枢网关转发不了；
- 米家 App 里的曲线是手机本地画的，不是云端历史。

唯一路径是本地单主 BLE 直连：

```
充电头 ──FE95 GATT──▶ 桥接进程 ──SSE / MQTT──▶ 浏览器 / Home Assistant
                        │
                        └── SQLite（原始帧 + 1Hz 采样 + Wh 积分）
```

协议要点（二次开发参考）：

| 环节 | 内容 |
|---|---|
| 扫描 | Service `0000fe95-0000-1000-8000-00805f9b34fb` |
| 认证 | `0x0010` / `0x0019`：mible v2，HKDF-SHA256 + HMAC 双向校验 |
| 数据 | `0x001A` 写 / `0x001B` 通知：AES-CCM-128 加密的 MIOT 属性帧 |
| 端口解码 | 4 字节 word：`V=b3/10`、`A=b2/10`、`W=b2*b3/100` |
| 凭据 | 12 字节 login token（24 hex）+ BLE Key，从米家云一次性获取 |

## 配置

配置文件在 `~/.smart10u/config.yaml`（安装时自动生成，权限与凭据相关，已排除在 git 之外）。

| 字段 | 说明 |
|---|---|
| `ble.mac` / `ble.token` / `ble.ble_key` | 扫码后自动写入，不要手改 |
| `server.host` | 默认 `127.0.0.1`；改成 `0.0.0.0` 才能手机访问（无鉴权，慎用） |
| `server.port` | 默认 `8199` |
| `mqtt.enabled` | 默认 `false`；接 Home Assistant 时打开并填 broker |
| `server.history_retention_days` | 历史采样保留天数，默认 2 |

改完配置后重启：`open ~/.smart10u/CuktechBridge.app`（先 `pkill -f ha_server.py`）。

## 常见问题

**终端里直接跑 `python ha_server.py` 会崩**

macOS TCC 要求可执行文件带 `NSBluetoothAlwaysUsageDescription`，命令行 Python 没有 `Info.plist` 会被直接终止（崩溃报告里写得很清楚）。必须用 `CuktechBridge.app` 启动。

**二维码扫了没反应 / 提示过期**

二维码只有 5 分钟。刷新 `config.html` 重新生成；扫码后还要在手机上点确认。

**面板 `connected: false`，一直重试**

九成是米家 App 还占着连接。强制退出米家 App，或给充电头拔插一次电源；服务会指数退避重连，通常 30–60 秒恢复。

**看不到温度**

固件有 NTC，但 BLE 的 MIOT 属性里没有温度字段（社区已扫过 `siid=2` 的隐藏属性），面板不伪造这个数字。

**端口开关 / 协议开关能用吗**

上游把这几项标为待验证（`port_ctl` 位图需要自己抓一次米家 App 的写帧确认）。场景模式、息屏、亮度、语言是已验证可写的。

**重启电脑后服务没了**

没装开机自启。把 `CuktechBridge.app` 加进「登录项」，或自己写一个 launchd plist。

**macOS 上能用 Docker 吗**

不能，容器没有 BLE 直通。Linux 可以用 Docker，见上游文档。

## 隐私与安全

- token / BLE Key 只写入本机 `~/.smart10u/config.yaml`，已在 `.gitignore` 排除；
- 仓库不含任何账号、真实设备 MAC 或凭据；
- 面板默认只监听 `127.0.0.1`。改成 `0.0.0.0` 前请想清楚：局域网内没有鉴权，任何人都能关你的充电口；
- 凭据等同密码：不要贴到 issue、截图或聊天记录。重新配对米家后 token 会轮换，需要重新扫码。

## 卸载

```bash
pkill -f ha_server.py
rm -rf ~/.smart10u
```

## 已验证环境

macOS 15.7.9 / Apple M1 / Python 3.13 / 固件 `2.1.2_0073`：连接约 39 秒，SSE 实时推送正常，解密成功率 100%，场景模式写入并回读成功。

## 上游与许可

本项目基于 [kairui1108/cuktech-ble-server](https://github.com/kairui1108/cuktech-ble-server)（MIT），补充了 macOS 适配、TCC 兼容的 app 封装与一键安装脚本。

协议与实现参考：

- [kairui1108/cuktech-ble-ha-integration](https://github.com/kairui1108/cuktech-ble-ha-integration)
- [zuyan9/ha-cuk-ble](https://github.com/zuyan9/ha-cuk-ble)
- [ohaiibuzzle/xiaomi-ad1204-python](https://github.com/ohaiibuzzle/xiaomi-ad1204-python)
- [PiotrMachowski/Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor)

MIT License，详见 [LICENSE](LICENSE)。
