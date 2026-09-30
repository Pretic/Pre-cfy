# 使用说明

## 安装依赖

Debian / Ubuntu：

```bash
apt-get update && apt-get install -y curl jq openssl coreutils util-linux grep sed
```

cfy 运行时不依赖 Python，不自动安装软件或启动额外服务。

## 可选参数

```bash
CFY_IP_VERSION_SCOPE=ipv4 cfy          # 仅 IPv4
CFY_IP_VERSION_SCOPE=ipv6 cfy          # 仅 IPv6
CFY_IP_VERSION_SCOPE=both cfy          # 双栈
CFY_PER_ISP_LIMIT=2 cfy                # 每运营商、每种地址最多 2 个
CFY_HEALTH_CONCURRENCY=1 cfy           # 显式并发数，1–6
CFY_SOURCE_MAX_TIME=30 cfy             # 云源总等待预算，4–120 秒
CFY_EDGE_FILE=/root/ips.txt cfy        # 直接使用本地入口文件
```

默认每入口检查 1 次、最多 3 秒。慢网络可增加检查时间：

```bash
CFY_HEALTH_PROBE_ATTEMPTS=2 CFY_HEALTH_MAX_TIME=5 CFY_HEALTH_CONNECT_TIMEOUT=3 cfy
```

环境变量也可加在 `cfy --manual` 或 `cfy --file` 前。仅需生成未经检查的候选时，可使用 `CFY_HEALTH_PROBE=0 cfy`。

## 本地文件

节点文件支持逐行链接或 Base64 订阅。混合订阅中的其他协议保留在综合结果中，只选择 VLESS/VMess WS+TLS 作为模板。原文件内容和权限保持不变。

入口文件每行一个 IPv4、IPv6 或 IP:端口，支持 `#` 注释；每次最多读取 30 个去重后的入口。IPv6 带端口必须写为 `[IPv6]:端口`。

可导入 [yx-tools](https://github.com/byJoey/yx-tools) 的 IPv4 `ips_ports.txt`。其 IPv6 带端口输出若未加方括号，需先规范格式。

## 检查与内存

- 云源默认网络等待预算 16 秒，自动地址族探测最多另需 6 秒
- 云源响应上限 1MiB；超大或截断响应拒绝解析，本地节点文件不受该上限影响
- 自动并发参考宿主机、可读 cgroup v1/v2 限额及剩余内存：总容量不超过 192MiB 默认 1 路、不超过 384MiB 默认 2 路，其余最多 3 路；未知或紧张时降档
- 降低并发保留候选和检查，仅增加等待时间。128MB 还需容纳系统与代理内核，避免同时运行多个管理或测速任务

TLS/WebSocket 握手不验证代理账号、出口连通性或客户端速度。第三方延迟也不代表客户端实际延迟。

## 结果与恢复

本机结果保存在 `/etc/sing-box/cfy-url.txt`，并同步到综合订阅；`cfy -c` 只显示与当前基础节点一致的结果。

独立导入保存在 `/var/lib/pre-cfy/` 的对应目录，包含节点文本和 Base64 订阅。混合来源的其他节点会保留。

安装及更新先暂存、检查，再替换脚本，并保留上一版本。订阅发布遇到可捕获的 INT/TERM/HUP 会回滚；断电、SIGKILL 或存储故障仍可能需要人工恢复。
