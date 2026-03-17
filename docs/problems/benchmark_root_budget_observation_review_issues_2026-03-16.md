---
title: flutter_rust_net benchmark root budget 观测 review 问题单（2026-03-16）
status: closed
---

# flutter_rust_net benchmark root budget 观测 review 问题单（2026-03-16）

> 用途：记录当前 git 暂存区严格复核后确认的未收口问题，供提交决策与后续修复使用。
>
> 单一判断口径：以“总状态”一节为准。
>
> 范围：本次 benchmark root budget 配置接线、报告观测口径与对应文档声明。

## 总状态

- 当前提交判断：`Ready`
- 阻塞项：`0`
- 已关闭问题：`2`
- 当前结论：benchmark 现已补齐“默认 cache root 隔离”“报告展示实际生效配置”以及“benchmark-owned Rust scope 自动收口”三项缺口；`rustCacheObservation.rootBytes` 与报告中的 `config.rustCache*` 字段可作为同一次 benchmark run 的归档依据使用。若省略 `rustCacheDir` 走 auto cache root，该路径会记录到报告，但在 benchmark 结束后由 runner best-effort 清理

## 问题 1：默认共享 cache root 会污染 `rootBytes` 观测与样例结论

### 现象

- `BenchmarkConfig.rustCacheDir == null` 时，会通过 `resolveRustCacheDirPath()` 落到固定默认目录，而不是当前 benchmark run 独占目录。
- `runNetworkBenchmark()` 在 Rust 初始化成功后，会对这个目录做递归文件大小统计，并把结果写入 `rustCacheObservation.rootBytes`。
- 同一默认目录还会被 Rust cache 真正使用；若启用 `cacheRootMaxBytes`，本次 benchmark 会在这个共享目录上执行 root prune。

这意味着：不显式传 `--rust-cache-dir` 时，历史 benchmark、手工调试、甚至其他调用路径遗留的缓存文件，都可能直接进入这次报告里的 `rootBytes` 与缓存命中结论。

### 为什么这是问题

当前新增文档与 runbook 已开始把 `rustCacheObservation.rootBytes` 当成 root budget 归档依据之一。但如果默认路径不是“每次 run 独占”：

1. cold / warm 样例可能从一开始就带着旧残留，无法解释真实起量过程。
2. `rootBytes` 可能反映的是“共享目录累计状态”，而不是当前这次 benchmark 产生的占用。
3. 打开 `cacheRootMaxBytes` 后，本次 benchmark 还可能清理掉不属于当前 run 的旧文件，进一步放大结果的不确定性。

### 涉及位置

- `lib/network/benchmark/benchmark_config.dart`
- `lib/network/rust_adapter.dart`
- `lib/network/rust_adapter/rust_adapter_init.dart`
- `lib/network/benchmark/benchmark_runner.dart`

### 建议修复

至少满足以下之一：

1. 只要 benchmark 需要 Rust cache 观测或 root budget，就强制要求显式传入 `rustCacheDir`。
2. 若仍允许省略 `rustCacheDir`，则默认生成“本次 run 唯一”的 cache root，并把实际路径写入报告。
3. 在代码收口前，不应把默认路径下得到的 `rootBytes` 作为稳定归档结论写入文档。

### 当前状态

- 状态：`Closed`
- 严重级别：`High`
- 收口说明：`BenchmarkConfig.resolveRuntimeConfig()` 现会在 benchmark 实际初始化 Rust 时把缺省 cache root 解析为“本次 run 独占目录”，`runNetworkBenchmark()` 也会把这份实际配置写入 `BenchmarkReport.config` 与 `rustCacheObservation`；若本次 run 自己创建了 Rust scope，runner 结束时还会自动 `shutdownEngine()` 并清理该 auto cache root，避免同进程双跑冲突与 temp 残留

## 问题 2：报告输出的是原始输入配置，不是 Rust 实际生效配置

### 现象

- `BenchmarkReport.toJson()` 与 `toPrettyText()` 直接读取 `BenchmarkConfig` 中的原始字段。
- 但 Rust 初始化前后会对部分缓存配置做归一化或语义改写：
  - `cacheRootMaxBytes: 0` 会按“未启用 root budget”处理，实际等价于 `null`
  - `cacheMaxNamespaceBytes: 0` 会在 Rust 侧回落到默认 namespace budget，而不是字面意义上的 `0`
  - `cacheDir`、`cacheResponseNamespace` 也会经过 trim / normalize 后才进入真正的 init config

结果是：报告里看到的缓存配置，不一定等于 Rust 实际生效配置。

### 为什么这是问题

这次变更的核心目标之一，是让 benchmark 报告能解释 root budget 行为。但如果报告展示的还是原始输入值：

1. 归档可能出现“报告写的是 0，实际生效却不是 0”的配置分叉。
2. 后续读者无法仅凭 JSON / pretty text 判断 Rust 当时究竟以什么参数运行。
3. 文档把这些字段描述成“已接好的观测口径”时，会高估报告的解释力。

### 涉及位置

- `lib/network/benchmark/benchmark_report.dart`
- `lib/network/benchmark/benchmark_config.dart`
- `lib/network/rust_adapter/rust_adapter_init.dart`
- `native/rust/net_engine/src/engine/client/mod.rs`

### 建议修复

建议满足以下之一：

1. benchmark 报告直接输出实际用于 init 的归一化后配置。
2. 若短期内拿不到 Rust 真实 active config，则 benchmark 层至少先按现有 Dart/Rust 语义做同口径归一化，再落到报告。
3. 文档在修复前应避免把这些字段表述成“Rust 实际生效配置”的权威记录。

### 当前状态

- 状态：`Closed`
- 严重级别：`High`
- 收口说明：benchmark 报告现改为记录运行时实际生效的 Rust cache 配置；`cacheDir` trim、`cacheResponseNamespace` trim、`cacheMaxNamespaceBytes=0 -> 默认值`、`cacheRootMaxBytes=0 -> null`、以及“缓存关闭时忽略 namespace/root budget”都已按 Rust init 口径归一化

## 已做的局部验证

```powershell
flutter test test/network/benchmark_runner_test.dart test/network/benchmark_types_test.dart test/network/network_realistic_flow_test.dart test/network/rust_adapter/rust_adapter_initialization_test.dart
dart run tool/network_bench.dart --help
```

结果：

- 上述定向验证均通过。
- 这些验证已覆盖 benchmark 运行时 cache root 隔离、实际生效配置归一化、同进程双次 Rust benchmark 生命周期收口，以及原有 Rust init 配置一致性回归。
- 本轮未运行 `flutter analyze`。

## 后续处理建议

建议按以下顺序推进：

1. 继续补 external / Android / iOS 归档样例，确认 `rootBytes` 与 `cacheRootMaxBytes` 在真实链路下保持可解释。
2. cold / warm 若需要复用同一 cache root，继续显式传入同一个 `--rust-cache-dir`；若只想要干净首跑观测，可直接依赖 benchmark 自动生成的 run 独占目录，但该目录会在 benchmark 结束后被 runner best-effort 清理。
3. 若后续仍发现 root budget 行为难以解释，再考虑追加更细粒度的 root usage 观测字段；当前无需再回退本问题单结论。

## 本次记录

- 日期：2026-03-16
- 记录人：Codex
- 来源：当前 git 暂存区严格 code review
