---
title: flutter_rust_net Rust net_engine 阻塞问题追踪（2026-03-13）
status: resolved
---

# flutter_rust_net Rust net_engine 阻塞问题追踪（2026-03-13）

> 范围：当前 git 更改区中引入的 package-local `native/rust/net_engine`、FRB bridge 路径调整、Rust adapter 接入。
>
> 当前判断（2026-03-13，更新）：原 3 个阻塞/高风险问题已完成修复并补齐回归，当前不再构成提交阻塞。
>
> 本文用途：作为持续跟踪的问题单，后续修复、验证结果、回归状态都直接回写本文。

## 结论

本轮 3 个问题均已闭环：

1. 已修复：Rust 引擎 `shutdown -> reinitialize` 与 Dart 生命周期契约对齐。
2. 已修复：Rust 传输任务会拒绝重复 `taskId`，且 Dart adapter 能正确映射该错误。
3. 已修复：桌面/CLI 本地动态库解析恢复对子目录工作目录的兼容。

## 问题 1：`shutdown -> reinitialize` 真实不可用

### 现象

Rust 全局引擎实例存放在 `OnceLock<NetEngine>` 中：

- `init_net_engine()` 只允许 `.set(engine)` 一次。
- `shutdown_net_engine()` 只执行 `engine.shutdown()`，并没有释放或替换全局实例。

这意味着第一次初始化成功后，即使执行了 shutdown，第二次初始化仍会返回 `NetEngine already initialized`。

### 为什么这是阻塞问题

Dart 侧已经把“shutdown 后允许重新初始化”作为公开生命周期契约和测试前提：

- `RustAdapter.shutdownEngine()` 之后允许同 scope 用新配置重新初始化。
- 现有生命周期测试明确断言第二次初始化应成功。

如果提交当前 Rust 实现：

1. Dart 生命周期状态机会认为 shutdown 已完成并允许 restart。
2. Rust 真正的底层引擎却拒绝 restart。
3. 最终会出现 Dart 合同与 Rust 真实行为分裂，线上/集成测试会遇到真实重启失败。

### 代码位置

- `native/rust/net_engine/src/api.rs`
  - `static ENGINE: OnceLock<NetEngine> = OnceLock::new();`
  - `pub async fn init_net_engine(...)`
  - `pub async fn shutdown_net_engine(...)`
- `test/network/rust_adapter_lifecycle_test.dart`
  - `shutdown allows reinitialize with new config on same scope`

### 复现方式

理论复现路径：

1. 调用 `RustAdapter.initializeEngine(options: A)`
2. 调用 `RustAdapter.shutdownEngine()`
3. 调用 `RustAdapter.initializeEngine(options: B)`
4. 预期：成功
5. 当前 Rust 实现实际结果：底层会报 `already initialized`

### 修复要求

至少满足以下之一：

1. Rust 侧支持真实的 `shutdown -> reinitialize`。
2. 或者明确收回 Dart 侧 restart 合同，并同步修改 adapter 逻辑、README、测试和调用方约束。

当前更合理的方向是修 Rust，而不是回退 Dart 合同，因为 Dart 侧已经围绕受控生命周期补了测试和状态管理。

### 验收标准

- `shutdownEngine()` 后重新 `initializeEngine()` 可成功。
- 不同配置的 restart 行为可预测，且与 `_RustAdapterInitTracker` 契约一致。
- 至少补一个真实 bridge 层回归，不能只靠 fake bridge。

### 当前状态

- 状态：`Resolved`
- 严重级别：`Blocking`
- 修复摘要：
  - Rust 全局引擎改为可清空的 `Mutex<Option<Arc<NetEngine>>>`，`shutdown_net_engine()` 会真正释放全局实例。
  - 新增 Rust API 回归：`shutdown_allows_reinitialize_with_new_config`。
  - 新增真实 bridge Dart 回归：`test/network/rust_adapter_real_bridge_test.dart` 中验证 shutdown 后可重新初始化。

## 问题 2：重复 `taskId` 未被拒绝

### 现象

Rust `start_transfer_task()` 会直接把 `task_id -> cancel_token` 写入 `cancel_tokens`：

- 如果相同 `taskId` 被再次启动，旧 token 会被覆盖。
- 旧任务不再可被正确取消。
- 新旧任务事件会混在同一个 `id` 下，消费方无法可靠区分。

### 为什么这是问题

现有 Dio 通道已经把重复 `taskId` 视为错误并拒绝启动。当前 Rust 通道的差异会带来：

1. 跨通道行为不一致。
2. `NetworkGateway.cancelTransferTask()` 语义被破坏。
3. 进度事件与终态事件可能串线。

### 代码位置

- `native/rust/net_engine/src/engine/client/transfer.rs`
  - `tokens.insert(task_id.clone(), cancel_token.clone());`
- `lib/network/dio_adapter.dart`
  - `_transferCancelTokens.containsKey(taskId)` 时直接抛错

### 修复要求

- Rust 通道在启动前显式检查重复 `taskId`。
- 行为与 DioAdapter 对齐，返回明确错误。
- 补充对应 Rust 测试和 Dart adapter 回归测试。

### 验收标准

- 相同 `taskId` 的第二次启动被拒绝。
- 旧任务 cancel token 不会被覆盖。
- 事件总线中同一 `taskId` 不会同时对应多个存活任务。

### 当前状态

- 状态：`Resolved`
- 严重级别：`High`
- 修复摘要：
  - `start_transfer_task()` 在写入 `cancel_tokens` 前显式拒绝重复 `taskId`。
  - `RustAdapter.startTransferTask()` 改为 `await` bridge future，确保 FRB 异步异常会走 Dart 错误映射。
  - 新增 Rust 回归：`start_transfer_task_rejects_duplicate_task_ids`。
  - 新增真实 bridge Dart 回归：重复 `taskId` 会抛出包含 `transfer task already exists` 的 `NetException`。

