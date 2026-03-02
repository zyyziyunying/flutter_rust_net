---
title: flutter_rust_net 真机测试命令清单（2026-03-02）
---

# flutter_rust_net 真机测试命令清单（2026-03-02）

> 适用范围：`flutter_rust_net` 真机回归与 Dio/Rust 对比。  
> 执行目录默认从仓库根目录 `D:\dev\flutter_code\harrypet_flutter` 开始。

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

---

## 2) 严格 CLI 对比（可追溯 JSON 产物）

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

## 5) 结果上传（可选）

```powershell
Set-Location .\flutter_rust_net

# 先 dry-run 看会上传哪些文件
dart run tool/upload_bench_log.dart --input=build --ext=json --dry-run

# 正式上传（按需补充 token / 额外字段）
dart run tool/upload_bench_log.dart --input=<your_output_dir> --ext=json --extra-field=project=flutter_rust_net --extra-field=network_profile=wifi
```

如服务端要求鉴权头，可追加（示例）：

```powershell
dart run tool/upload_bench_log.dart --input=<your_output_dir> --ext=json --header=token:<actual-token>
```

---

## 6) 结果判定顺序（统一口径）

1. `exceptions` / `exceptionRate`
2. `http5xx` / `fallbackCount`
3. `p95` / `p99`
4. `throughputRps`

建议每个场景至少跑 3 轮并取中位数，再回填 `docs/test_plans/test_run_log.md`（date / commit / command / result / notes）。
