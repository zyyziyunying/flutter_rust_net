---
title: flutter_rust_net cacheResponseNamespace review 问题跟踪（2026-03-14）
status: in_progress
---

# flutter_rust_net cacheResponseNamespace review 问题跟踪（2026-03-14）

> 范围：当前 git 更改区中 `cacheResponseNamespace` 全链路透传、兼容性、非法 namespace 校验，以及 FRB 生成文件差异。
>
> 当前判断（2026-03-14，暂存区严格复核）：问题 2 已修复；问题 1 与问题 3 仍有残留缺口，本文状态回退为 `in_progress`。另有 2 个附加观察项，暂不判定为阻塞缺陷，但建议继续跟踪。
>
> 本文用途：作为持续跟踪的问题单，后续修复、验证结果、是否关闭，直接回写本文。

## 结论

本轮记录的问题当前状态如下：

1. `normalize_namespace()` 对非法 namespace 的限制已收紧一轮，但在 Windows 上仍会放过 `responses.` 这类目录别名输入，问题未完全收口。
2. Dart 侧共享初始化配置比较已补齐与 Rust 一致的 namespace 规范化，当前判定为已修复。
3. Rust 已不再在缓存关闭时强校验 `cache_response_namespace`，但 Dart 对空白 `cacheDir` 的共享初始化比较仍未与 Rust 完全对齐，问题仅部分修复。

## 问题 1：非法 namespace 校验不够严格

### 现象

当前 `normalize_namespace()` 的逻辑：

- 会先 `trim()`
- 会拒绝空字符串
- 会拒绝绝对路径、`..`、Windows prefix
- 最终返回 `trimmed.to_owned()`

但它不会拒绝以下类型的值：

- `./responses`
- `tenant/a`
- `tenant\\a`

随后 `DiskCache::namespace_dir()` 会直接执行 `self.root_dir.join(namespace)`。

### 为什么这是问题

这会带来两个风险：

1. namespace 不再是稳定单层目录名，而是可以形成别名或多级目录。
2. 隔离边界会被削弱，例如 `tenant/a` 实际会落到 `tenant` 子树中，后续清理或统计边界会变得不可靠。

在当前实现下，`clear_cache(Some("tenant"))` 只要未来允许更宽输入，理论上就可能与 `tenant/...` 形成目录级联关系，不符合“命名空间隔离”的直觉契约。

### 代码位置

- `native/rust/net_engine/src/engine/cache/mod.rs`
  - `fn namespace_dir()`
  - `pub fn normalize_namespace()`

### 建议修复

建议将 namespace 收紧为“单层逻辑名称”，至少满足以下之一：

