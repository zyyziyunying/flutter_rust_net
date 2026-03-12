# 进度跟踪目录说明

该目录用于存放当前阶段的进度状态文档（如 P1/P2 状态、灰度推进状态等），
与计划目录（`flutter_rust_net/docs/plan/`）和测试报告目录（`flutter_rust_net/docs/dio_rust_test/`）分离，
便于按“计划 / 进度 / 结果”三个维度查看。

边界约定：

- `docs/plan/`：方案、执行模板、联调计划。
- `docs/progress/`：阶段状态事实源，只记录当前 Done / In Progress / Next。
- `docs/dio_rust_test/`：测试说明、runbook、策略、结果与验证结论。
- 详细会话补记、旧判断、替换前的状态快照默认不继续堆在 `docs/progress/`，迁到 `docs/archived/` 保留追溯。

建议命名：

- `pX_status_YYYY-MM-DD.md`（阶段状态）
- `rollout_status_YYYY-MM-DD.md`（灰度/上线状态）

