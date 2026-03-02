---
id: 7e0b6382-5d8a-4b4a-8fd4-9e619d2fb0cb
title: Dio vs Rust 真实场景网络测试说明（2026-02-24）
---

# Dio vs Rust 真实场景网络测试说明（2026-02-24）

> 目标：从“页面手工冒烟”升级到“可复现、可对比、可量化”的真实场景测试，持续评估 `Dio` 与 `Rust` 双通道在不同负载下的差异，并沉淀路由策略依据。
> 归档说明：本文件保留设计与执行细节；L1 决策请以 `flutter_rust_net/docs/dio_rust_test/network_benchmark_aggregation_2026-02-24.md` 为准，L2/large_json 补充请结合 `flutter_rust_net/docs/dio_rust_test/network_realistic_benchmark_l2_summary_2026-02-24.md` 与 `flutter_rust_net/docs/dio_rust_test/network_large_json_validation_2026-02-24.md`。

## 1) 本次改造范围

### 1.1 新增能力

1. **统一 benchmark 基建（本地可控场景服务 + 并发压测 runner）**
   - 文件：`flutter_rust_net/lib/network/benchmark/network_benchmark_harness.dart`
2. **命令行压测入口**
   - 文件：`flutter_rust_net/tool/network_bench.dart`
3. **真实场景自动化测试（Flutter test）**
   - 文件：`flutter_rust_net/test/network/network_realistic_flow_test.dart`

### 1.2 之前改造（作为基线）

1. 删除页面式网络冒烟入口：
   - `flutter_rust_net/lib/network_smoke_page.dart`（删除）
   - `media_kit_poc/lib/main.dart`（移除入口）
2. 保留并增强单测日志：
   - `flutter_rust_net/test/network/network_smoke_flow_test.dart`

---

## 2) 测试框架设计

### 2.1 总体思路

将测试拆成两层：

1. **自动化验证层（`flutter test`）**
   - 保证核心行为正确：路由、fallback、异常分类、状态码分布。
2. **压测对比层（`dart run tool/network_bench.dart`）**
   - 面向性能与稳定性：吞吐、尾延迟、失败率、fallback 率。

### 2.2 场景服务器（本地 loopback）

由 `network_benchmark_harness.dart` 内置 `HttpServer` 提供可控接口：

1. `small_json`
   - 小包 JSON，高频场景。
2. `large_json`
   - 大 JSON 响应，验证大对象返回与消费链路。
3. `large_payload`
   - 大响应体（默认 2MB，可配置）。
4. `jitter_latency`
   - 可控抖动延迟（base + extra）。
5. `flaky_http`
   - 按比例返回 503，模拟服务端波动。

### 2.3 通道执行方式

每个请求使用 `forceChannel` 强制走：

1. `dio`
2. `rust`

并通过 `enableFallback` 控制 Rust 失败后是否回退 Dio，用于观测“可用性优先”的效果。

---

## 3) 指标定义（统一采集）

每个通道输出：

1. **吞吐**
   - `throughputRps`（请求数 / 总墙钟时间）。
2. **延迟**
   - `endToEndLatencyMs`：p50 / p95 / p99 / avg / min / max。
   - `adapterCostLatencyMs`：适配器内 `costMs` 分布（与端到端对照）。
3. **结果分布**
   - `http2xx/http4xx/http5xx`
   - `statusCodes` 明细（如 `200`, `503`）
4. **稳定性**
   - `exceptions`、`exceptionRate`
   - `exceptionCodes`、`exceptionChannels`
5. **路由与回退**
   - `responseChannels`（最终响应来自 Dio 还是 Rust）
   - `routeReasons`
   - `fallbackCount`
   - `fallbackReasons`

---

## 4) 自动化测试用例说明（`network_realistic_flow_test.dart`）

### 4.1 `small json burst on dio keeps full success`

- 配置：`small_json`，80 请求，并发 8，仅 Dio。
- 验证点：
  1. `completed=80`
  2. `exceptions=0`
  3. `http2xx=80`
  4. `responseChannels.dio=80`

### 4.2 `flaky http exposes expected 5xx ratio without transport errors`

- 配置：`flaky_http`，50 请求，`failureEvery=5`（理论 20% 503）。
- 验证点：
  1. `exceptions=0`（HTTP 错误不等于传输异常）
  2. `200=40`
  3. `503=10`
  4. 分位关系合理：`p99 >= p95 >= p50`

### 4.3 `force rust with fallback keeps availability under load`

- 配置：`jitter_latency`，40 请求，并发 8，仅 Rust，Rust 不初始化，开启 fallback。
- 验证点：
  1. `exceptions=0`
  2. `fallbackCount=40`
  3. 最终响应通道为 Dio：`responseChannels.dio=40`
  4. 路由原因：`force_channel -> fallback_dio`
  5. 回退原因：`infrastructure`

