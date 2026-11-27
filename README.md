# Pre-cfy

为已有 Cloudflare 节点批量生成入口链接。支持 **VLESS / VMess · WebSocket + TLS**，可独立使用，也可与 [Sing-box-Pre](https://github.com/Pretic/Sing-box-Pre) 联动。

支持 IPv4 / IPv6、云优选和本地 IP 文件。Reality、HY2、TUIC 等直连节点不能作为优选模板。

## 安装

使用 root 用户执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh)
```

依赖：`bash`、`curl`、`jq`、`coreutils`、`util-linux`、`grep`、`sed`。开启握手检查时还需要 `openssl`。

## 使用

```bash
cfy                         # 读取本机节点
cfy --manual                # 手动粘贴节点链接
cfy --file /root/nodes.txt   # 导入逐行链接或 Base64 订阅
cfy -c                      # 查看本机节点最近一次结果
```

- 节点菜单选择 `0` 可手动粘贴其他节点
- 入口来源回车使用云优选，默认保留来源中的全部 IPv4 / IPv6 候选并去重
- 入口来源选择 `3` 可读取本地 IP 文件；IPv6 带端口写为 `[IPv6]:端口`
- 入口来源选择 `1` 从 Cloudflare 官方 IPv4 网段随机生成，自行填写数量
- 在 Sing-box-Pre 中使用 `sb --cfy`，或进入菜单 `11`

本机节点来自 `/etc/sing-box/url.txt`，结果同步到 sb 综合订阅。手动及文件导入的结果保存在 `/var/lib/pre-cfy/`，不覆盖 sb 订阅；具体路径会在完成后显示。

默认直接生成链接，不按 VPS 的地址族或握手结果删减候选，也不截断本地 IP 文件。生成后在实际使用的客户端测试、选择入口。需要从 VPS 检查 TLS / WebSocket 握手时：

```bash
CFY_HEALTH_PROBE=1 cfy
```

## 更新与卸载

```bash
cfy --update                # 更新脚本
rm /usr/local/bin/cfy        # 移除命令，保留已有结果
```

## 注意

云优选读取公开列表，不需要 API 密钥。官方网段随机生成不代表已测速；可选握手检查也不等同于代理认证和实际下载测速。失败时保留已有结果；小内存机器开启检查后自动降低并发。

更多参数、依赖安装和文件格式见[使用说明](docs/usage.md)。开发检查见[测试说明](docs/testing.md)。

## 项目来源

基于 [byJoey/cfy](https://github.com/byJoey/cfy) 二次开发，由 Pretic 维护。感谢原作者及贡献者。请遵守使用所在地的法律法规。
