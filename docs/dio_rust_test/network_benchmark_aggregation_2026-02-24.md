---
title: L1 传输层：Dio vs Rust 网络基准聚合结论（2026-02-24）
---

# L1 传输层：Dio vs Rust 网络基准聚合结论（2026-02-24）

> 目标：把 2026-02-24 当天的 benchmark 结果统一收敛成一份 L1（传输层）“可执行结论”，用于路由策略与后续验证。  
> 日期：2026-02-24（全部为 loopback：`127.0.0.1`）。

## 0) 文档定位（L1 传输层）

1. 本文是 2026-02-24 当日网络 benchmark 的唯一 L1 收敛文档（传输层）。
2. 已整合以下内容：
   - `flutter_rust_net/docs/dio_rust_test/network_realistic_benchmark_2026-02-24.md`（基线方案 + 首轮结果）
   - `flutter_rust_net/docs/dio_rust_test/network_benchmark_audit_2026-02-24.md`（jitter 并发梯度 + `maxInFlightTasks` 灵敏度）
   - `相关文档（按需）` 中的同轮执行记录
3. 本文结论只用于 L1：请求层时延/吞吐/错误/fallback/排队；不覆盖 L2 的 decode/model/UI/复杂对象回传成本。

## 1) 本次聚合覆盖范围

1. 基线场景对比（6 份报告）
   - `bench_small.json` / `bench_large.json` / `bench_jitter.json` / `bench_flaky.json` / `bench_fallback_on.json` / `bench_fallback_off.json`
2. `jitter_latency` 并发梯度复验（20 份报告，4 档并发 x 5 轮）
   - `bench_jitter_c{4,8,16,32}_r{1..5}.json`
3. `maxInFlightTasks` 灵敏度复验（18 份报告）
   - Rust-only：`bench_jitter_rust_c{16,32}_mif{12,32}_r{1..3}.json`
   - Dio+Rust 对照：`bench_jitter_c{16,32}_mif32_pair_r{1..3}.json`

总计：44 份 JSON 报告。

## 2) 快速背景：`jitter_latency` 是什么

1. 每个请求都会加“可控随机延迟”：`delay = baseDelayMs + id % (extraDelayMs+1)`。
2. 当前配置为 `base=12ms`、`extra=80ms`，即单请求延迟约 `12~92ms`。
3. 这个场景主要用于验证“抖动 + 并发”下的尾延迟（p95/p99）与排队放大，不代表所有日常流量都会触发。

## 3) 基线场景结论（单轮）

| 场景           | 参数                        |  Dio（p95/p99/tp） | Rust（p95/p99/tp） | 结论                        |
| -------------- | --------------------------- | -----------------: | -----------------: | --------------------------- |
| small_json     | requests=400, c=16          |   44 / 46 / 508.26 |  21 / 27 / 1078.17 | Rust 领先                   |
| large_payload  | requests=120, c=8           |  128 / 145 / 87.78 |   45 / 46 / 272.73 | Rust 显著领先               |
| flaky_http     | requests=240, c=16, every=4 |   33 / 34 / 750.00 |  13 / 16 / 1621.62 | 两边 5xx 同为 60，Rust 更快 |
| jitter_latency | requests=240, c=16          | 108 / 112 / 203.05 | 138 / 139 / 188.68 | Rust 落后（需复验）         |

fallback 演练：

1. 开启 fallback：`bench_fallback_on.json` 为 0 异常，`fallbackCount=120`。
2. 关闭 fallback：`bench_fallback_off.json` 为 120 异常（100%）。

## 4) `jitter_latency` 深挖结论（多轮）

### 4.1 并发梯度复验（5 轮中位数）

| 并发 |  Dio（p95/p99/tp） | Rust（p95/p99/tp） | 结论        |
| ---- | -----------------: | -----------------: | ----------- |
| c4   |   95 / 109 / 60.05 |   93 / 106 / 63.83 | Rust 优     |
| c8   | 107 / 110 / 112.73 |  94 / 103 / 125.07 | Rust 优     |
| c16  | 108 / 113 / 206.36 | 139 / 153 / 184.47 | Rust 劣     |
| c32  | 108 / 113 / 383.39 | 235 / 260 / 187.06 | Rust 显著劣 |

结论：拐点稳定出现在 `c8 -> c16`。

### 4.2 根因定位（已验证）

1. Rust 的 `adapterCostLatencyMs.avgMs` 基本稳定在 `~60-61ms`。
2. 但 `endToEndLatencyMs.avgMs` 在高并发显著上升，出现明显排队差值（`endToEnd - adapter`）。
3. 当 `maxInFlightTasks=12`：
   - c16：排队差值中位数 `19.98ms`
   - c32：排队差值中位数 `94.87ms`
4. 当 `maxInFlightTasks=32`：
   - c16：排队差值中位数降到 `2.01ms`
   - c32：排队差值中位数降到 `2.10ms`

即：高并发劣化主因是并发闸门导致的排队放大，不是适配器本体变慢。

### 4.3 `maxInFlightTasks=32` 的对照结果（3 轮中位数）

| 并发 |  Dio（p95/p99/tp） | Rust（p95/p99/tp） | 结论      |
| ---- | -----------------: | -----------------: | --------- |
| c16  | 104 / 110 / 224.30 |  95 / 104 / 245.15 | Rust 领先 |
| c32  | 107 / 111 / 391.52 |  94 / 105 / 460.65 | Rust 领先 |

## 5) 对客户端真实流量的意义

1. `jitter_latency` 更偏容量与极端稳定性压测，普通用户路径不一定持续命中 `c16/c32` 级并发。
2. 但在冷启动并发预拉取、弱网重试堆积、批量并发请求等边界场景，可能接近该模型。
3. 因此这轮结果价值在于“提前暴露容量阈值”，避免边缘场景尾延迟失控。

## 6) 可执行路由建议（仅 L1，按配置分支）

1. 若保持默认 `maxInFlightTasks=12`：
   - `jitter_latency` 建议 `<=8` 走 Rust，`>=16` 走 Dio，`8~16` 视业务继续补测（如 c12/c14）。
2. 若提升到 `maxInFlightTasks>=32`（且验证通过）：
   - `jitter_latency` 在 c16/c32 下 Rust 已恢复优势，可优先 Rust。
3. 其他已测场景（small/large/flaky）Rust 持续领先，但仍需结合真机网络与资源稳定性再做默认切换。

## 7) 本轮落地与后续（L1）

1. 已落地 benchmark 参数：支持 `--rust-max-in-flight`（默认 12），便于持续复验阈值。
2. 建议下一步按真机网络剖面补测（Wi-Fi / 4G / 弱网），并加入 30~120 分钟长稳压测。
3. 所有执行记录已整理到：`相关文档（按需）`。

## 8) L2 预留（暂不纳入本次提交）

1. L2 将新增 `bytes -> decode/json -> model -> UI` 全链路计时与资源指标。
2. L2 将单独评估 Rust 回传 bytes / 结构化对象 / 聚合后小结果三种路径。
3. 本文 L1 路由阈值会在 L2 完成后统一复核。

