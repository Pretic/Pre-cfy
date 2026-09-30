# 测试说明

在临时环境中运行，不要用真实服务器配置代替测试夹具：

```bash
find . -name '*.sh' -exec bash -n {} \;
for test_script in tests/*.sh; do bash "$test_script" || exit; done
find . -name '*.sh' -print0 | xargs -0 shellcheck -S error
```

测试使用临时目录、模拟下载和本机回环 TLS，覆盖安装、更新、导入、筛选、内存策略、订阅发布、回滚与取消，不修改真实服务器配置。

回环 TLS 测试额外需要 Python 3；它不是 cfy 的运行时依赖。测试成功不等于完成了真实客户端测速或整机 128MiB 硬内存限制验证。