## 问题 3：本地动态库路径对子目录运行不兼容

### 现象

当前手写 bridge loader 和 FRB 默认 loader 都改成了相对于当前工作目录的：

- `native/rust/net_engine`

但从 `example/` 目录运行时，真实存在的路径是：

- `../native/rust/net_engine`

本地验证结果：

- 在 `example/` 下，`native/rust/net_engine` 不存在。
- 在 `example/` 下，`../native/rust/net_engine` 存在。

### 为什么这是问题

这会让以下场景直接找不到本地库：

1. 在 `example/` 中本地运行桌面端或 CLI。
2. 某些从子目录启动的开发脚本。
3. 依赖当前工作目录而不是 package root 的宿主启动方式。

### 代码位置

- `lib/network/rust_bridge_api.dart`
  - `ensureBridgeLoaded()`
  - `resolveNativeProjectRoot()`
- `lib/rust_bridge/frb_generated.dart`
  - `ioDirectory: 'native/rust/net_engine/target/release/'`

### 修复要求

- 恢复对子目录工作目录的兼容。
- 候选路径至少应覆盖 package root 与 `example/` 启动场景。
- 需要明确当前兼容性由哪一层负责；如果 FRB 默认 loader 仍保留固定相对路径，则 package 内入口必须统一先经过 `FrbRustBridgeApi.ensureBridgeLoaded()`。

### 验收标准

- 从 package root 运行可加载。
- 从 `example/` 运行也可加载。
- stale library 检测与默认加载路径不互相打架。

### 当前状态

- 状态：`Resolved`
- 严重级别：`High`
- 修复摘要：
  - `FrbRustBridgeApi.ensureBridgeLoaded()` / `resolveNativeProjectRoot()` 改为从当前工作目录向上查找 package-local `native/rust/net_engine`，覆盖 package root、`example/` 及其他子目录启动场景。
  - 路径标准化去掉尾部 `/`，避免包装层的 stale library 检查路径与实际加载路径打架。
  - `lib/rust_bridge/frb_generated.dart` 的 FRB 默认 `ioDirectory` 也改为动态解析，直接调用 `RustLib.init()` 时同样覆盖 package root、`example/` 及其他子目录启动场景。
  - `tool/rust_codegen.dart` 增加生成后回补逻辑，保证重新执行 FRB codegen 后仍保留动态 `ioDirectory` 行为。
  - 新增回归：
    - `test/network/rust_bridge_api_test.dart`
    - `test/network/rust_adapter_real_bridge_test.dart`

## 提交前门槛

原提交前门槛已满足：

1. 问题 1 已完成修复，并补了真实 bridge 回归验证。
2. 问题 2、问题 3 均已完成代码修复和测试补齐。
3. `flutter_rust_bridge.yaml`、`tool/rust_build.dart`、`tool/rust_codegen.dart`、`tool/_rust_tool_utils.dart` 已存在于当前改动区。

## 已完成验证

2026-03-13 最新确认：

```powershell
cd native/rust/net_engine
cargo build --release -p net_engine
cargo test -q
cargo fmt --check
```

结果：

- `cargo build --release -p net_engine` 成功。
- `cargo test -q` 通过，当前为 27 个 Rust 测试全部通过。
- `cargo fmt --check` 通过。

```powershell
flutter test test/network/rust_bridge_api_test.dart test/network/rust_adapter_real_bridge_test.dart test/network/rust_adapter_lifecycle_test.dart test/network/rust_adapter/rust_adapter_transfer_test.dart
```

结果：12 个 Dart/Flutter 定向测试全部通过，其中包含真实 bridge 场景：

- 从 package root 运行可解析本地库。
- 从 `example/` 运行也可加载本地库。
- `shutdown -> reinitialize` 真实桥接回归通过。
- 重复 `taskId` 真实桥接回归通过。

```powershell
flutter test
```

结果：完整包测试通过，当前全量 `flutter test` 为 106 个测试全部通过。

## 本次更新

- 日期：2026-03-13
- 处理人：Codex
- 处理问题：问题 1、问题 2、问题 3
- 代码改动：
  - Rust 全局引擎生命周期改为可释放/可重建
  - Rust 传输任务增加重复 `taskId` 拒绝
  - Dart loader 改为向上查找 package-local native root，且 FRB 默认 loader 同步支持子目录启动
  - Dart transfer adapter 补上异步错误映射缺口
  - FRB codegen 工具增加生成后回补默认 loader 路径逻辑
- 新增/更新测试：
  - `native/rust/net_engine/src/api.rs`
  - `native/rust/net_engine/src/engine/client/transfer.rs`
  - `test/network/rust_bridge_api_test.dart`
  - `test/network/rust_adapter_real_bridge_test.dart`
- 验证命令：
  - `cargo build --release -p net_engine`
  - `cargo test -q`
  - `cargo fmt --check`
  - `flutter test test/network/rust_bridge_api_test.dart test/network/rust_adapter_real_bridge_test.dart test/network/rust_adapter_lifecycle_test.dart test/network/rust_adapter/rust_adapter_transfer_test.dart`
  - `flutter test`
- 结果：全部通过
- 是否解除阻塞：是

## 后续更新模板

后续每次推进建议按这个格式回写：

- 日期：
- 处理人：
- 处理问题：
- 代码改动：
- 新增/更新测试：
- 验证命令：
- 结果：
- 是否解除阻塞：
