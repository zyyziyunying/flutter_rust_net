# flutter_rust_net 风险审查记录（2026-03-09）

## 范围

- 审查对象：`flutter_rust_net/` Dart 侧网络层。
- 审查方式：静态阅读核心实现与测试，结合本地验证命令。
- 已执行验证：
  - `flutter analyze`
  - `flutter test`

结论先行：截至 2026-03-09，本次审查里已关闭三项高优先级风险：原始 P0（双通道 request body 编码漂移）、后续暴露的 P1（`List<int>` body 语义歧义），以及下载 fallback 静默破坏断点续传契约的问题。当前剩余高优先级风险主要集中在下载文件落盘语义不安全，以及 transfer 状态管理缺少边界。

## 主要问题

### 1. 已修复（2026-03-09）：请求 body 编码契约已统一，原审查前提已校正

- 修复证据：
  - `lib/network/request_body_codec.dart`
  - `lib/network/dio_adapter.dart:32-39`
  - `lib/network/rust_adapter.dart:211-233`
  - `test/network/request_body_channel_consistency_test.dart`
  - `README.md:55-61`
- 校正说明：
  - 原审查结论里“`Map<String, dynamic>` body + 未显式 JSON content-type 时，Dio 会默认走 `application/x-www-form-urlencoded` 风格编码”这一条表述过于绝对。
  - 在当前仓库使用的 Dio 5.9.1 默认客户端配置下，`ImplyContentTypeInterceptor` 会对 `Map` / `String` 推断 `application/json`；随后默认 transformer 会走 JSON 序列化，而不是表单编码。
  - 但继续依赖 Dio 的隐式推断仍然不安全，因为 Rust 通道并不共享这套拦截器/transformer 语义，双通道契约仍然会漂移。
- 当前实现：
  - 新增共享 `encodeRequestBody(...)`，统一规定：`bodyBytes` 发送原始字节，`String` 发送 UTF-8 字节，其它 JSON 可编码对象（包括 `List<int>` JSON 数组）发送 UTF-8 JSON 字节。
  - `DioAdapter` 与 `RustAdapter` 现在都先走这套归一化逻辑，再发起请求；不再把对象体直接交给 Dio 自行推断。
  - 包本身不再隐式补写或改写 `content-type`；如果服务端依赖 MIME，调用方必须显式设置请求头。
- 验证：
  - 已新增“`Map` body + 未显式 JSON content-type + Rust 失败 fallback 到 Dio”一致性测试，直接比对 Rust `RequestSpec.bodyBytes` 与 Dio 实际出站 body。
  - 已补原始二进制 body 与 JSON int 数组 body 的双通道一致性测试。
  - 本地验证通过：`flutter analyze`、`flutter test`。
- 结论：
  - 该项 P0 风险已关闭。
  - 剩余约束不是“双通道 body 不一致”，而是上层若要发送 `application/x-www-form-urlencoded` 或 multipart，必须自行编码并显式声明 `content-type`。
  - 历史上基于同一修复路径曾暴露一个新的独立 P1 风险：`List<int>` 被强制解释为原始字节；该项也已在同日关闭，见下一项。

### 2. 已修复（2026-03-09）：`List<int>` body 与原始 bytes 语义已显式拆分

- 证据：
  - `lib/network/request_body_codec.dart`
  - `lib/network/net_models.dart`
  - `lib/network/bytes_first_network_client.dart`
  - `README.md:55-61`
- 修复后实现：
  - `NetRequest` 与 `BytesFirstNetworkClient.request(...)` 现在显式区分 `body` 和 `bodyBytes`；两者不可同时设置。
  - `body: <int>[...]` 现在按 JSON int 数组编码为 UTF-8 文本，不再被静默当成原始字节。
  - 原始二进制请求体必须通过 `bodyBytes` 传入。
  - 显式 `bodyBytes` 现在会校验每个元素必须位于 `0..255`；超界值会直接抛出 `NetException(parse)`，不再允许 `Uint8List.fromList(...)` 的静默截断发生。
  - 误把 `Uint8List` / `TypedData` 塞进 `body` 时也会直接失败，并提示调用方改用 `bodyBytes`。
