# 计划目录说明

当前无 active plan。

本目录保留 `README` 作为入口说明；所有已完成、失效或被替代的计划文档统一放在 `archive/`。

补充说明：

- 仓库中仍保留 legacy flat `../plans/` 路径下的 2026-04-07 下载 benchmark 设计/计划记录；这些文件仅用于追溯，不代表当前存在 active `docs/plan/`。
- 最新执行状态统一回写到 `../progress/`。

当前历史计划入口：

- `archive/2026-04-04-remove-frb-hard-cut-resequenced-plan.md`：FRB hard cut 已完成实施计划
- `archive/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md`：旧版 hard cut 实施计划
- `archive/2026-04-02-rhttp-thin-gateway-v1-implementation-plan.md`：thin-gateway V1 旧实施计划
- `archive/network_p1_execution_template_2026-02-25.md`：P1 性能与容量瓶颈执行模板
- `archive/golang_remote_benchmark_server_plan_2026-03-02.md`：远端真机压测 Go 服务实现方案
- `archive/cache_namespace_budget_governance_plan_2026-03-14.md`：namespace 缓存预算治理方案

维护约定：

1. 计划文档只描述“准备做什么、如何做、如何验收”，不承载最新执行状态。
2. 执行状态统一回写到 `../progress/`。
3. 计划完成、失效或被新版本替代后，移入 `archive/`。
