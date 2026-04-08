# 进度跟踪目录说明

该目录用于存放当前阶段的状态事实源；历史阶段状态统一移入 `archive/`。

当前状态：

- 当前 active 状态事实源为 `current_status_2026-04-08.md`。
- 当前判断：hard cut 主线已完成，最近增量工作集中在独立 `rhttp` 下载 benchmark 的实现与验证补齐。
- FRB hard cut 收尾状态已归档到 `archive/frb_hard_cut_status_2026-04-04.md`。
- 若后续开启新阶段或当前判断发生变化，继续在本目录新增或替换当前事实源。

当前事实源入口：

- `current_status_2026-04-08.md`：hard cut 后当前状态快照；包含下载 benchmark 首轮落地与本轮验证结论

历史阶段文档入口：

- `archive/frb_hard_cut_status_2026-04-04.md`：hard cut 收尾状态快照
- `archive/p1_status_2026-02-25.md`
- `archive/p2_status_2026-03-02.md`
- `archive/rust_lifecycle_scope_status_2026-03-12.md`
- `archive/real_device_test_commands_2026-03-02.md`：历史 runbook 快照，包含已失效命令，不应直接按当前代码树执行

这些历史文档仍保留追溯价值，但其中涉及 Rust/FRB/runtime 的描述仅代表 pre-hard-cut 阶段，不代表当前代码树。
