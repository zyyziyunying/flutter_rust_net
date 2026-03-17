---
title: flutter_rust_net 公网 jitter root budget 样例（2026-03-17）
---

# flutter_rust_net 公网 jitter root budget 样例（2026-03-17）

> 范围：`flutter_rust_net` 主机 -> 公网 benchmark 服务的 root budget 归档样例。  
> 目的：补齐 P2 “external `jitter_latency` + `cacheRootMaxBytes`” 的 cold / warm 样例，并确认 JSON 中的 `rustCacheObservation.rootBytes` 已可作为归档依据。

## 1) 本轮执行信息

- 日期：`2026-03-17`
- `baseUrl`：`http://47.110.52.208:7777`
- 场景：`jitter_latency`
- 设备：`host_windows`
- 网络：`ethernet`
- 输出目录：`build/remote_cache_root_budget_20260317_143738/`
- 公共参数：`requests=96 concurrency=8 rustMaxInFlight=32 requestKeySpace=12 jitterBaseMs=12 jitterExtraMs=80`
- Rust cache 参数：`rustCacheDir=build/remote_cache_root_budget_20260317_143738/rust_cache_root_budget rustCacheResponseNamespace=responses rustCacheMaxNamespaceBytes=16777216 rustCacheRootMaxBytes=25165824`

说明：

1. 本轮 cold / warm 显式复用了同一个 `rustCacheDir`，用于观察同一 cache root 下的命中与占用变化。
2. 两份 JSON 里的 `config.rustCache*` 字段与命令行一致，未发生额外归一化漂移。
3. `rustCacheObservation.rootBytes=7660` 与本地对该目录递归求和的实际文件大小一致，可作为这次样例的 root usage 观测值。

执行命令：

```powershell
$baseUrl = "http://47.110.52.208:7777"
$out = "build/remote_cache_root_budget_20260317_143738"
$cacheDir = Join-Path $out "rust_cache_root_budget"

dart run tool/network_bench.dart --base-url=$baseUrl --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --requests=96 --warmup=0 --concurrency=8 --jitter-base-ms=12 --jitter-extra-ms=80 --rust-max-in-flight=32 --request-key-space=12 --rust-cache-dir="$cacheDir" --rust-cache-namespace=responses --rust-cache-max-namespace-bytes=16777216 --rust-cache-root-max-bytes=25165824 --output="${out}/remote_jitter_root_budget_cold.json"

dart run tool/network_bench.dart --base-url=$baseUrl --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --requests=96 --warmup=12 --concurrency=8 --jitter-base-ms=12 --jitter-extra-ms=80 --rust-max-in-flight=32 --request-key-space=12 --rust-cache-dir="$cacheDir" --rust-cache-namespace=responses --rust-cache-max-namespace-bytes=16777216 --rust-cache-root-max-bytes=25165824 --output="${out}/remote_jitter_root_budget_warm.json"
```

## 2) 样例结果

### 2.1 cold-start（`warmup=0`）

- Dio：`cacheHit=0/96`, `cacheMiss=96`, `repeatedMissCount=84`, `reqP95=129ms`, `throughput=186.05 req/s`
- Rust：`cacheHit=84/96`, `cacheMiss=12`, `repeatedMissCount=0`, `reqP95=92ms`, `throughput=297.21 req/s`
- Root 观测：`rustCacheObservation.rootBytes=7660`, `config.rustCacheRootMaxBytes=25165824`

观察：

1. cold-start 下 Rust 已把 12 个重复 key 全部压到首轮 miss 内，`cacheMiss=12` 与 `requestKeySpace=12` 对齐，没有再出现 repeated miss。
2. 相同并发下 Rust `reqP95` 约比 Dio 低 `37ms`，吞吐约为 Dio 的 `1.60x`。
3. 首次创建 cache root 后就已稳定产出 `rootBytes`，且显著低于 root budget。

### 2.2 warm-cache（`warmup=12`）

- Dio：`cacheHit=0/96`, `cacheMiss=96`, `repeatedMissCount=84`, `reqP95=43ms`, `throughput=220.69 req/s`
- Rust：`cacheHit=96/96`, `cacheMiss=0`, `repeatedMissCount=0`, `reqP95=21ms`, `throughput=461.54 req/s`
- Root 观测：`rustCacheObservation.rootBytes=7660`, `config.rustCacheRootMaxBytes=25165824`

观察：

1. warmup 覆盖全部 12 个 key 后，Rust 测量窗口内达到 `100%` cache hit。
2. warm 样例的 `rootBytes` 与 cold 样例一致，说明当前这组 external `jitter_latency` 样例在同一 cache root 下没有继续膨胀。
3. `rootBytes=7660 <= 25165824`，这轮样例中 root budget 口径可直接解释当前 cache root 的收敛状态。

## 3) 当前结论

1. P2 “external `jitter_latency` + root budget” 首批归档样例已补齐，`rustCacheObservation.rootBytes` 在 cold / warm 两份 JSON 中都稳定产出。
2. 对这次显式独占 cache root 的样例，报告里的 `rootBytes` 与实际目录字节数一致，说明 benchmark 当前观测口径可直接用于归档。
3. 当前剩余重点不再是 external 首批样例，而是补 Android / iOS 真机同口径归档，继续观察 `rootBytes <= cacheRootMaxBytes` 是否长期成立。