1. 明确只允许普通 segment，拒绝 `/`、`\`、`.`、`./` 这类路径语义输入。
2. 若确实要支持分层 namespace，则要同步重定义 clear/prune/隔离契约，并补对应测试，不能继续沿用当前“平面命名空间”的语义。

### 当前状态

- 状态：`Partially Fixed`
- 严重级别：`High`
- 备注：首轮修复已挡住 `./responses`、`tenant/a`、`tenant\\a`；但本次严格复核确认，在 Windows 目录语义下 `responses.` 仍会被接受并落成 `responses`。

### 修复结果（2026-03-14）

1. Rust `normalize_namespace()` 已收紧为“单层 normal segment”语义：
   - 先 `trim()`
   - 显式拒绝 `/`、`\`
   - 仅接受恰好一个 `Component::Normal`
2. `DiskCache::namespace_dir()` 继续统一走 `normalize_namespace()`，因此不会再接受 `./responses`、`tenant/a`、`tenant\\a` 这类路径语义输入。
3. 已新增 Rust 回归覆盖上述非法输入，并保留合法 `tenant_responses` 的正向断言。
4. 但该修复仍未覆盖 Windows 目录别名边界：`responses.` 当前仍会通过 `normalize_namespace()`，并在 Windows 文件系统上实际映射到 `responses` 目录，namespace 隔离仍可能被别名绕过。
5. 当前回归尚未覆盖 trailing-dot / 目录别名输入，因此本问题不能判定为已关闭。

## 问题 2：Dart / Rust 对 namespace 的规范化不一致

### 现象

Rust 在 `NetEngine::new()` 中会对 `config.cache_response_namespace` 先做 `normalize_namespace()`，也就是先 `trim()` 再进入实际运行态。

但 Dart 侧 `_RustAdapterInitTracker`：

- 在 `toNetEngineConfig()` 中直接透传 `options.cacheResponseNamespace`
- 初始化成功后直接记住原始 `config`
- 后续共享 bridge scope 复用时，直接比较 `active.cacheResponseNamespace` 和 `requested.cacheResponseNamespace`

这意味着：

1. 第一次若传入 `' tenant_cache '`
2. 第二次若传入 `'tenant_cache'`

Rust 真实使用的 namespace 相同，但 Dart 会把它们当成“不同配置”，并报冲突。

### 为什么这是问题

这不是纯展示差异，而是实际行为分裂：

1. Rust 认为两次配置等价。
2. Dart 生命周期跟踪器认为两次配置冲突。
3. 最终同一 bridge scope 下会出现误报初始化冲突，阻塞可复用场景。

### 代码位置

- `lib/network/rust_adapter/rust_adapter_init.dart`
  - `initialize()`
  - `_rememberInitConfig()`
  - `_describeInitConfigDiff()`
- `native/rust/net_engine/src/engine/client/mod.rs`
  - `NetEngine::new()`
- `native/rust/net_engine/src/engine/cache/mod.rs`
  - `normalize_namespace()`

### 建议修复

建议二选一：

1. Dart 侧在进入 `NetEngineConfig` 前，对 `cacheResponseNamespace` 做与 Rust 一致的规范化。
2. Rust 暴露“真实生效配置”查询接口，Dart 改为比较规范化后的 active config，而不是原始请求值。

### 当前状态

- 状态：`Fixed`
- 严重级别：`Medium`
- 备注：这是共享 bridge scope / 重复初始化路径的兼容性问题，不影响单次初始化成功。

### 修复结果（2026-03-14）

1. Dart `_RustAdapterInitTracker.toNetEngineConfig()` 现已在构造 `NetEngineConfig` 前，对 `cacheResponseNamespace` 执行与 Rust 对齐的规范化。
2. 共享 bridge scope 复用时，Dart 比较的是规范化后的配置值，不再把 `' tenant_cache '` 与 `'tenant_cache'` 误判为冲突。
3. 已新增 Dart 回归覆盖：
   - trim 前后 namespace 仍可复用同一 initialized scope
   - 透传到 Rust bridge 的配置值为规范化后的 namespace

## 问题 3：缓存关闭时仍强校验 namespace，存在兼容性回归

### 现象

`NetEngine::new()` 中当前顺序为：

1. 先 `normalize_namespace(&config.cache_response_namespace)?`
2. 再判断 `config.cache_dir.trim().is_empty()`
3. 若 cache dir 为空，则 `disk_cache = None`

也就是说，即使磁盘缓存已关闭，只要 `cache_response_namespace` 为空或非法，初始化仍会失败。

### 为什么这是问题

对于“未启用磁盘缓存”的调用方，`cache_response_namespace` 实际不会进入 request cache 路径；但这次改动后它变成了新的强制有效参数。

这会造成新的兼容性风险：

1. 旧调用方可能完全未关注这个字段。
2. 即使缓存关闭，也会因为无效 namespace 初始化失败。
3. 失败点与真实功能使用路径不一致，排查成本高。

### 代码位置

- `native/rust/net_engine/src/engine/client/mod.rs`
  - `NetEngine::new()`

### 建议修复

建议只在 `cache_dir` 非空、即真正启用磁盘缓存时，再校验和持有 `response_cache_namespace`。

如果产品定义要求“即使缓存关闭也必须保证该字段合法”，则需要把这条约束升级为公开配置契约，并在 Dart 层同步显式校验和报错说明。

### 当前状态

- 状态：`Partially Fixed`
- 严重级别：`Medium`
- 备注：Rust 侧行为回退已完成，但 Dart 在共享初始化配置比较中仍未把空白 `cacheDir` 规范化到与 Rust 相同的“缓存关闭”语义。

### 修复结果（2026-03-14）

1. Rust `NetEngine::new()` 现已改为：
   - 先判断 `cache_dir.trim().is_empty()`
   - 仅在真正启用磁盘缓存时才校验并持有 `response_cache_namespace`
2. 缓存关闭时，Rust 不再因空白或非法 `cache_response_namespace` 初始化失败。
3. Dart 初始化配置构造已部分对齐：缓存关闭时会忽略 `cacheResponseNamespace` 差异，并回落到默认 namespace。
4. 但 Dart 仍保留原始 `cacheDir` 字符串参与共享初始化配置比较；因此 `cacheDir: ''` 与 `cacheDir: '   '` 在 Rust 看来都等价于“缓存关闭”，在 Dart 侧仍会被误判为配置冲突。
5. 已新增 Rust/Dart 回归覆盖“缓存关闭 + 非法 namespace 仍可初始化/复用”，但当前尚未覆盖空白 `cacheDir` 等价值复用这一残留边界。

## 附加观察

### 观察 1：`cacheResponseNamespace` request-cache 透传链路本身已打通

本次改动在主链路上是对齐的：

1. Dart `RustEngineInitOptions` 已新增 `cacheResponseNamespace`
2. `_RustAdapterInitTracker.toNetEngineConfig()` 已透传到 FRB `NetEngineConfig`
3. Rust `NetEngine::new()` 已接收并保存 `response_cache_namespace`
4. request cache 的 `lookup` / `revalidate` / `store` 均已切换到该字段

当前判断：这部分不是问题项，保留为 review 留痕。

### 观察 2：FRB 生成文件字段顺序对齐，但 content hash 未变化

本次检查结果：

1. `lib/rust_bridge/frb_generated.dart`
2. `native/rust/net_engine/src/frb_generated.rs`

两侧都已包含新增字段，且字段顺序一致，未发现明显序列化错位。

但同时观察到：

- Dart `rustContentHash` 仍是 `1854914876`
- Rust `FLUTTER_RUST_BRIDGE_CODEGEN_CONTENT_HASH` 仍是 `1854914876`

尽管 wire schema 已变化，这个 hash 没有变化。当前未把它判定为明确缺陷，因为需要确认这是否是 FRB 2.11.1 的生成器行为；但建议后续继续留意，避免新旧桥接产物校验失效。

## 已完成定向验证

本次修复与复核期间已执行：

```powershell
cd native/rust/net_engine
cargo test -q normalize_namespace_rejects_path_like_inputs
cargo test -q net_engine_rejects_invalid_configured_response_cache_namespace
cargo test -q net_engine_allows_invalid_response_cache_namespace_when_cache_disabled
cargo test -q request_cache_uses_configured_response_namespace

