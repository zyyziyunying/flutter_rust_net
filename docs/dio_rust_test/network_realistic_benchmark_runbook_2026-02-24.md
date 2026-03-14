---
title: Dio vs Rust 网络测试执行手册（2026-02-24 起，补记至 2026-03-11，v4）
---

# Dio vs Rust 网络测试执行手册（2026-02-24 起，补记至 2026-03-11，v4）

> 适用范围（2026-02-25 拆分后）：网络相关命令统一在 `flutter_rust_net` 执行；目标是快速、稳定地跑出可对比结论，并指导路由策略。
>
> 2026-03-11 补记：保留历史基准执行手册主体不变；当前补充重点放在“公网 `--base-url` 可用”“归档命名 / 额外字段 / 回执口径”三件事。
>
> 2026-03-13 补记：已新增固定入口 `tool/p1_non_loopback_bench.dart`，可一键串联公网 benchmark、聚合摘要与 `run_manifest.json`；仓库内样例见 `docs/dio_rust_test/network_public_remote_sample_2026-03-13.md`。

## 0) 当前已知结果（基于 2026-02-24 更新轮次）

1. `small_json`：Rust 领先（L1/L2 均确认）。
2. `large_payload`：Rust 显著领先。
3. `large_json`：Rust 在请求与端到端指标领先，吞吐更高；但 consume 路径开销更重。
4. `flaky_http`：两边 5xx 一致（60/240），Rust 延迟和吞吐更优。
5. `jitter_latency`：默认 `maxInFlightTasks=12` 时，`c16` Rust 落后；提升到 `32` 后可恢复领先（需灰度验证）。
6. fallback 演练已验证：开兜底 0 异常，关兜底 100% 异常。
7. L2 consume 计时能力已接入：`--consume-mode=none|json_decode|json_model`（默认 `none`）。

---

## 1) 一次执行总览（照抄即可）

```bash
# 1. 进入目录
cd D:\dev\flutter_code\harrypet_flutter\flutter_rust_net

# 2. 代码静态与单测
flutter analyze lib test tool
flutter test test/network -r expanded
flutter test test/network/network_realistic_flow_test.dart -r expanded

# 3. 严格双通道基准（全部要求 Rust 可用，不允许静默跳过）
dart run tool/network_bench.dart --scenario=small_json --channels=dio,rust --initialize-rust=true --require-rust=true --requests=400 --concurrency=16 --output=build/bench_small.json
dart run tool/network_bench.dart --scenario=large_payload --channels=dio,rust --initialize-rust=true --require-rust=true --requests=120 --concurrency=8 --output=build/bench_large.json
dart run tool/network_bench.dart --scenario=large_json --channels=dio,rust --initialize-rust=true --require-rust=true --requests=120 --concurrency=8 --output=build/bench_large_json.json
dart run tool/network_bench.dart --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --requests=240 --concurrency=16 --jitter-base-ms=12 --jitter-extra-ms=80 --output=build/bench_jitter.json
dart run tool/network_bench.dart --scenario=flaky_http --channels=dio,rust --initialize-rust=true --require-rust=true --requests=240 --concurrency=16 --flaky-every=4 --output=build/bench_flaky.json

# 4. 兜底演练（验证 fallback 是否真能保可用）
dart run tool/network_bench.dart --scenario=small_json --channels=rust --initialize-rust=false --require-rust=false --fallback=true --requests=120 --concurrency=12 --output=build/bench_fallback_on.json
dart run tool/network_bench.dart --scenario=small_json --channels=rust --initialize-rust=false --require-rust=false --fallback=false --requests=120 --concurrency=12 --output=build/bench_fallback_off.json

# 5. L2 consume 复验（端到端解析/建模）
dart run tool/network_bench.dart --scenario=small_json --channels=dio,rust --initialize-rust=true --require-rust=true --consume-mode=json_decode --requests=240 --concurrency=16 --output=build/bench_small_l2_decode.json
dart run tool/network_bench.dart --scenario=small_json --channels=dio,rust --initialize-rust=true --require-rust=true --consume-mode=json_model --requests=240 --concurrency=16 --output=build/bench_small_l2_model.json
dart run tool/network_bench.dart --scenario=large_json --channels=dio,rust --initialize-rust=true --require-rust=true --consume-mode=json_decode --requests=120 --concurrency=8 --output=build/bench_large_json_l2_decode.json
dart run tool/network_bench.dart --scenario=large_json --channels=dio,rust --initialize-rust=true --require-rust=true --consume-mode=json_model --requests=120 --concurrency=8 --output=build/bench_large_json_l2_model.json
dart run tool/network_bench.dart --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --consume-mode=json_model --requests=240 --concurrency=16 --jitter-base-ms=12 --jitter-extra-ms=80 --output=build/bench_jitter_l2_model.json
```

