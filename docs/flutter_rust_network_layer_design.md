---
id: 0ada581e-e2e8-40ff-99d9-f45af7fc1d99
title: Flutter + Rust 网络层当前架构（Review 版）
---
# Flutter + Rust 网络层当前架构（Review 版）

> 更新时间：2026-02-25  
> 用途：给后续评审使用的架构视图（仅保留架构与职责，不展开代码实现细节）。

## 1. 架构目标

- 以 Rust `NetEngine` 作为当前测试阶段默认请求通道，直接验证主通道稳定性与收益。
- 保留 `Dio` 作为回退与兼容通道，确保 Rust 不可用或失败时可快速切回。
- 在 Dart 侧统一路由、回退、观测口径，避免业务层感知双通道复杂度。
- 明确 FFI 边界：跨边界仅传输 `bytes` 或 `file path`，业务对象映射留在 Dart。

## 2. 分层架构（当前）

```text
Flutter UI / Repository / UseCase
            |
            v
      NetworkGateway
 (Routing + Fallback + Metrics)
        /                \
       v                  v
  DioAdapter         RustAdapter (FRB)
       |                  |
       v                  v
   Dio Stack        Rust NetEngine
                  (Client + Scheduler + EventBus)
```

### 2.1 代码落位（2026-02-25 拆分后）

- Flutter 网络层实现：`flutter_rust_net/lib/network/`
- Flutter FRB 生成代码：`flutter_rust_net/lib/rust_bridge/`
- 网络层测试：`flutter_rust_net/test/network/`
- 网络 benchmark 入口：`flutter_rust_net/tool/network_bench.dart`
- 独立示例承载：`flutter_rust_net/example/`（用于本地/真机快速回归）
- Android Rust 打包入口：`flutter_rust_net/example/android/app/build.gradle.kts`
- 应用集成侧（业务 app）：`media_kit_poc/pubspec.yaml` 通过 path 依赖 `../flutter_rust_net`

## 3. 组件职责

### 3.1 Flutter 业务层
- 发起统一网络请求，不直接依赖 Dio 或 Rust SDK。
- 在业务仓储层完成 `bytes -> JSON/Model` 解析与映射。

### 3.2 NetworkGateway（Dart）
- 单一入口：统一提供 `request / startTransferTask / pollTransferEvents / cancelTransferTask`。
- 对同步请求产出统一响应模型；对传输任务产出统一启动结果与事件模型。
- 根据路由策略选择 Dio 或 Rust 通道。
- 命中 Rust 时先做 readiness gate；未初始化直接走 Dio（`... -> rust_not_ready_dio`），避免“先失败再 fallback”。
- Rust 通道失败时执行可控回退到 Dio（请求与传输任务均受控）。
- 维护任务到通道的映射，保障 `cancel` 可以命中正确执行通道。
- 汇总链路信息（requestId、route reason、fallback reason、response/transfer channel）；触发 fallback 时保留原始错误上下文。

### 3.3 RoutingPolicy + FeatureFlag
- 负责总开关与强制通道的判定。
- `enableRustChannel=true` 时默认走 Rust，`enableRustChannel=false` 时默认走 Dio。
- 支持强制通道（用于实验、压测、线上排障）。
- 当前只有 `forceChannel` 和 `enableRustChannel` 会参与路由决策。
- 普通请求只保留 `expectLargeResponse` 作为 Rust 传输 hint；传输任务调度优先级通过 `NetTransferTaskRequest.priority` 表达。

### 3.4 DioAdapter
- 承担常规 API 请求通道。
- 输出统一响应结构（状态码、响应头、bytes）。
- 支持传输任务（下载/上传）启动、进度事件轮询与取消。

### 3.5 RustAdapter + FRB
- 将 Dart 请求规格桥接到 Rust 引擎。
- 承接 Rust 响应并映射为统一响应结构（inline bytes 或 file path）。
- 对 Rust 错误做统一分类并标记是否允许回退。
- 桥接传输任务能力：`start_transfer_task / poll_events / cancel`。
- 暴露 `clear_cache`，用于按 namespace 或全量清理 Rust 落盘缓存。
- 公开受支持的 lifecycle 入口为 `RustAdapter.initializeEngine()` / `shutdownEngine()`；不建议业务代码直接调用底层 FRB 生成的 `shutdownNetEngine()`。

