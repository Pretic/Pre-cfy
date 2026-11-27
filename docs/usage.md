# 使用说明

## 安装依赖

Debian / Ubuntu：

```bash
apt-get update && apt-get install -y curl jq coreutils util-linux grep sed
```

cfy 运行时不依赖 Python，不自动安装软件或启动额外服务。可选握手检查另外需要 `openssl`。

## 默认行为

运行 `cfy` 后选择模板和入口来源。云优选默认读取公开网页，保留 IPv4 / IPv6 的全部合法候选并去重；第三方延迟缺失不会导致候选被删除。服务器自身能否连接某个地址族不影响默认生成。

本地 IP 文件按文件内容生成，不再只取前 30 条。Cloudflare 官方网段选项按填写数量随机抽取不同的 IPv4 地址，默认生成 10 条；这类地址需要在客户端测速后选择。

## 可选参数

```bash
CFY_IP_VERSION_SCOPE=ipv4 cfy          # 仅 IPv4
CFY_IP_VERSION_SCOPE=ipv6 cfy          # 仅 IPv6
CFY_IP_VERSION_SCOPE=both cfy          # 双栈
CFY_PER_ISP_LIMIT=2 cfy                # 云源每运营商、每种地址最多 2 个；默认 0 不限
CFY_HEALTH_PROBE=1 cfy                 # 开启 VPS 上的握手筛选
CFY_HEALTH_PROBE=1 CFY_HEALTH_CONCURRENCY=1 cfy  # 单路检查
CFY_SOURCE_MAX_TIME=30 cfy             # 云源总等待预算，4–120 秒
CFY_EDGE_FILE=/root/ips.txt cfy        # 直接使用本地入口文件
```

开启检查后，每入口检查 1 次、最多 3 秒。慢网络可增加检查时间：

```bash
CFY_HEALTH_PROBE=1 CFY_HEALTH_PROBE_ATTEMPTS=2 CFY_HEALTH_MAX_TIME=5 CFY_HEALTH_CONNECT_TIMEOUT=3 cfy
```

环境变量也可加在 `cfy --manual` 或 `cfy --file` 前。`CFY_HEALTH_PROBE=0` 为默认的直接生成方式。显式限制云源数量时，优先保留来源延迟较低的候选，延迟未知的候选排在其后；该延迟不是客户端测速结果。

如已有自己的微测网 API 令牌，可设置 `CFY_OPTIMIZED_IP_API_KEY`，届时优先 API、失败回退公开网页。脚本不内置共享令牌。接口规则见[微测网文档](https://www.wetest.vip/doc/article/cloudflare-ip.html)。

## 本地文件

节点文件支持逐行链接或 Base64 订阅。混合订阅中的其他协议保留在综合结果中，只选择 VLESS/VMess WS+TLS 作为模板。原文件内容和权限保持不变。

入口文件每行一个 IPv4、IPv6 或 IP:端口，支持 `#` 注释和去重。IPv6 带端口必须写为 `[IPv6]:端口`。

可导入 [yx-tools](https://github.com/byJoey/yx-tools) 的 IPv4 `ips_ports.txt`。其 IPv6 带端口输出若未加方括号，需先规范格式。

## 检查与内存

- 云源默认网络等待预算 16 秒，不额外探测 VPS 的 IPv4 / IPv6 出口
- 云源响应上限 1MiB；超大或截断响应拒绝解析，本地节点文件不受该上限影响
- 开启握手检查后，自动并发参考宿主机、可读 cgroup v1/v2 限额及剩余内存：总容量不超过 192MiB 默认 1 路、不超过 384MiB 默认 2 路，其余最多 3 路；未知或紧张时降档
- 降低并发保留候选和检查，仅增加等待时间。128MB 还需容纳系统与代理内核，避免同时运行多个管理或测速任务

TLS/WebSocket 握手不验证代理账号、出口连通性或客户端速度。第三方延迟也不代表客户端实际延迟。

## 结果与恢复

本机结果保存在 `/etc/sing-box/cfy-url.txt`，并同步到综合订阅；`cfy -c` 只显示与当前基础节点一致的结果。

独立导入保存在 `/var/lib/pre-cfy/` 的对应目录，包含节点文本和 Base64 订阅。混合来源的其他节点会保留。

安装及更新先暂存、检查，再替换脚本，并保留上一版本。订阅发布遇到可捕获的 INT/TERM/HUP 会回滚；断电、SIGKILL 或存储故障仍可能需要人工恢复。
