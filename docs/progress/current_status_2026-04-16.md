---
title: 当前状态快照（2026-04-16）
---

# 当前状态快照（2026-04-16）

> 范围：`flutter_rust_net` 在 FRB hard cut 收尾完成后、`rhttp` 下载 benchmark V1 首轮落地后的仓库当前状态。
>
> 当前判断：项目主线仍稳定在 `rhttp + Dio` thin-gateway，当前阶段已经不是核心能力开发，而是下载 benchmark 的远端兼容验证与业务准入证据补齐。自 2026-04-08 状态快照之后，未出现需要重判阶段目标的新功能里程碑；2026-04-16 复核时包级测试基线仍通过，最近代码提交仅包含 `tool/p1_non_loopback_bench.dart` 的 1 行清理，不改变阶段判断。

## 快速跳转（当前关联文档）

- 项目概览：[`flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md`](../../FLUTTER_RUST_NET_OVERVIEW_ZH.md)
- 当前网络层设计：[`flutter_rust_net/docs/flutter_rust_network_layer_design.md`](../flutter_rust_network_layer_design.md)
- 上一版 active 状态快照（已归档）：[`flutter_rust_net/docs/progress/archive/current_status_2026-04-08.md`](./archive/current_status_2026-04-08.md)
- 历史 hard cut 状态快照：[`flutter_rust_net/docs/progress/archive/frb_hard_cut_status_2026-04-04.md`](./archive/frb_hard_cut_status_2026-04-04.md)
- 下载 benchmark 设计记录（legacy `docs/plans/` 路径）：[`flutter_rust_net/docs/plans/2026-04-07-rhttp-download-bench-design.md`](../plans/2026-04-07-rhttp-download-bench-design.md)
- 下载 benchmark 实施记录（legacy `docs/plans/` 路径）：[`flutter_rust_net/docs/plans/2026-04-07-rhttp-download-bench.md`](../plans/2026-04-07-rhttp-download-bench.md)
- 远端下载 benchmark 端点契约：[`flutter_rust_net/docs/design/2026-04-08-remote-download-benchmark-endpoint-contract.md`](../design/2026-04-08-remote-download-benchmark-endpoint-contract.md)

## 文档口径（当前阅读口径）

- 本文自 2026-04-16 起作为 `docs/progress/` 的 active 状态事实源。
- `archive/current_status_2026-04-08.md` 已转为历史快照，保留阶段交接价值，但不再代表当前最新状态。
- `docs/plans/2026-04-07-rhttp-download-bench*.md` 保留在 legacy flat `docs/plans/` 路径中，作为 2026-04-07 当次工作的设计与执行记录，不代表当前存在 active `docs/plan/`。

## 1) 已完成（Done）

1. `flutter_rust_net` 当前主线仍稳定在 `rhttp + Dio` thin-gateway 口径。
   - 请求主路径为 `RhttpAdapter`
   - fallback 与 transfer 路径为 `DioAdapter`
   - `NetChannel.rust` / `enableRustChannel` / `BenchmarkChannel.rust` 仅保留兼容命名
2. FRB / legacy runtime / package-local native engine 的 hard cut 收尾已完成，活动代码树未回退到旧 runtime surface。
3. 包级核心测试基线截至 2026-04-16 仍健康。
   - 当日实测 `flutter test` 通过
   - 结果为 `96 passed, 8 skipped`
   - 被跳过项仍属于 opt-in real-`rhttp` lane，依赖本地 `librhttp.dylib` 前置条件
4. 独立下载 benchmark V1 仍保持已落地状态。
   - 本地 `/bench/download-file` 场景端点已存在
   - `dio` / `rhttp` 下载到文件的 harness、校验与聚合报告已存在
   - `tool/rhttp_download_bench.dart` CLI wrapper 与对应 driver test 已存在
   - benchmark tests 已覆盖 scenario server、channel runner、harness/support
5. 2026-04-08 之后未出现新的功能性里程碑。
   - 最近代码提交为 2026-04-10 对 `tool/p1_non_loopback_bench.dart` 的 1 行清理
   - 当前阶段判断仍应保持为“核心开发完成，验证收口中”

## 2) 当前正在做（In Progress）

1. 当前无 blocking 的 hard-cut 主线工作项。
2. 下载 benchmark 这条线处于“远端兼容验证与长期证据补齐”阶段。
   - 代码、本地基础测试与本地 loopback smoke 已具备
   - fixed public remote base URL `http://47.110.52.208:7777` 仍未提供兼容的 `/bench/download-file?...` 端点
   - remote smoke 与 real-device / weak-network 证据仍未补齐
3. `docs/progress/` 已恢复为当前状态事实源；旧 active 快照已归档，后续状态变化应继续在本目录滚动维护。

## 3) 风险与缺口（Risk / Gap）

1. 下载 benchmark 的 remote smoke 仍被远端端点兼容性阻塞。
   - 当前兼容要求见 [`docs/design/2026-04-08-remote-download-benchmark-endpoint-contract.md`](../design/2026-04-08-remote-download-benchmark-endpoint-contract.md)
   - 在兼容端点未就绪前，`--base-url=...` 路径无法形成可靠对比证据
2. real-`rhttp` 仍非默认覆盖。
   - 未配置 `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` 且目录中无 `librhttp.dylib` 时，相关用例继续处于 opt-in 跳过状态
3. 业务准入证据仍不足。
   - 当前更接近“本地能力已验证”
   - 距离“可据此判断实际业务收益”仍缺 non-loopback / real-device / weak-network 样例

## 4) 下一步准备做（Next）

1. 优先补齐现有公网服务的 `/bench/download-file` 兼容端点，或提供新的兼容 base URL。
2. 兼容端点就绪后，补一次 `dio,rhttp` 的 remote smoke，并把结果回写到新的状态或验证文档。
3. 补 real-device / weak-network / non-loopback 样例，形成更接近业务准入的证据集。
4. 若后续阶段判断再次变化，继续新增新的 active 状态文档，并及时把旧 active 快照移入 `archive/`。

## 5) 本轮验证（2026-04-16）

本轮实际执行并通过：

- `flutter test`

本轮用于状态复核但不构成功能新增的检查：

- `git log --date=short --pretty=format:'%h %ad %s' -12`
- `git show --stat --summary --oneline c0acc81`
- `git show --unified=20 c0acc81 -- tool/p1_non_loopback_bench.dart`

本轮未执行：

- `flutter analyze`
- 兼容远端下载端点上的 remote smoke