### 3.6 Rust NetEngine
- 提供高并发 HTTP 能力与任务调度能力。
- 对大响应执行“内联返回 / 落盘返回路径”两种策略。
- 提供 `clear_cache(namespace)`，负责删除缓存目录中的落盘响应文件。
- 提供任务模型（下载/上传/进度事件/取消）。

## 4. 数据边界与解析策略

- 跨 FFI 边界不传业务对象图，只传原始数据载体：
  - 小响应：inline bytes
  - 大响应：file path
- 业务解码统一放在 Dart：
  - `raw response -> bytes materialize -> json/model decode`
- 当响应以 `file path` 返回时，Dart 在 materialize 后执行 best-effort 删除，避免临时文件长期残留。
- 支持主动清理：可通过 Rust `clear_cache` 对历史落盘文件做批量删除。
- 该策略的核心价值是：避免 Rust 对象与 Dart 对象之间的大规模双向重建开销。

## 5. 通道路由策略（2026-02-25 测试基线）

- `forceChannel` 显式指定时，直接按指定通道执行（`force_channel`）。
- 未指定 `forceChannel` 时：
  - `enableRustChannel=true`：走 Rust（`rust_enabled`）
  - `enableRustChannel=false`：走 Dio（`rust_disabled`）
- 命中 Rust 但 `rustAdapter.isReady=false` 时，直接走 Dio（`... -> rust_not_ready_dio`），不先触发失败再回退。
- 当前测试阶段不启用按接口/阈值分流，路由层只保留总开关 + 强制通道两类控制。

> 测试模式路由与回退说明详见：`flutter_rust_net/docs/dio_rust_test/network_route_strategy_2026-02-24.md`

## 6. 回退与稳定性策略

- 仅 Rust 通道触发回退，且必须满足：
  - 已开启 fallback 开关
  - 错误码在可回退白名单（`timeout/dns/tls/io/infrastructure`）
  - 错误被标记为可回退（通常为基础设施类瞬时错误）
- 不回退场景：业务语义错误（如明确 4xx）或 `internal`/未知错误
- 传输任务回退边界：
  - 下载任务允许回退
  - 上传任务必须满足幂等条件（幂等方法或显式 `Idempotency-Key`）
- 回退后响应保留完整链路信息（最终 requestId、原始 requestId 与原始错误上下文），便于按通道复盘。

## 7. 并发模型

- 并发执行由 Rust 运行时与引擎调度器承担。
- Dart 不依赖 Isolate 承担网络并发调度。
- Dart 主要负责发起请求、接收结果、执行业务解码。

## 8. 可观测性（当前最小集合）

- 路由层：QPS、p50/p95/p99、exception rate、5xx。
- 回退层：fallback count、fallback reason 分布。
- FFI 边界：bridge bytes（跨边界字节量）、inline/file 响应分布。
- 业务层：首屏时延、成功率、关键转化指标。

## 9. 评审重点（建议）

- 路由规则是否与当前测试目标一致（全量 Rust + 快速回退）。
- fallback 触发边界是否足够严格，避免掩盖业务错误。
- bytes-first 数据边界是否在所有新接口中被一致遵守。
- 观测指标是否能支撑“按接口、按通道”快速定位回归。
- 总开关回退流程是否可演练、可自动化。

## 10. 当前结论

- 当前架构已经是“Rust 主通道 + Dio 回退”的双通道形态（测试模式）。
- 同步请求与传输任务都已纳入统一入口治理，不再要求业务绕过网关直连 FRB。
- Rust 已作为默认主通道（`enableRustChannel=true`），可通过总开关快速切回 Dio；Dart 负责业务解码与编排。
- 大响应落盘文件已具备生命周期闭环（读取后清理 + `clear_cache` 主动清理）。
- 后续接入业务应用前，仍需补齐可观测与回退演练，确保切换策略可控。