cd ../../..
flutter test test/network/rust_adapter/rust_adapter_initialization_test.dart
flutter test test/network/rust_adapter/rust_adapter_request_test.dart
```

结果：

1. 上述定向 Rust / Flutter 测试均通过。
2. 这些定向测试可以证明首轮修复主路径有效，但不足以证明问题已全部收口；本次严格复核另外确认了 2 个未被现有回归覆盖的残留边界：
   - Windows 目录别名输入 `responses.`
   - Dart 侧空白 `cacheDir` 的等价值复用
3. 本次未运行全量 `cargo test` / `flutter test` / `flutter analyze`。

## 后续跟踪建议

当前建议先完成以下收尾项，再考虑关闭本单：

1. 继续收紧 namespace 校验与回归：至少拒绝 Windows 目录别名输入 `responses.`，避免与默认 `responses` 落成同一路径。
2. 将 Dart 对 `cacheDir` 的共享初始化比较与 Rust 对齐：`''` 与空白字符串都应视为“缓存关闭”并可安全复用同一 initialized scope。
3. 在上述两项收口后，再继续关注 FRB 生成文件 `content hash` 未变化是否属于生成器正常行为，避免后续桥接产物校验失效。
4. 若后续产品需要支持“分层 namespace”，需重新定义 clear/prune/隔离契约，而不是放宽当前单层 segment 规则。

## 本次记录

- 日期：2026-03-14
- 记录人：Codex
- 来源：当前 git 更改区 code review
- 关注主题：`cacheResponseNamespace` 全链路透传、兼容性、非法 namespace 校验、FRB 生成文件差异
- 当前是否阻塞提交：`是（问题 1 未完全收口；问题 3 仍有 Dart/Rust 空白 cacheDir 口径差异）`
