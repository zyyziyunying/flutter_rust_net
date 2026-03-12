# flutter_rust_net 风险审查记录（2026-03-09）

## 范围

- 审查对象：`flutter_rust_net/` Dart 侧网络层。
- 审查方式：静态阅读核心实现与测试，结合本地验证命令。
- 已执行验证：
  - `flutter analyze`
  - `flutter test`

结论先行：截至 2026-03-12，本次审查里原始八项已识别问题中，大部分已经闭环，包括：原始 P0（双通道 request body 编码漂移）、后续暴露的 P1（`List<int>` body 语义歧义）、下载 fallback 静默破坏断点续传契约的问题、Dio 下载脏文件污染最终路径的问题、“默认 API 让人误以为 Rust 已启用”的误导性接入路径、Rust 错误分类完全依赖字符串前缀的问题、公开 request hint 字段制造错误预期的问题，以及 Rust 初始化 `already initialized` 分支吞掉配置冲突的问题。当前剩余优先处理项不只一项：除了 transfer 状态管理缺少边界外，Rust 初始化状态还缺少 shutdown/reset 生命周期清理，且默认 `FrbRustBridgeApi` 共享作用域路径仍缺少直接回归测试。

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

### 4. 已修复（2026-03-09）：Dio 下载改为临时文件落盘，失败/取消/非 2xx 不再污染最终路径

- 修复证据：
  - `lib/network/dio_adapter.dart:231-376`
  - `lib/network/dio_adapter.dart:379-442`
  - `test/network/dio_adapter_test.dart:48-213`
- 修复后实现：
  - `DioAdapter` 现在会先为 download 准备同目录 `.part` 临时文件，再把 `downloadUri(...)` 的落盘目标切到该临时文件。
  - 只有收到 2xx 且后续发布成功时，才会通过 rename/替换把临时文件发布到 `request.localPath`。
  - 非 2xx、取消、`DioException`、`NetException` 与兜底异常路径都会执行临时文件清理，不再把错误响应体或半截文件留在最终路径。
  - 已存在的最终文件会在下载成功前保持不变，避免业务仅凭“文件存在”误判下载成功。
- 验证：
  - 已新增 `DioAdapter` 回归：覆盖“成功下载后替换目标文件”。
  - 已新增 `DioAdapter` 回归：覆盖“非 2xx 下载失败时保留旧文件并清理临时文件”。
  - 已新增 `DioAdapter` 回归：覆盖“取消下载时保留旧文件并清理临时文件”。
  - 本地验证通过：`flutter analyze`、`flutter test`。
- 结论：
  - 该项 P0 风险已关闭。
  - 当前 Dio download 契约已明确为“临时文件写入 + 成功后发布”，不会再把失败产物直接暴露给业务最终路径。
  - 若未来补 resume 语义，需要在此基础上继续设计分片 append、校验与原子发布，而不是回退到直接覆盖最终文件。

### 5. 中高：transfer 事件队列与任务路由状态都可能无界增长

- 证据：
  - `lib/network/dio_adapter.dart:16-17`
  - `lib/network/dio_adapter.dart:240-247`
  - `lib/network/dio_adapter.dart:266-273`
  - `lib/network/dio_adapter.dart:483-484`
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

### 6. 已修复（2026-03-09）：默认 API 不再暗示 Rust 已启用，Rust 接入改为显式 opt-in

- 修复证据：
  - `lib/network/bytes_first_network_client.dart:122-173`
  - `test/network/bytes_first_network_client_test.dart:16-80`
  - `README.md:42-73`
- 修复后实现：
  - `BytesFirstNetworkClient.standard()` 现在默认 `enableRustChannel: false`，安全默认值明确落在 Dio。
  - 若调用方显式设置 `enableRustChannel: true`，但传入的 `RustAdapter` 尚未 ready，`standard()` 会直接抛出 `StateError`，不再允许“表面启用 Rust、实际静默跑 Dio”的配置继续运行。
  - 新增 `BytesFirstNetworkClient.standardWithRust()` 显式入口；该入口会先执行 `rustAdapter.initializeEngine(...)`，随后再构造启用 Rust 的 client。
  - README quick usage 已拆分为“安全默认 Dio”与“显式启用 Rust”两条路径，不再把未初始化的 RustAdapter 包装成默认示例。
