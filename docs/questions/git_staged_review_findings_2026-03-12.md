# flutter_rust_net 暂存区审查问题记录（2026-03-12）

## 范围

- 审查对象：`git diff --cached` 当前暂存区改动。
- 重点文件：
  - `lib/network/dio_adapter.dart`
  - `lib/network/network_gateway.dart`
  - `test/network/dio_adapter_transfer_state_test.dart`
  - `test/network/network_gateway_transfer_state_test.dart`
- 已执行验证：
  - `flutter analyze`
  - `flutter test test/network/dio_adapter_transfer_state_test.dart`
  - `flutter test test/network/network_gateway_test.dart`
  - `flutter test test/network/network_gateway_transfer_state_test.dart`

## 结论

当前记录中的原始 3 个问题里，问题 1 已在 2026-03-12 修复并补回归；剩余 2 个中优先级行为/文档一致性问题待继续处理。按当前状态，仍建议先收敛剩余问题再放行合并。

## 主要问题

### 1. 已修复（2026-03-12）：已知通道上的 cancel 恢复保留原始异常语义

- 修复证据：
  - `lib/network/network_gateway.dart`
  - `test/network/network_gateway_test.dart`
- 修复后实现：
  - `cancelTransferTask()` 对已知 `tracked channel` 不再走 `_safeCancelTransferTask()`，而是直接调用对应 adapter。
  - 因此，tracked channel 上的 `NetException.infrastructure` / `NetException.internal` 会继续向上抛出，不再被静默降级成 `false`。
  - 只有“未跟踪 / stale 映射探测”路径仍保留 best-effort 的 `_safeCancelTransferTask()` 行为。
- 验证：
  - 已新增 gateway 回归：覆盖“tracked rust cancel 首次抛 infrastructure 异常时不探测 Dio，且不丢失 tracked 状态；再次 cancel 仍能在原通道成功”。
  - 本地验证通过：`flutter test test/network/network_gateway_test.dart`、`flutter test test/network/network_gateway_transfer_state_test.dart`、`flutter analyze`。
- 结论：
  - 该项高优先级语义回退已关闭。
  - 当前 transfer cancel 语义已收敛为：已知通道保留真实错误，未知或 stale 场景再走双侧安全探测。

### 2. 中：Dio 事件队列并没有稳定保留“最新状态”，只是压缩了重复 progress

- 位置：
  - `lib/network/dio_adapter.dart:493-500`
  - `lib/network/dio_adapter.dart:515-520`
- 现状：
  - progress 事件命中同任务旧 progress 时是原位覆盖，不会把该事件移动到队尾。
  - 队列截断策略是按列表头部 FIFO 删除。
- 风险：
  - 老任务即使刚刚上报了最新 progress，它的快照位置仍可能比一些更旧的新任务事件更靠前。
  - 当后续有大量新任务事件涌入时，这个“最新 progress”会被更早淘汰。
  - 因此，当前实现不能严格支撑“尽量保留最新状态”的说法。
- 当前测试缺口：
  - 新增测试没有覆盖“长任务持续 progress + 后续新任务挤压”的场景。
- 建议：
  - 如果目标是尽量保留最近状态，progress 更新时应同步刷新保留顺序，或者改为显式的按任务聚合缓冲结构。

### 3. 中：Gateway 的任务淘汰不是按最近活跃，而是按最早插入

- 位置：
  - `lib/network/network_gateway.dart:111-116`
  - `lib/network/network_gateway.dart:334-345`
- 现状：
  - `pollTransferEvents()` 每次收到非终态事件都会调用 `_trackTransferTaskChannel()`。
  - `_trackTransferTaskChannel()` 对同一个 `Map` key 的重复赋值不会刷新插入顺序。
  - 实际淘汰结果是“最早插入 task 先被移除”，不是“最久未活跃 task 先被移除”。
- 风险：
  - 一个仍在持续活跃的老任务，也会在后续任务足够多时被挤出 `_transferTaskChannels`。
  - 之后 `cancelTransferTask()` 会退化成双侧探测，行为虽然能兜底，但和“按状态活跃度追踪”的预期不一致。
  - 相关文档把这部分描述为“有上限跟踪、风险已闭环”，表述偏乐观。
- 当前测试缺口：
  - 新增测试没有验证“持续活跃老任务是否应保留映射”的语义。
- 建议：
  - 如果目标是按最近活跃淘汰，需要显式刷新顺序或改用独立的 LRU/活动时间结构；如果只是固定容量 FIFO，应在文档里直说。

## 备注

- 本记录基于 2026-03-12 的暂存区 diff 和本地验证结果整理。
- 问题 1 已在 2026-03-12 修复并回写本文件与 `docs/progress/`。
- 问题 2 / 3 尚未处理，后续修复时建议继续补对应回归后再更新结论文档。
