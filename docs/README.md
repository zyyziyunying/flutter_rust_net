# flutter_rust_net 文档索引

本目录用于存放 `flutter_rust_net` 的项目内文档，按职责拆分：

- `flutter_rust_network_layer_design.md`：hard cut 后当前有效的网络层设计主文档
- `progress/`：当前阶段状态事实源
- `design/`：仍有参考价值的设计文档与 hard-cut 设计决策
- `plan/`：当前无 active plan；保留目录说明与 `archive/` 历史计划
- `dio_rust_test/`：历史测试方案、runbook、策略建议、基准结果、验证结论归档入口
- `analyse/`：分析文档与业务适用性建议
- `problems/`：当前问题单与历史问题单入口；已闭环问题集中在 `problems/archive/`
- `archived/`：已完成或已失效但保留追溯价值的历史文档

当前优先入口：

- `progress/frb_hard_cut_status_2026-04-04.md`：FRB hard cut 当前执行状态事实源
- `../FLUTTER_RUST_NET_OVERVIEW_ZH.md`：hard cut 后当前能力概览
- `flutter_rust_network_layer_design.md`：hard cut 后当前架构
- `design/2026-04-02-rhttp-dio-hard-cut-design.md`：hard cut 设计决策记录

历史/legacy 资料入口：

- `progress/archive/p1_status_2026-02-25.md`：P1 历史阶段状态（pre-hard-cut）
- `progress/archive/p2_status_2026-03-02.md`：P2 历史阶段状态（pre-hard-cut）
- `progress/archive/rust_lifecycle_scope_status_2026-03-12.md`：legacy Rust lifecycle 历史状态
- `progress/archive/real_device_test_commands_2026-03-02.md`：pre-hard-cut 真机 / benchmark runbook 历史快照；包含失效命令，仅供追溯
- `plan/archive/2026-04-04-remove-frb-hard-cut-resequenced-plan.md`：FRB hard cut 已完成实施计划归档
- `problems/archive/2026-04-05-frb-hard-cut-resequenced-plan-audit-findings.md`：2026-04-05 hard cut 审计记录；现仅保留历史审计价值
- `dio_rust_test/archive/`：pre-hard-cut benchmark 与验证资料归档
- `archived/2026-04-02-project-progress-and-gap-assessment.md`：2026-04-02 状态评估，现仅作 hard cut 前背景
- `archived/2026-04-02-rhttp-thin-gateway-design-review-status-check.md`：2026-04-02 设计核对，现仅作 hard cut 前背景

维护建议：

1. `Done / In Progress / Next` 只在 `docs/progress/` 维护。
2. 当前架构事实优先回写 `FLUTTER_RUST_NET_OVERVIEW_ZH.md`、`docs/flutter_rust_network_layer_design.md` 与 `docs/progress/frb_hard_cut_status_2026-04-04.md`。
3. hard cut 之前的 Rust/FRB/runtime 资料统一优先进入各目录下的 `archive/`，避免与当前入口混放。
