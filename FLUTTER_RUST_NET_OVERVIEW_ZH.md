# flutter_rust_net 项目作用与实现概览（中文）

## 快速跳转（当前有效）

- 当前执行状态：[`docs/progress/frb_hard_cut_status_2026-04-04.md`](./docs/progress/frb_hard_cut_status_2026-04-04.md)
- 当前执行计划：[`docs/plan/2026-04-04-remove-frb-hard-cut-resequenced-plan.md`](./docs/plan/2026-04-04-remove-frb-hard-cut-resequenced-plan.md)
- 文档索引：[`docs/README.md`](./docs/README.md)

## 文档口径

- 本文描述 hard cut 后的当前架构与能力边界。
- 历史 P1/P2/Rust lifecycle 资料仍保留，但只作为 legacy/pre-hard-cut 证据。
- 当前阶段状态以 `docs/progress/frb_hard_cut_status_2026-04-04.md` 为准。

## 1) 这个库现在是什么

`flutter_rust_net` 当前是一个 **`rhttp + Dio` 薄网关**：

- 请求主路径：`RhttpAdapter`
- 请求回退路径：`DioAdapter`
- transfer 路径：Dio-only
- 统一入口：`BytesFirstNetworkClient` / `NetworkGateway`

仓库内已不再保留 package-local FRB、`RustAdapter`、`rust_bridge` 或 `native/rust/net_engine` 作为当前实现的一部分。

## 2) 当前公开能力

- 统一模型：`NetRequest / NetResponse / NetTransferTaskRequest / NetTransferEvent`
- 路由与总开关：`RoutingPolicy + NetFeatureFlag`
- 主请求通道 + Dio fallback
- Dio-only transfer 执行
- bytes-first request contract
- `baseUrl` 与相对路径统一解析

## 3) 兼容命名边界

本次 hard cut 仍保留以下兼容名：

- `NetChannel.rust`
- `enableRustChannel`
- `BenchmarkChannel.rust`

这些名字现在只表示“主请求通道兼容别名”，不再表示 FRB/runtime ownership。

## 4) 当前分层

1. Dart API 层：`BytesFirstNetworkClient` / `NetworkGateway`
2. 路由与回退层：`RoutingPolicy` + `NetFeatureFlag`
3. 请求通道层：`RhttpAdapter`（primary）+ `DioAdapter`（fallback）
4. transfer 层：`DioAdapter`

## 5) 一次请求的典型流程

1. 业务构造 `NetRequest` 并进入 `NetworkGateway.request`
2. `RoutingPolicy` 根据 `forceChannel` 与 `enableRustChannel` 决策 Dio 或主请求通道
3. 若命中主请求通道，网关先做 request preflight
4. 请求成功则返回统一 `NetResponse`
5. 若主请求通道命中可回退错误且请求满足条件，自动回退到 Dio

## 6) 当前边界

- `expectLargeResponse` 在 thin-gateway V1 中仍是兼容字段，不改变 request-path bytes-first 合同
- transfer API 不支持主请求通道；强制 `NetChannel.rust` 会显式失败
- Web 仍不是当前支持目标
- 内建业务拦截器链、声明式 API 生成、高级代理/证书/DNS 控制面仍未补齐

## 7) 验证口径

- 包级基线：`flutter test`
- 非 loopback / 远端样例：`tool/p1_non_loopback_bench.dart`
- real-`rhttp` lane 若仍依赖本地原生前置条件，应明确标注为 opt-in，而不是默认已覆盖

## 8) 历史资料说明

- `docs/progress/p1_status_2026-02-25.md`、`docs/progress/p2_status_2026-03-02.md`、`docs/progress/rust_lifecycle_scope_status_2026-03-12.md` 仍保留追溯价值
- 这些文档中的 Rust cache/runtime/FRB 描述只代表 pre-hard-cut 历史阶段，不代表当前代码树
