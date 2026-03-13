# flutter_rust_net 文档索引

本目录用于存放 `flutter_rust_net` 的项目内文档，按职责拆分：

- `flutter_rust_network_layer_design.md`：当前有效的网络层设计主文档。
- `progress/`：阶段执行进度与状态事实源（如 P1/P2 状态、当前 In Progress / Next）。
- `plan/`：仍在执行或待执行的方案、执行模板、联调计划。
- `dio_rust_test/`：测试方案说明、runbook、策略建议、基准结果、验证结论。
- `problems/`：阻塞问题、提交门槛、持续跟踪中的问题单。
- `questions/`：审查问题记录、待收敛 follow-up、临时问题单。
- `archived/`：已完成或已失效但需要保留追溯价值的历史文档。

当前索引：

- `progress/p1_status_2026-02-25.md`：P1 当前状态（精简版状态页）。
- `progress/rust_lifecycle_scope_status_2026-03-12.md`：Rust 生命周期与共享作用域修复状态。
- `problems/rust_net_engine_blockers_2026-03-13.md`：当前 git 更改区 Rust net_engine 接入的阻塞问题追踪。
- `plan/network_p1_execution_template_2026-02-25.md`：P1 执行模板。
- `plan/golang_remote_benchmark_server_plan_2026-03-02.md`：远端真机压测 Go 服务方案。
- `questions/git_staged_review_findings_2026-03-12.md`：当前 staged review follow-up 与待收敛问题。
- `archived/p1_status_history_2026-03-12.md`：从旧版 P1 进度文档迁出的详细历史记录。
- `archived/flutter_rust_net_lifecycle_scope_fix_plan_2026-03-12.md`：已归档的 Rust 生命周期与共享作用域修复计划。
- `archived/flutter_rust_network_layer_design_review_findings_2026-02-24.md`：已闭环的设计评审与修复建议。

维护建议：

1. 新增“方案/模板/待执行计划”时，优先放入 `docs/plan/`。
2. `Done / In Progress / Next` 只在 `docs/progress/` 维护，避免计划文档和进度文档互相覆盖。
3. 测试结果、策略结论、runbook 统一放在 `docs/dio_rust_test/`。
4. 文档结论已闭环或被新文档替代后，移入 `docs/archived/`，并在原引用处改到新路径。
5. 变更后同步检查 `FLUTTER_RUST_NET_OVERVIEW_ZH.md` 与 `FLUTTER_RUST_NET_PRIORITY_ROADMAP_ZH.md` 的跳转链接是否一致。
