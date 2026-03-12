# flutter_rust_net 暂存区审查补充问题（2026-03-11）

## 范围

- 审查对象：当前暂存区改动。
- 重点文件：
  - `lib/network/rust_adapter.dart`
  - `test/network/rust_adapter_test.dart`
  - `docs/questions/flutter_rust_net_risk_review_findings_2026-03-09.md`
- 审查方式：静态阅读 + 本地验证 `flutter analyze lib/network/rust_adapter.dart test/network/rust_adapter_test.dart` + `flutter test test/network/rust_adapter_test.dart`

## 结论

本次暂存区改动的方向是对的：Rust 重复初始化/并发初始化的配置一致性校验已经补上。当前第 1 项已修复；第 2 项真实存在，但需要把风险边界写精确；第 3 项则是明确存在的测试缺口。

## 问题清单

### 1. 已修复（2026-03-11）：`already initialized` 的“未知首配”分支现在会锁定第一份被接受的请求配置

- 修复证据：
  - `lib/network/rust_adapter.dart`
  - `test/network/rust_adapter_test.dart`
  - `docs/questions/flutter_rust_net_risk_review_findings_2026-03-09.md`
- 修复后实现：
  - 当 bridge 返回 `already initialized` 但 Dart 侧还拿不到真实首配时，`RustAdapter` 现在会记录“第一份被接受的请求配置”作为兼容基线。
  - 同一个 adapter 后续再次 `initializeEngine(...)` 时，只有相同配置才会继续通过；冲突配置会直接抛 `NetException.infrastructure`。
  - 同 scope 下的其他 adapter 如果再传入不同配置，也会在 `already initialized` 分支显式失败，不再继续把配置漂移静默吞掉。
- 验证：
  - 已新增 Dart 回归，覆盖：
    - 首配未知时，同 adapter 的同配置重复初始化仍可重入；
    - 首配未知时，同 scope 的冲突配置会显式报错，并带出发生漂移的字段。
  - 本地验证命中：`flutter analyze lib/network/rust_adapter.dart test/network/rust_adapter_test.dart`、`flutter test test/network/rust_adapter_test.dart`
- 残余边界：
  - Dart 仍然拿不到 Rust 真正生效的首配；当前只是把“第一份被接受的请求配置”锁成兼容基线，防止后续调用方继续自相矛盾。
  - 若要彻底验证真实配置，仍需要 Rust bridge 暴露当前生效配置或配置指纹。

### 2. 中高：共享初始化状态缺少 shutdown/reset 生命周期清理，外部 shutdown 后旧 adapter 状态会脏

- 证据：
  - `lib/network/rust_adapter.dart:64-81`
  - `lib/network/rust_adapter/rust_adapter_init.dart:5-7`
  - `lib/network/rust_adapter/rust_adapter_init.dart:92-99`
  - `lib/network/rust_adapter/rust_adapter_init.dart:267-280`
  - `lib/rust_bridge/api.dart:33-34`
- 现状：
  - `_trackedInitStates` 以静态 `Expando` 挂在 bridge scope 上，`FrbRustBridgeApi` 还被强行折叠到同一个 `_sharedBridgeConfigScope`。
  - 当前代码只有“写入 init 状态”，没有任何“清空 init 状态”的正式路径；`_rememberInitConfig(...)` 会写入 `knownConfig`，但没有对应 reset。
  - `RustAdapter` 自身也只维护 `_initialized` 布尔值；一旦初始化成功，后续请求路径只看这个本地状态。
  - 但公开底层 bridge API 仍然存在 `shutdownNetEngine()`。
- 风险：
  - 如果宿主或测试代码绕过 `RustAdapter` 直接调用 `shutdownNetEngine()`，现有 `RustAdapter` 仍可能保留 `_initialized == true`，之后请求会继续把自己当作 ready。
  - 同一个旧 adapter 在外部 shutdown 后若尝试用新配置重新 `initializeEngine(...)`，Dart 侧可能先拿旧的 `knownConfig` / `_initialized` 做判断，导致“状态已变但本地缓存未清”的脏状态。
  - benchmark、example、测试工具或宿主进程复用长生命周期 adapter 的场景里，这类状态污染会比较难查。
- 边界校正：
  - 这项风险没有原文说得那么宽。额外本地 probe 表明：如果 shutdown 后新建一个新的 `RustAdapter`，当前实现仍可重新初始化，并会以新的成功配置覆盖共享 `knownConfig`。
  - 当前真正未闭环的是“外部 shutdown / reset 之后继续复用旧 adapter”这条生命周期路径，而不是“所有 restart 都会被旧缓存拦住”。
- 修复方向：
  - 需要一个受控的 shutdown/reset 路径，同时清理对应 scope 的 `_RustEngineInitState`，并让关联 `RustAdapter` 的 `_initialized` 一起失效。
  - 如果暂时不打算支持 runtime shutdown/restart，就应该把这一约束明确写进 API 和文档，并避免继续暴露一个不会维护 Dart 侧状态的 public shutdown 入口。

### 3. 中：新增测试仍未直接覆盖默认生产路径的共享作用域行为

- 证据：
  - `lib/network/rust_adapter.dart:51-57`
  - `lib/network/rust_adapter/rust_adapter_init.dart:278-279`
  - `test/network/rust_adapter_test.dart:371-466`
  - `test/network/rust_adapter_test.dart:533-623`
- 现状：
  - 生产默认路径是每个 `RustAdapter()` 自带一个新的 `FrbRustBridgeApi()` 实例。
  - 真正的共享行为依赖 `FrbRustBridgeApi -> _sharedBridgeConfigScope` 这条特殊分支。
  - 现有新增测试全部是让多个 adapter 共享同一个 `_FakeRustBridgeApi` 实例，并没有验证“不同 bridge 实例但同属 FRB 默认实现”的场景。
- 补充验证：
  - 额外本地 probe 已验证：使用两个不同的 `FrbRustBridgeApi` 子类实例时，当前实现的顺序初始化与并发同配置初始化都能命中共享 scope。
  - 因此这一项当前更准确地说是“测试没有锁住真实生产路径”，而不是“已经确认实现有 bug”。
- 风险：
  - 当前测试更像是在验证 fake 对象共享下的行为，不足以证明默认生产路径的共享作用域逻辑可靠。
  - 一旦后续有人调整 `_initConfigScope` 判定、bridge 注入方式或 `FrbRustBridgeApi` 的包装层，这组测试很可能继续绿，但真实路径已经悄悄偏了。
- 修复方向：
  - 增加能覆盖“不同 bridge 实例但共享同一 FRB scope”的测试缝隙。
  - 同时补一条 shutdown/restart 场景测试，避免第 2 项问题长期隐身。

## 建议处理顺序

1. 先修第 2 项，补生命周期清理或明确不支持重启。
2. 再修第 3 项测试，把默认生产路径和 shutdown/restart 都纳入回归。

## 备注

- 这份文档是对“当前暂存区改动”的补充问题记录，不替代总审查结论。
- 若后续修复上述问题，建议同步回写 `docs/questions/flutter_rust_net_risk_review_findings_2026-03-09.md`，避免主文档结论继续过度乐观。
