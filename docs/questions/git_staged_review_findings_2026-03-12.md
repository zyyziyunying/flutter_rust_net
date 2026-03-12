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
  - `flutter test test/network/network_gateway_transfer_state_test.dart`

## 结论

当前暂存区存在 3 个需要先处理的问题，其中 1 个高优先级语义回退、2 个中优先级行为/文档不一致问题。按当前状态不建议直接放行合并。

## 主要问题

### 1. 高：已知通道上的 cancel 错误被吞掉，并且会丢失任务归属状态

- 位置：
  - `lib/network/network_gateway.dart:123-130`
  - `lib/network/network_gateway.dart:133-139`
  - `lib/network/network_gateway.dart:313-326`
- 现状：
  - `cancelTransferTask()` 对已知 `tracked channel` 也改为走 `_safeCancelTransferTask()`。
  - `_safeCancelTransferTask()` 会把 `NetException.infrastructure` / `NetException.internal` 吞成 `false`。
  - 当主 adapter 实际发生基础设施故障时，代码随后会删除 `_transferTaskChannels[taskId]`，并继续尝试另一侧 adapter。
- 风险：
  - 调用方不再能看到真实故障，只会收到 `false`。
  - 已知任务的通道路由状态会被提前删除，后续诊断信息变差。
  - 这是 API 行为变化，不是单纯实现细节调整。
- 当前测试缺口：
  - 新增测试只覆盖了 stale channel 和 eviction 后双侧探测成功的场景，没有覆盖“已知通道 cancel 抛出 infrastructure/internal 异常”的路径。
- 建议：
  - 对“已知通道”的 cancel 保留原始异常语义，或者显式定义并文档化 best-effort/no-throw 契约后再改。

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
- 若后续修复这些问题，建议补对应回归后再更新 `docs/progress/` 与风险结论文档。
