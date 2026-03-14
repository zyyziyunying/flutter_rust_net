# 计划目录说明

该目录用于存放仍在执行、待执行，或作为当前阶段输入的计划类文档。

适合放入本目录的内容：

- 执行模板
- 联调方案
- 阶段性实施计划
- 尚未完成、但需要多人共享口径的行动清单

当前文档：

- `network_p1_execution_template_2026-02-25.md`：P1 性能与容量瓶颈执行模板。
- `golang_remote_benchmark_server_plan_2026-03-02.md`：远端真机压测 Go 服务实现方案。
- `cache_namespace_budget_governance_plan_2026-03-14.md`：namespace 缓存预算治理方案。

维护约定：

1. 计划文档只描述“准备做什么、如何做、如何验收”，不承载最新执行状态。
2. 执行状态统一回写到 `../progress/`。
3. 计划完成、失效或被新版本替代后，移入 `../archived/`。
