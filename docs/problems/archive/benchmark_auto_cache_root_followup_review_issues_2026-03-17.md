---
title: flutter_rust_net benchmark auto cache root follow-up review 问题单（2026-03-17）
status: closed
---

# flutter_rust_net benchmark auto cache root follow-up review 问题单（2026-03-17）

> 用途：记录当前 git 暂存区继续严格复核后新增确认的问题，供提交决策与后续修复使用。
>
> 单一判断口径：以“总状态”一节为准。
>
> 范围：本次 benchmark 默认 run-unique cache root 变更、Rust engine 生命周期，以及对应 runbook / 问题单声明。

## 总状态

- 当前提交判断：`Ready`
- 阻塞项：`0`
- 已关闭问题：`2`
- 当前结论：benchmark 现已补上 Rust scope ownership：若 runner 在本次 run 内创建了 Rust engine，会在结束后自动 `shutdownEngine()`；若省略 `rustCacheDir` 触发 auto cache root，该目录也会在 `rustCacheObservation` 采样后按 benchmark-owned 临时目录 best-effort 清理。同一 Dart 进程连续两次 Rust benchmark 不再因 `cacheDir` 漂移失败，runbook / P2 / `2026-03-16` 问题单口径也已回写到修复后的真实状态

## 问题 1：默认 run-unique cache root 会与共享 Rust init scope 冲突，第二次 benchmark 直接失败

### 现象

- `runNetworkBenchmark()` 在 Rust 初始化前，会先把缺省 `rustCacheDir` 解析为 `_defaultBenchmarkRustCacheDir(startedAt)`。
- `_defaultBenchmarkRustCacheDir()` 每次都会生成不同的 `benchmark_<runId>` 子目录。
- 但 `_RustAdapterInitTracker` 对 `FrbRustBridgeApi` 使用共享 init scope；只要当前 Dart 进程里 Rust engine 还处于已初始化状态，就会拿新旧 `cacheDir` 做一致性比较。
- `runNetworkBenchmark()` 结束时只关闭 `ScenarioServer`，不会在“本次 benchmark 自己初始化了 Rust engine”之后执行 `shutdownEngine()`。

结果是：同一个 Dart VM 里连续两次调用 `runNetworkBenchmark()`，第二次即使传入相同 `BenchmarkConfig`，也会因为自动生成的新 `cacheDir` 与第一次不同，被 Rust init tracker 拒绝。

### 为什么这是问题

1. 示例页当前推荐顺序是先跑 `Dio vs Rust (small_json)`，再跑 `Dio vs Rust (jitter c16 mif32)`；按现状，第二个 Rust preset 会直接撞上配置冲突，而不是正常起跑。
2. benchmark 新文档把“省略 `--rust-cache-dir` 时自动分配本次 run 独占目录”描述成当前可直接依赖的默认行为，但没有同步写明“同进程重复运行必须 shutdown 或显式复用同一目录”。
3. 在本次 follow-up 复核当时，`docs/problems/archive/benchmark_root_budget_observation_review_issues_2026-03-16.md` 的总状态仍写成 `Ready / 阻塞项 0`，无法覆盖这个新回归。

### 已确认的最小复现

在同一个 Dart VM 内连续两次执行：

```dart
await runNetworkBenchmark(const BenchmarkConfig(
  scenario: BenchmarkScenario.smallJson,
  requests: 4,
  warmupRequests: 0,
  concurrency: 1,
  channels: {BenchmarkChannel.rust},
  initializeRust: true,
  requireRust: true,
  verbose: false,
));
```

实际观察到：

```text
first_ok:C:\Users\zyy\AppData\Local\Temp\harrypet_net_engine_cache\benchmark_1773717288343949_0
second_error:[rust] infrastructure: Rust engine already initialized with a different config; requested init options were ignored. Changed fields: cacheDir="...benchmark_1773717288343949_0" -> "...benchmark_1773717288615171_1"
```

### 涉及位置

- `lib/network/benchmark/benchmark_runner.dart`
- `lib/network/rust_adapter.dart`
- `lib/network/rust_adapter/rust_adapter_init.dart`
- `example/lib/pages/benchmark_page.dart`
- `docs/progress/real_device_test_commands_2026-03-02.md`
- `docs/problems/archive/benchmark_root_budget_observation_review_issues_2026-03-16.md`

### 建议修复

至少满足以下之一：

1. 若 benchmark 进程内自动初始化了 Rust engine，则 benchmark 结束后由 runner 自己负责 `shutdownEngine()`，避免把自动生成的 `cacheDir` 长驻为共享活动配置。
2. 若不打算在 benchmark 内 shutdown，则默认 `cacheDir` 不能按“每次 run 唯一”生成，而应在同一进程生命周期内保持稳定，并把这一限制写进文档。
3. 在收口前，示例页 / runbook / 问题单不应继续把当前状态表述为 `Ready`。

