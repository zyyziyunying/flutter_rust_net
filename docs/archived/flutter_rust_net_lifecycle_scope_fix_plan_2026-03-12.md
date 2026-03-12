---
title: flutter_rust_net 生命周期与共享作用域修复计划（2026-03-12）
---

# flutter_rust_net 生命周期与共享作用域修复计划（2026-03-12）

> 归档说明：截至 2026-03-12，本计划的实现、测试与文档同步已完成，现转入 `docs/archived/` 供追溯。
>
> 目标：闭环 `RustAdapter` / `RustBridgeApi` 的 `shutdown/reset` 生命周期，并补齐默认 `FrbRustBridgeApi` 共享作用域的真实生产路径回归。  
> 适用目录：`D:\dev\flutter_code\harrypet_flutter\flutter_rust_net`  
> 输入问题：  
> - `docs/questions/flutter_rust_net_staged_review_followups_2026-03-11.md` 第 36-59 行  
> - `docs/questions/flutter_rust_net_risk_review_findings_2026-03-09.md` 第 214-246 行  
> - `docs/questions/flutter_rust_net_staged_review_followups_2026-03-11.md` 第 61-80 行

## 0) 本轮计划要解决的 4 个问题

1. `shutdown/reset` 之后，如何确保 Dart 侧不再保留脏的 init 状态？
2. 同一 bridge scope 下存在多个 `RustAdapter` 时，如何让旧实例在 shutdown 后一起失效？
3. 如何给默认生产路径补上“不同 `FrbRustBridgeApi` 实例但共享同一默认 scope”的正式回归？
4. 如何在不手改 FRB 生成文件的前提下，完成最小闭环修复？

---

## 1) 推荐决策

- 主方案：正式支持“受控 `shutdown -> reinitialize`”生命周期，由 `RustAdapter` / `RustBridgeApi` 统一收口。
- 采用主方案的原因：
  - 当前真实风险不在“新建 adapter 后无法重启”，而在“旧 adapter 复用时本地状态未失效”。
  - 仅补文档或继续暴露底层 `shutdownNetEngine()`，都无法解决 Dart 侧 `_initialized` 与共享 `knownConfig` 脱节的问题。
  - 现有 FRB 已经提供 `shutdownNetEngine()`，本轮优先做 Dart 侧生命周期收口，不新增 Rust bridge 合同。
- 非目标：
  - 不手改 `lib/rust_bridge/api.dart` 等 FRB 生成文件。
  - 不在本轮引入“读取 Rust 当前实际配置”的新桥接能力；若 Dart 侧方案被实现细节卡住，再作为备选增强项评估。

---

## 2) 修复后必须成立的不变量

- 同一 init scope 在任意时刻只允许一个生命周期操作生效：初始化或 shutdown，不能无序交错。
- `shutdown` 成功后，旧代次的所有 `RustAdapter` 都必须变为 not ready，请求路径不能继续把自己当作已初始化。
- `shutdown` 成功后，同一 scope 必须允许用新配置重新初始化。
- 默认生产路径下，两个不同的 `FrbRustBridgeApi` 实例仍然共享同一默认 scope，并遵循同样的 init/shutdown 约束。
- 若 `shutdown` 失败，Dart 侧不能误清空状态；需要保持“仍可能处于已初始化”这一保守语义，避免出现假阴性 ready。

---

## 3) 实施拆解

### 3.1 生命周期 API 收口

- 修改 `lib/network/rust_bridge_api.dart`：
  - 为 `RustBridgeApi` 增加 `Future<void> shutdownNetEngine();`
  - `FrbRustBridgeApi.shutdownNetEngine()` 直接转发到已存在的 `rust_api.shutdownNetEngine()`
- 修改 `lib/network/rust_adapter.dart`：
  - 新增公开的 `Future<void> shutdownEngine()`，作为宿主侧唯一受支持的 shutdown 入口。
  - `isReady` / `isInitialized` / `_ensureInitialized()` 不再只信任本地 `_initialized` 布尔值。
  - adapter 需要持有“当前绑定的生命周期代次”或等价 token，用于判断自己是否仍属于当前有效 init 状态。

### 3.2 共享 init 状态模型重构

- 修改 `lib/network/rust_adapter/rust_adapter_init.dart`：
  - 在 `_RustEngineInitState` 中增加生命周期字段，建议至少包含：
    - `int generation`
    - `bool initialized`
    - `Future<void>? shutdownInFlight`
  - `initialize(...)` 改为返回当前有效代次或等价句柄，供 `RustAdapter` 绑定。
  - 新增 `shutdown(...)`：
    - 串行化处理 `initialize` / `shutdown`
    - 调用 bridge shutdown
    - 仅在 shutdown 成功后清空 `knownConfig` / `acceptedConfigWhenActualUnknown` / `pendingConfig`
    - 成功后提升 `generation`，让旧 adapter 自动失效
