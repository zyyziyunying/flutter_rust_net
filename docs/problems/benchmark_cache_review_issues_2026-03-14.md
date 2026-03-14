---
title: flutter_rust_net benchmark / cache review 问题记录（2026-03-14）
status: resolved
---

# flutter_rust_net benchmark / cache review 问题记录（2026-03-14）

> 范围：本次 review 覆盖 benchmark 代码改动、已更新文档，以及 `build/remote_cache_probe_20260313/` 本地执行产物样例 JSON。
>
> 当前判断（2026-03-14）：本文记录的 3 个问题已完成首轮修复，保留为修复留痕与后续复核入口。
>
> 本文用途：记录本次 review 的问题、影响、建议修复方向与验证状态，后续处理结果直接回写本文。

## 结论

本轮记录的问题如下：

1. external `baseUrl` benchmark 默认注入 `x-network-bench-channel`，会改变真实链路请求形态，并进入 Rust 缓存 key。
2. `cacheEvict` 的口径当前混合了客户端 repeated-miss 近似值与 scenario server repeated-origin 信号，本地场景下与 `cacheRevalidate` 的边界不再稳定。
3. 文档把 `build/remote_cache_probe_20260313/` 描述成“仓库内事实样例”，但 `build/` 实际被忽略，样例 JSON 不会随仓库提交流转。

## 问题 1：external benchmark 请求头改变了真实链路形态

### 现象

修复前 benchmark runner 会将 bench channel header 固定为始终注入：

- `lib/network/benchmark/benchmark_runner.dart`
  - `const includeBenchChannelHeader = true;`
  - `_buildRequest()` 中会追加 `x-network-bench-channel`
- `native/rust/net_engine/src/engine/cache/key.rs`
  - Rust 缓存 key 会纳入普通请求头（仅排除条件请求头）

这意味着 external `baseUrl` 路径下：

1. 请求不再是原始业务请求形态。
2. Rust 通道的缓存 key 会包含这个 benchmark 专用 header。
3. 中间层/CDN/WAF 若对未知 header 有差异化处理，remote probe 结果可能被放大或扭曲。

### 为什么这是问题

这次改动的目标之一是补“真实链路缓存收益样例”。如果 external 路径天然带着 benchmark 专用 header：

1. 样例结果不再是纯业务形态下的真实链路。
2. Rust 缓存收益可能部分来自“带 header 的独立 key 空间”，而不是纯 URL/业务头部维度的命中行为。
3. 后续把这些结论外推到真机或业务接口时，可信度会下降。

### 代码位置

- `lib/network/benchmark/benchmark_runner.dart:87`
- `lib/network/benchmark/benchmark_runner.dart:281`
- `native/rust/net_engine/src/engine/cache/key.rs:21`

### 修复建议

至少满足以下之一：

1. external `baseUrl` 默认不注入 `x-network-bench-channel`，只在本地 scenario server 口径下开启。
2. 若 external 路径仍要保留该 header，则应明确把它定义为“观测专用请求形态”，文档中不能再称为原始真实链路样例。
3. 若需要 external repeated-origin 观测，建议改为单独 telemetry 参数或 query 标记，并确保不会进入 Rust 缓存 key。

### 当前状态

- 状态：`Resolved`
- 严重级别：`Medium`
- 处理结果（2026-03-14）：external `baseUrl` 路径已改为不注入 `x-network-bench-channel`，只在本地 scenario server 口径下携带该 header。

## 问题 2：`cacheEvict` 指标口径发生混合

### 现象

修复前 `cacheEvict` 同时来源于两套统计：

1. 客户端侧：
   - `lib/network/benchmark/benchmark_accumulator.dart`
   - 对“重复 requestKey 且 `fromCache=false`”直接计入 `cacheEvict`
2. scenario server 侧：
   - `lib/network/benchmark/benchmark_scenario_server.dart`
   - `conditionalRequests` 与 `repeatedOriginRequests` 分开统计
3. 汇总侧：
   - `lib/network/benchmark/benchmark_runner.dart`
   - 最终对 `cacheEvictCount` 使用 `max(result.cacheEvictCount, telemetry.repeatedOriginRequests)`

这样一来，本地场景下 `cacheEvict` 已不再是单一来源指标。

### 为什么这是问题

当前文档仍在表述：

- `cacheRevalidate` 承载条件请求信号
- `cacheEvict` 承载重复回源信号

但在实现层面，客户端近似统计已经把“重复 key 且未命中缓存”的所有情况都算进 `cacheEvict`。后续一旦出现：

