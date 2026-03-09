# flutter_rust_net 远端真机压测：Go 服务实现方案（2026-03-02）

## 目标

让真机测试走真实网络链路（手机 -> 公网 Go 服务），而不是本地 loopback。

## 当前现状（基于现有代码）

- `tool/network_bench.dart` 调用 `runNetworkBenchmark(...)`。
- `runNetworkBenchmark(...)` 内部会启动本地 `_ScenarioServer`，地址固定是 `127.0.0.1` 随机端口。
- 因此默认只能做本地回环测试，不能直接命中远端服务。

## 你需要改的两部分

1. **Go 服务端**：实现与本地 `_ScenarioServer` 一致的接口语义（见下文“接口契约”）。
2. **flutter_rust_net 基准入口**（最小改动）：支持传入 `baseUrl`，有值时不再启动本地 server。

---

## 接口契约（Go 服务必须对齐）

统一约定：

- 方法：`GET`
- 编码：`utf-8`
- 大 JSON / 二进制返回时建议带 `Content-Length`
- 路径不存在返回 `404`
- 非 GET 返回 `405`

### 1) small json

- `GET /bench/small-json?id=<int>`
- 响应：`200 application/json`
- body 示例：

```json
{"title":"network-bench","ok":true,"payload":"xxxxx..."}
```

### 2) large json

- `GET /bench/large-json?id=<int>`
- 响应：`200 application/json`
- body：大约 `2MB`（可配置）的 JSON 字符串字段（例如 `payload`）

### 3) large payload

- `GET /bench/large-payload?id=<int>`
- 响应：`200 application/octet-stream`
- body：大约 `2MB`（可配置）二进制

### 4) jitter latency

- `GET /bench/jitter?id=<int>&baseDelayMs=<int>&extraDelayMs=<int>`
- 延迟公式（建议与现有逻辑完全一致）：
  - `delayMs = baseDelayMs + (abs(id) % (extraDelayMs + 1))`
- 睡眠后返回：`200 application/json`
- body 示例：

```json
{"id":12,"delayMs":37,"kind":"jitter"}
```

### 5) flaky http

- `GET /bench/flaky?id=<int>&failureEvery=<int>`
- 失败判定（与当前逻辑一致）：
  - `shouldFail = ((abs(id + 1) % failureEvery) == 0)`
- `shouldFail=true`：
  - 返回 `503 text/plain`
  - body: `temporary_unavailable`
- 否则：
  - 返回 `200 application/json`
  - body 示例：

```json
{"id":9,"kind":"flaky","ok":true}
```

### 6) health check（建议）

- `GET /healthz`
- 返回 `200 application/json`，例如：`{"ok":true}`

---

## Go 侧建议实现要点

- 用 `net/http`，每个路径独立 handler。
- 大 JSON / 大二进制尽量复用预生成缓存（避免每次请求都重新构造）。
- 服务端日志至少记录：path、status、latency、remote addr。
- 容器部署时监听 `0.0.0.0:<port>`，确保公网可达。

---

## Flutter 侧最小改造建议（你本地可自己改）

在 `BenchmarkConfig` 增加可选字段：

- `scenarioBaseUrl`（默认空字符串）

在 `runNetworkBenchmark(...)`：

- 若 `scenarioBaseUrl` 非空：直接使用该地址拼接 `scenario.path`
- 若为空：保持现有行为，启动本地 `_ScenarioServer`

CLI 透传参数示例：

```bash
dart run tool/network_bench.dart --base-url=http://<server-ip>:18080 --scenario=small_json --channels=dio,rust
```

---

## 联调顺序（建议）

1. 先在服务端验证：
   - `curl http://<server>/healthz`
   - `curl "http://<server>/bench/small-json?id=1"`
2. 再让真机跑 `small_json` 单场景；
3. 再跑 `jitter_latency` 和 `flaky_http`；
4. 最后跑 `large_json` / `large_payload` 压力场景。

---

## 验收判定（和现有报告口径一致）

优先看：

1. `exceptions` / `exceptionRate`
2. `http5xx` / `fallbackCount`
3. `p95` / `p99`
4. `throughputRps`

建议每个场景至少 3 轮取中位数。
