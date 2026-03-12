---
title: P1 详细历史记录（归档于 2026-03-12）
---

# P1 详细历史记录（归档于 2026-03-12）

> 说明：本文件迁自旧版 `docs/progress/p1_status_2026-02-25.md` 中的详细 `Done` 清单与会话补记。
>
> 自 2026-03-12 起，当前状态请以 [`flutter_rust_net/docs/progress/p1_status_2026-02-25.md`](../progress/p1_status_2026-02-25.md) 为准；本文件仅保留追溯价值，不再作为当前事实源。

## 详细 Done 清单（迁自旧版进度文档）

1. 已确认 P1 目标与执行口径（并发分档、`maxInFlightTasks`、路由阈值）。
2. 已新增 P1 执行模板文档：`flutter_rust_net/docs/plan/network_p1_execution_template_2026-02-25.md`。
3. 已新增聚合脚本：`flutter_rust_net/tool/p1_aggregate.dart`，可自动汇总 `jitter` 报告并输出 PASS/FAIL。
4. 已完成一次 smoke 验证（单组 `jitter`）并产出示例汇总：
   - `flutter_rust_net/build/p1_jitter/p1_summary_none.md`
   - `flutter_rust_net/build/p1_jitter/p1_summary_none.json`
5. 已完成 P1-L1 全量粗扫（`c8/c16/c32 x mif12/24/32/48 x 3轮`，共 36 份报告）：
   - `flutter_rust_net/build/p1_jitter/20260225_1440/`
6. 已完成本轮 L1 聚合并输出：
   - `flutter_rust_net/build/p1_jitter/20260225_1440/p1_summary_none.md`
   - `flutter_rust_net/build/p1_jitter/20260225_1440/p1_summary_none.json`
7. 已完成 P1-L2 复验（`json_model`，6 组 Top2 x 5 轮，共 30 份报告）：
   - `flutter_rust_net/build/p1_jitter/20260225_1448/`
8. 已完成本轮 L2 聚合并输出（全部 PASS）：
   - `flutter_rust_net/build/p1_jitter/20260225_1448/p1_summary_model.md`
   - `flutter_rust_net/build/p1_jitter/20260225_1448/p1_summary_model.json`
9. 已同步更新路由策略文档（新增 P1 复验更新段）：
   - `flutter_rust_net/docs/dio_rust_test/network_route_strategy_2026-02-24.md`
10. 已追加测试运行记录两条（L1/L2）：
    - `相关文档（按需）`
11. 已产出 P1 聚合结论文档：
    - `flutter_rust_net/docs/dio_rust_test/network_benchmark_p1_aggregation_2026-02-25.md`
12. 已新增独立示例承载壳（不依赖 `media_kit_poc`）：
    - `flutter_rust_net/example/`
13. 已将 Android Rust `.so` 构建/打包脚本迁移到示例工程：
    - `flutter_rust_net/example/android/app/build.gradle.kts`
14. 已切换为测试模式单开关路由（Rust 主通道 + Dio 回切）：
    - `flutter_rust_net/lib/network/net_feature_flag.dart`
    - `flutter_rust_net/lib/network/routing_policy.dart`
15. 已清理旧灰度分流字段与策略（阈值/allowlist/denylist）并完成回归：
    - `flutter_rust_net/test/network/routing_policy_test.dart`
    - `flutter_rust_net/test/network/network_gateway_test.dart`
16. 已补充 Rust 主通道路由基线（small_json + jitter/mif32）并入库：
    - `flutter_rust_net/build/small_json_rust_first.json`
    - `flutter_rust_net/build/jitter_latency_rust_first_mif32.json`
    - `相关文档（按需）`（`TR-20260225-14` / `TR-20260225-15`）
17. 已同步架构/策略相关文档到测试模式：
    - `flutter_rust_net/docs/flutter_rust_network_layer_design.md`
    - `flutter_rust_net/docs/dio_rust_test/network_route_strategy_2026-02-24.md`
    - `flutter_rust_net/docs/archived/flutter_rust_network_layer_design_review_findings_2026-02-24.md`
    - `flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md`

## 会话补记（归档）

### 2026-02-26

1. 已确认下一阶段验证口径：以真机网络剖面 + 远端链路为主，loopback 基准仅作为回归参考。
2. 已盘点当前可复用 benchmark JSON 资产（基线 + P1-L1/L2 原始报告 + 聚合报告）。
3. 已确认产物归档方向：真机测试生成的 JSON 需统一上传到 TOS，作为准入与追溯依据。
4. 当前待补齐的外部输入：TOS 类型（平台）、鉴权方式、目标 bucket/prefix。

### 2026-02-28

