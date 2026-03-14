---
title: flutter_rust_net 真机测试命令清单（2026-03-13）
---

# flutter_rust_net 真机测试命令清单（2026-03-13）

> 适用范围：`flutter_rust_net` 真机回归与 Dio/Rust 对比。  
> 执行目录默认从仓库根目录 `D:\dev\flutter_code\harrypet_flutter` 开始。
>
> 当前口径（2026-03-13）：
> 1. `example/` 里的预设主要用于真机 App 冒烟、Rust 打包链路和上传按钮回归，默认仍走本地 loopback。
> 2. 已新增固定入口 `tool/p1_non_loopback_bench.dart`，可一键串联公网 benchmark、聚合摘要和 `run_manifest.json`。
> 3. `tool/network_bench.dart` 仍保留为底层命令入口，适合手工拆分单场景复验。
> 4. 若 Rust 初始化触发“本地 `net_engine` 动态库陈旧”保护，先执行 `cd flutter_rust_net && dart run tool/rust_build.dart --profile=release` 再复跑。

## 0) 一次性预检查（建议先跑）

```powershell
flutter --version
flutter doctor -v
flutter devices

Set-Location .\flutter_rust_net
flutter pub get
flutter analyze lib test tool
flutter test test/network -r expanded
flutter test test/network/network_realistic_flow_test.dart -r expanded

# 如需严格核对当前 Rust 侧状态，再补：
dart run tool/rust_build.dart --build=false --test=true

# 如遇 stale library 预检或准备远端 Rust 对比，再补：
dart run tool/rust_build.dart --profile=release
```

Android 真机补充检查（Rust 构建链路）：

```powershell
cargo --version
cargo ndk --version
```

---

## 1) 真机 App 冒烟（推荐先做）

```powershell
Set-Location .\flutter_rust_net\example
flutter pub get
flutter devices
flutter run -d <device_id> --debug
```

App 内建议顺序：

1. 先跑 `Dio smoke (small_json)`（`Require Rust init` 先关闭）。
2. 再跑 `Dio vs Rust (small_json)`（打开 `Require Rust init`）。
3. 再跑 `Dio vs Rust (jitter c16 mif32)`（确认 `mif=32` 表现）。
4. 若需要上报，点击 `Upload last report`。

说明：

1. 当前示例 App 预设仍主要用于 **loopback 冒烟**，适合验证 UI、Rust Android 打包、Dio/Rust 通道和上传动作是否通。
2. 若要核对当前公网 benchmark 服务，请使用下方 CLI 的 `--base-url` 命令；当前示例 UI 还没有把 `scenarioBaseUrl` 暴露出来。

---

## 2) 严格 CLI 对比（可追溯 JSON 产物）

### 2.1 公网 non-loopback smoke（主机 -> 公网服务，推荐固定入口）

推荐先跑固定入口：

```powershell
Set-Location .\flutter_rust_net

dart run tool/p1_non_loopback_bench.dart --preset=smoke --network-profile=ethernet --device=host_windows
```

默认产物：

1. `remote_small_dio.json`
2. `remote_small_rust.json`
3. `remote_jitter_mif32.json`
4. `aggregate_small_json.(md|json)`
5. `aggregate_jitter_latency.(md|json)`
6. `run_manifest.json`
7. `logs/*.stdout.log` 与 `logs/*.stderr.log`

说明：

1. 该入口默认输出到 `build/remote_public_<runId>/`，并把本轮 `git commit`、归档字段、每条实际执行命令都写进 `run_manifest.json`。
2. 若需要上传，可追加 `--upload=true --upload-header=token:<actual-token>`；上传日志也会落到同一目录。
3. 该入口会对 `--upload-header` 做脱敏；`run_manifest.json` 和命令摘要中只保留 `token:<redacted>`。
4. 仓库内已留一份主机 smoke + 上传回执样例记录：`docs/dio_rust_test/network_public_remote_sample_2026-03-13.md`。

如需手工拆分命令，再使用下面这组底层 CLI：

```powershell
Set-Location .\flutter_rust_net

$baseUrl = "http://47.110.52.208:7777"
$runId = Get-Date -Format "yyyyMMdd_HHmm"
$out = "build/remote_public_$runId"
New-Item -ItemType Directory -Path $out -Force | Out-Null

# health / small_json：先确认服务可达
dart run tool/network_bench.dart --base-url=$baseUrl --scenario=small_json --channels=dio --requests=40 --warmup=4 --concurrency=8 --output="${out}/remote_small_dio.json"

# Rust strict smoke：若失败先看是否命中 stale library 提示
dart run tool/network_bench.dart --base-url=$baseUrl --scenario=small_json --channels=rust --initialize-rust=true --require-rust=true --requests=40 --warmup=4 --concurrency=8 --rust-max-in-flight=32 --output="${out}/remote_small_rust.json"

# Dio vs Rust：当前重点保留 jitter(c16,mif32)
dart run tool/network_bench.dart --base-url=$baseUrl --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --requests=240 --warmup=24 --concurrency=16 --jitter-base-ms=12 --jitter-extra-ms=80 --rust-max-in-flight=32 --output="${out}/remote_jitter_mif32.json"
```

