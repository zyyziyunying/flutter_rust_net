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
  - `flutter test`

## 结论

当前记录中的原始 3 个问题已在 2026-03-12 全部修复并补回归。按当前状态，可按正常流程继续合并。

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

### 2. 已修复（2026-03-12）：Dio 事件队列会刷新最新 progress 的保留顺序

- 修复证据：
  - `lib/network/dio_adapter.dart`
  - `test/network/dio_adapter_transfer_state_test.dart`
- 修复后实现：
  - `progress` 事件命中同任务旧 `progress` 时，会先移除旧项再追加到队尾。
  - 队列截断仍是有界 FIFO，但同任务最新 `progress` 的保留顺序会随着最近一次上报一起刷新。
- 验证：
  - 已新增 Dio 回归：覆盖“长任务持续 progress + 后续新任务挤压”场景，确认缓冲里保留下来的是最近快照而不是旧位置上的过期快照。
  - 本地验证通过：`flutter test test/network/dio_adapter_transfer_state_test.dart`、`flutter analyze`、`flutter test`。
- 结论：
  - 当前实现已能支撑“尽量保留最近状态与终态”的表述；该项中优先级语义问题已关闭。

### 3. 已修复（2026-03-12）：Gateway tracked transfer 按最近活跃淘汰

- 修复证据：
  - `lib/network/network_gateway.dart`
  - `test/network/network_gateway_transfer_state_test.dart`
- 修复后实现：
  - `_transferTaskChannels` 显式使用 `LinkedHashMap` 维护顺序。
  - `_trackTransferTaskChannel()` 在记录非终态事件时，会先移除旧 key 再重新插入，显式刷新最近活跃顺序。
  - 当 tracked task 容量超限时，被淘汰的是“最久未活跃”的映射，而不是“最早插入”的映射。
- 验证：
  - 已新增 gateway 回归：覆盖“老任务收到 progress 刷新活跃度后，再发生容量溢出时仍保留映射，cancel 不退化成双侧探测”。
  - 本地验证通过：`flutter test test/network/network_gateway_transfer_state_test.dart`、`flutter analyze`、`flutter test`。
- 结论：
  - 当前 gateway tracked task 的容量淘汰语义已与“按最近活跃跟踪”的实现和文档表述一致。

## 备注

- 本记录基于 2026-03-12 的暂存区 diff 和本地验证结果整理。
- 问题 1 已在 2026-03-12 修复并回写本文件与 `docs/progress/`。
- 问题 2 / 3 已在 2026-03-12 修复并补回归，结论文档已同步更新。
