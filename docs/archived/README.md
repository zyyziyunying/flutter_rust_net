# 归档目录说明

该目录用于存放已经闭环、已失效，或已被新文档替代，但仍需要保留追溯价值的历史文档。

适合归档的内容：

- 过期方案或被替代的旧版本计划
- 不再作为当前事实源的阶段性记录
- 已失效但仍需保留追溯价值的历史评审/风险记录

说明：

- 当前仍按“问题单”管理的文档放在 `../problems/`。
- 已闭环的问题单统一放在 `../problems/archive/`，不放在本目录。

当前文档：

- `p1_status_history_2026-03-12.md`：从旧版 P1 进度文档迁出的详细历史记录，不再作为当前事实源。
- `2026-04-01-rhttp-thin-gateway-design-review.md`：thin-gateway 设计评审原始问题记录；当前状态以 `../problems/2026-04-02-rhttp-thin-gateway-design-review-status-check.md` 为准。
- `flutter_rust_net_risk_review_findings_2026-03-09.md`：风险审查记录与后续闭环情况。
- `flutter_rust_net_lifecycle_scope_fix_plan_2026-03-12.md`：Rust 生命周期与共享作用域修复计划归档。
- `flutter_rust_network_layer_design_review_findings_2026-02-24.md`：网络层架构评审问题记录，问题已于 2026-02-25 全部闭环。

维护约定：

1. 归档文档默认不再作为“当前状态”或“当前方案”的事实源。
2. 若引用归档文档，应同时给出当前生效文档路径。
3. 新增归档时，优先更新 `../README.md` 中的索引与说明。
