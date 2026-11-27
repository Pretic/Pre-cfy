# Pre-cfy

批量生成使用 Cloudflare IP 的节点链接，支持 **VLESS / VMess（WebSocket + TLS）**，可独立使用，也可与 [Sing-box-Pre](https://github.com/Pretic/Sing-box-Pre) 联动。

## 安装

使用 root 用户执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh)
```

## 常用命令

```bash
cfy                         # 读取本机节点
cfy --manual                # 手动粘贴节点链接
cfy --file /root/nodes.txt   # 导入逐行链接或 Base64 订阅
cfy -c                      # 查看本机节点最近一次结果
cfy --update                # 更新脚本
```

在 Sing-box-Pre 中也可以运行 `sb --cfy`，或选择菜单 `11`。

## IP 来源

运行后按提示选择节点和 IP 来源：

1. **Cloudflare 官方网段**：随机生成 IPv4 地址，自行填写数量。
2. **云优选**：读取公开的 IPv4 / IPv6 优选列表，回车默认使用这一项。
3. **本地 IP 文件**：使用自己准备的 IP 列表。

## 结果

本机节点结果保存在 `/etc/sing-box/cfy-url.txt`，并同步到 sb 综合订阅；手动或文件导入的结果保存在 `/var/lib/pre-cfy/`，完成后会显示具体路径。

更多用法见[使用说明](docs/usage.md)。

## 原作者

基于 [byJoey/cfy](https://github.com/byJoey/cfy) 二次开发，由 Pretic 维护。