- 验证：
  - 已新增默认工厂回归：验证 `standard()` 默认保持 `enableRustChannel == false`。
  - 已新增误用保护回归：验证“显式启用 Rust + 未初始化 adapter”会直接失败。
  - 已新增显式 Rust 路径回归：验证 `standardWithRust()` 会先初始化 `RustAdapter` 再返回 client。
  - 本地验证通过：`flutter analyze`、`flutter test`。
- 结论：
  - 该项 P1 风险已关闭。
  - `NetworkGateway` 的 readiness gate 仍然保留，用于处理显式 Rust 路径下的运行时状态；但默认公开 API 与文档入口已不再误导调用方。

### 7. 已修复（2026-03-09）：Rust 错误契约改为显式 typed kind，Dart 不再依赖字符串前缀

- 修复证据：
  - `native/rust/net_engine/src/api.rs`
  - `native/rust/net_engine/src/engine/error.rs`
  - `native/rust/net_engine/src/engine/client/request.rs`
  - `lib/network/rust_adapter.dart`
  - `test/network/rust_adapter_test.dart`
- 修复后实现：
  - Rust `ResponseMeta` 新增 `error_kind`，由 `NetError.kind()` 显式填充；人类可读错误文案仍通过 `error` 传回，但不再承担分类职责。
  - HTTP 错误现在会把真实 `status_code` 一并带回 Dart；Dart 侧基于 typed kind 和状态码构造 `NetException`，不再依赖 `http 404:` 这类字符串格式。
  - `RustAdapter` 仍保留旧字符串前缀解析作为兼容回退，用于处理旧 mock 或不完整桥接环境；正式桥接契约已切换到 typed kind。
- 验证：
  - 已新增 Rust 单测：验证 `NetError.kind()` 对 timeout 与 HTTP 家族的映射稳定。
  - 已新增 Dart 回归：验证 typed timeout、typed HTTP 4xx、typed internal 映射，以及 legacy 字符串前缀兼容路径。
  - 本地验证通过：`flutter analyze`、`flutter test`、`cargo test -q`。
- 结论：
  - 该项 P1 风险已关闭。
  - 现有残余兼容逻辑只作为过渡保护；后续若 bridge 已全面升级，可再评估是否移除 legacy 字符串分支。

### 8. 已修复（2026-03-11）：公开的请求 hint 字段几乎没有实际作用，容易制造错误预期

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

### 9. 已修复（2026-03-11）：Rust 重复初始化/并发初始化已补齐配置一致性校验

- 修复证据：
  - `lib/network/rust_adapter.dart:72-115`
  - `lib/network/rust_adapter.dart:610-680`
  - `test/network/rust_adapter_test.dart:324-449`
- 修复后实现：
  - `RustAdapter.initializeEngine(...)` 现在会先把 `RustEngineInitOptions` 归一化成有效的 `NetEngineConfig`，再进入初始化流程。
  - 首次初始化成功后，Dart 会按 bridge scope 记录已知首配；`FrbRustBridgeApi` 走进程级共享作用域，自定义 bridge 按实例隔离，避免测试或注入场景互相污染。
  - 同一个 `RustAdapter` 已初始化后再次调用 `initializeEngine(...)` 时，会先比较请求配置与已知首配；一致则直接返回，不一致会抛 `NetException.infrastructure`，并在 message 中列出发生漂移的字段。
  - 同 scope 下若已有 in-flight 初始化，后续相同配置会复用同一个初始化 future；冲突配置会在 Dart 侧直接失败，不再发起第二次 `initNetEngine(...)`。
  - 如果 bridge 返回 `already initialized`，Dart 也不再无条件吞掉：已知首配场景会直接比对已知配置；首配未知场景会记录“第一份被接受的请求配置”作为兼容基线，后续只有同配置才能继续通过，冲突配置会显式报错。
- 验证：
  - 已新增 Dart 回归，覆盖：
    - 同配置重复初始化可重入；
    - 同 adapter 重复初始化但配置冲突会直接失败；
    - 同 scope 并发初始化时，相同配置会共享同一次初始化；
    - 同 scope 并发初始化时，冲突配置会在第二次 init 发生前直接失败；
    - 共享 bridge 命中 `already initialized` 时，一致配置允许通过、冲突配置显式报错；
    - 首配未知时，会保留兼容入口，但会锁定第一份被接受的请求配置；后续同配置允许通过、冲突配置显式报错。
  - 本地验证通过：`flutter analyze`、`flutter test`。
