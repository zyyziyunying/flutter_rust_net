# L2 测试简要结论（2026-02-24）

> 关联记录：`docs/test_plans/test_run_log.md` / `TR-20260224-08`

## 范围

- 项目：`media_kit_poc`
- 轮次：L2 consume 复验
- 场景：
  - `small_json` + `consume-mode=json_decode`
  - `small_json` + `consume-mode=json_model`
  - `jitter_latency` + `consume-mode=json_model`

## 结论

- **small_json（json_decode / json_model）**：**Rust 明显优于 Dio**
  - Rust：p95 = 11~13ms，p99 = 16ms，吞吐 = 1739~1875 rps
  - Dio：p95 = 42~48ms，p99 = 43~49ms，吞吐 = 632~721 rps
- **jitter_latency（json_model）**：**Dio 优于 Rust**
  - Dio：p95 = 97ms，p99 = 102ms，吞吐 = 234.83 rps
  - Rust：p95 = 137ms，p99 = 171ms，吞吐 = 184.47 rps

## 稳定性

- 三组测试两通道均：`exceptions=0`、`http5xx=0`
- 两通道 `consume p95=0ms`（毫秒粒度下可视为接近可忽略）

## 建议动作

- 默认将 **small_json 路由到 Rust**
- **jitter_latency 暂保留 Dio**，待补齐 5 轮中位数与并发梯度测试后再定最终策略

## 原始结果文件

- `media_kit_poc/build/bench_small_l2_decode.json`
- `media_kit_poc/build/bench_small_l2_model.json`
- `media_kit_poc/build/bench_jitter_l2_model.json`

