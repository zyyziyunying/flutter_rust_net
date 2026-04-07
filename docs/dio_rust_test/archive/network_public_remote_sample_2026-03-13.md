---
title: flutter_rust_net 公网 non-loopback 样例报告（2026-03-13）
---

# flutter_rust_net 公网 non-loopback 样例报告（2026-03-13）

> 范围：`flutter_rust_net` 主机 -> 公网 benchmark 服务的固定入口 smoke 样例。
>
> 目的：为 P1 的“non-loopback 自动化命令 + 可追溯样例报告 + `/upload` 回执样例”保留一份本地执行产物样例摘要。

## 1) 本轮执行信息

- 日期：`2026-03-13`
- 固定入口：`tool/p1_non_loopback_bench.dart`
- 执行命令：

```powershell
dart run tool/p1_non_loopback_bench.dart --preset=smoke --run-id=sample_20260313_host_windows_upload --output-dir=build/remote_public_sample_20260313_upload --network-profile=ethernet --device=host_windows --operator=codex --upload=true --upload-header=token:<redacted>
```

- `baseUrl`：`http://47.110.52.208:7777`
- `preset`：`smoke`
- `runId`：`sample_20260313_host_windows_upload`
- `network_profile`：`ethernet`
- `device`：`host_windows`
- `link_type`：`public_remote`
- `git commit`：`a7e2e8fea17f8bfaae2dd026565cd34674a712f8`
- `gitDirty`：`true`
- 本轮本地产物目录：`build/remote_public_sample_20260313_upload/`
- 上传头处理：`run_manifest.json` 与命令摘要中只保留 `token:<redacted>`，不落盘真实 token

## 2) 产物清单

固定入口本轮已生成：

1. `remote_small_dio.json`
2. `remote_small_rust.json`
3. `remote_jitter_mif32.json`
4. `aggregate_small_json.md`
5. `aggregate_small_json.json`
6. `aggregate_jitter_latency.md`
7. `aggregate_jitter_latency.json`
8. `run_manifest.json`
9. `logs/*.stdout.log`
10. `logs/*.stderr.log`

`run_manifest.json` 中已固化：

1. 本轮所有 benchmark / aggregate 的完整命令行
2. 每条命令的开始时间、结束时间、耗时、退出码
3. 输出文件与 stdout/stderr 日志路径
4. 推荐归档前缀：`flutter_rust_net/20260313/ethernet/host_windows/sample_20260313_host_windows_upload`
5. 推荐额外字段：`project`、`run_id`、`network_profile`、`device`、`link_type`、`commit`、`operator`
6. 上传命令摘要与 `headers` 字段中的敏感鉴权值已做脱敏

## 3) 聚合结果

### 3.1 `small_json`

- `dio`: `reqP95=28ms`, `throughput=206.19 req/s`
- `rust`: `reqP95=32ms`, `throughput=168.07 req/s`
- 聚合判定：`FAIL`
- 原因：Rust `reqP95` 高于 Dio 阈值，且 `throughput` 低于 Dio

### 3.2 `jitter_latency`

- `dio`: `reqP95=102ms`, `throughput=103.63 req/s`
- `rust`: `reqP95=188ms`, `throughput=65.41 req/s`
- 聚合判定：`FAIL`
- 原因：Rust `reqP95` 高于 Dio 阈值，且 `throughput` 低于 Dio

## 4) 上传回执样例

本轮 `--upload=true` 已向 `POST /upload` 上传 5 个 JSON 文件：

1. `aggregate_jitter_latency.json`
2. `aggregate_small_json.json`
3. `remote_jitter_mif32.json`
4. `remote_small_dio.json`
5. `remote_small_rust.json`

上传结果：

1. `success=5`
2. `failed=0`
3. 各文件回执均为 `HTTP 200`
4. 客户端回执口径：`status=<code>, client=common.DioLogUploader, costMs=<ms>`

本轮归档口径：

1. `remotePrefix=flutter_rust_net/20260313/ethernet/host_windows/sample_20260313_host_windows_upload`
2. `extraFields.project=flutter_rust_net`
3. `extraFields.run_id=sample_20260313_host_windows_upload`
4. `extraFields.network_profile=ethernet`
5. `extraFields.device=host_windows`
6. `extraFields.link_type=public_remote`
7. `extraFields.commit=a7e2e8fea17f8bfaae2dd026565cd34674a712f8`
8. `extraFields.operator=codex`

## 5) 当前结论

1. non-loopback 固定入口已可用，且能稳定生成 benchmark JSON、聚合摘要与 `run_manifest.json`。
2. 带鉴权上传样例也已具备，`/upload` 的命名约定、额外字段和服务端回执口径已在仓库内留痕。
3. 这份样例已满足“至少一份可追溯样例报告”和“至少一份带上传回执样例”的要求，因为命令、元信息、产物、聚合结论和上传回执都已落到同一目录。
4. 从本轮 `host_windows + ethernet + public_remote` smoke 看，Rust 在当前公网 `jitter_latency` 样例下仍未达到 P1 聚合门槛，不能据此给出业务接入准入结论。

## 6) 仍未覆盖的点

1. 本轮样例是主机侧 `ethernet`，还不是 Android / iOS 真机，也不是 Wi-Fi / 4G / 弱网剖面。
2. 当前样例仍是 `smoke` 级别，不是 `standard` 长一点的复测轮次。
3. 若要继续补证据，优先下一步：
   - 用相同固定入口补 `android_real` / `ios_real`
   - 覆盖 `wifi` / `4g` / `weaknet`
   - 在必要时改跑 `--preset=standard`