- 结论：
  - 该项 P2 风险已关闭。
  - 当前包内通过 `RustAdapter` 管理初始化的接入路径，已不会再在 Dart 侧静默接受后续配置漂移。
  - 残余边界是：若 Rust engine 在包外已被预先初始化，Dart 当前仍拿不到真实首配，只能把“第一份被接受的请求配置”当作兼容基线；若要彻底封死该场景，需要 Rust 侧进一步暴露当前生效配置或配置指纹。

### 10. 中：Rust 初始化状态缺少 shutdown/reset 生命周期清理

- 证据：
  - `lib/network/rust_adapter.dart:64-81`
  - `lib/network/rust_adapter/rust_adapter_init.dart:5-7`
  - `lib/network/rust_adapter/rust_adapter_init.dart:92-99`
  - `lib/network/rust_adapter/rust_adapter_init.dart:267-280`
  - `lib/rust_bridge/api.dart:33-34`
- 现状：
  - `_RustAdapterInitTracker` 会按 bridge scope 缓存 `knownConfig` / `acceptedConfigWhenActualUnknown`，但没有正式 reset 路径。
  - `RustAdapter` 自身只保留 `_initialized` 本地状态；请求与再次初始化时都会参考这份本地状态。
  - 底层 FRB 仍暴露 `shutdownNetEngine()`，但 `RustBridgeApi`/`RustAdapter` 没有配套的 shutdown 生命周期管理。
- 风险：
  - 如果宿主绕过 `RustAdapter` 直接 shutdown，旧 adapter 可能继续把自己当作 ready。
  - 外部 shutdown 后继续复用同一个 adapter 时，Dart 侧可能仍受旧 `_initialized` / `knownConfig` 影响，出现“引擎已重置但本地状态未清”的脏状态。
  - 额外本地 probe 表明：shutdown 后新建新的 adapter 当前可以重新 init；因此风险边界主要落在“旧 adapter 复用”与“缺少受控 reset”，不是“所有 restart 都会失败”。
- 建议优先级：P2

### 11. 中：默认 `FrbRustBridgeApi` 共享作用域路径仍缺少直接回归

- 证据：
  - `lib/network/rust_adapter.dart:51-57`
  - `lib/network/rust_adapter/rust_adapter_init.dart:278-279`
  - `test/network/rust_adapter_test.dart:371-466`
  - `test/network/rust_adapter_test.dart:533-623`
- 现状：
  - 生产默认路径下，每个 `RustAdapter()` 都会创建新的 `FrbRustBridgeApi()`。
  - 真正的共享初始化语义依赖 `bridgeApi is FrbRustBridgeApi ? _sharedBridgeConfigScope : bridgeApi` 这条特殊分支。
  - 现有新增测试主要覆盖“多个 adapter 共用同一个 fake bridge 实例”，没有直接锁住“不同 FRB bridge 实例但共享同一默认 scope”的生产路径。
- 风险：
  - 这类测试即使持续为绿，也不足以证明默认生产路径没有被后续重构悄悄破坏。
  - 当前额外本地 probe 未发现实现 bug，但缺少正式回归意味着这一行为仍可能在后续改动中退化。
- 建议优先级：P3

## 当前测试盲区

- transfer 长时间运行、业务不轮询或低频轮询时的内存边界。
- Rust shutdown/reset 与长生命周期 adapter 复用的生命周期边界。
- 默认 `FrbRustBridgeApi` 共享作用域路径缺少直接回归。
- Rust typed error 已落地后，legacy 字符串兼容分支在版本升级后的保留策略。
- 若 Rust engine 被包外路径预先初始化，Dart 侧缺少读取当前生效配置的桥接能力。

## 建议处理顺序

1. 给 transfer 事件与 task 状态增加上限、过期策略或背压策略。
2. 为 Rust 初始化补一个受控 shutdown/reset 路径，或明确声明不支持 runtime restart。
3. 把默认 `FrbRustBridgeApi` 共享作用域路径与 shutdown/restart 场景纳入正式回归。
4. 在 bridge 全量升级后，评估是否收敛或移除 Dart 侧 legacy 错误字符串兼容分支。
5. 若要覆盖包外预初始化场景，在 Rust bridge 暴露当前生效 `NetEngineConfig` 或配置指纹。

## 备注

- 本次结论主要基于 `flutter_rust_net/` Dart 侧审查；未同步深入审阅 `../native/rust/net_engine` Rust 实现。
- `flutter analyze` 与 `flutter test` 均通过，但这只能证明当前测试集没有命中上述风险，不能证明这些风险不存在。