1. 已完成一次 P1 复评：当前仍属于“业务 App 接入前”验证阶段，尚未形成最终准入结论。
2. 新识别阻塞项：Rust transfer 的 upload 语义尚未与 Dio 行为完全对齐，需补实现与一致性回归。
3. 新识别口径偏差：`maxInFlightTasks` 文档建议值为 `32`，但代码/CLI 仍存在默认 `12`，会导致 `jitter` 结果漂移。
4. 本地复验观察（loopback，仅作回归参考）：`jitter(c16)` 下 `mif=32` 可恢复 Rust 优势，`mif=12` 出现明显退化。
5. 工程一致性待确认：`write_timeout_ms`、`max_connections` 等配置项需补“是否实际生效”的验证与记录。
6. 真机弱网 / 远端链路 / TOS 归档仍未闭环，继续作为 P1 准入前置条件。
7. 归档链路外部输入有进展：已确认日志上传入口 `http://47.110.52.208:7777/upload`，待补齐鉴权与命名规范。
8. 已补齐上传动作入口：CLI 脚本 + 示例 App 按钮（真机可直接点击上传报告 JSON）。
9. 已确认登录入口：`POST /user/login`（当前示例 App 上传前先登录并附带 token）。
10. 上传请求头已按服务端口径补齐：`token: <actual-token>`（并保留 `Authorization` 兼容头）。

### 2026-03-02

1. 真机测试已完成首轮验证，P1 当前从“准入证据收集”转入“收尾与同步更新”阶段。
2. 后续开发已开始并行启动 P2：先落地 Rust `DiskCache` 的可用基础能力（GET + TTL/ETag/LRU）。
3. P2 启动进度已单独记录到：`flutter_rust_net/docs/progress/p2_status_2026-03-02.md`。
4. 真机首轮 smoke 结果已同步更新 `TR-20260302-36`：3 份 JSON 全部 `exceptions/http5xx/fallback=0`；`jitter(c16,mif32)` 下 Rust `p95` 优于 Dio，但 `p99` 仍偏高。

### 2026-03-03（upload 语义补齐计划前后）

1. 已完成 Rust `DiskCache` 模块化重构（`engine/cache.rs` 拆分为 `engine/cache/` 子模块），行为口径保持不变，便于继续推进 P2 能力扩展。
2. 已同步更新测试记录 `TR-20260303-37`：`cargo fmt --check` + `cargo test -q` 通过（Rust `13/13`）。
3. P1 三个准入阻塞项状态未变化：upload 语义对齐、`maxInFlightTasks` 默认值统一、真机弱网/远端链路与归档规范闭环。
4. 已完成差距确认：当前 Rust transfer 主流程未按 `kind` 区分 upload/download，upload 仍沿用下载写文件路径，和 Dio 侧“读取 `localPath` 作为上传源文件”的语义不一致。
5. 已确定补齐原则（以 Dio 为对齐基线）：`localPath` 在 upload 场景必须表示“本地源文件路径”；源文件不存在返回 `io`；仅 2xx 记为 completed；取消统一记为 canceled。
6. 已锁定最小回归集（首批必须通过）：upload success、source file not found、non-2xx fail、cancel、fallback 安全边界（POST + `Idempotency-Key`）。
7. 已完成 Rust transfer upload 语义补齐：按 `kind` 区分 upload/download，upload 路径改为读取 `localPath` 本地源文件上传；`source file not found -> io`；`non-2xx -> failed`；取消统一记为 `canceled`。
8. 已补最小回归集：
   - Rust 侧：`upload success`、`source missing`、`non-2xx fail`、`cancel`、`kind parse`
   - Dart 侧：transfer upload fallback 安全边界（`POST` 且无 `Idempotency-Key` 不允许回切 Dio）
9. 已统一 `maxInFlightTasks` 默认口径到 `32`：
   - Rust `NetEngineConfig::default`
   - Dart `RustEngineInitOptions`
   - benchmark `BenchmarkConfig` 与 CLI `--rust-max-in-flight` 默认值
10. 已在 benchmark CLI 暴露 `--base-url` 并透传 `scenarioBaseUrl`，可直接跑“真机/公网服务”非 loopback 命令。
11. 本会话验证命令已通过：`cargo fmt --check`、`cargo test -q`、`flutter analyze`、`flutter test`。
12. P1 未闭环项收敛为三类：Rust 配置项生效性验证、真机弱网/远端链路补测、JSON 归档命名与服务端回执口径固化。
13. 已定位并解除 Rust init `UnexpectedEof` 阻塞：根因是本地 `net_engine` 动态库陈旧（与当前源码构建产物不一致）；执行 `cd ../native/rust/net_engine && cargo build --release -p net_engine` 后恢复。
14. 已补防回归保护：Rust bridge 加载前增加“本地动态库是否陈旧”预检，命中时直接给出重建命令，避免再次出现 `frb_generated.rs` 解码阶段 Panic。
15. `jitter` Rust 通道最小复跑已恢复（`--scenario=jitter_latency --channels=rust --initialize-rust=true --require-rust=true` 可正常完成）。

### 2026-03-04