---

## 2) 执行前检查（2 分钟）

1. 工作区干净：`git status --short`
2. 依赖正常：`cd flutter_rust_net && flutter pub get`
3. 参数一致：同一轮比较中，除目标变量外不要改其他参数
4. Rust 严格对比：默认加 `--initialize-rust=true --require-rust=true`

---

## 3) 场景与目标（最小记忆版）

1. `small_json`
   - 目标：高频小包场景下对比尾延迟与吞吐。
2. `large_payload`
   - 目标：大包体场景下对比吞吐与稳定性。
3. `large_json`
   - 目标：大 JSON 场景下对比请求/端到端收益与 consume 成本。
4. `jitter_latency`
   - 目标：抖动网络下看 p95/p99（当前该项是重点复验项）。
5. `flaky_http`
   - 目标：服务端波动时看可用性、错误分布与吞吐退化幅度。

---

## 4) 判定顺序（先稳后快）

每个场景按这个顺序看：

1. `exceptions` / `exceptionRate`（必须先看）
2. `http5xx` + `fallbackCount`
3. `p95/p99`
4. `throughputRps`

---

## 5) 快速结论模板（每个场景一行）

```text
场景: <scenario>
结论: <Dio|Rust> 更适合
证据: p95=<...>, p99=<...>, throughput=<...>, exceptionRate=<...>, fallbackRate=<...>
动作: <保持 Dio / 路由到 Rust / 调整 fallback 与阈值>
```

---

## 6) 常见异常与处理

1. Rust 初始化失败
   - 现象：报告里 `skippedChannels.rust` 有原因。
   - 处理：先单独跑 `--channels=dio`；排查 Rust 初始化后再复测。
2. 压测结果抖动很大
   - 处理：同场景跑 3~5 次，取中位数；使用 A-B-B-A 交替顺序。
3. 503 比例不符合预期
   - 检查 `--flaky-every` 与请求总数是否对应（例如 240、every=4，理论 60 次 503）。
4. `jitter_latency` 中 Rust 反而更慢
   - 先复跑 5 次确认是否稳定复现。
   - 若稳定复现，进一步按并发梯度（例如 4/8/16/32）复测。
   - 对比 `endToEndLatencyMs` 和 `adapterCostLatencyMs`，判断是链路排队还是适配层开销。

---

## 7) 建议记录（提交可追溯）

跑完后在 `相关文档（按需）` 增加记录，至少包含：

1. `date`（例如：2026-02-24）
2. `commit`
3. `command`
4. `result`
5. `notes`（写 1~2 条关键结论）

---

## 8) 真机结果归档（2026-03-11 更新）

当前已确认的服务口径：

1. `baseUrl=http://47.110.52.208:7777`
2. `upload endpoint=/upload`
3. 登录接口：`POST /user/login`
4. 当前探测结果：
   - `GET /healthz -> 200`
   - `GET /bench/small-json?id=1 -> 200`
   - 未登录 `POST /upload -> 401`

真机侧可直接使用 `flutter_rust_net/example` 的 **Upload last report** 按钮上传。
但要注意：当前示例 App 预设默认仍产出 loopback 报告；若要归档“当前公网服务”报告，应优先使用 `tool/network_bench.dart --base-url=...` 生成 JSON，或自行扩展 example 暴露 `scenarioBaseUrl`。

若只是要快速留一份“可追溯的 non-loopback 样例”，优先使用固定入口：

```powershell
dart run tool/p1_non_loopback_bench.dart --preset=smoke --network-profile=ethernet --device=host_windows
```

该入口会固定生成：

1. benchmark JSON
2. `aggregate_small_json.(md|json)`
3. `aggregate_jitter_latency.(md|json)`
4. `run_manifest.json`
5. `logs/*.stdout.log` 与 `logs/*.stderr.log`

