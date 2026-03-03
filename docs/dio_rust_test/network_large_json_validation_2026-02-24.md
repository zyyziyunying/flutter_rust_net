# large_json 验证记录（对照掘金文章）

- 日期：2026-02-24
- 目标：在当前仓库中补齐并执行 `large_json` 基准，验证 Dio vs Rust（FFI）表现
- 对照文章：<https://juejin.cn/post/7604666872128389139>
- 关联记录：`相关文档（按需）`

## 1. 背景说明

在本仓库原有 benchmark 中，只有 `small_json` / `large_payload` / `jitter_latency` / `flaky_http`，没有 `large_json`。  
本次先补充 `large_json` 场景，再执行严格双通道对比。

## 2. 本次执行命令

```bash
cd D:\dev\flutter_code\harrypet_flutter\media_kit_poc

dart run tool/network_bench.dart --scenario=large_json --channels=dio,rust --initialize-rust=true --require-rust=true --consume-mode=json_decode --requests=120 --concurrency=8 --output=build/bench_large_json_l2_decode.json

dart run tool/network_bench.dart --scenario=large_json --channels=dio,rust --initialize-rust=true --require-rust=true --consume-mode=json_model --requests=120 --concurrency=8 --output=build/bench_large_json_l2_model.json
```

## 3. 结果总览（核心指标）

| 场景                     | 通道 | req p95 | e2e p95 | consume p95 |        吞吐 |
| ------------------------ | ---- | ------: | ------: | ----------: | ----------: |
| large_json + json_decode | Dio  |   159ms |   163ms |         8ms | 58.08 req/s |
| large_json + json_decode | Rust |    80ms |   123ms |        90ms | 90.23 req/s |
| large_json + json_model  | Dio  |   149ms |   154ms |         8ms | 58.06 req/s |
| large_json + json_model  | Rust |    81ms |   106ms |        54ms | 90.84 req/s |

稳定性：两组均 `exceptions=0`、`http5xx=0`、`fallbackCount=0`。

## 4. FFI 路径有效性证据

- `rustInitialized=true`（Rust 引擎已初始化）
- `responseChannels.rust=120`（Rust 分组请求实际由 Rust 响应）
- `fallbackCount=0`（未回退到 Dio）

对应结果文件：

- `media_kit_poc/build/bench_large_json_l2_decode.json`
- `media_kit_poc/build/bench_large_json_l2_model.json`

## 5. 与文章结论的关系（非常关键）

当前项目这套 benchmark 测到的是：

1. Rust 网络请求（FRB/FFI 调用）
2. 返回 `bodyBytes/bodyFilePath` 给 Dart
3. Dart 侧执行 `jsonDecode` / model build

也就是说，它不是“Rust 把 JSON 解析成对象再跨 FFI 回 Dart 对象”的测试模型。  
因此，本次结果可以验证**网络通道与数据搬运链路**，但不能一比一复现文章中“Rust parse + FFI 对象回传通常吃亏”的结论。

## 6. 本轮结论

1. 在当前仓库实现下，`large_json` 场景里 Rust 通道整体指标优于 Dio（req/e2e p95 更低、吞吐更高）。
2. Rust 通道在 consume 侧更重（尤其 `materializeBody`），说明其额外开销主要在“数据落盘/回读或跨边界搬运”路径，而非纯网络请求延迟。
3. 若要严格验证文章主张，建议新增“Rust 端解析 JSON 并返回 Dart dynamic/模型”的独立基准，再与 Dart `jsonDecode`/`compute` 对照。