1. 已完成 `write_timeout_ms`、`max_connections`、`max_connections_per_host` 的代码路径核查（Dart 初始化参数 -> FRB -> Rust `NetEngine`）。
2. 结论 A：`write_timeout_ms` 当前未生效；`NetEngine::new` 仅设置了 `connect_timeout` 与 `read_timeout`，没有写超时映射。
3. 结论 B：`max_connections` 当前未生效；字段进入 Rust 配置结构体后未被 HTTP client 构建流程消费。
4. 结论 C：`max_connections_per_host` 当前仅映射到 `pool_max_idle_per_host`，可控制“空闲连接池上限”，但不等价于“每 host 最大活跃连接数”。
5. 已沉淀校验记录：`flutter_rust_net/docs/dio_rust_test/network_rust_config_effectiveness_2026-03-04.md`。
6. P1 阻塞项状态更新：配置项“是否生效”已完成判定，下一步转为“补齐实现 + 回归验证”。
7. 已补齐 `write_timeout_ms` 生效路径：请求/上传发送阶段接入超时控制（超时统一映射为 `timeout`）。
8. 已补齐 `max_connections`、`max_connections_per_host` 生效路径：新增连接并发限制器，分别约束“全局活跃连接数”与“单 host 活跃连接数”。
9. `max_connections_per_host` 继续保留对 `pool_max_idle_per_host` 的映射，用于空闲连接池上限控制。
10. 已补最小回归：
    - Rust：`connection limiter` 的 global/per-host 限流行为测试
    - Rust：upload `write_timeout_ms` 生效测试（延迟回包触发超时）
11. 本会话验证命令通过：`cargo fmt --check`、`cargo test -q`（Rust `22/22`）。
12. P1 阻塞项状态更新：配置项“是否生效”已闭环，后续仅需在真机/远端补测中补充证据。

### 2026-03-09

1. 已同步更晚的 Dart 侧风险审查结论：请求 body 编码契约、`List<int>`/`bodyBytes` 语义、resume download fallback 契约、Dio 下载临时文件发布、Rust typed error 映射均已补齐并通过本地回归。
2. 公开默认接入路径已调整为“安全默认 Dio，Rust 显式 opt-in”：
   - `BytesFirstNetworkClient.standard()` 默认 `enableRustChannel=false`
   - `BytesFirstNetworkClient.standardWithRust()` 负责显式初始化 Rust
3. 因此，虽然 P1 尚未输出最终“业务 App 接入前”准入结论，但当前包的默认公开 API 已经偏向保守接入策略，不再暗示“默认即 Rust”。
4. 新增并保留的后续高优先级风险有两项：
   - transfer 事件队列与任务路由状态缺少边界，长时间运行时可能无界增长
   - Rust 重复初始化命中 `already initialized` 时，当前仍会吞掉配置冲突
5. 以上两项来自后续风险审查，不影响本次 P1 已完成的基准、upload 语义、`mif=32` 与配置项生效结论，但会影响最终业务接入判定的可信度。

### 2026-03-11 至 2026-03-12

1. 已完成当前仓库核对：P1 文档列出的核心产物、脚本、示例工程、聚合报告与专题文档均存在，关键代码结论也能从当前实现直接追证。
2. 当前验证命令通过：`flutter analyze`、`flutter test`、`cargo test -q`；其中 Rust 测试规模已从 2026-03-04 记录的 `22/22` 增长到当前 `24/24`。
3. 已确认公网服务 `http://47.110.52.208:7777` 当前同时承载 benchmark 与上传链路：
   - `GET /healthz -> 200`
   - `GET /bench/small-json?id=1 -> 200`
   - 未登录 `POST /upload -> 401`
4. 已完成一次最小远端 smoke 核对：
   - 初次运行命中本地 `net_engine.dll` 陈旧保护
   - 执行 `cd ../native/rust/net_engine && cargo build --release -p net_engine` 后恢复
   - Rust-only `small_json` 远端 smoke 可完成 `4/4`、`exceptions=0`、`fallback=0`
5. 已确认早期“TOS 待定”口径不再代表当前事实；当前已知归档方向是 `47.110.52.208:7777/upload`，但“命名约定 / 服务端回执口径 / 样例归档”仍未在仓库内形成稳定规范文档。
6. 结论更新：截至 2026-03-11，P1 的工程实现与基础远端链路已基本打通，但仍不建议宣称“已完成最终准入”；后续应先补非 loopback 证据归档和剩余高优先级风险闭环，再输出业务接入决策。
7. 已在 2026-03-12 补齐 transfer 事件/任务状态边界：`DioAdapter` 的 transfer 事件缓冲改为有界保留并压缩中间 progress，`NetworkGateway` 的任务路由状态改为有上限跟踪；对于 tracked channel 的 cancel 继续保留真实 adapter 异常语义，仅在未跟踪 / stale 状态下自动探测另一侧 cancel。