- 验证：
  - 已新增 `test/network/request_body_codec_test.dart`，覆盖：
    - `List<int>` 作为 JSON int 数组编码；
    - `body + bodyBytes` 冲突保护；
    - `Uint8List` 误传 `body` 的保护；
    - `bodyBytes` 越界值保护。
  - 已更新 `test/network/request_body_channel_consistency_test.dart`，补齐：
    - JSON int 数组 body 的 Dio/Rust fallback 一致性；
    - 原始 bytes body 的 Dio/Rust fallback 一致性。
  - 本地验证通过：`flutter analyze`、`flutter test`。
- 结论：
  - 该项 P1 风险已关闭。
  - 剩余事项是 API 迁移成本而不是语义歧义：历史调用若用 `body: Uint8List(...)` 或 `body: <int>[...]` 表示原始字节，需迁移到 `bodyBytes`。

### 3. 已修复（2026-03-09）：resume download 不再 fallback 到 Dio，Dio 默认拒绝断点续传

- 证据：
  - `lib/network/net_models.dart`
  - `lib/network/network_gateway.dart`
  - `lib/network/dio_adapter.dart`
  - `test/network/network_gateway_test.dart`
  - `test/network/dio_adapter_test.dart`
- 修复后实现：
  - 新增 `NetTransferTaskRequest.isResumeDownload`，显式定义“`resumeFrom > 0` 的 download”为 resume download。
  - 网关不再把所有 `download` 都视为可 fallback；只有非 resume download 才允许 Rust 失败后 fallback 到 Dio。
  - `DioAdapter.startTransferTask(...)` 收到 `resumeFrom > 0` 的 download 时会直接抛错，不再把 `resumeFrom` 当作“仅影响进度显示”的弱 hint。
  - Rust not ready 场景下，resume download 也不会再静默退化成 Dio 重头下载，而是显式暴露“不支持 resume”的错误。
- 验证：
  - 已新增网关回归：覆盖“resume download + Rust start 失败时不 fallback 到 Dio”。
  - 已新增 readiness gate 回归：覆盖“Rust not ready + resume download”会显式失败，而不是被动转 Dio。
  - 已新增 `DioAdapter` 回归：直接验证 Dio 默认拒绝 `resumeFrom > 0` 的 download。
  - 本地验证通过：`flutter analyze`、`flutter test`。
- 结论：
  - 该项 P0 风险已关闭。
  - 当前契约已明确：断点续传属于 Rust-only 能力；Dio 默认不承诺 resume 语义。
  - 若未来需要让 Dio 也支持 resume，应单独补齐 `Range`、部分文件 append、临时文件与原子替换语义，而不是恢复“download 一律可 fallback”。

### 4. 高危：Dio 下载失败、取消、非 2xx 时会在最终路径留下脏文件

- 证据：
  - `lib/network/dio_adapter.dart:351-369`
  - `lib/network/dio_adapter.dart:268-279`
  - `lib/network/dio_adapter.dart:293-343`
- 现状：
  - 文件直接下载到 `request.localPath`。
  - 收到非 2xx 时只是事后抛错。
  - 失败、取消、异常路径都没有清理最终文件，也没有临时文件再原子替换。
- 风险：
  - 404/503 响应体、半截文件、取消残片都可能落在业务最终路径上。
  - 后续业务如果只看“文件存在”，就会把坏文件当成功产物继续使用。
- 当前测试缺口：
  - 没有覆盖下载失败后的文件清理语义。
- 建议优先级：P0

### 5. 中高：transfer 事件队列与任务路由状态都可能无界增长

- 证据：
  - `lib/network/dio_adapter.dart:13-14`
  - `lib/network/dio_adapter.dart:239-247`
  - `lib/network/dio_adapter.dart:256-264`
  - `lib/network/dio_adapter.dart:411-412`
  - `lib/network/network_gateway.dart:33`
  - `lib/network/network_gateway.dart:109-116`
  - `lib/network/network_gateway.dart:221-223`
- 现状：
  - Dio transfer 的 progress 事件全部进入 `_transferEvents` 内存列表。
  - 只有业务主动调用 `pollTransferEvents` 才会出队。
  - 网关中的 `_transferTaskChannels` 只在轮询到终态事件时清理。
- 风险：
  - 长时间下载/上传且业务轮询不及时，会导致内存持续增长。
  - 即使任务已经结束，只要终态事件没有被消费，路由状态也会一直滞留。
  - 后续 `cancelTransferTask` 会基于陈旧状态做判断。
