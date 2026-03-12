# flutter_rust_net 暂存区审查补充问题（2026-03-11）

## 范围

- 审查对象：当前暂存区改动。
- 重点文件：
  - `lib/network/rust_adapter.dart`
  - `test/network/rust_adapter_test.dart`
  - `docs/questions/flutter_rust_net_risk_review_findings_2026-03-09.md`
- 审查方式：静态阅读 + 本地验证 `flutter analyze lib/network/rust_adapter.dart test/network/rust_adapter_test.dart` + `flutter test test/network/rust_adapter_test.dart`

## 结论

本次暂存区改动的方向是对的：Rust 重复初始化/并发初始化的配置一致性校验已经补上。基于 2026-03-12 的 staged 增量复核，原文第 2、3 项也已经闭环：`RustAdapter` 已补受控 shutdown/reinitialize 生命周期，默认生产路径的共享 scope 回归也已入库。当前没有新增的未记录 P0/P1 级问题；生命周期侧剩余边界已经收敛到“低层 `RustBridgeApi.shutdownNetEngine()` 仍是可见的 bridge passthrough，但这条路径明确不受支持”。

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

### 2. 已修复（2026-03-12）：共享初始化状态已补受控 shutdown/reset 生命周期清理

- 修复证据：
  - `lib/network/rust_adapter.dart`
  - `lib/network/rust_adapter/rust_adapter_init.dart`
  - `lib/network/rust_bridge_api.dart`
  - `test/network/rust_adapter_lifecycle_test.dart`
- 修复后实现：
  - `RustAdapter` 新增受支持的 `shutdownEngine()` 生命周期入口，bridge-backed adapter 的 ready 判定改为“本地已初始化 + 绑定 generation 仍是共享 scope 的活动代次”。
  - `_RustAdapterInitTracker` 已补共享 `generation` 与串行化 lifecycle 管理；shutdown 成功后会清空共享 init config 状态，并让同 scope 下旧代次 adapter 统一失效。
  - 同一 scope 现在已支持 `shutdown -> reinitialize`，并允许新配置重新生效；shutdown 失败时则保持保守 ready 状态，不会误清空当前 tracker。
- 验证：
  - 已新增 lifecycle 回归，覆盖单 adapter 失效、同 scope 联动失效、shutdown 后重启、shutdown 失败保守状态。
  - 本地验证命中：`flutter analyze`、`flutter test`
- 残余边界：
  - 低层 `RustBridgeApi.shutdownNetEngine()` 仍是 bridge passthrough；如果宿主绕过 `RustAdapter.shutdownEngine()` 直接调用，Dart tracker 不会自动同步。
  - 因此真正还没封死的是“直调低层 shutdown”的误用路径，而不是 `RustAdapter` 的受支持生命周期本身仍缺 reset。

### 3. 已修复（2026-03-12）：新增测试已直接覆盖默认生产路径的共享作用域行为

- 修复证据：
  - `lib/network/rust_adapter/rust_adapter_init.dart`
  - `test/network/rust_adapter_shared_scope_test.dart`
- 修复后实现：
  - 已新增直接覆盖默认生产路径的共享 scope 回归，用两个不同的 `FrbRustBridgeApi` 子类实例验证真实共享路径，而不再只依赖 fake bridge 复用同一实例。
  - 新测试同时覆盖顺序初始化、并发同配置初始化，以及 shutdown 后的 restart。
- 验证：
  - 本地验证命中：`flutter analyze`、`flutter test`
- 结论：
  - 原文第 3 项测试缺口已关闭。
  - 当前 staged 内容没有再暴露出新的未记录高危 runtime 问题。

## 建议处理顺序

1. 这一轮 follow-up 原始第 2、3 项已闭环；后续优先回到主风险文档里的 transfer 状态边界问题。
2. 若还要继续加固生命周期约束，下一步应考虑进一步收窄低层 `RustBridgeApi.shutdownNetEngine()` 的误用面，或补更显式的保护说明。

## 备注

- 这份文档是对“当前暂存区改动”的补充问题记录，不替代总审查结论。
- 2026-03-12 已按本次复核结果同步回写 `docs/questions/flutter_rust_net_risk_review_findings_2026-03-09.md`。
