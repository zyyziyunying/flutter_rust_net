---
title: flutter_rust_net cacheResponseNamespace review 问题单（提交决策版，2026-03-14）
status: resolved
---

# flutter_rust_net cacheResponseNamespace review 问题单（提交决策版，2026-03-14）

> 用途：仅用于当前 git 更改区的提交判断。
>
> 单一判断口径：以“总状态”一节为准。
>
> 不纳入本文主结论的内容：历史回写、P2 进度会话、FRB content hash 观察。

## 总状态

- 当前提交判断：`Ready`
- 阻塞项：`0`
- 已关闭问题：`5`
- 当前结论：`cacheResponseNamespace` 相关提交阻塞已收口

## 本轮修复结果

- Dart 已同步 Rust 的 trailing-dot namespace 拒绝规则。
  - 实现：`lib/network/rust_adapter/rust_adapter_init.dart`
    - `_normalizeCacheResponseNamespace()` 现已拒绝 `trimmed.endsWith('.')`。
  - 回归：`test/network/rust_adapter/rust_adapter_initialization_test.dart`
    - 新增 `responses.` 与 `tenant_cache..` 在 bridge init 前即被拒绝的覆盖。
- Dart 已同步 Rust 对非空 `cacheDir` 的 `trim()` 语义。
  - 实现：`lib/network/rust_adapter/rust_adapter_init.dart`
    - `_normalizeCacheDir()` 现对非空路径返回 `trim()` 后的值。
  - 回归：`test/network/rust_adapter/rust_adapter_initialization_test.dart`
    - 新增“非空路径前后空白仍可复用同一 initialized scope”覆盖。
  - 回归：`test/network/rust_adapter/rust_adapter_request_test.dart`
    - 补充断言透传到 Rust bridge 的 `cacheDir` 为规范化后的路径。

## 已关闭项

- Rust 侧非法 path-like namespace 收紧已完成。
  - 证据：`native/rust/net_engine/src/engine/cache/mod.rs`、`native/rust/net_engine/src/engine/cache/tests.rs`。
- 缓存关闭时不再强制校验 `cacheResponseNamespace`，兼容性回退已完成。
  - 证据：`native/rust/net_engine/src/engine/client/mod.rs`、`native/rust/net_engine/src/engine/client/tests.rs`、`test/network/rust_adapter/rust_adapter_initialization_test.dart`、`test/network/rust_adapter/rust_adapter_request_test.dart`。
- `cacheResponseNamespace` 已打通到 request-cache 主链路。
  - 证据：`lib/network/rust_adapter/rust_adapter_init.dart`、`native/rust/net_engine/src/engine/client/mod.rs`、`native/rust/net_engine/src/engine/client/request.rs`、`native/rust/net_engine/src/engine/client/tests.rs`。

## 已验证命令（2026-03-14）

```powershell
flutter test test/network/rust_adapter/rust_adapter_initialization_test.dart
flutter test test/network/rust_adapter/rust_adapter_request_test.dart
```

结果：

- 上述 2 个 Dart 定向测试命令均通过。
- 新增回归已覆盖本轮修复的两个 Dart 残留口径问题。
- 本次未重新运行全量 `flutter test` 或 `flutter analyze`。

## 备注

- 本文不再承担历史漂移记录或进度日志用途。
- `FRB content hash` 未变化目前不纳入提交阻塞判断；如需继续跟踪，应单独记录。
- 若后续产品要支持“分层 namespace”，需另开设计项，不在本次提交判断范围内。

## 本次记录

- 日期：2026-03-14
- 记录人：Codex
- 来源：当前 git 更改区 code review
