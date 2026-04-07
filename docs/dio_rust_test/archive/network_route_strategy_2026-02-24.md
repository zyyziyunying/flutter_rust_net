# 网络路由策略建议（2026-02-24，2026-02-25 测试模式更新）

> 当前项目尚未接入业务 App，本文件按“全量测试 Rust 主通道”执行方式更新。  
> 数据来源：`network_benchmark_aggregation_2026-02-24.md`、`network_realistic_benchmark_l2_summary_2026-02-24.md`、`network_large_json_validation_2026-02-24.md`（对应 `TR-20260224-03/04/05/07/08`）。

## 1) 当前默认路由策略（测试模式）

| 条件 | 执行通道 | routeReason |
| --- | --- | --- |
| `forceChannel` 已指定 | 按指定通道 | `force_channel` |
| 未指定且 `enableRustChannel=true` | Rust | `rust_enabled` |
| 未指定且 `enableRustChannel=false` | Dio | `rust_disabled` |
| 目标为 Rust 但 `rustAdapter.isReady=false` | Dio（readiness gate） | `... -> rust_not_ready_dio` |

说明：当前不执行按接口、阈值、标签的分流规则，仅保留“总开关 + 强制通道”。

## 2) 建议配置参数（当前）

### 2.1 FeatureFlag

```dart
const flag = NetFeatureFlag(
  enableRustChannel: true,
  enableFallback: true,
);
```

### 2.2 Rust 初始化

```dart
const rustInit = RustEngineInitOptions(
  maxInFlightTasks: 32,
  largeBodyThresholdKb: 256,
);
```

## 3) 与基准结果的关系

1. `small_json`（L2）Rust 明显领先：p95 降低约 73%，吞吐提升约 160%~175%。
2. `large_payload` Rust 显著领先：p95 降低约 65%，吞吐提升约 181%。
3. `large_json` Rust 仍领先：req p95 降低约 46%~50%，吞吐提升约 55%~56%。
4. `jitter_latency` 在 `c=16,mif=12` 时 Dio 更稳；`mif>=32` 后 Rust 可恢复优势。

## 4) 回退规则（必须落地）

满足回退资格时，由网关从 Rust 自动回退到 Dio：

1. `enableFallback=true`。
2. 错误码在可回退集合（`timeout/dns/tls/io/infrastructure`）。
3. 请求满足安全条件（幂等方法，或显式 `Idempotency-Key`）。

运维级回切使用总开关：`enableRustChannel=false`，立即切回 Dio 全量执行。

## 5) 监控面板最小集合

1. 按通道：QPS、p50/p95/p99、exceptionRate、5xx。
2. fallback：fallbackCount、fallbackReason 分布。
3. Rust 侧：`adapterCost`、`materializeBodyLatency`、队列/并发饱和度。
4. 业务指标：首屏时延、成功率、核心转化漏斗。

## 6) 当前执行结论

1. 测试阶段默认全量走 Rust，保留 Dio 作为自动回退与总开关回切通道。
2. 优先稳定跑通端到端观测、错误分层与回退演练，不在本阶段引入细粒度分流。
3. 待接入业务 App 后，再根据监控与业务风险决定是否恢复更细路由策略。

## 7) P1 复验更新（2026-02-25）

> 数据来源：  
> `build/p1_jitter/20260225_1440/p1_summary_none.md`（L1）  
> `build/p1_jitter/20260225_1448/p1_summary_model.md`（L2）

### 7.1 结果摘要

1. L1（36 报告）：失败仅 3 组（`c16/mif12`、`c32/mif12`、`c32/mif24`）。
2. L2（30 报告）：6 组复验全部通过（`json_model` 下无结论反转）。
3. 失败组均伴随 `queueGap` 放大，根因仍是并发闸门造成排队。

### 7.2 jitter 参数建议（当前）

1. 全局默认 `maxInFlightTasks=32`。
2. 高吞吐目标可尝试 `48`，但优先保持 `32` 作为主默认值。
3. 若临时回退到 `<32`，需重点关注 jitter 场景的 p95 与异常率。