- 保留现有 `_sharedBridgeConfigScope` 机制，不改变“默认 FRB 实例共用同一 scope”的设计，只补生命周期闭环。

### 3.3 兼容性与约束说明

- 不直接修改 FRB 生成文件；约束说明应放在手写层：
  - `RustBridgeApi` 接口注释
  - `RustAdapter` API 注释
  - 相关设计/进度文档
- 需要明确写清：
  - 宿主如果绕过 `RustAdapter` 直接调用底层生成的 `rust_api.shutdownNetEngine()`，Dart 侧无法自动感知，这是“不受支持路径”。
  - 包内测试与示例代码应统一改为走 `RustAdapter.shutdownEngine()` 或 `RustBridgeApi.shutdownNetEngine()` 抽象层，不再直接碰底层生成函数。

### 3.4 回归测试补齐

- 新增 lifecycle 测试，覆盖同一 fake bridge scope：
  - 一个 adapter 初始化成功后 shutdown，请求必须报未初始化。
  - 两个共享 scope 的 adapter 中，一个执行 shutdown 后，另一个也必须失效。
  - shutdown 后同 scope 允许以新配置重新初始化。
  - shutdown 失败时，状态保持保守，不误报已重置。
- 新增默认生产路径共享作用域测试：
  - 使用两个不同的 `FrbRustBridgeApi` 子类实例，而不是两个实现 `RustBridgeApi` 的 fake 实例。
  - 覆盖顺序初始化、并发同配置初始化，以及 shutdown 后重启。
- 测试文件布局：
  - `test/network/rust_adapter_test.dart` 当前已 830 行，不应继续追加新用例。
  - 新回归建议拆到新的测试文件，例如：
    - `test/network/rust_adapter_lifecycle_test.dart`
    - `test/network/rust_adapter_shared_scope_test.dart`

### 3.5 文档同步

- 在 `docs/progress/` 回写本次实现状态与验证结果。
- 若最终 API 合同有公开变化，在 `docs/` 中补一条简短说明：
  - 推荐使用 `RustAdapter.initializeEngine()` / `shutdownEngine()`
  - 不建议业务代码直接依赖底层生成 bridge API 的生命周期函数

---

## 4) 建议执行顺序

1. 先改 `RustBridgeApi` 与 `RustAdapter` 生命周期接口，确定公共 API 形状。
2. 再改 `_RustAdapterInitTracker` 状态模型，引入 generation/token 失效机制。
3. 补 lifecycle 单元测试，锁住 shutdown 后旧 adapter 失效与 restart。
4. 补默认 `FrbRustBridgeApi` 共享作用域测试，锁住真实生产路径。
5. 最后更新文档与 progress 记录。

---

## 5) 验证命令

本轮按 Dart 侧改动规划，默认验证命令如下：

```powershell
flutter analyze
flutter test test/network/rust_adapter_lifecycle_test.dart
flutter test test/network/rust_adapter_shared_scope_test.dart
flutter test
```

如果实施过程中引入了新的 Rust bridge 合同或需要重新生成绑定，再追加：

```powershell
cd ../native/rust/net_engine
cargo test -q
cargo fmt --check
```

---

## 6) 验收标准

1. `shutdownEngine()` 成功后，旧 adapter 的 `isReady` 为 `false`，请求路径抛出未初始化基础设施错误。
2. 同一 scope 下的多个 adapter 会被同一次 shutdown 一并失效。
3. shutdown 后，同 scope 用新配置重新 `initializeEngine()` 可以成功，且不会被旧 `knownConfig` 污染。
4. 默认生产路径的共享作用域测试稳定覆盖“不同 `FrbRustBridgeApi` 实例”的场景。
5. `flutter analyze` 与 `flutter test` 全绿。

---

## 7) 主要风险与备选方案

- 风险 1：仍然存在外部直接调用底层 FRB `shutdownNetEngine()` 的可能。
  - 应对：本轮通过文档与抽象层收口来降低风险，不在生成文件上做脆弱改动。
- 风险 2：init 与 shutdown 并发交错后，状态机容易出现清空过早或代次漂移。
  - 应对：统一在 `_RustAdapterInitTracker` 内串行化；不要把状态迁移分散到 `RustAdapter` 调用侧。
- 风险 3：真实生产路径回归如果继续沿用 fake bridge，将无法覆盖 `bridgeApi is FrbRustBridgeApi` 分支。
  - 应对：必须改用 `FrbRustBridgeApi` 子类探针。

不推荐但可选的收缩方案：

- 若评审最终决定“不支持 runtime shutdown/restart”，则只能做以下收缩：
  - 明确把底层 `shutdownNetEngine()` 定义为不受支持路径
  - 仅补默认共享作用域回归
  - 更新文档，要求 shutdown 后必须丢弃旧 adapter
- 该方案无法真正消除“外部 shutdown 后旧 adapter 状态脏”的风险，因此不建议作为主线修复。
