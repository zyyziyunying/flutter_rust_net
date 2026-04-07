---
title: Rust 配置项生效性校验（2026-03-04）
---

# Rust 配置项生效性校验（2026-03-04）

> 范围：P1 工程一致性项 `write_timeout_ms`、`max_connections`、`max_connections_per_host`。

## 1) 校验与修复方法

本次按“两阶段”推进：

1. 代码路径核查（Dart 初始化参数 -> FRB -> Rust `NetEngine`），先确认字段是否被真实消费。
2. 针对未生效项补实现，并补最小回归测试验证语义与稳定性。

## 2) 逐项结论（修订后）

1. `write_timeout_ms`：**已生效**  
   - 实现：请求/上传发送阶段接入超时控制，超时映射为 `timeout`。  
   - 入口：`native/rust/net_engine/src/engine/client/common.rs`、`request.rs`、`transfer.rs`。
2. `max_connections`：**已生效**  
   - 实现：新增全局连接并发限制器，约束全局活跃连接数。  
   - 入口：`native/rust/net_engine/src/engine/client/mod.rs`（`ConnectionLimiter`）。
3. `max_connections_per_host`：**已生效（语义对齐）**  
   - 实现：新增单 host 活跃连接并发限制；同时保留 `pool_max_idle_per_host` 映射用于空闲连接池上限。  
   - 入口：`native/rust/net_engine/src/engine/client/mod.rs`。

## 3) 最小回归结果

1. `connection_limiter_applies_per_host_limit`：通过。  
2. `connection_limiter_applies_global_limit`：通过。  
3. `upload_transfer_honors_write_timeout`：通过。  
4. 全量 Rust 测试：`cargo test -q` 通过（`22/22`）。

## 4) 关键证据文件

- Dart 初始化透传：`flutter_rust_net/lib/network/rust_adapter.dart`
- Rust 配置定义：`native/rust/net_engine/src/api.rs`
- Rust 配置生效实现：`native/rust/net_engine/src/engine/client/mod.rs`
- 写超时实现：`native/rust/net_engine/src/engine/client/common.rs`
- 请求写超时接入：`native/rust/net_engine/src/engine/client/request.rs`
- 传输写超时接入：`native/rust/net_engine/src/engine/client/transfer.rs`
- 回归测试：`native/rust/net_engine/src/engine/client/tests.rs`、`native/rust/net_engine/src/engine/client/transfer.rs`

## 5) 可复现命令

```bash
cd native/rust/net_engine
cargo fmt --check
cargo test -q
```

## 6) 对 P1 的影响

1. P1 中“Rust 配置项是否生效”阻塞项已闭环。
2. 后续仅需在真机/远端补测中补齐非 loopback 证据并归档。
