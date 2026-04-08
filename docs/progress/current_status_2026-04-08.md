---
title: 当前状态快照（2026-04-08）
---

# 当前状态快照（2026-04-08）

> 范围：`flutter_rust_net` 在 FRB hard cut 收尾之后、`rhttp` 下载 benchmark 首轮落地后的当前状态事实。
>
> 当前判断：项目主线已收敛为 `rhttp + Dio` thin-gateway，hard cut 收尾工作完成；最近新增的独立下载 benchmark 已完成代码与本地双通道 smoke 验证接线。包级基线测试当前通过；real-`rhttp` 原生库链路虽仍是 opt-in，但已在配置本地 native 库目录后完成本地 loopback 双通道实跑，未应被描述为默认已覆盖。

## 快速跳转（当前关联文档）

- 项目概览：[`flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md`](../../FLUTTER_RUST_NET_OVERVIEW_ZH.md)
- 当前网络层设计：[`flutter_rust_net/docs/flutter_rust_network_layer_design.md`](../flutter_rust_network_layer_design.md)
- 历史 hard cut 状态快照：[`flutter_rust_net/docs/progress/archive/frb_hard_cut_status_2026-04-04.md`](./archive/frb_hard_cut_status_2026-04-04.md)
- 下载 benchmark 设计：[`flutter_rust_net/docs/plans/2026-04-07-rhttp-download-bench-design.md`](../plans/2026-04-07-rhttp-download-bench-design.md)
- 下载 benchmark 实施计划：[`flutter_rust_net/docs/plans/2026-04-07-rhttp-download-bench.md`](../plans/2026-04-07-rhttp-download-bench.md)

## 文档口径（当前阅读口径）

- 本文是当前阶段的状态事实源，用于覆盖“`docs/progress/` 暂无 active 状态文档”的空档。
- `archive/frb_hard_cut_status_2026-04-04.md` 仍保留 hard cut 收尾快照价值，但按历史资料解读。
- `docs/plans/2026-04-07-rhttp-download-bench*.md` 描述的是下载 benchmark 的设计与执行计划，不自动代表最新执行状态。

## 1) 已完成（Done）

1. `flutter_rust_net` 当前主线已稳定在 `rhttp + Dio` thin-gateway 口径。
   - 请求主路径为 `RhttpAdapter`
   - fallback 与 transfer 路径为 `DioAdapter`
   - `NetChannel.rust` / `enableRustChannel` / `BenchmarkChannel.rust` 仅保留兼容命名
2. FRB / legacy runtime / package-local native engine 的 hard cut 收尾已完成，活动代码树不再把这些表述成当前实现事实。
3. 包级核心测试基线当前健康。
   - 2026-04-08 实测 `flutter test` 通过
   - 当次结果为 `96 passed, 8 skipped`
   - 被跳过项属于 opt-in real-`rhttp` lane，依赖本地 `librhttp.dylib` 前置条件
4. 独立下载 benchmark 首轮实现已落地。
   - 已补本地 `/bench/download-file` 场景端点
   - 已补 `dio` / `rhttp` 下载到文件的 harness、校验与聚合报告
   - 已补 `tool/rhttp_download_bench.dart` CLI wrapper 与 `tool/rhttp_download_bench_driver_test.dart` driver test
   - 已补相应 benchmark tests：scenario server、channel runner、harness/support
5. 当前 workspace 下下载 benchmark 的基本执行链路与本地双通道 smoke 已验证可用。
   - `dart run tool/rhttp_download_bench.dart --help` 可正常输出参数说明
   - 注入 `FRN_RHTTP_DOWNLOAD_BENCH_ARGS_JSON` 后，driver test 可在本地 loopback 模式下完成 `dio` 下载 smoke
   - `dart run tool/rhttp_download_bench.dart --channels=dio --requests=1 --warmup=0 --file-bytes=131072 --verbose=false --output=build/rhttp_download_local_smoke_dio.json` 已成功写出本地 JSON 报告
   - 配置 `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` 后，`flutter test test/network/benchmark/download_benchmark_channels_test.dart -r compact` 已实跑通过 `dio` 与 `rhttp` 两个下载通道用例
   - `dart run tool/rhttp_download_bench.dart --channels=dio,rhttp --requests=1 --warmup=0 --file-bytes=131072 --verbose=false --output=build/rhttp_download_local_smoke_dual.json` 已成功写出包含 `dio` 与 `rhttp` 双通道结果的本地 JSON 报告

## 2) 当前正在做（In Progress）

1. 当前无 blocking 的 hard-cut 主线工作项。
2. 下载 benchmark 这条线已从“设计/计划”进入“远端或长期留档证据补齐”阶段。
   - 代码、本地基础测试与 real-`rhttp` 本地双通道 smoke 已落地
   - fixed public remote base URL `http://47.110.52.208:7777` 当前对 `/bench/download-file?...` 返回 `404 Not Found`，尚不满足下载 benchmark remote smoke 所需端点契约
   - remote smoke 与 real-device / weak-network 证据仍未在当前状态文档下补齐
3. 文档层刚恢复 active 状态事实源；后续状态更新应继续回写 `docs/progress/`，不再只停留在计划文档里。

## 3) 下一步准备做（Next）

1. 若要继续把下载 benchmark V1 的证据补完整，优先在现有公网服务补齐 `/bench/download-file` 兼容端点或提供新的兼容 base URL 后补 remote smoke，并把结果回写到状态或验证文档。
2. 若要继续补业务准入证据，重点仍应放在 non-loopback / real-device / weak-network 样例，而不是回滚已删除的 legacy runtime surface。
3. 若后续下载 benchmark 的验证结论需要长期保留，可再决定是否单独沉淀到专门的 check/验证文档；在此之前，阶段状态仍以 `docs/progress/` 为准。

## 4) 本轮验证

本轮实际执行并通过：

- `flutter test`
- `dart run tool/rhttp_download_bench.dart --help`
- `FRN_RHTTP_DOWNLOAD_BENCH_ARGS_JSON='["--channels=dio","--requests=1","--warmup=0","--file-bytes=131072","--verbose=false"]' flutter test tool/rhttp_download_bench_driver_test.dart --plain-name=rhttp_download_bench_driver`
- `dart run tool/rhttp_download_bench.dart --channels=dio --requests=1 --warmup=0 --file-bytes=131072 --verbose=false --output=build/rhttp_download_local_smoke_dio.json`
- 以下两条命令中的 `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` 为当次机器上的实际值；复跑时应替换为本机包含 `librhttp.dylib` 的目录。
- `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR="$HOME/.pub-cache/hosted/pub.flutter-io.cn/rhttp-0.16.0/rust/target/release" flutter test test/network/benchmark/download_benchmark_channels_test.dart -r compact`
- `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR="$HOME/.pub-cache/hosted/pub.flutter-io.cn/rhttp-0.16.0/rust/target/release" dart run tool/rhttp_download_bench.dart --channels=dio,rhttp --requests=1 --warmup=0 --file-bytes=131072 --verbose=false --output=build/rhttp_download_local_smoke_dual.json`
- `curl -sS -D - 'http://47.110.52.208:7777/bench/download-file?bytes=32&chunkBytes=8&chunkDelayMs=0' -o /tmp/flutter_rust_net_remote_download_probe.bin`

本轮未执行：

- `flutter analyze`
- 兼容远端下载端点上的 remote smoke（当前 fixed public remote base URL `http://47.110.52.208:7777` 对 `/bench/download-file?...` 返回 `404 Not Found`）