1. 带 validator 的重复请求返回 200；
2. 某些请求因为实现细节未命中 `fromCache`，但本质不是 eviction；
3. 本地/远端两套统计来源同时存在且数值不同；

`cacheEvict` 的含义就会变成混合口径，和文档中的单一语义不再一致。

### 代码位置

- `lib/network/benchmark/benchmark_accumulator.dart:66`
- `lib/network/benchmark/benchmark_runner.dart:112`
- `lib/network/benchmark/benchmark_scenario_server.dart:309`

### 修复建议

建议二选一：

1. 严格拆分字段：
   - `cacheEvict` 仅表示服务端/权威 repeated-origin
   - 客户端近似值改成新字段，例如 `repeatedMissCount`
2. 保留单字段，但同步修改所有文档与报告口径，明确它是“客户端/服务端混合近似指标”，不再把它表述成单一 eviction 信号。

若继续沿用当前实现，建议至少补一组含 validator 的本地 benchmark 回归，防止 `revalidate` 与 `evict` 口径继续漂移。

### 当前状态

- 状态：`Resolved`
- 严重级别：`Medium`
- 处理结果（2026-03-14）：客户端侧 repeated miss 已拆分为 `repeatedMissCount`；`cacheEvict` 仅保留本地 scenario server 的权威 repeated-origin 统计，external 路径不再混入近似值。

## 问题 3：样例 JSON 未真正沉淀到仓库

### 现象

修复前文档曾多次引用以下路径作为“仓库内事实样例”：

- `build/remote_cache_probe_20260313/remote_jitter_cache_cold.json`
- `build/remote_cache_probe_20260313/remote_jitter_cache_warm.json`

但仓库根 `.gitignore` 已忽略 `build/`：

- `.gitignore`
  - `/build/`

因此：

1. 这两份 JSON 当前不会进入 staged 变更。
2. 其他 reviewer / CI / 新 clone 环境无法直接获得这份样例。
3. 文档所说“仓库内事实样例”与仓库真实可见状态不一致。

### 为什么这是问题

这不会直接影响运行时行为，但会影响结论留档与复核：

1. 文档引用的证据无法随提交流转。
2. 后续读者只能看到摘要数字，看不到原始报告 JSON。
3. 若后面数据重跑，当前样例无法做逐字段比对。

### 代码/文档位置

- `docs/dio_rust_test/network_public_remote_cache_probe_2026-03-13.md:8`
- `docs/progress/p2_status_2026-03-02.md:47`
- `docs/progress/real_device_test_commands_2026-03-02.md:154`
- `.gitignore:30`

### 修复建议

至少满足以下之一：

1. 将需要长期留档的 benchmark 样例迁移到可提交目录，例如 `docs/fixtures/` 或 `docs/dio_rust_test/samples/`。
2. 若仍保留在 `build/`，则文档应改成“本地执行产物样例”，不要再表述为仓库内事实样例。
3. 最少在文档中附上关键字段摘录和生成日期，避免原始 JSON 丢失后结论完全不可追溯。

### 当前状态

- 状态：`Resolved`
- 严重级别：`Low`
- 处理结果（2026-03-14）：相关文档已改成“本地执行产物样例/摘要”表述，不再把 `build/` 目录产物描述成仓库内事实样例。

## 验证情况

本次 review 期间已完成的定向验证：

```powershell
cargo test -q clear_cache_rejects_blank_namespace --manifest-path native/rust/net_engine/Cargo.toml
cargo test -q clear_cache_keeps_materialized_response_files_outside_cache_root --manifest-path native/rust/net_engine/Cargo.toml
```

结果：

1. 两个 Rust 定向测试均通过。
2. 新增 Dart 定向 `flutter test` 在当前环境中均超时，未能确认通过或失败。

## 后续处理建议

建议按以下顺序继续补强：

1. 若需要 external 链路的权威 repeated-origin / revalidate 统计，补独立 telemetry 方案，避免重新把观测字段混进 cache key。
2. 若需要长期留档原始 benchmark JSON，再将关键样例迁移到可提交目录，例如 `docs/dio_rust_test/samples/`。
3. 补一组包含 validator 的本地 benchmark 回归，继续守住 `revalidate/evict/repeatedMiss` 三者边界。

## 本次记录

- 日期：2026-03-14
- 记录人：Codex
- 来源：本次针对代码改动、已更新文档与 `build/remote_cache_probe_20260313/` 的 review
- 问题数量：3
- 当前是否阻塞提交：否