判定要点：

1. 这组命令验证的是 **当前公网服务链路**，不是手机网络剖面本身。
2. 若 Rust 被跳过并提示 `Detected stale net_engine native library`，先执行：

```powershell
dart run tool/rust_build.dart --profile=release
```

3. 当前已确认 `http://47.110.52.208:7777` 可返回：
   - `GET /healthz -> 200`
   - `GET /bench/small-json?id=1 -> 200`

### 2.1.1 公网 jitter 缓存收益补跑（P2）

适用场景：

1. 需要确认真实链路下 Rust 缓存命中收益，而不是只看 loopback。
2. 需要对比 `cold-start` 与 `warm-cache` 两种口径。

推荐命令：

```powershell
Set-Location .\flutter_rust_net

$baseUrl = "http://47.110.52.208:7777"
$runId = Get-Date -Format "yyyyMMdd_HHmm"
$out = "build/remote_cache_probe_$runId"
New-Item -ItemType Directory -Path $out -Force | Out-Null

# cold-start：不做 warmup，允许前 12 个 key 自然建缓存
dart run tool/network_bench.dart --base-url=$baseUrl --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --requests=96 --warmup=0 --concurrency=8 --jitter-base-ms=12 --jitter-extra-ms=80 --rust-max-in-flight=32 --request-key-space=12 --output="${out}/remote_jitter_cache_cold.json"

# warm-cache：warmup 覆盖全部 12 个 key，观察稳态缓存收益
dart run tool/network_bench.dart --base-url=$baseUrl --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --requests=96 --warmup=12 --concurrency=8 --jitter-base-ms=12 --jitter-extra-ms=80 --rust-max-in-flight=32 --request-key-space=12 --output="${out}/remote_jitter_cache_warm.json"
```

当前本地执行产物摘要（`2026-03-13`, `host_windows + ethernet`）：

1. `cold-start`：Rust `cacheHit=82/96`, `repeatedMissCount=3`（历史 JSON 字段名：`cacheEvict=3`）, `reqP95=85ms`, `throughput=405 req/s`；Dio `cacheHit=0/96`, `repeatedMissCount=84`（历史 JSON 字段名：`cacheEvict=84`）, `reqP95=120ms`, `throughput=186 req/s`
2. `warm-cache`：Rust `cacheHit=96/96`, `repeatedMissCount=0`（历史 JSON 字段名：`cacheEvict=0`）, `reqP95=7ms`, `throughput=1371 req/s`；Dio `cacheHit=0/96`, `repeatedMissCount=84`（历史 JSON 字段名：`cacheEvict=84`）, `reqP95=43ms`, `throughput=226 req/s`

判读说明：

1. 自 `2026-03-14` 起，external `baseUrl` 下的客户端 repeated miss 统一看 `repeatedMissCount`；`cacheRevalidate/cacheEvict` 仅在本地 scenario server 口径下有权威值。
2. 这组 `2026-03-13` 历史样例里的 `cacheEvict` 应按当时 external 口径理解为 repeated miss，不再作为当前 `cacheEvict` 语义示例。
3. 若 `warmup >= request-key-space` 且 Rust 仍大量 miss，优先检查是否命中 stale library、是否切到非 GET、或请求头是否显式禁用了缓存。

### 2.2 本地 loopback 基线（回归参考）

```powershell
Set-Location .\flutter_rust_net

$runId = Get-Date -Format "yyyyMMdd_HHmm"
$out = "build/real_device_$runId"
New-Item -ItemType Directory -Path $out -Force | Out-Null

# small_json
dart run tool/network_bench.dart --scenario=small_json --channels=dio,rust --initialize-rust=true --require-rust=true --requests=400 --concurrency=16 --output="${out}/bench_small.json"

# large_payload
dart run tool/network_bench.dart --scenario=large_payload --channels=dio,rust --initialize-rust=true --require-rust=true --requests=120 --concurrency=8 --output="${out}/bench_large_payload.json"

# large_json
dart run tool/network_bench.dart --scenario=large_json --channels=dio,rust --initialize-rust=true --require-rust=true --requests=120 --concurrency=8 --output="${out}/bench_large_json.json"

# flaky_http
dart run tool/network_bench.dart --scenario=flaky_http --channels=dio,rust --initialize-rust=true --require-rust=true --requests=240 --concurrency=16 --flaky-every=4 --output="${out}/bench_flaky.json"

# jitter: mif=12（基线）
dart run tool/network_bench.dart --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --requests=240 --concurrency=16 --jitter-base-ms=12 --jitter-extra-ms=80 --rust-max-in-flight=12 --output="${out}/bench_jitter_mif12.json"

# jitter: mif=32（重点复验）
dart run tool/network_bench.dart --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --requests=240 --concurrency=16 --jitter-base-ms=12 --jitter-extra-ms=80 --rust-max-in-flight=32 --output="${out}/bench_jitter_mif32.json"
```

