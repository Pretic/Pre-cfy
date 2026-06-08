# 节点优选生成器 (cfy)

> 完美适配  的4合一sing-box，可快速生成优选 VLESS-WS-TLS-Argo 节点。

一个强大且易于使用的 Bash 脚本，用于批量生成基于 Cloudflare IP 的 `vless` 节点链接。脚本会优先读取 VLESS-WS-TLS-Argo 模板，自动替换服务器地址，并可智能生成优选节点；仅在没有 VLESS 模板时兼容旧 `vmess` 模板。

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
        * 将所有优选 IP 合并并**随机打乱**顺序。
        * **全自动生成**所有找到的优选节点，无需用户输入数量。
        * 自动在节点备注后添加 `-优选[运营商]` 后缀，方便识别。

## 依赖要求

在运行脚本之前，请确保您的系统中已安装以下命令行工具：

* `jq`: 用于解析 JSON 数据。
* `curl`: 用于发起网络请求。
* `coreutils`: 提供 `base64`, `mktemp`, `shuf` 等基础命令。
* `grep`, `sed`: 用于文本处理。

**在 Debian / Ubuntu 系统中安装:**
```bash
apt update && apt install -y jq curl coreutils grep sed sudo
```

## 一键安装与运行

请复制并执行以下命令。它会自动下载脚本，并触发脚本的自我安装程序。首次运行即完成安装。

```bash
bash <(curl -l -s https://raw.githubusercontent.com/byJoey/cfy/main/cfy.sh)
```
安装成功后，您可以随时在终端的任何位置输入以下命令来启动脚本：
```bash
cfy
```

## 更新与卸载

* **更新脚本**: 重新运行一次上面的“一键安装”命令即可覆盖更新。
    ```bash
  bash <(curl -l -s https://raw.githubusercontent.com/byJoey/cfy/main/cfy.sh)
    ```

* **卸载脚本**: 只需删除安装好的文件即可。
    ```bash
    sudo rm /usr/local/bin/cfy
    ```

## 免责声明

* 本脚本仅供学习和技术交流使用，请勿用于任何非法用途。
* 脚本从第三方网站获取优选 IP 数据，其可用性和准确性由数据源决定。
* 用户需自行承担使用本脚本所带来的一切风险。

---
