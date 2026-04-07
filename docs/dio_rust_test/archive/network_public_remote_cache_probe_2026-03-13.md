---
title: flutter_rust_net 公网 jitter 缓存收益样例（2026-03-13）
---

# flutter_rust_net 公网 jitter 缓存收益样例（2026-03-13）

> 范围：`flutter_rust_net` 主机 -> 公网 benchmark 服务的 P2 缓存收益补跑样例。  
> 目的：保留一份 `2026-03-13` 本地执行产物摘要，并记录当前 benchmark 口径的后续修正。

## 1) 本轮执行信息

- 日期：`2026-03-13`
- `baseUrl`：`http://47.110.52.208:7777`
- 场景：`jitter_latency`
- 设备：`host_windows`
- 网络：`ethernet`
- 输出目录：`build/remote_cache_probe_20260313/`
- 公共参数：`requests=96 concurrency=8 rustMaxInFlight=32 requestKeySpace=12 jitterBaseMs=12 jitterExtraMs=80`

说明：

1. 上述 JSON 是 `2026-03-13` 的本地执行产物，默认不会随仓库提交。
2. 这些历史产物生成时，external `baseUrl` 路径仍会注入 `x-network-bench-channel`。
3. 自 `2026-03-14` 起，external 路径已改为不注入该 header，且客户端 repeated miss 改由 `repeatedMissCount` 单独输出。

执行命令：

```powershell
dart run tool/network_bench.dart --base-url=http://47.110.52.208:7777 --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --requests=96 --warmup=0 --concurrency=8 --jitter-base-ms=12 --jitter-extra-ms=80 --rust-max-in-flight=32 --request-key-space=12 --output=build/remote_cache_probe_20260313/remote_jitter_cache_cold.json

dart run tool/network_bench.dart --base-url=http://47.110.52.208:7777 --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --requests=96 --warmup=12 --concurrency=8 --jitter-base-ms=12 --jitter-extra-ms=80 --rust-max-in-flight=32 --request-key-space=12 --output=build/remote_cache_probe_20260313/remote_jitter_cache_warm.json
```

## 2) 样例结果

### 2.1 cold-start（`warmup=0`，历史产物摘要）

- Dio：`cacheHit=0/96`, `cacheMiss=96`, `repeatedMissCount=84`（历史 JSON 字段名：`cacheEvict=84`）, `reqP95=120ms`, `throughput=185.69 req/s`
- Rust：`cacheHit=82/96`, `cacheMiss=14`, `repeatedMissCount=3`（历史 JSON 字段名：`cacheEvict=3`）, `reqP95=85ms`, `throughput=405.06 req/s`

观察：

1. 冷启动下 Rust 已出现明显缓存收益，命中率约 `85.4%`。
2. Rust 的 `cacheMiss=14` 高于 key-space 的 `12`，说明并发冷启动阶段存在少量重复首 miss；这与 `concurrency=8` 下的竞争窗口一致。
3. 同一配置下 Rust `reqP95` 约比 Dio 低 `35ms`，吞吐约为 Dio 的 `2.18x`。

### 2.2 warm-cache（`warmup=12`，历史产物摘要）

- Dio：`cacheHit=0/96`, `cacheMiss=96`, `repeatedMissCount=84`（历史 JSON 字段名：`cacheEvict=84`）, `reqP95=43ms`, `throughput=225.88 req/s`
- Rust：`cacheHit=96/96`, `cacheMiss=0`, `repeatedMissCount=0`（历史 JSON 字段名：`cacheEvict=0`）, `reqP95=7ms`, `throughput=1371.43 req/s`

观察：

1. 当 warmup 覆盖全部 12 个重复 key 后，Rust 测量窗口内达到了 `100%` fresh cache 命中。
2. 稳态下 Rust `reqP95=7ms`，相对 Dio `43ms` 降幅明显，吞吐约为 Dio 的 `6.07x`。
3. `repeatedMissCount=0` 说明稳态测量窗口里没有继续发生 repeated miss。

## 3) 口径说明

1. 自 `2026-03-14` 起，external `baseUrl` 路径不再注入 `x-network-bench-channel`，避免 benchmark 专用 header 进入真实链路请求形态与 Rust cache key。
2. 当前 benchmark 报告里，客户端侧 repeated miss 统一记到 `repeatedMissCount`；`cacheRevalidate/cacheEvict` 仅在本地 scenario server 口径下输出权威条件请求/重复回源统计。
3. 这两份历史产物里的 `cacheEvict` 应按当时 external 口径理解为 repeated miss，不再作为当前 `cacheEvict` 语义示例。
4. 若后续要专门观察 `cacheRevalidate`，需要把样例改成短 TTL 或显式 validator（`ETag` / `Last-Modified`）链路，并优先使用本地 scenario server 口径。

## 4) 当前结论

1. P2 “真实链路缓存收益观测”已具备最小证据：即使在公网 jitter 场景，Rust 缓存也能显著压低 tail latency 并提升 throughput。
2. 对当前这组配置，可先沿用一个简单阈值建议：
   - `requestKeySpace <= warmup` 时，Rust 缓存稳态收益显著，可优先保留 Rust 缓存链路。
   - `requestKeySpace > warmup` 且并发为 `8` 量级时，允许出现少量重复首 miss，但若 `repeatedMissCount` 持续明显大于 `requestKeySpace / 4`，应复查是否有缓存被绕过。
3. 下一步优先补：
   - Android / iOS 真机同口径样例
   - `cache on/off` 一致性复测
   - `DiskCache` 级 namespace 预算互不干扰回归
