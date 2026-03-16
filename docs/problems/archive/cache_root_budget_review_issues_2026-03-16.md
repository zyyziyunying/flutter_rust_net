---
title: flutter_rust_net cacheRootMaxBytes review 问题单（提交决策版，2026-03-16）
status: resolved
---

# flutter_rust_net cacheRootMaxBytes review 问题单（提交决策版，2026-03-16）

> 用途：仅用于当前 git 更改区 / 暂存区的提交判断。
>
> 单一判断口径：以“总状态”一节为准。
>
> 范围：本次 `cacheRootMaxBytes / cache_root_max_bytes` 最小实现及其文档声明。

## 总状态

- 当前提交判断：`Ready`
- 阻塞项：`0`
- 已关闭问题：`5`
- 当前结论：`cacheRootMaxBytes` 相关实现、并发保护与文档契约已收口，本问题单转归档

## 本轮修复结果

- 问题 1 已修复：`prune_root()` 现按 cache root 实际文件占用计量。
  - 现状：root scan 会计入 body + `.meta.json` 文件大小，并在扫描时清理 root 内残留文件。
  - 结果：`cacheRootMaxBytes` 不再只是 body bytes 预算，而是实际文件总占用治理入口。
  - 证据：`native/rust/net_engine/src/engine/cache/prune.rs`

- 问题 2 已修复：root budget 不再只靠写路径懒触发。
  - 现状：`NetEngine::new()` 完成 `DiskCache` 构造后，会先执行一次 root-level prune。
  - 结果：若用户在已有缓存目录上首次开启 `cacheRootMaxBytes`，初始化阶段即可收敛已有超限目录。
  - 证据：`native/rust/net_engine/src/engine/client/mod.rs`

- 问题 3 已修复：Dart 侧已补齐 `u32` 上界校验。
  - 现状：`_normalizeCacheRootMaxBytes()` 现显式要求 `0 <= cacheRootMaxBytes <= 0xFFFFFFFF`。
  - 结果：超大值会在进入 bridge 前以 `NetException.infrastructure` 失败，不再泄漏成 FRB 序列化异常。
  - 证据：`lib/network/rust_adapter/rust_adapter_init.dart`

- 问题 4 已修复：root prune 与缓存内部临时文件写入的并发竞争已被保护。
  - 现状：启用 root budget 时，`DiskCache` 会串行化 `lookup()`、`store()`、`revalidate()`、`clear()` 与 `prune_root()` 的关键路径，避免 `prune_root()` 抢在 `*.tmp -> 正式文件` 之间误删缓存自己正在写入的临时文件。
  - 结果：root budget 收敛不再把缓存命中路径放大成真实请求可见错误；`lookup()` 不会因为自己的 metadata 临时文件被并发 prune 删除而冒泡成 `NetError::Internal`。
  - 证据：
    - `native/rust/net_engine/src/engine/cache/mod.rs`
      - root budget 路径新增内部互斥保护
    - `native/rust/net_engine/src/engine/cache/prune.rs`
      - `prune_root()` 走同一保护路径
    - `native/rust/net_engine/src/engine/cache/tests.rs`
      - 已新增并发回归 `lookup_waits_out_concurrent_root_prune_during_metadata_temp_write`

- 问题 5 已修复：启用 `cacheRootMaxBytes` 时，`cacheDir` 独占要求已升级为显式文档契约。
  - 现状：root prune 仍会删除 cache root 顶层非目录文件，并递归清理 namespace 下不符合当前 cache 布局的内容。
  - 结果：文档已明确声明启用 root budget 时，`cacheDir` 必须是当前组件独占的专用目录，不能指向共享目录。
  - 证据：
    - `docs/plan/cache_namespace_budget_governance_plan_2026-03-14.md`
      - 已把“独占专用目录”补进正式契约与验收标准
    - `docs/progress/p2_status_2026-03-02.md`
      - 已同步会话补记与验证结论

## 现有回归覆盖

- Rust：
  - root budget 触发的跨 namespace 淘汰
  - metadata 实际占用计量
  - root 内残留文件清理
  - 初始化阶段已有超限目录收敛
  - root prune 与 metadata 临时文件写入的并发竞争保护
- Dart：
  - `cacheRootMaxBytes > u32::MAX` 预检拒绝
  - 共享初始化配置漂移拒绝
  - 缓存关闭时 root budget 忽略
  - init 配置透传

## 已验证命令（2026-03-16，本轮补充）

```powershell
cargo test -q lookup_waits_out_concurrent_root_prune_during_metadata_temp_write --manifest-path native/rust/net_engine/Cargo.toml
cargo test -q root_prune_removes_residual_files_under_cache_root --manifest-path native/rust/net_engine/Cargo.toml
cargo test -q stores_and_reads_fresh_cache_entry --manifest-path native/rust/net_engine/Cargo.toml
cargo test -q stale_entry_with_validator_can_be_revalidated --manifest-path native/rust/net_engine/Cargo.toml
cargo test -q root_byte_budget_prunes_across_namespaces --manifest-path native/rust/net_engine/Cargo.toml
```

结果：

- 上述 Rust 定向验证均通过。
- 本次已补齐 root prune 与 metadata 临时文件写入的并发竞争回归，并复核 residual 清理与既有 root budget 行为未被破坏。
- 本次未重新运行 Dart 定向测试、全量 `cargo test`、全量 `flutter test`，也未运行 `flutter analyze`。

## 备注

- `plan / progress` 文档现已同步到“root 实际文件总占用预算 + cacheDir 独占目录契约”口径。
- 若后续产品要把 `cacheRootMaxBytes > 4 GiB` 明确纳入正式支持范围，需要继续评估 Rust / FRB / Dart 三侧的大值契约与观测口径。

## 本次记录

- 日期：2026-03-16
- 记录人：Codex
- 来源：当前 git 暂存区严格 code review
