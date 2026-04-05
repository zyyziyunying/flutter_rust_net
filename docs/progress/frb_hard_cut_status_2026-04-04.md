---
title: FRB Hard Cut 当前状态（2026-04-04）
---

# FRB Hard Cut 当前状态（2026-04-04）

> 范围：`flutter_rust_net` 的 FRB / legacy Rust surface 收敛执行状态。
>
> 当前判断：hard cut 已进入正式执行阶段；执行顺序已按当前代码树重排，Phase 1 与 Phase 2 已完成，当前主工作可转入 Phase 3 的 Dart-side legacy runtime 删除窗口。

## 快速跳转（当前有效）

- 当前执行计划：[`flutter_rust_net/docs/plan/2026-04-04-remove-frb-hard-cut-resequenced-plan.md`](../plan/2026-04-04-remove-frb-hard-cut-resequenced-plan.md)
- 被替代旧计划：[`flutter_rust_net/docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md`](../plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md)
- thin-gateway 设计：[`flutter_rust_net/docs/plan/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md`](../plan/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md)
- 当前项目状态评估：[`flutter_rust_net/docs/problems/2026-04-02-project-progress-and-gap-assessment.md`](../problems/2026-04-02-project-progress-and-gap-assessment.md)

## 文档口径（当前事实源）

- 本文只维护 FRB hard cut 的 `Done / In Progress / Next`。
- 计划顺序、验收口径与非目标以 `docs/plan/2026-04-04-remove-frb-hard-cut-resequenced-plan.md` 为准。
- 若后续 hard cut 影响 active docs、P1/P2 口径或业务准入判断，应在对应事实源同步回写。

## 1) 已完成（Done）

1. 已完成 hard cut 执行顺序重排：当前计划不再沿用“先删 runtime、后清 benchmark/tooling”的旧顺序，改为先清 benchmark/runtime 编译依赖，再做物理删除。
2. 已补充多视角审查结论并固化为当前计划输入：已明确 runtime/API、benchmark/tooling、validation/docs 三个方向的主要风险与顺序约束。
3. 已完成 Phase 1：冻结 surviving contract，保留 `NetChannel.rust` / `enableRustChannel` / `BenchmarkChannel.rust` 作为兼容名。
4. 已将 client/gateway 的公开注入 seam 中性化：`BytesFirstNetworkClient.standard()` 新增 `primaryAdapter`，`NetworkGateway` 新增 `primaryRequestAdapter`；`rustAdapter` 仅保留为 deprecated 兼容别名。
5. 已去掉 `BytesFirstNetworkClient.standard()` 对 legacy `RustAdapter` 初始化语义的显式要求；正常 V1 request happy path 不再暗示 FRB lifecycle 是默认前提。
6. 已完成 Phase 1 定向回归并通过：
   - `flutter test test/network/bytes_first_network_client_test.dart test/network/network_gateway/network_gateway_request_test.dart test/network/network_gateway/network_gateway_transfer_task_test.dart test/flutter_rust_net_test.dart`
7. 已完成 Phase 2：benchmark 主线已去掉对 FRB/runtime Dart 类型的编译依赖；`BenchmarkConfig` 不再暴露 `RustEngineInitOptions`、`initializeRust`、`requireRust`、`rustMaxInFlightTasks`、`rustCache*`，`runNetworkBenchmark()` 也已移除 `rustBridgeApi`。
8. 已将 benchmark request-channel 语义中性化：benchmark 主线改用 `primaryRequestAdapter` / `primaryChannelPreflighted`，同时保留 `BenchmarkChannel.rust` 作为兼容别名，deprecated `rustAdapter` 仅作注入兼容名。
9. 已重写 Phase 2 相关 benchmark 测试：不再依赖 FRB generated API 或 fake Rust bridge；`benchmark_runner_test.dart` 改为只验证中性的 primary request adapter seam。
10. 已做最小范围 benchmark CLI / example 迁移，使仓库内 active benchmark 调用点不再依赖被移除的旧引擎配置字段。
11. 已完成 Phase 2 定向回归并通过：
   - `flutter test test/network/benchmark_runner_test.dart test/network/benchmark_types_test.dart test/network/network_realistic_flow_test.dart`

## 2) 当前正在做（In Progress）

1. 准备 Phase 3 删除窗口：收拢仍直接依赖 `RustAdapter` / `RustBridgeApi` / FRB generated Dart API 的 runtime 与测试面，确保物理删除与测试重写在同一变更中完成。
2. 评估 Phase 4 的 P1 tooling 清理边界；`tool/p1_non_loopback_bench.dart` 与 `tool/p1_aggregate/` 仍保留历史 `rustMaxInFlightTasks` 口径，尚未并入本轮 Phase 2 迁移。

## 3) 下一步准备做（Next）

1. 执行 Phase 3：删除 Dart-side legacy runtime，并同步删除/重写直接依赖 `RustAdapter` / `RustBridgeApi` / FRB 的测试。
2. 在 runtime 物理删除的同一窗口更新 active docs/progress，明确旧 P1/P2 Rust 证据转为历史或 legacy-path-only，不再作为当前包契约。
3. 进入 Phase 4 时，再统一清理 benchmark/P1 tooling 与 example 文案中仍残留的历史 `rust`/`mif` 术语与聚合 schema。
