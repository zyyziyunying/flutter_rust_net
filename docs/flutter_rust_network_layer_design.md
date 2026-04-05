---
title: flutter_rust_net 当前网络层架构（Hard Cut 后）
---

# flutter_rust_net 当前网络层架构（Hard Cut 后）

> 更新时间：2026-04-05
> 用途：说明 FRB hard cut 后仍生效的网络层分层、能力边界与验证口径。

## 1. 架构目标

- 以 `rhttp` 作为请求主路径
- 以 `Dio` 作为 fallback 与 transfer 路径
- 在 Dart 侧统一路由、回退与观测口径
- 不再维护 package-local FRB/runtime/native-engine ownership

## 2. 分层架构

```text
Flutter UI / Repository / UseCase
            |
            v
      NetworkGateway
 (Routing + Fallback + Metrics)
        /                \
       v                  v
  DioAdapter        RhttpAdapter
       |                  |
       v                  v
   Dio Stack          rhttp stack
```

## 3. 代码落位

- Flutter 网络层实现：`flutter_rust_net/lib/network/`
- 网络层测试：`flutter_rust_net/test/network/`
- benchmark CLI：`flutter_rust_net/tool/network_bench.dart`
- fixed public-remote benchmark runner：`flutter_rust_net/tool/p1_non_loopback_bench.dart`
- 独立示例：`flutter_rust_net/example/`

## 4. 组件职责

### 4.1 `NetworkGateway`

- 统一提供 `request / startTransferTask / pollTransferEvents / cancelTransferTask`
- 负责通道路由、request preflight、fallback 与链路信息汇总
- 保持请求与 transfer 的失败边界显式可见

### 4.2 `RoutingPolicy + NetFeatureFlag`

- 只负责强制通道与总开关判定
- `enableRustChannel=true` 仍是兼容命名，语义是“启用主请求通道”
- `NetChannel.rust` 同样只保留为兼容别名

### 4.3 `RhttpAdapter`

- 承担主请求通道
- 在进入主路径前执行 request readiness / preflight
- 复用统一 request shaping 与 bytes-first contract

### 4.4 `DioAdapter`

- 承担请求 fallback 通道
- 承担 transfer start / poll / cancel
- 继续作为 V1 的唯一 transfer 实现

## 5. 当前行为边界

- 普通请求：主路径 `rhttp`，失败时按规则 fallback 到 Dio
- transfer：Dio-only；强制 `NetChannel.rust` 会显式失败
- `expectLargeResponse`：兼容字段，当前不改变 request-path bytes-first 合同
- package 内不再存在 `RustAdapter` / `RustBridgeApi` / `lib/rust_bridge/` / `native/rust/net_engine`

## 6. 验证口径

- 默认包级验证：`flutter test`
- benchmark CLI：`dart run tool/network_bench.dart --help`
- 远端固定入口：`dart run tool/p1_non_loopback_bench.dart --help`
- 若 real-`rhttp` lane 依赖本地原生前置条件，应明确标记为 opt-in

## 7. 历史边界

- 旧版 “Rust NetEngine / FRB / lifecycle / cache” 文档仍保留在仓库中
- 这些文档只用于追溯 pre-hard-cut 历史，不应再作为当前架构事实源
