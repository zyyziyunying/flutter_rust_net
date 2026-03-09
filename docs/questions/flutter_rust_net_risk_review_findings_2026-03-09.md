# flutter_rust_net 风险审查记录（2026-03-09）

## 范围

- 审查对象：`flutter_rust_net/` Dart 侧网络层。
- 审查方式：静态阅读核心实现与测试，结合本地验证命令。
- 已执行验证：
  - `flutter analyze`
  - `flutter test`

结论先行：原始 P0（双通道 request body 编码漂移）已关闭，但当前实现距离“语义稳定、可放心上量”还有明显差距。高优先级风险现在主要集中在 `List<int>` body 语义歧义、下载语义不安全、以及 transfer 状态管理缺少边界。

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
  - 新增共享 `encodeRequestBody(...)`，统一规定：`Uint8List` / `List<int>` 发送原始字节，`String` 发送 UTF-8 字节，其它 JSON 可编码对象发送 UTF-8 JSON 字节。
  - `DioAdapter` 与 `RustAdapter` 现在都先走这套归一化逻辑，再发起请求；不再把对象体直接交给 Dio 自行推断。
  - 包本身不再隐式补写或改写 `content-type`；如果服务端依赖 MIME，调用方必须显式设置请求头。
- 验证：
  - 已新增“`Map` body + 未显式 JSON content-type + Rust 失败 fallback 到 Dio”一致性测试，直接比对 Rust `RequestSpec.bodyBytes` 与 Dio 实际出站 body。
  - 已补原始二进制 body 的双通道一致性测试。
  - 本地验证通过：`flutter analyze`、`flutter test`。
- 结论：
  - 该项 P0 风险已关闭。
  - 剩余约束不是“双通道 body 不一致”，而是上层若要发送 `application/x-www-form-urlencoded` 或 multipart，必须自行编码并显式声明 `content-type`。
  - 但基于同一修复路径，已暴露出一个新的独立 P1 风险：`List<int>` 被强制解释为原始字节，见下一项。

### 2. P1：`List<int>` body 语义二义性会让 JSON int 数组被静默当成原始字节

- 证据：
  - `lib/network/request_body_codec.dart:17-18`
  - `lib/network/net_models.dart:54-77`
  - `lib/network/bytes_first_network_client.dart:153-178`
  - `README.md:55-61`
- 现状：
  - 公开 API 仍然把请求体暴露成宽泛的 `Object? body`。
  - 共享编码逻辑里，凡是命中 `body is List<int>`，都会直接走 `Uint8List.fromList(body)`，不再进入 JSON 编码分支。
  - README 也把 `List<int>` 明确定义为“原始字节”。
- 风险：
  - 如果调用方把 `body: [1, 2, 3]` 当成 JSON 数组发送，当前实现会把它发成 3 个裸字节，而不是 UTF-8 文本 `[1,2,3]`。
  - 这不是显式失败，而是静默错发；双通道会一致，但一致地错。
  - Dart `Uint8List.fromList(...)` 还会对越界值做截断。本地补充验证显示：`Uint8List.fromList([1, 2, 256])` 实际得到 `[1, 2, 0]`，`Uint8List.fromList([-1, 0, 1])` 实际得到 `[255, 0, 1]`。如果上层把这类值当 JSON int 数组传入，会直接发生数据损坏。
- 当前测试缺口：
  - 没有覆盖“JSON int 数组 body”与“原始 bytes body”的区分约束。
  - 没有覆盖 `List<int>` 中负值、超过 255 的值、以及调用方误传 JSON 数组时的失败/保护行为。
- 建议优先级：P1

### 3. 高危：download fallback 被视为天然安全，但 Dio 实现并不支持断点续传

- 证据：
  - `lib/network/network_gateway.dart:269-280`
  - `lib/network/dio_adapter.dart:217-219`
  - `lib/network/dio_adapter.dart:346-369`
- 现状：
  - 网关把所有 `download` 都视为可 fallback。
  - `DioAdapter` 虽然接收了 `resumeFrom`，但只把它当作进度初始值。
  - 实际下载时没有设置 `Range` 请求头，也没有 append 到临时文件或部分文件。
- 风险：
  - Rust 侧若支持 resume，fallback 到 Dio 后会静默退化成“从头覆盖重下”。
  - 上层如果依据 `resumeFrom` 或 `expectedTotal` 做体验承诺，现在的实现会直接违约。
- 当前测试缺口：
  - 没有覆盖“resume download + fallback 到 Dio”。
- 建议优先级：P0

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

- `List<int>` body 作为“原始字节”与“JSON int 数组”两种语义时的边界与保护策略。
- `List<int>` 中负值、超过 255 的值是否应显式拒绝，而不是静默截断。
- `download + resumeFrom + fallback` 的真实行为。
- 下载失败、取消、非 2xx 后的文件残留与清理策略。
- transfer 长时间运行、业务不轮询或低频轮询时的内存边界。
- Rust 初始化重复调用且配置不一致时的行为。

## 建议处理顺序

1. 收紧请求 body API：把“原始 bytes”与“JSON 值”拆成不易混淆的建模，至少不要让裸 `List<int>` 同时承担两种潜在语义。
2. 对 `List<int>` 的非法字节值建立显式保护；如果继续支持原始 bytes，至少要拒绝负值与大于 255 的元素，而不是静默截断。
3. 重做下载语义：临时文件、原子替换、失败清理、resume/Range 契约、fallback 限制。
4. 给 transfer 事件与 task 状态增加上限、过期策略或背压策略。
5. 明确默认初始化模型：是“默认 Rust 真启用”，还是“默认 Dio，仅允许显式初始化后启用 Rust”。
6. 把 Rust 错误从字符串协议升级为结构化错误码。

## 备注

- 本次结论主要基于 `flutter_rust_net/` Dart 侧审查；未同步深入审阅 `../native/rust/net_engine` Rust 实现。
- `flutter analyze` 与 `flutter test` 均通过，但这只能证明当前测试集没有命中上述风险，不能证明这些风险不存在。