- 当前测试缺口：
  - 没有覆盖“不轮询、低频轮询、超长任务”的行为。
- 建议优先级：P1

### 6. 中高：默认 API 让人误以为 Rust 已启用，实际可能长期静默跑在 Dio

- 证据：
  - `lib/network/bytes_first_network_client.dart:122-141`
  - `lib/network/network_gateway.dart:51-58`
  - `lib/network/rust_adapter.dart:344-351`
  - `README.md:42-52`
- 现状：
  - `BytesFirstNetworkClient.standard()` 默认 `enableRustChannel: true`。
  - 但它只是 new 出一个未初始化的 `RustAdapter`。
  - 网关检测到 `isReady == false` 后，会无提示走 Dio。
  - README 的 quick usage 也没有要求先初始化 Rust engine。
- 风险：
  - 调用方会误判自己已经接入 Rust 通道。
  - 线上监控如果没有 routeReason 维度，几乎发现不了“实际一直没走 Rust”。
- 当前测试缺口：
  - 有 readiness gate 测试，但没有针对文档/API 误导性的验收约束。
- 建议优先级：P1

### 7. 中：Rust 错误契约完全依赖字符串前缀，极易漂移

- 证据：
  - `lib/network/rust_adapter.dart:283-290`
  - `lib/network/rust_adapter.dart:354-375`
  - `lib/network/rust_adapter.dart:377-485`
- 现状：
  - Dart 侧通过 `timeout:`、`dns:`、`tls:`、`io:`、`internal:` 等前缀解析错误类型。
  - 未匹配的错误文案大多直接降级为 `internal`，并被禁止 fallback。
- 风险：
  - Rust 侧只要改一下文案，Dart 侧的 fallback 判定、监控分类、异常统计都会静默变化。
  - 这是弱契约，不适合作为稳定跨语言接口。
- 当前测试缺口：
  - 只覆盖了少数字符串样例，没有覆盖版本升级后的兼容性约束。
- 建议优先级：P1

### 8. 中：公开的请求 hint 字段几乎没有实际作用，容易制造错误预期

- 证据：
  - `lib/network/net_models.dart:54-77`
  - `lib/network/routing_policy.dart:14-32`
  - `test/network/routing_policy_test.dart:34-49`
- 现状：
  - `NetRequest` 暴露了 `expectLargeResponse`、`isJitterSensitive`、`contentLengthHint` 等字段。
  - 当前 `RoutingPolicy` 只看 `forceChannel` 和 `enableRustChannel`。
  - 测试还明确确认这些标签不会影响路由。
- 风险：
  - 对外暴露“像是参与调度”的字段，但实际上不会改变决策。
  - 业务很容易写出依赖错觉，后期再改真实路由逻辑时也容易发生行为回归。
- 建议优先级：P2

### 9. 中：Rust 初始化的“already initialized”分支会吞掉配置冲突

- 证据：
  - `lib/network/rust_adapter.dart:82-121`
  - `lib/network/rust_adapter.dart:103-105`
- 现状：
  - 如果 Rust 侧返回 `already initialized`，Dart 直接视为成功。
  - 当前没有校验二次初始化的配置是否与首次一致。
- 风险：
  - 调用方可能以为自己的新配置生效了，实际上被无声忽略。
  - 这类配置漂移问题在 benchmark、灰度环境和多入口初始化场景下尤其难查。
- 建议优先级：P2

## 当前测试盲区

- 下载失败、取消、非 2xx 后的文件残留与清理策略。
- transfer 长时间运行、业务不轮询或低频轮询时的内存边界。
- Rust 初始化重复调用且配置不一致时的行为。

## 建议处理顺序

1. 重做剩余下载语义：临时文件、原子替换、失败清理，避免脏文件落到最终路径。
2. 给 transfer 事件与 task 状态增加上限、过期策略或背压策略。
3. 明确默认初始化模型：是“默认 Rust 真启用”，还是“默认 Dio，仅允许显式初始化后启用 Rust”。
4. 把 Rust 错误从字符串协议升级为结构化错误码。

## 备注

- 本次结论主要基于 `flutter_rust_net/` Dart 侧审查；未同步深入审阅 `../native/rust/net_engine` Rust 实现。
- `flutter analyze` 与 `flutter test` 均通过，但这只能证明当前测试集没有命中上述风险，不能证明这些风险不存在。
