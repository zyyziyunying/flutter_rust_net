# flutter_rust_net 项目作用与实现概览（中文）

## 快速跳转（同日文档）

- P1 执行状态（进度主文档）：[`docs/progress/p1_status_2026-02-25.md`](./docs/progress/p1_status_2026-02-25.md)
- 优先级路线图：[`flutter_rust_net/FLUTTER_RUST_NET_PRIORITY_ROADMAP_ZH.md`](./FLUTTER_RUST_NET_PRIORITY_ROADMAP_ZH.md)
- 测试运行记录：`相关文档（按需）`

## 文档口径（单一事实源）

- 本文是 **架构分层、能力边界、术语定义** 的唯一事实源。
- 阶段优先级与里程碑以 `flutter_rust_net/FLUTTER_RUST_NET_PRIORITY_ROADMAP_ZH.md` 为准。
- 执行进度与准入结论以 `docs/progress/p1_status_2026-02-25.md` 与 `相关文档（按需）` 为准。

## 更新流程（建议）

1. 当接口模型、路由/fallback 机制、能力边界发生变化时，在本文更新架构与术语描述。
2. 性能结论和测试状态只写“汇总结论”，详细数据统一引用 `相关文档（按需）`。
3. 若结论影响阶段目标，联动更新 `flutter_rust_net/FLUTTER_RUST_NET_PRIORITY_ROADMAP_ZH.md`。
4. 若结论影响执行计划或准入判断，联动更新 `docs/progress/p1_status_2026-02-25.md`。

## 1) 这个库在做什么
`flutter_rust_net` 是一个 **Flutter + Rust** 双通道网络层：  
对 Flutter 业务暴露统一请求/传输 API，对底层执行同时接入 Dart `Dio` 与 Rust `net_engine(reqwest)`，并通过 `flutter_rust_bridge` 连接两端。

它当前的目标是：在保持 Flutter 侧开发效率与稳定性的前提下，以 Rust 作为测试模式主通道（非最终线上结论），并通过统一路由与回退机制降低切换风险，完成业务 App 接入前准入验证。

## 2) 对外核心能力
- 统一模型：`NetRequest / NetResponse / NetTransferTaskRequest / NetTransferEvent`。
- 双通道路由：`RoutingPolicy + NetFeatureFlag` 支持总开关与强制通道。
- 受控 fallback：仅 Rust 通道触发，且受错误类型与幂等性保护。
- 统一传输任务入口：下载/上传启动、事件轮询、任务取消（Dio/Rust 都可接入）。
- bytes-first 边界：跨 FFI 返回 `bytes` 或 `file path`，业务解码留在 Dart。
- 大响应生命周期：支持 Rust 侧 `clear_cache` + Dart 侧 materialize 后 best-effort 清理。

## 3) 实现架构（分层思路）
1. **Dart API 层**：业务仅依赖 `BytesFirstNetworkClient/NetworkGateway`。
2. **请求编排层**：`NetworkGateway` 负责路由、readiness gate、fallback、链路信息汇总。
3. **通道实现层**：`DioAdapter` 与 `RustAdapter` 实现统一 `NetAdapter` 接口。
4. **桥接层**：`rust_bridge_api.dart` + FRB 生成代码完成 Dart/Rust 互调。
5. **Rust 执行层**：`net_engine`（`reqwest + scheduler + event_bus`）处理请求、传输、取消、缓存清理。

## 4) 一次请求的典型流程
1. Dart 侧构造 `NetRequest`，进入 `NetworkGateway.request`。  
2. `RoutingPolicy` 基于强制通道与总开关决策 Dio 或 Rust。  
3. 若命中 Rust，先做 `isReady` 检查；未就绪直接走 Dio（避免“先失败再回退”）。  
4. 执行通道请求：Rust 返回 inline bytes 或 file path；Dio 返回 bytes。  
5. 若 Rust 出现可回退错误且请求满足幂等条件，网关自动回退至 Dio。  
6. 业务层按 bytes-first 模式完成 decode/model 映射。

## 5) 与成熟 Flutter / Rust 网络库对比（截至 2026-02-25）

### 5.1 Flutter 生态对比
| 库 | 成熟能力（现状） | 与 flutter_rust_net 的关系/差异 |
| --- | --- | --- |
| Dio (5.9.0) | 拦截器、取消、表单、下载上传进度、超时、适配器生态成熟 | 当前测试模式为 Rust 主通道 + Dio 兜底回切；`flutter_rust_net` 在 Dio 之上补了“多通道路由 + fallback + FFI 边界治理” |
| http (1.6.0) | 官方轻量客户端抽象，简单稳定、组合式客户端 | `flutter_rust_net` 更重，更偏“网关+策略层”；不适合作为轻量替代 |
| Chopper (8.4.0) / Retrofit (4.9.1) | 类型安全 API 声明 + 代码生成，业务 API 组织能力强 | `flutter_rust_net` 目前偏传输治理，尚缺“声明式 API 生成层” |
| rhttp (0.7.2) | Flutter+Rust 一体化网络库，强调协议覆盖（含 HTTP/3）、拦截器、TLS/代理/DNS、兼容层 | `flutter_rust_net` 在“策略路由+快速回退”更突出；在“协议/网络策略广度”上仍有差距 |

