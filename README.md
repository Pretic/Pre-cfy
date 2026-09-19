# Pre-cfy

Cloudflare 节点优选生成器。基于已有节点批量生成优选入口，支持独立使用，也可与 [Sing-box-Pre](https://github.com/Pretic/Sing-box-Pre) 联动。

## 支持范围

支持已接入 Cloudflare 的 **VLESS / VMess · WebSocket + TLS** 节点，包括 CDN、Tunnel（Argo）和 Workers 部署，不限定搭建脚本。

Reality、HY2、TUIC、普通 TCP 直连节点不适用。cfy 优选的是 Cloudflare 入口，不会把直连节点转换为 CDN 节点。

## 功能

- 自动读取本机节点，也可手动粘贴链接或导入节点文件。
- 支持 Cloudflare 官方 IP 与第三方云优选数据，支持 IPv4 / IPv6。
- 保留节点认证、域名和路径，批量更新入口地址与备注。
- 默认检查 TLS / WebSocket 握手，生成失败时保留已有结果。

优选效果以客户端实际网络为准。

## 一键安装

使用 root 用户执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh)
```

依赖：`bash`、`curl`、`jq`、`openssl`、`coreutils`、`util-linux`、`grep`、`sed`。

Debian / Ubuntu：

```bash
apt-get update && apt-get install -y curl jq openssl coreutils util-linux grep sed
```

## 使用

```bash
# 读取本机节点
cfy

# 手动粘贴其他来源的节点
cfy --manual

# 导入节点文件：逐行链接或 Base64 订阅
cfy --file /root/nodes.txt

# 查看本机节点的最近一次优选结果
cfy -c
```

在 Sing-box-Pre 中，也可通过 `sb → 11` 或 `sb --cfy` 进入。

### 节点来源与结果

自动模式读取 `/etc/sing-box/url.txt`，生成后同步到 sb 综合订阅。

手动导入和文件导入的结果独立保存在 `/var/lib/pre-cfy/`，具体路径在生成完成后显示，不覆盖 sb 订阅。生成后复制节点，或在客户端刷新对应订阅。

### 可选设置

```bash
# 只选 IPv4 候选
CFY_IP_VERSION_SCOPE=ipv4 cfy

# 同时选择 IPv4 / IPv6 候选
CFY_IP_VERSION_SCOPE=both cfy

# 每个运营商、每种地址最多取 2 个
CFY_PER_ISP_LIMIT=2 cfy
```

## 更新与卸载

```bash
# 更新脚本
cfy --update

# 移除 cfy 命令
rm /usr/local/bin/cfy
```

## 项目来源

基于 [byJoey/cfy](https://github.com/byJoey/cfy) 二次开发，由 Pretic 维护。感谢原作者及贡献者。

配套项目：[Sing-box-Pre](https://github.com/Pretic/Sing-box-Pre)。请遵守服务器所在地和使用所在地的法律法规。
