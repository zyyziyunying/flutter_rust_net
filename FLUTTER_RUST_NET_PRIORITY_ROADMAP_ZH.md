# flutter_rust_net 优化路线（草案）

> 日期：2026-02-25（2026-02-28 复评补记）  
> 当前状态：已进入测试模式（Rust 主通道 + Dio 兜底回切）。  
> 目标：先完成 Rust 主通道准入验证，再扩大 Rust 通道收益，最后提升接入体验与工程化能力。

## 快速跳转（同日文档）

- P1 执行状态（进度主文档）：[`docs/progress/p1_status_2026-02-25.md`](./docs/progress/p1_status_2026-02-25.md)
- P2 执行状态（缓存阶段）：[`docs/progress/p2_status_2026-03-02.md`](./docs/progress/p2_status_2026-03-02.md)
- 架构与能力概览：[`flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md`](./FLUTTER_RUST_NET_OVERVIEW_ZH.md)
- 测试运行记录：[`docs/test_plans/test_run_log.md`](../docs/test_plans/test_run_log.md)

## 文档口径（单一事实源）

- 本文是 **阶段优先级与里程碑** 的唯一事实源（P0-P4 定义、顺序、阶段目标）。
- 执行进度（Done / In Progress / Next）不在本文维护，统一以 `docs/progress/p1_status_2026-02-25.md` 为准。
- 测试数据明细以 `docs/test_plans/test_run_log.md` 与对应 benchmark 文档为准。

## 更新流程（建议）

1. 当“阶段顺序、目标、验收门槛”变化时，仅在本文更新 P0-P4 与阶段目标。
2. 进度项不在本文增删，统一回填到 `docs/progress/p1_status_2026-02-25.md`。
3. 若路线调整伴随性能结论变化（或用户明确要求），再同步 `docs/test_plans/test_run_log.md`。
4. 更新后检查与 `flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md` 的术语是否一致（如“测试模式/准入结论”）。

## 路线原则

- 先稳定性，再性能扩面，再能力补齐，再易用性建设。
- 每一阶段都要求“可观测 + 可回滚”，避免一次性大切换。
- 以现有双通道架构为基础，优先做“增量优化”而非推倒重来。

## 最新评估补记（2026-02-28）

- P1 准入阻塞 A：Rust transfer 的 upload 语义仍待补齐，当前实现与 Dio 双通道能力尚未完全对齐。
- P1 准入阻塞 B：`maxInFlightTasks` 默认值口径未统一（文档建议 `32`，代码/CLI 默认仍有 `12`），会导致 `jitter` 结果漂移。
- P1 证据缺口：真机弱网、远端链路、TOS 归档尚未闭环，当前不足以给出“业务 App 接入”最终准入结论。
- P1 归档进展：日志上传入口已确认（`baseUrl=http://47.110.52.208:7777`，`POST /upload`），仍需补齐鉴权口径与命名规范。
- P1 工具进展：已提供 CLI 上传脚本与示例 App 一键上传按钮（真机点击可直传报告 JSON）。
- P1 鉴权进展：登录接口已知为 `POST /user/login`，示例 App 已接入“上传前登录”路径。
- P1 对接进展：上传请求头已按服务端口径写入 `token: <actual-token>`（并保留 Authorization 兼容）。
- P2 依赖项（已解除）：Rust `DiskCache` 占位实现问题已开始收敛，缓存收益阶段已启动。
- P2 启动进展（2026-03-02）：`DiskCache` 已接入首版可用实现（GET 缓存 + TTL/ETag/LRU + namespace 清理），进入参数外置与收益观测阶段。
- P2 推进补记（2026-03-03）：已完成缓存策略参数外置最小闭环（默认 TTL + namespace 容量上限），并打通 Dart 初始化配置入口。
- 工程一致性项：`write_timeout_ms`、`max_connections` 等配置项需补“是否生效”的验证与回归。

## P0：稳定基线（已完成）

- 已切换为测试模式单开关路由：Rust 主通道 + Dio 兜底回切。
- 已固化灰度与回滚规则（异常率、fallback 率、p95 回归阈值）。
- 已固化最小观测面板（按接口/通道的 QPS、p95/p99、异常、fallback reason）。
- 已完成 P1-L1/P1-L2 基准与聚合，形成路由调参输入。

**阶段结论**：已具备“可观测 + 可回退”闭环，可进入实网准入验证。

## P1：性能与容量瓶颈（当前优先）

- 重点优化 `jitter + 高并发` 场景（排队时延、并发闸门、路由阈值）。
- 系统复验 `maxInFlightTasks` 在不同并发档位下的收益与风险，并统一代码/CLI/文档默认口径为 `32`。
- 补齐 Rust transfer 的 upload 语义与回归测试，确保与 Dio 通道行为一致。
- 输出稳定的“路由策略表”（测试模式下什么场景 Rust 优先，什么场景临时回切 Dio）。
- 补齐真机弱网与远端服务链路复验（非 loopback），验证跨网络稳定性。
- 校验 Rust 配置项（`write_timeout_ms`、`max_connections` 等）是否实际生效，并沉淀验证结论。

**阶段目标**：形成“业务 App 接入前”准入结论（继续 Rust 默认 / 临时回切 Dio）。

## P2：缓存体系补齐（第三优先）

- 将 Rust `DiskCache` 从占位实现升级为可用实现（ETag/TTL/LRU/命名空间治理）。
- 对齐 Dart 与 Rust 的落盘生命周期（读后清理、主动清理、失败兜底）。
- 明确缓存一致性与失效策略，补齐回归测试。

**阶段目标**：减少重复请求与 I/O 成本，形成持续收益。

## P3：网络策略控制面（第四优先）

- 补齐代理、证书 pinning/mTLS、DNS 覆盖、重定向策略等能力。
- 将策略能力纳入 `FeatureFlag` 或配置中心，支持按环境与业务开关。
- 建立策略变更的验证清单（功能正确性 + 性能影响 + 回滚路径）。

**阶段目标**：在复杂网络环境下保持可控与可治理。

## P4：接入体验与工程化（第五优先）

- 增加业务拦截器层，统一鉴权、重试、日志、错误映射扩展点。
- 规划声明式 API 接入层（类 Retrofit/Chopper 风格）降低业务接入成本。
- 建立版本与发布治理（语义化版本、兼容性说明、升级指南）。

**阶段目标**：让团队低成本接入并可持续演进。

## 建议的下一会话起点

建议从 **P1（性能与容量瓶颈）** 开始，先聚焦：

1. 先修复 Rust transfer upload 语义缺口，并补齐跨通道一致性回归用例。
2. 统一 `maxInFlightTasks` 默认口径到 `32`（代码/CLI/文档），并重跑 `jitter` 基线。
3. 校验 `write_timeout_ms`、`max_connections` 等配置项的生效路径并记录结果。
4. 基于 `http://47.110.52.208:7777/upload` 补齐归档细节（鉴权方式 + JSON 命名约定 + 上传脚本联调）。
5. 真机弱网 + 远端链路补测（非 loopback），按同口径归档 JSON。
6. 若性能结论变化，再回填 `test_run_log` 与路由策略文档，输出准入决策。
