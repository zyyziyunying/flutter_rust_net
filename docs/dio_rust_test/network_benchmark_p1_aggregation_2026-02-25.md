---
title: P1 基准聚合结论（2026-02-25）
---

# P1 基准聚合结论（2026-02-25）

> 目标：基于 P1-L1/L2 结果，确定 `jitter + 高并发` 场景下的 `maxInFlightTasks` 默认值与路由建议。

## 1) 输入数据

1. L1（传输层粗扫）  
   - 目录：`flutter_rust_net/build/p1_jitter/20260225_1440/`
   - 规模：`c8/c16/c32 x mif12/24/32/48 x 3轮 = 36 报告`
   - 汇总：`flutter_rust_net/build/p1_jitter/20260225_1440/p1_summary_none.md`
2. L2（json_model 复验）  
   - 目录：`flutter_rust_net/build/p1_jitter/20260225_1448/`
   - 规模：`6 组 Top2 x 5轮 = 30 报告`
   - 汇总：`flutter_rust_net/build/p1_jitter/20260225_1448/p1_summary_model.md`

验收门槛沿用 P1 模板：

- Rust `exceptionRate == 0`
- Rust `fallbackCount == 0`
- Rust `reqP95 <= Dio * 1.05`
- Rust `throughput >= Dio`
- Rust `queueGap <= 10ms`

## 2) L1 结论（none）

### 2.1 通过/失败分布

- 通过：9 组
- 失败：3 组  
  - `c16/mif12`
  - `c32/mif12`
  - `c32/mif24`

### 2.2 关键观察

1. `c8`：`mif12/24/32/48` 全通过，Rust 稳定领先。
2. `c16`：`mif12` 失败；`mif24/32/48` 全通过。
3. `c32`：`mif12/24` 失败；`mif32/48` 通过。
4. 失败组合都伴随 `queueGap` 明显放大（约 `19ms` 到 `96ms`），与此前“排队放大”判断一致。

## 3) L2 结论（json_model）

复验组合（6 组）全部通过：

- `c8/mif24`、`c8/mif48`
- `c16/mif24`、`c16/mif48`
- `c32/mif32`、`c32/mif48`

关键观察：

1. `json_model` 下结论与 L1 一致，没有出现反转。
2. `c32` 档位 `mif32` 与 `mif48` 都稳定通过；`mif32` 在本轮吞吐中位数略优。

## 4) 默认值建议（P1 第一版）

1. 默认值：`maxInFlightTasks = 32`
2. 备选：`48`（当后续压测目标偏吞吐上限时）
3. 保守备选：`24`（仅建议用于 `c16` 及以下档位，不建议覆盖 `c32`）

## 5) 路由建议（仅 jitter 场景）

1. 若全局默认 `mif=32`：`c8/c16/c32` 可放 Rust（保留灰度回滚）。
2. 若运行时降到 `mif<32`：`c32` 建议回 Dio 保守。
3. 灰度节奏保持：`5% -> 25% -> 50% -> 100%`，按既有门槛触发回切。

## 6) 结论

本轮 P1 数据支持将 `maxInFlightTasks` 默认值从历史 `12` 提升到 `32`。  
在 `jitter + 高并发` 下，`mif=32` 能稳定抑制排队放大并保持 Rust 在 p95 与吞吐的综合优势。