---

## 3) fallback 演练（可用性兜底）

```powershell
Set-Location .\flutter_rust_net

$runId = Get-Date -Format "yyyyMMdd_HHmm"
$out = "build/real_device_$runId"
New-Item -ItemType Directory -Path $out -Force | Out-Null

# fallback on: 预期异常接近 0
dart run tool/network_bench.dart --scenario=small_json --channels=rust --initialize-rust=false --require-rust=false --fallback=true --requests=120 --concurrency=12 --output="${out}/bench_fallback_on.json"

# fallback off: 预期异常显著上升
dart run tool/network_bench.dart --scenario=small_json --channels=rust --initialize-rust=false --require-rust=false --fallback=false --requests=120 --concurrency=12 --output="${out}/bench_fallback_off.json"
```

---

## 4) L2 consume 复验（端到端解析开销）

```powershell
Set-Location .\flutter_rust_net

$runId = Get-Date -Format "yyyyMMdd_HHmm"
$out = "build/real_device_$runId"
New-Item -ItemType Directory -Path $out -Force | Out-Null

dart run tool/network_bench.dart --scenario=small_json --channels=dio,rust --initialize-rust=true --require-rust=true --consume-mode=json_decode --requests=240 --concurrency=16 --output="${out}/bench_small_l2_decode.json"
dart run tool/network_bench.dart --scenario=small_json --channels=dio,rust --initialize-rust=true --require-rust=true --consume-mode=json_model --requests=240 --concurrency=16 --output="${out}/bench_small_l2_model.json"
dart run tool/network_bench.dart --scenario=jitter_latency --channels=dio,rust --initialize-rust=true --require-rust=true --consume-mode=json_model --requests=240 --concurrency=16 --jitter-base-ms=12 --jitter-extra-ms=80 --rust-max-in-flight=32 --output="${out}/bench_jitter_l2_model_mif32.json"
```

---

## 5) 结果上传与归档（可选，但建议统一）

```powershell
Set-Location .\flutter_rust_net

# 先 dry-run 看会上传哪些文件
dart run tool/upload_bench_log.dart --input=build --ext=json --dry-run

# 推荐：直接用固定入口生成并上传
dart run tool/p1_non_loopback_bench.dart --preset=smoke --network-profile=wifi --device=android_real --upload=true --upload-header=token:<actual-token>

# 推荐先约定本轮归档元信息
$runId = Get-Date -Format "yyyyMMdd_HHmm"
$day = Get-Date -Format "yyyyMMdd"
$networkProfile = "wifi"       # 可替换为 4g / weaknet / ethernet
$device = "android_real"       # 可替换为 host_windows / android_real / ios_real
$linkType = "public_remote"    # 可替换为 loopback / public_remote
$archivePrefix = "flutter_rust_net/$day/$networkProfile/$device/$runId"

# 正式上传（推荐字段）
dart run tool/upload_bench_log.dart --input=<your_output_dir> --ext=json --base-url=http://47.110.52.208:7777 --endpoint=/upload --remote-prefix=$archivePrefix --extra-field=project=flutter_rust_net --extra-field=run_id=$runId --extra-field=network_profile=$networkProfile --extra-field=device=$device --extra-field=link_type=$linkType
```

如服务端要求鉴权头，可追加（示例）：

```powershell
dart run tool/upload_bench_log.dart --input=<your_output_dir> --ext=json --base-url=http://47.110.52.208:7777 --endpoint=/upload --remote-prefix=$archivePrefix --extra-field=project=flutter_rust_net --extra-field=run_id=$runId --extra-field=network_profile=$networkProfile --extra-field=device=$device --extra-field=link_type=$linkType --header=token:<actual-token>
```

当前建议归档口径：

1. 文件组织优先靠 `--remote-prefix`，推荐格式：`flutter_rust_net/<YYYYMMDD>/<network_profile>/<device>/<run_id>`。
2. 最少额外字段：`project`、`run_id`、`network_profile`、`device`、`link_type`。
3. 若要进一步便于追溯，可再补：`commit`、`scenario_group`、`operator`。
4. `POST /upload` 未携带有效登录态时，当前预期返回是 `401`；这应视为鉴权失败，不应误判为服务不可达。
5. CLI 会输出统一回执摘要：`status=<code>, client=common.DioLogUploader, costMs=<ms>, response=<preview>`；建议把这串摘要原样同步到 `相关文档（按需）` 或本轮记录中。
6. 若使用 `tool/p1_non_loopback_bench.dart --upload=true`，同目录下的 `run_manifest.json` 会保留本轮 `remotePrefix` / `extraFields`；上传 stdout/stderr 另存到 `logs/upload_json_reports.*.log`。

---

## 6) 结果判定顺序（统一口径）

1. `exceptions` / `exceptionRate`
2. `http5xx` / `fallbackCount`
3. `p95` / `p99`
4. `throughputRps`

可按需多跑几轮并取代表值，再把关键结论同步到 `相关文档（按需）`。