### 当前状态

- 状态：`Closed`
- 严重级别：`High`
- 收口说明：`RustAdapter` 现会记录当前 adapter 是否真正创建了活动 generation；`runNetworkBenchmark()` 只在 benchmark 自己创建 Rust scope 时执行 `shutdownEngine()`，不会越权关闭外部已持有的共享 scope。已新增 `test/network/benchmark_runner_test.dart` 覆盖同进程双次 Rust benchmark 与外部 scope 复用场景

## 问题 2：自动生成的 benchmark cache root 没有回收策略，文档把默认行为写得过于轻量

### 现象

- 自动生成的默认目录位于共享 temp root 下：`<systemTemp>/harrypet_net_engine_cache/benchmark_<runId>`。
- 当前代码只会统计该目录的 `rootBytes`，不会在 benchmark 结束后删除自动生成的目录，也不会清理历史 `benchmark_*` 子目录。
- `cacheRootMaxBytes` 只约束单个 benchmark run 实际使用的那个子目录，不能替代整个共享 temp root 的历史目录治理。

结果是：不显式传 `--rust-cache-dir` 时，benchmark 会持续在共享 temp root 下累积历史 `benchmark_*` 目录；如果只看新增文档，读者容易误以为这只是“无副作用的临时目录默认值”。

### 为什么这是问题

1. 这和“启用 root budget 时 `cacheDir` 必须是独占目录”的正式契约并不冲突，但会让 benchmark 默认行为变成“不断产出独占目录”，而不是“自动得到一块会被妥善回收的临时目录”。
2. 当前 runbook 已开始鼓励在不传 `--rust-cache-dir` 时依赖自动目录做首跑观测；如果不补回收语义或至少补明确告警，后续很容易在开发机上堆积 temp 垃圾。
3. `2026-03-16` 的问题单把现状总结为 `Ready / 阻塞项 0`，没有把这个 residual risk 保留下来。

### 本地观测

在完成上面的重复运行复现后，`C:\Users\zyy\AppData\Local\Temp\harrypet_net_engine_cache\` 下已经能直接看到残留的 `benchmark_*` 目录；当前 staged 代码没有对应删除路径。

### 涉及位置

- `lib/network/benchmark/benchmark_runner.dart`
- `lib/network/rust_adapter/rust_adapter_init.dart`
- `docs/progress/p2_status_2026-03-02.md`
- `docs/progress/real_device_test_commands_2026-03-02.md`
- `docs/problems/archive/benchmark_root_budget_observation_review_issues_2026-03-16.md`

### 建议修复

建议满足以下之一：

1. 对“benchmark 自动生成的 cacheDir”增加 ownership 语义，在 runner 结束后按策略清理。
2. 若短期内不做自动清理，文档必须显式写明：默认 auto cache root 只保证 run 隔离，不保证生命周期回收；长期使用应显式指定并自行治理 `--rust-cache-dir`。
3. 在本次 follow-up 复核当时，`docs/problems/archive/benchmark_root_budget_observation_review_issues_2026-03-16.md` 的总结需要补充这一 residual risk，不能只保留 `Ready` 结论。

### 当前状态

- 状态：`Closed`
- 严重级别：`Medium`
- 收口说明：runner 现把“auto-generated rust cache dir”视为 benchmark-owned 临时目录；在完成 `rustCacheObservation` 采样后会 best-effort 删除。显式传入的 `rustCacheDir` 仍由调用方自行治理

## 已做的局部验证

```powershell
flutter test test/network/benchmark_runner_test.dart test/network/benchmark_types_test.dart test/network/network_realistic_flow_test.dart test/network/rust_adapter/rust_adapter_initialization_test.dart
dart run tool/network_bench.dart --help
```

结果：

- 上述定向验证通过。
- 新增 `test/network/benchmark_runner_test.dart` 已覆盖“同一 Dart VM 连续两次跑 Rust benchmark”“auto cache root 会在采样后回收”以及“外部已初始化 scope 不会被 benchmark 越权 shutdown”三条关键路径。
- 本轮未运行 `flutter analyze`。

## 本轮处理结果

已按以下顺序收口：

1. 已修 benchmark 对 Rust engine 生命周期的 ownership 语义，明确自动 `cacheDir` 与共享 init scope 的关系。
2. 已补一条覆盖“同一进程连续两次 Rust benchmark”的 Dart 测试，避免问题回流。
3. 已回写 runbook / P2 进展 / `2026-03-16` 问题单，把结论同步到修复后的真实状态。

## 本次记录

- 日期：2026-03-17
- 记录人：Codex
- 来源：当前 git 暂存区严格 code review（继续复核补充）