若带鉴权上传，再追加：

```powershell
dart run tool/p1_non_loopback_bench.dart --preset=smoke --network-profile=wifi --device=android_real --upload=true --upload-header=token:<actual-token>
```

建议使用 `flutter_rust_net/tool/upload_bench_log.dart` 归档 benchmark JSON：

```powershell
$runId=$(Get-Date -Format "yyyyMMdd_HHmm")
$day=$(Get-Date -Format "yyyyMMdd")
$networkProfile="wifi"
$device="android_real"
$linkType="public_remote"
$archivePrefix="flutter_rust_net/$day/$networkProfile/$device/$runId"

# 单文件上传
dart run tool/upload_bench_log.dart --input=build/bench_jitter.json --base-url=http://47.110.52.208:7777 --endpoint=/upload --remote-prefix=$archivePrefix --extra-field=project=flutter_rust_net --extra-field=run_id=$runId --extra-field=network_profile=$networkProfile --extra-field=device=$device --extra-field=link_type=$linkType

# 目录批量上传（默认递归，默认过滤 json/log/txt）
dart run tool/upload_bench_log.dart --input=build/p1_jitter/20260225_1448 --ext=json --base-url=http://47.110.52.208:7777 --endpoint=/upload --remote-prefix=$archivePrefix --extra-field=project=flutter_rust_net --extra-field=run_id=$runId --extra-field=network_profile=$networkProfile --extra-field=device=$device --extra-field=link_type=$linkType

# 建议优先使用 token 头；Authorization 兼容保留
dart run tool/upload_bench_log.dart --input=build/bench_small.json --base-url=http://47.110.52.208:7777 --endpoint=/upload --remote-prefix=$archivePrefix --extra-field=project=flutter_rust_net --extra-field=run_id=$runId --extra-field=network_profile=$networkProfile --extra-field=device=$device --extra-field=link_type=$linkType --header=token:<actual-token>
```

归档建议：

1. 目录层级优先使用 `--remote-prefix`，推荐格式：`flutter_rust_net/<YYYYMMDD>/<network_profile>/<device>/<run_id>`。
2. 最少额外字段：`project`、`run_id`、`network_profile`、`device`、`link_type`。
3. `network_profile` 建议只用固定枚举：`wifi` / `4g` / `weaknet` / `ethernet`。
4. `link_type` 建议只用固定枚举：`loopback` / `public_remote`。
5. 若服务端字段名不是 `file`，可通过 `--field-name=<name>` 覆盖。
6. 上传成功以 **HTTP 2xx** 为准；`upload_bench_log.dart` 输出里的 `status / costMs / response=<preview>` 视作本轮客户端回执，建议一并记入测试记录。
7. 未登录返回 `401` 时，应先排查 token / 登录态，不应直接判定上传服务失效。
8. 若本轮包含 P2 缓存收益样例，建议在归档记录中至少摘录：`cacheHit`、`cacheMiss`、`repeatedMissCount`、`reqP95`、`throughput`；若使用本地 scenario server，再补 `cacheRevalidate`、`cacheEvict`。
9. external `baseUrl` 口径下，`cacheRevalidate/cacheEvict` 当前不作为权威字段；若文档需要列出，建议显式写为 `n/a` 并备注“仅本地 scenario server 有权威值”。

P2 缓存收益摘录模板：

```text
channel=<dio|rust>
scenario=<jitter_latency|...>
requests=<N> warmup=<N> requestKeySpace=<N or n/a>
cacheHit=<N> cacheMiss=<N> repeatedMissCount=<N>
cacheRevalidate=<N or n/a> cacheEvict=<N or n/a>
reqP95=<ms> throughput=<req/s>
note=<external baseUrl / local scenario server / cold-start / warm-cache>
```

---

## 9) 你现在要做什么（按顺序）

1. 用 `small_json/large_payload/large_json` 先做接口白名单灰度（5% -> 25% -> 50% -> 100%）。
2. `jitter_latency` 默认保持保守路由，并对 `maxInFlightTasks=32` 做定向灰度复验。
3. 增补“Rust 端解析 JSON 并跨 FFI 回传对象”的专项 benchmark，验证文章主张边界。
4. （可选）把本轮命令和结论同步到 `相关文档（按需）`，并更新路由策略文档。
