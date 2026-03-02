---
title: Dio vs Rust 网络基准审计报告（2026-02-24，jitter 并发梯度复验）
---

# Dio vs Rust 网络基准审计报告（2026-02-24，jitter 并发梯度复验）

> 目的：对 `jitter_latency` 做 5 轮 x 4 档并发复验，给出可落地的路由阈值。  
> 本次仅基于 20 个 JSON：`bench_jitter_c{4,8,16,32}_r{1..5}.json`。
> 归档说明：本报告关键结论已并入 `flutter_rust_net/docs/dio_rust_test/network_benchmark_aggregation_2026-02-24.md` 作为 L1 统一口径。

## 1) 输入数据（原始文件）

1. `media_kit_poc/build/bench_jitter_c4_r1.json` ~ `media_kit_poc/build/bench_jitter_c4_r5.json`
2. `media_kit_poc/build/bench_jitter_c8_r1.json` ~ `media_kit_poc/build/bench_jitter_c8_r5.json`
3. `media_kit_poc/build/bench_jitter_c16_r1.json` ~ `media_kit_poc/build/bench_jitter_c16_r5.json`
4. `media_kit_poc/build/bench_jitter_c32_r1.json` ~ `media_kit_poc/build/bench_jitter_c32_r5.json`

## 2) 参数一致性校验

20 个文件参数一致，只有并发不同（4/8/16/32）：

- `scenario=jitter_latency`
- `requests=240`
- `warmupRequests=12`
- `channels=[dio,rust]`
- `initializeRust=true`
- `requireRust=true`
- `jitterBaseDelayMs=12`
- `jitterExtraDelayMs=80`

## 3) 聚合结果（每档 5 轮，中位数）

| 并发 | 通道 | exceptions | http5xx | fallbackCount | p95(ms) | p99(ms) | throughput(req/s) |
| ---- | ---: | ---------: | ------: | ------------: | ------: | ------: | ----------------: |
| c4   |  dio |          0 |       0 |             0 |      95 |     109 |             60.05 |
| c4   | rust |          0 |       0 |             0 |      93 |     106 |             63.83 |
| c8   |  dio |          0 |       0 |             0 |     107 |     110 |            112.73 |
| c8   | rust |          0 |       0 |             0 |      94 |     103 |            125.07 |
| c16  |  dio |          0 |       0 |             0 |     108 |     113 |            206.36 |
| c16  | rust |          0 |       0 |             0 |     139 |     153 |            184.47 |
| c32  |  dio |          0 |       0 |             0 |     108 |     113 |            383.39 |
| c32  | rust |          0 |       0 |             0 |     235 |     260 |            187.06 |

## 4) 审计结论（按 runbook“先稳后快”）

### A. 可用性：全量通过

- 总请求量（双通道合计）：`9600`，完成数 `9600`。
- 20 文件中 Dio/Rust 均为：`exceptions=0`、`http5xx=0`、`fallbackCount=0`。

### B. 性能分段：Rust 只在低并发领先

- `c4`：Rust 优于 Dio（`p95 -2.1%`，`p99 -2.8%`，`throughput +6.3%`）。
- `c8`：Rust 优于 Dio（`p95 -12.1%`，`p99 -6.4%`，`throughput +10.9%`）。
- `c16`：Rust 落后 Dio（`p95 +28.7%`，`p99 +35.4%`，`throughput -10.6%`）。
- `c32`：Rust 显著落后 Dio（`p95 +117.6%`，`p99 +130.1%`，`throughput -51.2%`）。

### C. 性能拐点：发生在 `c8 -> c16`

- 逐轮胜负统计（Rust 胜出次数/5）：
  - `c4`: `p95/p99/tp = 4/5/5`
  - `c8`: `p95/p99/tp = 5/5/5`
  - `c16`: `p95/p99/tp = 0/0/0`
  - `c32`: `p95/p99/tp = 0/0/0`
- 该模式在 5 轮内稳定复现，不是偶发噪声。

### D. 根因线索：更像链路排队，不是适配层变慢

