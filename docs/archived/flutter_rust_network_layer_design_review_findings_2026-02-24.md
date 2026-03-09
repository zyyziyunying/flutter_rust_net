---
id: bdf5a235-4552-4315-85c1-9c804735dbf8
title: Flutter + Rust 网络层架构评审问题记录（2026-02-24）
---

# Flutter + Rust 网络层架构评审问题记录（2026-02-24）

> 评审对象：`flutter_rust_net/docs/flutter_rust_network_layer_design.md`（当前版）  
> 评审时间：2026-02-24  
> 评审目标：先记录“高风险优先”的架构与实现偏差，供后续逐项修复。

## 1. 已修复清单

### F-01（Resolved）回退幂等保护已补齐

- 结论：已修复（2026-02-24）。
- 修复内容：Rust 失败后回退前增加请求安全性判定；仅幂等方法可自动回退，非幂等方法必须带 `Idempotency-Key`。
- 证据：
  - 代码：`flutter_rust_net/lib/network/network_gateway.dart:7`
  - 代码：`flutter_rust_net/lib/network/network_gateway.dart:61`
  - 代码：`flutter_rust_net/lib/network/network_gateway.dart:84`
  - 测试：`flutter_rust_net/test/network/network_gateway_test.dart:175`
  - 测试：`flutter_rust_net/test/network/network_gateway_test.dart:221`
- 单测验证：`flutter test test/network/network_gateway_test.dart`（6/6 通过）。

### F-02（Resolved）路由到 Rust 前的 readiness gate 已补齐

- 结论：已修复（2026-02-24）。
- 修复内容：命中 Rust 路由时先检查 `rustAdapter.isReady`；未就绪直接走 Dio，不再触发“先失败再 fallback”。
- 证据：
  - 代码：`flutter_rust_net/lib/network/net_adapter.dart:4`
  - 代码：`flutter_rust_net/lib/network/rust_adapter.dart:54`
  - 代码：`flutter_rust_net/lib/network/network_gateway.dart:39`
  - 测试：`flutter_rust_net/test/network/network_gateway_test.dart:41`
  - 测试：`flutter_rust_net/test/network/network_smoke_flow_test.dart:73`
  - 测试：`flutter_rust_net/test/network/network_realistic_flow_test.dart:147`
- 单测验证：`flutter test test/network`（28/28 通过）。

### F-03（Resolved）“传输任务”能力已纳入统一入口

- 结论：已修复（2026-02-24）。
- 修复内容：`NetAdapter`/`NetworkGateway`/`BytesFirstNetworkClient` 增加 `startTransferTask / pollTransferEvents / cancelTransferTask`，Rust 与 Dio 双通道均纳入统一入口；网关补齐 transfer 路由、readiness gate 与可控 fallback。
- 证据：
  - 代码：`flutter_rust_net/lib/network/net_adapter.dart:8`
  - 代码：`flutter_rust_net/lib/network/network_gateway.dart:58`
  - 代码：`flutter_rust_net/lib/network/bytes_first_network_client.dart:125`
  - 代码：`flutter_rust_net/lib/network/rust_bridge_api.dart:15`
  - 代码：`flutter_rust_net/lib/network/rust_adapter.dart:130`
  - 代码：`flutter_rust_net/lib/network/dio_adapter.dart:55`
  - 测试：`flutter_rust_net/test/network/network_gateway_test.dart:307`
  - 测试：`flutter_rust_net/test/network/rust_adapter_test.dart:112`
- 单测验证：`flutter test test/network`（32/32 通过）。

### F-04（Resolved）大响应落盘生命周期闭环已补齐

- 结论：已修复（2026-02-25）。
- 修复内容：Rust `clear_cache` 已实现（支持全量/namespace 清理并返回删除字节数）；Dart 在 `bodyFilePath` materialize 后执行 best-effort 删除；桥接层补齐 `clearCache` 调用入口，默认使用独立 cache 子目录。
- 证据：
  - 文档：`flutter_rust_net/docs/flutter_rust_network_layer_design.md:60`
  - 文档：`flutter_rust_net/docs/flutter_rust_network_layer_design.md:79`
  - 文档：`flutter_rust_net/docs/flutter_rust_network_layer_design.md:133`
  - 代码：`native/rust/net_engine/src/engine/client.rs:605`
  - 代码：`flutter_rust_net/lib/network/bytes_first_network_client.dart:202`
  - 代码：`flutter_rust_net/lib/network/benchmark/network_benchmark_harness.dart:873`
  - 代码：`flutter_rust_net/lib/network/rust_bridge_api.dart:21`
  - 代码：`flutter_rust_net/lib/network/rust_adapter.dart:181`
  - 测试：`native/rust/net_engine/src/engine/client.rs:759`
  - 测试：`flutter_rust_net/test/network/bytes_first_network_client_test.dart:42`
  - 测试：`flutter_rust_net/test/network/rust_adapter_test.dart:172`
