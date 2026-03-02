---
title: P1 性能与容量瓶颈执行模板（2026-02-25）
---

# P1 性能与容量瓶颈执行模板（2026-02-25）

> 目标：围绕 `jitter + 高并发` 复验并固化 `maxInFlightTasks` 与路由阈值，产出可灰度的策略表。  
> 适用目录：`D:\dev\flutter_code\harrypet_flutter\flutter_rust_net`

## 0) 本轮要回答的 3 个问题

1. 并发分档目标：`c8/c16/c32` 下，Rust 是否可稳定优于或不劣于 Dio？
2. `maxInFlightTasks` 默认值：`12/24/32/48` 哪档收益-风险比最佳？
3. 路由阈值：在什么并发/接口特征下走 Rust，什么情况下保守走 Dio？

---

## 1) 执行矩阵

### 1.1 粗扫（L1）

- 场景：`jitter_latency`
- `concurrency`: `8,16,32`
- `rust-max-in-flight`: `12,24,32,48`
- 每组重复：`3` 轮
- 通道：`dio,rust`
- `consume-mode`: `none`
- 请求参数：`requests=360 warmup=24 jitter-base-ms=12 jitter-extra-ms=80`

### 1.2 复验（L2）

- 从每个并发档挑选 Top2 `maxInFlightTasks`
- 每组重复：`5` 轮
- `consume-mode`: `json_model`
- 其余参数保持与粗扫一致

---

## 2) 命令模板（PowerShell）

```powershell
$stamp = Get-Date -Format "yyyyMMdd_HHmm"
$cs = @(8,16,32)
$mifs = @(12,24,32,48)

foreach ($c in $cs) {
  foreach ($mif in $mifs) {
    foreach ($r in 1..3) {
      $out = "build/p1_jitter/$stamp/jitter_c${c}_mif${mif}_r${r}.json"
      dart run tool/network_bench.dart `
        --scenario=jitter_latency `
        --channels=dio,rust `
        --initialize-rust=true `
        --require-rust=true `
        --fallback=true `
        --consume-mode=none `
        --requests=360 `
        --warmup=24 `
        --concurrency=$c `
        --jitter-base-ms=12 `
        --jitter-extra-ms=80 `
        --rust-max-in-flight=$mif `
        --verbose=false `
        --output=$out
    }
  }
}
```

### 2.1 聚合命令（新增）

```powershell
dart run tool/p1_aggregate.dart `
  --input=build/p1_jitter `
  --scenario=jitter_latency `
  --consume-mode=none `
  --output-md=build/p1_jitter/p1_summary_none.md `
  --output-json=build/p1_jitter/p1_summary_none.json
```

---

## 3) 指标口径与计算

从 `channelResults[*]` 读取并按组统计中位数（group by: `concurrency + maxInFlightTasks + channel`）：

- 稳定性：`exceptions`, `exceptionRate`, `fallbackCount`
- 延迟：`requestLatencyMs.p95Ms`, `requestLatencyMs.p99Ms`, `endToEndLatencyMs.p95Ms`
- 吞吐：`throughputRps`
- 排队放大：`queueGapAvg = endToEndLatencyMs.avgMs - adapterCostLatencyMs.avgMs`

建议先按 L1 结果筛选，再用 L2 结果复核是否仍成立。

---

## 4) 验收阈值（建议）

### 4.1 硬门槛（不满足即淘汰）

1. `exceptionRate == 0`
2. `fallbackCount == 0`（严格对比轮次）
3. 无异常分布偏移（`exceptionCodes` 无新增高频类型）

### 4.2 性能门槛（按每组中位数）

1. Rust `reqP95 <= Dio * 1.05`
2. Rust `throughputRps >= Dio`
3. Rust `queueGapAvg <= 10ms`

---

## 5) 结果记录表（填空）

### 5.1 粗扫汇总（L1）

| concurrency | maxInFlight | channel | reqP95 | reqP99 | e2eP95 | throughput | exceptionRate | fallbackCount | queueGapAvg |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 | 12 | dio |  |  |  |  |  |  |  |
| 8 | 12 | rust |  |  |  |  |  |  |  |
| ... | ... | ... |  |  |  |  |  |  |  |

### 5.2 复验汇总（L2）

| concurrency | maxInFlight | channel | reqP95 | e2eP95 | consumeP95 | throughput | exceptionRate | queueGapAvg | 结论 |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 16 | 32 | dio |  |  |  |  |  |  |  |
| 16 | 32 | rust |  |  |  |  |  |  |  |
| ... | ... | ... |  |  |  |  |  |  |  |

---

## 6) 路由策略输出模板（P1 产物）

### 6.1 路由策略表（v0.1）

| 条件 | 默认通道 | 说明 |
| --- | --- | --- |
| `jitter && c<=8` | Rust | 已通过阈值，优先 Rust |
| `jitter && c>=16 && mif>=32` | Rust(灰度) | 先 5% 放量，观察 24h |
| `jitter && c>=16 && mif<32` | Dio | 保守策略 |
| 未覆盖场景 | Dio | 先保守，后续补测 |

### 6.2 灰度节奏

`5% -> 25% -> 50% -> 100%`，每档至少 24h。  
触发任一条件立即回切：

1. `exceptionRate > 0.5%`（5 分钟窗口）
2. `fallbackRate > 2%`（5 分钟窗口）
3. Rust `p95` 相对 Dio 基线恶化 > 20% 且持续 15 分钟

---

## 7) 本轮交付清单

1. 基准 JSON 报告目录（`build/p1_jitter/<stamp>/...`）
2. 聚合结论文档（建议新建 `network_benchmark_p1_aggregation_<date>.md`）
3. 路由策略更新（更新 `network_route_strategy_2026-02-24.md`）
4. 测试记录追加到 `docs/test_plans/test_run_log.md`

---

## 8) test_run_log 追加模板

| run_id | date | branch | commit | scope | command | result | notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TR-YYYYMMDD-XX | 2026-02-25 | main | <commit> | P1 jitter + mif sweep | `dart run tool/network_bench.dart ...` | PASS/FAIL | 关键结论：`mif=<x>` 在 `c16/c32` 达标/不达标 |