- Rust 的 `adapterCostLatencyMs.avgMs` 在各并发都稳定在约 `60~61ms`。
- 但 Rust 的 `endToEndLatencyMs.avgMs` 从 `c8` 的约 `61.8ms` 升到：
  - `c16` 约 `81.2ms`（额外排队约 `19.8ms`）
  - `c32` 约 `154.4ms`（额外排队约 `93.2ms`）
- Dio 的同类差值在各并发约 `0.02~0.03ms`，基本无排队放大。

### E. 一句话记录（当前批次）

- 除 `jitter_latency` 的高并发段（`c>=16`）外，当前批次结果里 Rust 基本占优。

## 5) 路由建议（仅针对 jitter_latency）

1. 并发 `<=8`：优先 Rust。
2. 并发 `>=16`：优先 Dio。
3. `8~16` 区间建议补测 `c12/c14` 后再固化阈值。

## 6) 备注与限制

1. 本轮流量是 loopback（`baseUrl=127.0.0.1`），结论先用于相对比较，不直接外推公网绝对值。
2. 当前是强制通道对比（`routeReasons.force_channel`），不是自动分流在线结果。
3. 本报告替代旧版“单个 `bench_jitter.json`”结论，避免单轮样本误导策略。

## 7) 补充验证（2026-02-24）：`maxInFlightTasks` 灵敏度复验

### A. 目的

- 验证 `c>=16` 时 Rust 劣化是否由 Rust 引擎并发闸门（`maxInFlightTasks=12`）触发。

### B. 本次新增数据

1. Rust-only（每组 3 轮）：
   - `media_kit_poc/build/bench_jitter_rust_c16_mif12_r{1..3}.json`
   - `media_kit_poc/build/bench_jitter_rust_c16_mif32_r{1..3}.json`
   - `media_kit_poc/build/bench_jitter_rust_c32_mif12_r{1..3}.json`
   - `media_kit_poc/build/bench_jitter_rust_c32_mif32_r{1..3}.json`
2. Dio+Rust 对照（每组 3 轮，`rustMaxInFlightTasks=32`）：
   - `media_kit_poc/build/bench_jitter_c16_mif32_pair_r{1..3}.json`
   - `media_kit_poc/build/bench_jitter_c32_mif32_pair_r{1..3}.json`

### C. Rust-only 结果（中位数）

| 并发 | Rust `maxInFlightTasks` | p95(ms) | p99(ms) | throughput(req/s) | endToEnd avg(ms) | adapter avg(ms) | 排队差值(ms) |
| ---- | ----------------------: | ------: | ------: | ----------------: | ---------------: | --------------: | -----------: |
| c16  |                      12 |     138 |     152 |            182.51 |            81.42 |           61.45 |        19.98 |
| c16  |                      32 |      93 |     107 |            245.40 |            63.20 |           61.18 |         2.01 |
| c32  |                      12 |     240 |     261 |            183.21 |           157.09 |           62.22 |        94.87 |
| c32  |                      32 |      95 |      98 |            473.37 |            61.75 |           59.65 |         2.10 |

### D. Rust-only 变化幅度（`12 -> 32`）

- `c16`：`p95 -32.6%`，`p99 -29.6%`，`throughput +34.5%`，排队差值 `-89.9%`。
- `c32`：`p95 -60.4%`，`p99 -62.5%`，`throughput +158.4%`，排队差值 `-97.8%`。

### E. Dio+Rust 对照（`rustMaxInFlightTasks=32`，中位数）

| 并发 | 通道 | p95(ms) | p99(ms) | throughput(req/s) |
| ---- | ---: | ------: | ------: | ----------------: |
| c16  |  dio |     104 |     110 |            224.30 |
| c16  | rust |      95 |     104 |            245.15 |
| c32  |  dio |     107 |     111 |            391.52 |
| c32  | rust |      94 |     105 |            460.65 |

### F. 补充结论

1. 高并发劣化主要由排队放大导致，`maxInFlightTasks=12` 是关键触发条件。
2. 将 Rust 并发闸门提升到 `32` 后，`c16/c32` 的高并发劣化不再复现。
3. 因此，第 5 节“`>=16` 走 Dio”仅适用于默认 `maxInFlightTasks=12` 配置；若配置为 `>=32`，`jitter_latency` 下 Rust 在 `c16/c32` 重新占优（基于本轮 loopback 结果）。

