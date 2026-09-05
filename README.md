# Pre-cfy：Cloudflare 节点优选

`cfy` 是面向 Sing-box-Pre 订阅的独立 Cloudflare 边缘入口生成器。它优先读取 VLESS-WS-TLS-Argo 模板，只替换入口地址、端口和节点备注，不改变 UUID、Host、SNI、Path、TLS 等连接参数；找不到 VLESS 模板时，才使用旧 VMess 模板兼容路径。

本仓库从 [byJoey/cfy](https://github.com/byJoey/cfy) 演进而来，现由本仓库独立维护，不代表上游项目。

## 主要特性

- 从 `/etc/sing-box/url.txt` 读取基础模板，避免把旧优选结果再次当成输入。
- 支持域名、IPv4、IPv6、`host:port` 和 `[IPv6]:port` 形式的 Cloudflare 入口。
- 提供 Cloudflare 官方 IPv4 随机生成和第三方低 RTT 优选两种模式。
- 对第三方结果校验地址与 RTT，过滤 `-1`、超时、空值、零值及无效记录；重复 IP 只保留数据源第一次出现的记录。
- 按“运营商 × IP 版本”分别排序，始终先输出 IPv4，再输出 IPv6。
- 质量优先：候选不足时按实际有效数量输出，不使用无效地址补足上限。
- 识别中国电信、中国联通、中国移动；节点名保留协议、运营商、IP 版本和序号信息。
- 使用发布锁、同目录临时文件、原子替换和回滚，生成失败时保留最近一次成功结果。
- 与 Sing-box-Pre 共用稳定订阅事务锁，但不进入代理数据转发路径，不影响节点日常速度。

## 候选数量与地址族

默认根据 VPS 实际出站能力选择范围：

| VPS 出站能力 | 每个运营商默认输出 | 顺序 |
| --- | --- | --- |
| IPv4 单栈 | 最多 5 个 IPv4 | IPv4 |
| IPv6 单栈 | 最多 5 个 IPv6 | IPv6 |
| IPv4 + IPv6 双栈 | 最多 3 个 IPv4 + 3 个 IPv6 | IPv4 在前，IPv6 在后 |

这里的数量是上限，不是必须凑满的配额。例如某运营商只有 2 个带有效 RTT 的候选，就只输出 2 个。可通过 `CFY_IP_VERSION_SCOPE` 覆盖自动检测，通过 `CFY_PER_ISP_LIMIT` 覆盖每个“运营商 × 地址族”的上限。

第三方 RTT 来自数据源所在的测量环境，只适合初筛，不等同于最终客户端到节点的实际延迟。脚本默认不从 VPS 对所有候选做强制健康探测，因为 VPS 路由与最终客户端路由可能完全不同，容易误删客户端可用地址。

云优选先读取微测网 JSON API，某个地址族的 API 不可用时回退到对应网页。网页中的 `ms` 和 `毫秒` 延迟单位均可识别；负数、零值及无效记录仍会被过滤。若所有来源均不可用，保留最近一次成功结果。

## 安装与使用

### 首次安装并运行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh)
```

安装后可直接运行：

```bash
cfy
```

### 查看最近一次结果

```bash
cfy -c
```

### 仅更新 cfy

```bash
cfy --update
```

通过 `bash <(curl ...) --update` 或 `curl ... | bash` 安装时，脚本会读完下载流后再退出或启动安装后的命令，避免提前关闭管道引起 `curl: (23) Failure writing output`。

也可以从远端脚本更新：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh) --update
```

更新只替换 `/usr/local/bin/cfy`，不会启动新一轮优选，也不会修改基础节点或最近一次成功结果。

### 卸载

```bash
sudo rm /usr/local/bin/cfy
```

卸载命令本身不会删除 `/etc/sing-box` 中已有的基础节点、优选结果和历史结果。

## 与 Sing-box-Pre 联动

cfy 始终是独立模块，保留独立仓库、命令和更新周期。Sing-box-Pre 只提供低风险入口联动：

```text
sb → 11. Cloudflare优选
```

也可直接运行：

```bash
sb --cfy
```

- 已安装 `/usr/local/bin/cfy` 时直接以前台交互方式运行。
- 未安装时，sb 从固定且经过摘要校验的稳定版本安全安装，成功后再进入 cfy。
- cfy 退出后返回 sb 的 Cloudflare 优选子菜单，不退出 sing-box 管理脚本。
- cfy 下载、安装或运行失败，不重启 sing-box、Argo、Nginx，不修改端口、基础节点或已有代理服务。
- 两个项目保持代码边界；sb 不复制 cfy 的候选解析和节点生成逻辑。

## 订阅文件契约

| 文件 | 所有者与用途 |
| --- | --- |
| `/etc/sing-box/url.txt` | Sing-box-Pre 管理的基础节点，也是 cfy 的模板来源。 |
| `/etc/sing-box/cfy-url.txt` | cfy 最近一次成功生成的明文优选节点。 |
| `/etc/sing-box/cfy-sub.txt` | cfy 优选节点的 Base64 订阅。 |
| `/etc/sing-box/cfy-source.generation` | 记录生成时的基础订阅代际，格式为 `sha256(url.txt):字节数`。 |
| `/etc/sing-box/all-url.txt` | 基础节点与当前有效 cfy 节点的合并明文。 |
| `/etc/sing-box/all-sub.txt` | 综合 Base64 订阅。 |
| `/etc/sing-box/sub.txt` | Nginx 实际发布的综合订阅，权限为 `0644`。 |
| `/etc/sing-box/cfy-results/` | 按时间保存的历史结果，不参与当前订阅代际判断。 |

除 Nginx 读取的 `sub.txt` 外，内部订阅与代际文件默认使用 `0600`。cfy 与 Sing-box-Pre 在短事务内共同锁定 `/var/lib/sing-box-transactions/subscription.lock`，防止同时发布造成文件交叉覆盖。

如果基础订阅、UUID、Argo 域名或入口配置发生变化，代际记录会失配。此时旧 cfy 结果仍可通过 `cfy -c` 查看，但不会混入公开综合订阅；重新成功运行 cfy 后才恢复并入。发布过程中任一步骤失败，旧结果、代际记录和公开订阅会一并回滚，不留下部分更新状态。

## NAT VPS 与单栈环境

- cfy 不新增 VPS 入站监听端口，只生成客户端使用的 Cloudflare 入口地址。
- 端口受限 NAT VPS 可以优先使用 WS-TLS-Argo/cfy 节点，不要求服务商额外映射 Argo 本地回环端口。
- 只有内网 IPv4、但可正常 IPv4 出网的 NAT VPS，会按 IPv4 单栈处理。
- VPS 没有 IPv6，但最终客户端有 IPv6 时，可显式使用 `CFY_IP_VERSION_SCOPE=both cfy` 生成双栈候选；能否使用取决于客户端网络和客户端软件。
- Nginx 订阅端口未映射时，订阅 URL 可能无法从公网访问，但 `cfy -c` 和 `cfy-url.txt` 中的结果仍可使用。

## 可选参数

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `CFY_IP_VERSION_SCOPE` | 自动检测 | `ipv4`、`ipv6` 或 `both`。 |
| `CFY_PER_ISP_LIMIT` | 双栈 3，单栈 5 | 每个运营商、每个地址族的候选上限。 |
| `CFY_NAME_PREFIX` | 从模板备注派生 | 仅覆盖本次运行的节点名前缀，不做持久化改名。 |
| `CFY_HEALTH_PROBE` | `0` | 设为 `1` 时，对真实 SNI、Host 和 WebSocket Path 做轻量 HTTPS 探测。 |
| `CFY_HEALTH_PROBE_ATTEMPTS` | `2` | 单个候选探测次数。 |
| `CFY_HEALTH_MIN_SUCCESS` | `2` | 候选保留所需的最少成功次数。 |
| `CFY_HEALTH_CONNECT_TIMEOUT` | `3` | 健康探测连接超时，单位秒。 |
| `CFY_HEALTH_MAX_TIME` | `5` | 单次健康探测总超时，单位秒。 |
| `CFY_CURL_CONNECT_TIMEOUT` | `10` | 拉取候选数据源的连接超时，单位秒。 |
| `CFY_CURL_MAX_TIME` | `30` | 拉取候选数据源的总超时，单位秒。 |

示例：

```bash
CFY_IP_VERSION_SCOPE=both cfy
CFY_PER_ISP_LIMIT=2 cfy
CFY_NAME_PREFIX=HK-NAT cfy
CFY_HEALTH_PROBE=1 cfy
```

健康探测适合在与最终客户端网络条件相近的环境中主动启用。直接在 VPS 上启用可能因为路由差异产生假阴性，因此不作为默认行为。

## 依赖

需要 `bash`、`curl`、`jq`、`flock`、`sha256sum`、`stat`、`base64`、`mktemp`、`grep` 和 `sed`。Debian/Ubuntu 可安装：

```bash
apt update && apt install -y curl jq coreutils util-linux grep sed
```

只有将 `SING_BOX_TRANSACTION_GROUP` 设置为组名而不是数字 GID 时，才额外需要 `getent`。

## 开发验证

仓库测试均使用临时目录和模拟命令，不写入真实 `/etc/sing-box`：

```bash
bash -n cfy.sh
shellcheck -S error cfy.sh
for test_file in tests/*.sh; do bash "$test_file"; done
```

测试覆盖候选质量与数量、无效 RTT、单双栈选择、VLESS/VMess 改写、订阅代际、权限、事务锁、回滚、安装更新和跨项目文件契约。

## 上游与鸣谢

- 上游项目：[byJoey/cfy](https://github.com/byJoey/cfy)
- 感谢 byJoey 及上游贡献者提供早期脚本基础。

## 免责声明

- 本脚本仅供学习和技术交流使用，请勿用于任何非法用途。
- 第三方优选数据的时效性与准确性由数据源决定；脚本只做格式、RTT 和可选连通性筛选，不承诺每个候选始终可用。
- 用户应遵守服务器所在地和使用所在地的法律法规，并自行承担使用风险。