- 单测验证：
  - `cargo test -q`（8/8 通过）
  - `flutter test test/network/bytes_first_network_client_test.dart test/network/rust_adapter_test.dart`（10/10 通过）

### F-05（Resolved）“完整链路信息”描述与实现已对齐

- 结论：已修复（2026-02-25）。
- 修复内容：`NetResponse` 增加 `requestId/fallbackError`，`NetTransferTaskStartResult` 增加 `fallbackError`，`NetException` 增加 `requestId`；Rust/Dio 映射统一填充 requestId；Rust -> Dio fallback 保留原始错误上下文。
- 证据：
  - 文档：`flutter_rust_net/docs/flutter_rust_network_layer_design.md:47`
  - 文档：`flutter_rust_net/docs/flutter_rust_network_layer_design.md:105`
  - 代码：`flutter_rust_net/lib/network/net_models.dart:173`
  - 代码：`flutter_rust_net/lib/network/network_gateway.dart:139`
  - 代码：`flutter_rust_net/lib/network/dio_adapter.dart:27`
  - 代码：`flutter_rust_net/lib/network/rust_adapter.dart:262`
  - 测试：`flutter_rust_net/test/network/network_gateway_test.dart:132`
  - 测试：`flutter_rust_net/test/network/rust_adapter_test.dart:67`
- 单测验证：`flutter test test/network`（34/34 通过）。

### F-06（Resolved）路由策略已收敛为测试模式单开关

- 结论：已修复（2026-02-25）。
- 修复内容：先补齐了请求侧抖动标签表达；随后按当前测试阶段目标将路由策略收敛为“总开关 + 强制通道”，不再依赖细粒度接口分流配置。
- 证据：
  - 文档：`flutter_rust_net/docs/flutter_rust_network_layer_design.md:93`
  - 文档：`flutter_rust_net/docs/dio_rust_test/network_route_strategy_2026-02-24.md:6`
  - 代码：`flutter_rust_net/lib/network/net_models.dart:23`
  - 代码：`flutter_rust_net/lib/network/net_feature_flag.dart:1`
  - 代码：`flutter_rust_net/lib/network/routing_policy.dart:14`
  - 测试：`flutter_rust_net/test/network/routing_policy_test.dart:24`
- 单测验证：`flutter test test/network/routing_policy_test.dart`（5/5 通过）。

### F-07（Resolved）fallback 资格边界已收敛

- 结论：已修复（2026-02-25）。
- 修复内容：Rust 未知/`internal` 错误统一映射为不可回退；网关 fallback 决策增加错误码白名单（`timeout/dns/tls/io/infrastructure`），即使错误被错误标记为 `fallbackEligible=true` 也不会对 `internal` 自动回退。
- 证据：
  - 文档：`flutter_rust_net/docs/flutter_rust_network_layer_design.md:100`
  - 代码：`flutter_rust_net/lib/network/rust_adapter.dart:452`
  - 代码：`flutter_rust_net/lib/network/network_gateway.dart:16`
  - 测试：`flutter_rust_net/test/network/rust_adapter_test.dart:104`
  - 测试：`flutter_rust_net/test/network/network_gateway_test.dart:226`
- 单测验证：`flutter test test/network`（39/39 通过）。

### F-08（Resolved）文档引用路径失效已修复

- 结论：已修复（2026-02-25）。
- 修复内容：设计文档路由策略引用改为存在的实际路径。
- 证据：
  - 文档：`flutter_rust_net/docs/flutter_rust_network_layer_design.md:96`
  - 实际文件：`flutter_rust_net/docs/dio_rust_test/network_route_strategy_2026-02-24.md:1`

### F-09（Resolved）“Rust 承担主力”文案与默认开关已对齐

- 结论：已修复（2026-02-25）。
- 修复内容：设计文档与代码默认开关已对齐到测试模式主通道：`enableRustChannel=true`，并保留总开关回切 Dio 的能力。
- 证据：
  - 文档：`flutter_rust_net/docs/flutter_rust_network_layer_design.md:139`
  - 代码：`flutter_rust_net/lib/network/net_feature_flag.dart:6`

## 2. 待修复问题清单（按严重度）

- 当前无待修复项（截至 2026-02-25）。

## 3. 处理建议（记录版）

- 当前优先级：无。（`F-01`~`F-09` 已修复）
- 每个问题修复后补充最小回归用例（尤其是回退、幂等、落盘清理、路由可配置性）。
- 修复完成后同步更新 `flutter_rust_net/docs/flutter_rust_network_layer_design.md`，确保“文档描述 = 实际行为”。
