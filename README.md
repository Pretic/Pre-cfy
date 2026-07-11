# 节点优选生成器 (cfy)

> 基于原项目二改的自用版本，用于配合 `Sing-box-Pre` 生成优选 VLESS-WS-TLS-Argo 节点。

一个强大且易于使用的 Bash 脚本，用于批量生成基于 Cloudflare IP 的 `vless` 节点链接。脚本会优先读取 VLESS-WS-TLS-Argo 模板，自动替换服务器地址，并可智能生成优选节点；仅在没有 VLESS 模板时兼容旧 `vmess` 模板。

---

## 本仓库说明（PreNet 自用二改）

本仓库基于原作者 [byJoey/cfy](https://github.com/byJoey/cfy) 二次修改，保留原作者信息、联系方式和免责声明。感谢 byJoey 提供的 Cloudflare 优选节点生成脚本基础。

本仓库主要用于个人 VPS 节点优选测试，配合 [Pretic/Sing-box-Pre](https://github.com/Pretic/Sing-box-Pre) 生成的 `/etc/sing-box/url.txt` 使用，不代表上游项目。二改重点：

* 优先读取并改写 `VLESS-WS-TLS-Argo` 模板，避免继续依赖旧 `VMess-WS-TLS-Argo`。
* 生成优选节点时只替换 Cloudflare 入口地址/端口，保留 `host`、`sni`、`path`、`security=tls` 等关键参数。
* 兼容优选入口为域名、IPv4、IPv6、`host:port`、`[IPv6]:port` 等格式。
* 保留旧 VMess 模板兼容逻辑，但仅作为找不到 VLESS 模板时的兜底。
* 修正 IPv6 优选源，并从 Cloudflare 官方 CIDR 随机生成可用 IPv4 地址。
* 最近一次生成的优选节点会保存到 `/etc/sing-box/cfy-url.txt`，后续可用 `cfy -c` 再次查看。


## 与 Sing-box 订阅的同步机制

* cfy 会优先从 `/etc/sing-box/url.txt` 查找模板；如果基础文件里没有可用模板，还会继续检查 `/etc/sing-box/all-url.txt`、`/etc/sing-box/cfy-url.txt` 和已对外服务的 `/etc/sing-box/sub.txt`。
* cfy 生成的优选节点会保存到 `/etc/sing-box/cfy-url.txt`，对应 Base64 文件为 `/etc/sing-box/cfy-sub.txt`。
* 每次成功生成后，cfy 会把 `/etc/sing-box/url.txt` 的基础节点和 `/etc/sing-box/cfy-url.txt` 的优选节点合并到 `/etc/sing-box/all-url.txt`。
* 合并后的 Base64 订阅写入 `/etc/sing-box/all-sub.txt`，并同步覆盖 `/etc/sing-box/sub.txt`，因此原来的 Nginx 订阅地址会自动包含优选节点。
* 如果还没有运行过 cfy，Sing-box 的订阅地址仍只包含基础节点，不会因为没有优选结果而失效。

## NAT 机使用说明

* cfy 不在 VPS 上新增监听端口，只改写 `VLESS-WS-TLS-Argo` 模板里的 Cloudflare 入口地址和入口端口。
* 云优选里的 `IPv4 + IPv6` 指客户端访问 Cloudflare 边缘入口的地址族，不要求 VPS 本身支持 IPv6；实际可用性取决于客户端网络和客户端软件。
* 端口受限 NAT 机建议优先使用 cfy 输出的 WS TLS Argo 节点；这类节点不需要服务商额外开放 `ARGO_PORT`。
* 如果 Nginx 订阅端口没有映射，订阅 URL 可能不可访问，但仍可通过 `cfy -c` 或 `/etc/sing-box/cfy-url.txt` 查看最近一次生成的优选节点。

## 命令速查

### cfy 新装
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh)
```

### 已安装后更新 cfy
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh) --update
```

### 查看最近一次优选结果
```bash
cfy -c
```

* 更新命令只覆盖 `/usr/local/bin/cfy`，不会进入优选生成流程，也不会修改 sing-box 已有节点或最近一次优选结果。
* 首次使用请执行新装命令；已经安装过且只想同步仓库脚本时，再执行更新命令。
* 本仓库命令统一使用 `curl -fsSL`，下载失败时会显示错误，避免 `curl -Ls` 失败后 Bash 静默执行空脚本。
* `cfy -c` 优先显示 `/etc/sing-box/cfy-url.txt` 中最近一次优选结果；如果还没生成过优选节点，会尝试显示 `/etc/sing-box/url.txt` 中可作为模板的 VLESS-WS-TLS-Argo 节点。

## 已安装后如何更新

以前已经安装过 `cfy` 时，直接执行上面的 `--update` 命令即可。它只覆盖 `/usr/local/bin/cfy`，不会自动开始优选生成，也不会修改 `/etc/sing-box/url.txt`、`/etc/sing-box/cfy-url.txt` 或当前对外订阅。

更新完成后，如需重新生成优选节点，再手动运行：

```bash
cfy
```

---

### 联系与支持

* **作者:** byJoey ([GitHub](https://github.com/byJoey))
* **个人博客:** [joeyblog.net](https://joeyblog.net)
* **Telegram 交流群:** [点击加入](https://t.me/+ft-zI76oovgwNmRh)

---

## 功能特性

* **一键安装**: 只需一条命令即可完成安装，自动将脚本部署为系统命令 `cfy`。
* **智能模板源**: 自动从 `/etc/sing-box/url.txt` 读取节点作为模板，优先选择 VLESS-WS-TLS-Argo。
* **无模板启动**: 如果模板文件为空或无效，会提示用户手动粘贴一个链接作为模板。
* **两种生成模式**:
    1.  **Cloudflare 官方 IP**: 从 Cloudflare 官方获取全量 IPv4 地址段，用户可指定生成数量，脚本会随机选择 IP 进行替换。
    2.  **优选 IP (全自动)**:
        * 自动从第三方源抓取已优选的 **IPv4 和 IPv6 地址**。
        * 按第三方源返回的原始顺序合并候选，不再随机打乱；相同 IP 仅保留第一次出现的记录。
        * 符合所选 IPv4/IPv6 范围的去重候选会全部生成，不再按运营商限量。
        * 可识别的运营商会使用 `中国电信`、`中国联通`、`中国移动` 中文名称；通用或未知分组不额外加组名，但仍保留节点。
        * 选择“云优选”并抓取地址后，可选择 `IPv4`、`IPv4 + IPv6` 或 `IPv6`；直接按回车默认选择 `IPv4`。VPS 本身没有 IPv6 也可以生成 Cloudflare IPv6 入口，是否可用取决于客户端网络。
        * 抓取完成后会显示候选数量，例如 `15 IPv4, 15 IPv6`，方便确认双栈源是否正常。
        * 节点备注格式为 `前缀-中国联通-ipv4-序号` 这类中文运营商名称。

## 依赖要求

在运行脚本之前，请确保您的系统中已安装以下命令行工具：

* `jq`: 用于解析 JSON 数据。
* `curl`: 用于发起网络请求。
* `coreutils`: 提供 `base64`, `mktemp` 等基础命令。
* `grep`, `sed`: 用于文本处理。

**在 Debian / Ubuntu 系统中安装:**
```bash
apt update && apt install -y jq curl coreutils grep sed sudo
```

## 一键新装与运行

请复制并执行以下命令。它会自动下载脚本，并触发脚本的自我安装程序。首次运行即完成安装。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh)
```
安装成功后，您可以随时在终端的任何位置输入以下命令来启动脚本：
```bash
cfy
```

查看最近一次生成的优选节点：
```bash
cfy -c
```

如需修改优选节点备注名前缀，可在运行时设置：
```bash
CFY_NAME_PREFIX=PreNet cfy
CFY_IP_VERSION_SCOPE=both cfy
```

## 更新与卸载

* **更新脚本**: 使用上方“已安装后更新 cfy”命令即可覆盖 `/usr/local/bin/cfy`，不会进入优选生成流程，也不会修改 sing-box 已有节点或最近一次优选结果。

* **卸载脚本**: 只需删除安装好的文件即可。
    ```bash
    sudo rm /usr/local/bin/cfy
    ```

## 免责声明

* 本脚本仅供学习和技术交流使用，请勿用于任何非法用途。
* 脚本从第三方网站获取优选 IP 数据，其可用性和准确性由数据源决定。
* 用户需自行承担使用本脚本所带来的一切风险。

---
