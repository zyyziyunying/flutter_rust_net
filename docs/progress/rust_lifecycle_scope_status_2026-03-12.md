---
title: Rust 生命周期与共享作用域修复状态（2026-03-12）
---

# Rust 生命周期与共享作用域修复状态（2026-03-12）

> 范围：`flutter_rust_net` 的 Dart 侧 Rust lifecycle / shared scope 修复闭环。
>
> 当前状态（2026-03-12）：`RustAdapter` 已补齐受控 `shutdown -> reinitialize` 生命周期；`RustBridgeApi.shutdownNetEngine()` 仅保留为低层 bridge passthrough，不再被视为会同步 Dart 生命周期状态。默认生产路径下“不同 `FrbRustBridgeApi` 实例共享同一默认 scope”的正式回归也已入库。

## 快速跳转（同日文档）

- 修复计划：[`flutter_rust_net/docs/plan/flutter_rust_net_lifecycle_scope_fix_plan_2026-03-12.md`](../plan/flutter_rust_net_lifecycle_scope_fix_plan_2026-03-12.md)
- 跟进问题：[`flutter_rust_net/docs/questions/flutter_rust_net_staged_review_followups_2026-03-11.md`](../questions/flutter_rust_net_staged_review_followups_2026-03-11.md)
- 风险审查：[`flutter_rust_net/docs/questions/flutter_rust_net_risk_review_findings_2026-03-09.md`](../questions/flutter_rust_net_risk_review_findings_2026-03-09.md)
- 架构概览：[`flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md`](../../FLUTTER_RUST_NET_OVERVIEW_ZH.md)

## 文档口径（事实源）

- 本文维护本专题的阶段结论与 `Done / In Progress / Next`。
- 具体实现细节以代码与测试为准；本文只记录当前事实，不重复展开完整设计推演。
- 若后续有更晚日期的专题文档与本文冲突，以日期更晚者为准，并应尽快回写本文或归档本文。

## 1) 已完成（Done）

1. 已为 `RustBridgeApi` 增加 `shutdownNetEngine()` 抽象，并由 `FrbRustBridgeApi` 转发到 FRB 已有的 `shutdownNetEngine()`；该入口当前仅表示低层 bridge shutdown passthrough，不负责同步 Dart 侧共享 lifecycle 状态。
2. 已为 `RustAdapter` 增加受支持的 `shutdownEngine()` 生命周期入口，`isReady` / `isInitialized` 不再只依赖本地 `_initialized` 布尔值。
3. 已在 `_RustAdapterInitTracker` 引入共享 `generation` 与串行化 lifecycle 状态，确保同一 scope 下的 `initialize` / `shutdown` 不会无序交错。
4. `shutdownEngine()` 成功后，同一 scope 下旧代次的所有 adapter 都会失效；旧 adapter 请求路径会抛出未初始化基础设施错误。
5. `shutdownEngine()` 成功后，同一 scope 已允许使用新配置重新初始化，旧的 `knownConfig` / `acceptedConfigWhenActualUnknown` 不会继续污染后续 restart。
6. `shutdownEngine()` 失败时，Dart 侧保持保守语义，不会误清空当前 scope 的已初始化状态。
7. 已新增 lifecycle 回归：`test/network/rust_adapter_lifecycle_test.dart`，覆盖单实例失效、同 scope 联动失效、shutdown 后重启、shutdown 失败保守状态。
8. 已新增默认生产路径共享 scope 回归：`test/network/rust_adapter_shared_scope_test.dart`，覆盖两个不同 `FrbRustBridgeApi` 子类实例的顺序初始化、并发同配置初始化，以及 shutdown 后重启。
9. 已同步 README / 架构文档中的公开约束：推荐使用 `RustAdapter.initializeEngine()` / `shutdownEngine()`，不直接依赖底层生成生命周期函数；`initialized` / `markInitialized()` 仅保留给 `requestHandler` 型 test double。

## 2) 当前正在做（In Progress）

1. 继续把后续示例代码、宿主接入代码和新增测试统一收口到 `RustAdapter` 生命周期入口。
2. `RustBridgeApi.shutdownNetEngine()` 仍是可见的低层 bridge 接口；当前通过合同说明降低误用概率，但不会自动同步 Dart tracker。

## 3) 下一步准备做（Next）

1. 若后续再调整 bridge 注入或 `FrbRustBridgeApi` 包装层，优先保留并先跑 `test/network/rust_adapter_shared_scope_test.dart`，避免真实默认路径回归被 fake bridge 测试掩盖。
2. 若未来需要支持“观察 Rust 当前真实配置”，再评估是否新增桥接合同；当前实现仍以 Dart 侧共享状态机为主。
3. 按需将本专题状态并入更高层阶段文档，避免 lifecycle 风险再次游离在阶段事实源之外。

## 4) 本轮验证

本轮已执行并通过：

```powershell
flutter analyze
flutter test
flutter test test/network/rust_adapter_test.dart
flutter test test/network/rust_adapter_lifecycle_test.dart
flutter test test/network/rust_adapter_shared_scope_test.dart
flutter test test/network/request_body_channel_consistency_test.dart
```
