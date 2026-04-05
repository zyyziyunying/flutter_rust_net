---
title: FRB Hard Cut 当前状态（2026-04-04，更新至 2026-04-05）
---

# FRB Hard Cut 当前状态（2026-04-04，更新至 2026-04-05）

> 范围：`flutter_rust_net` 的 FRB / legacy Rust surface hard cut 当前执行状态。
>
> 当前判断：Phase 1 ~ 6 已在当前 worktree 完成。active package 已收敛为 `rhttp + Dio` thin-gateway；剩余公开 `rustAdapter` seam 已移除，仓库级入口不再把已删除的 FRB/runtime/native-engine 口径描述成当前事实。

## 快速跳转（当前有效）

- 当前执行计划：[`flutter_rust_net/docs/plan/2026-04-04-remove-frb-hard-cut-resequenced-plan.md`](../plan/2026-04-04-remove-frb-hard-cut-resequenced-plan.md)
- 当前架构概览：[`flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md`](../../FLUTTER_RUST_NET_OVERVIEW_ZH.md)
- 当前网络层设计：[`flutter_rust_net/docs/flutter_rust_network_layer_design.md`](../flutter_rust_network_layer_design.md)
- 文档索引：[`flutter_rust_net/docs/README.md`](../README.md)

## 文档口径（当前事实源）

- 本文只维护 FRB hard cut 的 `Done / In Progress / Next`。
- 计划顺序、验收口径与非目标以 `docs/plan/2026-04-04-remove-frb-hard-cut-resequenced-plan.md` 为准。
- pre-hard-cut 的 P1/P2/Rust lifecycle 文档仍保留追溯价值，但只按历史资料解读。

## 1) 已完成（Done）

1. 已完成 Phase 1：冻结 surviving contract，保留 `NetChannel.rust` / `enableRustChannel` / `BenchmarkChannel.rust` 作为兼容名。
   - `BytesFirstNetworkClient.standard` 与 `NetworkGateway` 的活动 `rustAdapter` 公开 seam 已移除，统一收口到中性的 primary adapter 命名
2. 已完成 Phase 2：benchmark 主线已去掉对 FRB/runtime Dart 类型的编译依赖；公开 benchmark contract 改为 primary request adapter seam。
   - `runNetworkBenchmark(..., rustAdapter: ...)` 活动参数已移除
3. 已完成 Phase 3：Dart-side legacy runtime、FRB generated Dart files 与直接依赖测试已物理删除。
4. 已完成 Phase 4：benchmark/example/tooling 的 active 入口已改成 primary-channel 口径。
   - `tool/network_bench.dart` 保留 `BenchmarkChannel.rust` 兼容别名，但不再描述为 FRB/runtime
   - `tool/p1_non_loopback_bench.dart` 不再生成 `initialize-rust` / `require-rust` / `rust-max-in-flight` 之类已失效参数
   - `tool/p1_aggregate.dart` 输出已改为中性的 `variant / primary` 口径，并仅兼容读取历史 `rustMaxInFlightTasks`
   - example UI / README / Android wiring 不再暴露历史 Rust runtime 构建面
5. 已完成 Phase 5：FRB 依赖、配置、构建脚本与 package-local native engine 已删除。
   - 已删除 `flutter_rust_bridge` package dependency
   - 已删除 `flutter_rust_bridge.yaml`
   - 已删除 `tool/rust_codegen.dart`
   - 已删除 `tool/rust_build.dart`
   - 已删除 `tool/_rust_tool_utils.dart`
   - 已删除 `native/rust/net_engine/`
   - 已移除 `example/android/app/build.gradle.kts` 中的 Rust build wiring
6. 已完成 Phase 6：active docs/progress 已回写到 hard cut 后事实。
   - `README.md`
   - `FLUTTER_RUST_NET_OVERVIEW_ZH.md`
   - `docs/README.md`
   - `docs/flutter_rust_network_layer_design.md`
   - `docs/progress/README.md`
   - `docs/archived/2026-04-02-project-progress-and-gap-assessment.md`
   - `docs/archived/2026-04-02-rhttp-thin-gateway-design-review-status-check.md`
   - `docs/progress/p1_status_2026-02-25.md`
   - `docs/progress/p2_status_2026-03-02.md`
   - `docs/progress/rust_lifecycle_scope_status_2026-03-12.md`
   - `docs/progress/real_device_test_commands_2026-03-02.md`
   - `docs/plan/README.md`
   - `AGENTS.md`
   - opt-in real-`rhttp` 测试 skip/help 文案已改为中性 “native rhttp library directory” 表述，不再把 FRB 品牌词当作当前包契约说明
7. 已完成一轮最小 docs 归档治理：
   - superseded 旧计划已移入 `docs/plan/archive/`
   - pre-hard-cut 状态评估与设计状态核对已移入 `docs/archived/`
8. 已补 benchmark CLI 启动链路修复：`tool/network_bench.dart` 现为纯 Dart wrapper，实际 benchmark 执行转由 `tool/network_bench_driver_test.dart` 通过 `flutter test` driver 运行，恢复当前 workspace 下的可执行性。

## 2) 当前正在做（In Progress）

1. 无 blocking hard-cut 工作项。

## 3) 下一步准备做（Next）

1. 若要继续补业务准入证据，重点回到 non-loopback / real-device / weak-network 样例，而不是回滚已删除的 runtime surface。
2. 若后续要继续清理文档噪音，可按需把更多 pre-hard-cut runbook / review 文档继续归档或缩链。

## 4) 本轮验证

用户已在本轮开始前手动完成并确认：

- full `flutter test` 通过

本轮实际执行并通过：

- `flutter pub get`
- `flutter test test/network/bytes_first_network_client_test.dart test/network/cache_channel_consistency_test.dart test/network/network_gateway_transfer_state_test.dart test/network/benchmark_runner_test.dart`
- `flutter test`
- `cd example && flutter pub get`
- `dart run tool/network_bench.dart --help`
- `dart run tool/network_bench.dart --scenario=small_json --channels=dio --requests=1 --warmup=0 --concurrency=1 --verbose=false --output=build/network_bench_smoke.json`
- `dart run tool/p1_non_loopback_bench.dart --help`
- `dart run tool/p1_aggregate.dart --help`
- `flutter test test/network/benchmark_runner_test.dart test/network/benchmark_types_test.dart test/network/network_realistic_flow_test.dart`
- `cd example && flutter test test/widget_test.dart`

本轮未执行：

- `flutter analyze`
