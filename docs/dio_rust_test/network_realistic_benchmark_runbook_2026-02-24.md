---
title: Dio vs Rust 网络测试执行手册（2026-02-24，v3）
---

# Dio vs Rust 网络测试执行手册（2026-02-24，v3）

> 适用范围（2026-02-25 拆分后）：网络相关命令统一在 `flutter_rust_net` 执行；目标是快速、稳定地跑出可对比结论，并指导路由策略。

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

跑完后在 `docs/test_plans/test_run_log.md` 增加记录，至少包含：

1. `date`（例如：2026-02-24）
2. `commit`
3. `command`
4. `result`
5. `notes`（写 1~2 条关键结论）

---

## 8) 真机结果归档（2026-02-28 更新）

已确认日志上传入口：

1. `baseUrl=http://47.110.52.208:7777`
2. `upload endpoint=/upload`
3. 登录接口：`POST /user/login`（示例 App 上传前会先登录，再以请求头 `token: <actual-token>` 上传）

真机侧可直接使用 `flutter_rust_net/example` 的 **Upload last report** 按钮上传。

建议使用 `flutter_rust_net/tool/upload_bench_log.dart` 归档 benchmark JSON：

```bash
# 单文件上传
dart run tool/upload_bench_log.dart --input=build/bench_jitter.json --extra-field=project=flutter_rust_net --extra-field=network_profile=wifi

# 目录批量上传（默认递归，默认过滤 json/log/txt）
dart run tool/upload_bench_log.dart --input=build/p1_jitter/20260225_1448 --ext=json --extra-field=run_id=TR-20260228-XX --extra-field=device=android_real

# 如需鉴权头
dart run tool/upload_bench_log.dart --input=build/bench_small.json --header=Authorization:Bearer <token>
```

> 说明：若服务端字段名不是 `file`，可通过 `--field-name=<name>` 覆盖。

---

## 9) 你现在要做什么（按顺序）

1. 用 `small_json/large_payload/large_json` 先做接口白名单灰度（5% -> 25% -> 50% -> 100%）。
2. `jitter_latency` 默认保持保守路由，并对 `maxInFlightTasks=32` 做定向灰度复验。
3. 增补“Rust 端解析 JSON 并跨 FFI 回传对象”的专项 benchmark，验证文章主张边界。
4. 把本轮命令和结论写入 `docs/test_plans/test_run_log.md`，并同步到路由策略文档。