### 5.2 Rust 生态对比
| 库 | 成熟能力（现状） | 与 net_engine 的关系/差异 |
| --- | --- | --- |
| reqwest (0.13.2) | Rust 高层 HTTP 客户端事实标准，易用、生态完善 | `net_engine` 已基于 reqwest 构建；当前是“面向 Flutter 场景的裁剪封装” |
| hyper (1.8.1) | 底层高性能 HTTP 基础库，可高度定制 | 你当前不直接暴露 hyper 级能力，重点是工程化可用性而非底层自由度 |

### 5.3 当前竞争力与短板（结论）
- **优势**：双通道治理（路由+fallback）在 Flutter 侧比较少见，且已形成可测试闭环。  
- **优势**：针对大响应与传输任务有明确 bytes/file 边界，便于压测与演进。  
- **数据侧观察（本仓库基准）**：`small_json` 场景 Rust p95 明显优于 Dio（11~13ms vs 42~48ms）；`jitter` 场景已完成 L1/L2 调参与复验并通过聚合门槛，但实网（弱网/远端）稳定性仍需补测。  
- **短板**：声明式 API 生成、拦截器生态、证书/代理/DNS 策略能力尚不如成熟库完整。  
- **短板**：虽已切到 Rust 默认主通道（`enableRustChannel=true`），但尚未在业务 App 接入场景完成长期与跨网络链路稳定性验证。

## 6) 可借鉴成熟库的升级方向（建议）
- **API 层**：补一层 Chopper/Retrofit 风格的声明式 API 生成（可选），降低业务接入成本。
- **网络策略层**：补齐代理、证书 pinning/mTLS、DNS 覆盖、重定向策略等高级控制面。
- **传输层参数化**：将 `maxInFlightTasks` 做成可动态调参（按场景/并发档位切换）。
- **可观测性**：统一输出通道级指标（p95/p99、fallbackRate、bridgeBytes、queue delay）并沉淀面板。
- **发布治理**：形成稳定的 semver 与兼容性承诺（API/ABI/行为变更分级）。

## 7) 当前边界
- Web 端暂不可用（当前实现依赖本地动态库 + FRB）。
- Rust `DiskCache` 已有首版可用能力（GET + TTL/ETag/LRU + namespace 清理），策略参数化与更细粒度一致性仍待补齐。
- 暂无内建“业务拦截器链”与“声明式 API 客户端生成”能力。
- 协议/网络策略控制面（HTTP/3 显式配置、代理、证书高级能力）仍待扩展。

## 8) 打分制对比表（用于选型）

评分口径（1~5 分）：  
- 功能完整度、工程成熟度：越高越好。  
- 迁移成本：**越低越好（越容易迁移分越高）**。  
- 性能风险：**越低越好（越稳定分越高）**。

### 8.1 Flutter 侧（业务接入视角）
| 方案 | 功能完整度 | 工程成熟度 | 迁移成本 | 性能风险 | 简述 |
| --- | ---: | ---: | ---: | ---: | --- |
| flutter_rust_net（当前） | 3.5 | 3.0 | 3.0 | 3.0 | 双通道路由 + fallback 很有特色，但声明式 API/策略控制面仍在补齐 |
| Dio | 4.5 | 5.0 | 4.5 | 4.0 | Flutter 默认基线方案，生态与稳定性最成熟 |
| rhttp | 4.5 | 4.0 | 3.5 | 4.0 | Flutter+Rust 一体化能力强，协议与网络策略覆盖更广 |
| Chopper/Retrofit（配 Dio/http） | 4.0 | 4.5 | 4.0 | 4.0 | 强项是声明式 API 与业务组织，不是底层通道治理 |

### 8.2 Rust 侧（执行引擎视角）
| 方案 | 功能完整度 | 工程成熟度 | 迁移成本 | 性能风险 | 简述 |
| --- | ---: | ---: | ---: | ---: | --- |
| net_engine（当前） | 3.0 | 3.0 | 3.5 | 3.0 | 已有请求/传输/事件/取消/并发闸门，缓存与高级策略仍待完善 |
| reqwest 直接封装 | 4.0 | 4.5 | 3.0 | 4.0 | 上限高、生态强，但跨端治理能力要自行补齐 |
| hyper 自研引擎 | 5.0 | 4.0 | 2.0 | 2.5 | 可定制性最高，同时引入更高的实现与维护复杂度 |

### 8.3 你当前阶段的实用结论
- 近期测试策略：**Rust 主通道 + Dio 兜底回退**，优先验证稳定性、观测与回退闭环。
- `jitter` 类场景已完成主要参数扫描，下一步重点是弱网与远端链路复验。
- 下一阶段建议将真机测试 JSON 统一归档到 TOS，确保跨会话与跨版本可追溯。
- 若补齐“声明式 API + 网络策略控制面 + 缓存体系”，`flutter_rust_net` 的综合分可明显上升。

## 9) 参考资料
- 本仓库：`flutter_rust_net/lib/network/`、`native/rust/net_engine/src/`、`flutter_rust_net/docs/dio_rust_test/`（本地基准记录）。
- pub.dev：Dio、http、Chopper、Retrofit、rhttp（版本与能力说明，访问日期：2026-02-25）。
- docs.rs：reqwest、hyper（版本与项目定位，访问日期：2026-02-25）。