### 4.4 `large json with json_model consume keeps full success`

- 配置：`large_json`，20 请求，并发 4，仅 Dio，`consume-mode=json_model`。
- 验证点：
  1. `exceptions=0`
  2. `consumeAttempted=20`、`consumeSucceeded=20`
  3. `jsonDecodeLatencyMs.count=20`
  4. `modelBuildLatencyMs.count=20`
  5. `consumeBytesTotal` 达到大 JSON 量级

---

## 5) 执行命令清单

> 建议工作目录：`D:\dev\flutter_code\harrypet_flutter\media_kit_poc`

### 5.1 自动化回归

```bash
flutter test test/network -r expanded
flutter test test/network/network_realistic_flow_test.dart -r expanded
```

### 5.2 压测对比（生成 JSON 报告）

#### A. 小包高频

```bash
dart run tool/network_bench.dart --scenario=small_json --channels=dio,rust --initialize-rust=true --require-rust=true --requests=400 --concurrency=16 --output=build/bench_small.json
```

#### B. 大包体

```bash
dart run tool/network_bench.dart --scenario=large_payload --channels=dio,rust --initialize-rust=true --require-rust=true --requests=120 --concurrency=8 --output=build/bench_large.json
```

#### C. 大 JSON

```bash
dart run tool/network_bench.dart --scenario=large_json --channels=dio,rust --initialize-rust=true --require-rust=true --requests=120 --concurrency=8 --output=build/bench_large_json.json
```

#### D. 抖动延迟

```bash
dart run tool/network_bench.dart --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --requests=240 --concurrency=16 --jitter-base-ms=12 --jitter-extra-ms=80 --output=build/bench_jitter.json
```

#### E. 服务端波动（503）

```bash
dart run tool/network_bench.dart --scenario=flaky_http --channels=dio,rust --initialize-rust=true --require-rust=true --requests=240 --concurrency=16 --flaky-every=4 --output=build/bench_flaky.json
```

#### F. fallback 兜底演练

```bash
dart run tool/network_bench.dart --scenario=small_json --channels=rust --initialize-rust=false --require-rust=false --fallback=true --requests=120 --concurrency=12 --output=build/bench_fallback_on.json
dart run tool/network_bench.dart --scenario=small_json --channels=rust --initialize-rust=false --require-rust=false --fallback=false --requests=120 --concurrency=12 --output=build/bench_fallback_off.json
```

---

## 6) 结果解读建议（Dio vs Rust）

### 6.1 先看稳定性，再看性能

优先级：

1. `exceptions` / `exceptionRate`
2. `http5xx`、`fallbackCount`
3. `p95/p99`
4. `throughput`

### 6.2 场景化决策参考

1. **small_json**
   - 若 Rust 无明显 `p95/p99` 优势且复杂度更高，默认继续 Dio。
2. **large_payload**
   - 若 Rust 在 `p95/p99`、吞吐或内存稳定性更优，可考虑迁移该类接口到 Rust。
3. **large_json**
   - 若 Rust 在 `req/e2e` 明显领先但 consume 偏重，优先迁移“下载+落地”型接口，解析重负载场景先灰度。
4. **jitter/flaky**
   - 重点观察 fallback 策略是否提升总体成功率与尾部稳定性。

### 6.3 对比结论模板

可按场景输出一句话结论：

1. 结论：`<scenario>` 下 `<channel>` 更适合。
2. 证据：`p95/p99/throughput/exceptionRate/fallbackRate`。
3. 动作：路由策略调整（`allow_list`、阈值、fallback 开关）。

---

## 7) 运行记录模板（建议回填）

在测试后补充到 `docs/test_plans/test_run_log.md`：

| run_id         | date       | branch | commit     | scope                       | command                                                     | result    | notes                      |
| -------------- | ---------- | ------ | ---------- | --------------------------- | ----------------------------------------------------------- | --------- | -------------------------- |
| TR-20260224-XX | 2026-02-24 | main   | `<commit>` | network realistic benchmark | `flutter test ...` + `dart run tool/network_bench.dart ...` | PASS/FAIL | 记录关键场景结论与异常摘要 |

---

## 8) 已知限制与后续建议

### 8.1 当前限制

1. 当前场景服务为本地 loopback，尚未覆盖真实移动网络链路（Wi-Fi/4G/弱网代理）。
2. 指标以请求层为主，尚未自动采集 CPU/内存峰值与漂移。
3. 仍需在真机长稳（30~120 分钟）验证资源稳定性。

### 8.2 下一步（建议）

1. 增加“真机网络剖面”专项（Wi-Fi/4G/弱网）。
2. 增加长稳压测（Soak）与中断恢复场景。
3. 将 JSON 报告聚合成趋势图（按日期/commit 对比）。

