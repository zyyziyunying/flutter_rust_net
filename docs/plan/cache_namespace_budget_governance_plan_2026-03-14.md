# flutter_rust_net namespace 预算治理方案（2026-03-14）

## 目标

在不打乱当前缓存契约的前提下，明确 `cacheMaxNamespaceBytes` 的现状边界、后续治理优先级，以及何时才值得继续扩展为显式分区策略。

## 当前现状（基于现有代码与回归）

1. Rust `DiskCache` 当前只有一个 `max_namespace_bytes` 配置，作用域是“每个 namespace 独立上限”，不是 cache root 总上限。
2. Rust 请求缓存默认 namespace 已外置为初始化配置 `cache_response_namespace`；Dart 对应入口是 `RustEngineInitOptions.cacheResponseNamespace`。
3. 同一 Rust engine scope 下，Dart 共享初始化会拒绝 `cacheResponseNamespace` 与 `cacheMaxNamespaceBytes` 配置漂移，避免静默沿用旧预算。
4. Rust 回归已确认：不同 namespace 会各自执行 LRU 淘汰，不会跨 namespace 互相驱逐。
5. 这也意味着：若同一 `cache_dir` 下累计存在多个 namespace，cache root 总占用可以高于单个 `cacheMaxNamespaceBytes`。

## 现在不建议直接扩接口的原因

1. 当前主链路一次只绑定一个响应缓存 namespace；现有产品代码还没有“多 namespace 同时活跃并需要统一预算仲裁”的明确契约。
2. 若现在直接引入“按 namespace 配权重 / 配独立上限”的复杂策略，会同时扩大 Dart 配置面、FRB bridge 面和共享初始化漂移比较面，收益不确定。
3. `clear_cache(namespace)`、namespace 隔离和 on-disk 目录语义刚完成一轮收口；此时再放宽成分层或复杂分区，风险高于收益。

## 推荐路线

### 阶段 A：维持现状并补齐文档口径

当前建议把“每 namespace 独立上限”明确视为已生效的正式契约：

1. 默认行为保持不变：
   - `cacheMaxNamespaceBytes` 继续表示单 namespace 上限。
   - `cacheResponseNamespace` 继续表示请求缓存落盘分区。
2. 当同一 cache root 下出现多个 namespace 时：
   - 允许总占用超过单 namespace 上限。
   - 不承诺跨 namespace 全局淘汰。
3. 阶段 A 不新增 bridge 字段，不修改磁盘格式，不重定义 `clear_cache` 语义。

结论：当前阶段先稳定“平面 namespace + 独立 budget”契约，不立即引入显式分区策略。

### 阶段 B：若出现磁盘总量治理诉求，优先加 root budget，而不是先加分区表

若后续出现以下任一信号，再进入代码实现阶段：

1. 同一 `cache_dir` 下长期保留多个 namespace，导致总磁盘占用不可接受。
2. 真机归档或 benchmark 复盘中，明确发现“单 namespace 预算健康，但 root 总占用失控”。
3. 产品需要在 tenant 切换后保留旧 namespace 一段时间，但又要求总量受控。

这时优先推荐的新增能力是：

1. 新增可选 `cacheRootMaxBytes`，表示整个 cache root 的总预算上限。
2. 保持 `cacheMaxNamespaceBytes` 语义不变，继续作为单 namespace 上限。
3. root budget 触发时，按跨 namespace 的最近访问时间做全局淘汰；单 namespace budget 触发时，仍在 namespace 内部淘汰。

这样做的原因：

1. 它直接解决“总盘占用失控”问题。
2. 它是对现有模型的加法，不会推翻 namespace 独立隔离语义。
3. 它比“分区权重表 / 每 namespace 显式配额”更容易通过 FRB 和共享初始化比较落地。

### 阶段 C：只有在产品明确需要多档缓存配额时，才考虑显式分区策略

只有出现下面的明确业务要求，才建议继续扩展为显式分区策略：

1. 不同业务 tenant 需要不同缓存上限，且必须长期共存于同一 cache root。
2. 需要表达“某些 namespace 必须保底、某些 namespace 只能吃剩余额度”。
3. 需要把缓存治理从“技术实现细节”升级为公开产品配置能力。

若进入阶段 C，推荐把策略定义为新增配置对象，而不是继续堆平铺字段：

1. 例如 `CacheBudgetPolicy`：
   - `perNamespaceBytes`
   - `rootMaxBytes`
   - 预留 `pinnedNamespaces` / `tieredNamespaces`
2. 但阶段 C 必须同步重审以下契约：
   - `clear_cache(namespace)` 是否仍维持平面 namespace 语义
   - 共享初始化配置漂移怎么判定
   - benchmark / 真机归档需要新增哪些预算指标

## 建议的后续实现顺序

若要继续做代码实现，建议按下面顺序推进：

1. 先补观测口径：
   - benchmark 或真机归档中记录 `cache_dir`、`cacheResponseNamespace`、`cacheMaxNamespaceBytes`
   - 若进入阶段 B，再补 root 总占用观测
2. 再做最小代码扩展：
   - Rust `NetEngineConfig` / Dart `RustEngineInitOptions` 增加可选 `cacheRootMaxBytes`
   - `_RustAdapterInitTracker` 把该字段纳入共享初始化一致性比较
   - `DiskCache` 增加 root-level prune 路径
3. 最后才考虑显式分区策略对象：
   - 只在阶段 B 不能满足需求时再做

## 验收标准

### 仅阶段 A（当前建议）

1. 文档明确写清：`cacheMaxNamespaceBytes` 是“每 namespace 独立上限”，不是 root 总预算。
2. `p2_status` 的 In Progress / Next 不再把“预算治理方案未成型”作为模糊项。

### 若进入阶段 B

1. root budget 打开后，跨 namespace 总占用不会长期高于 `cacheRootMaxBytes`。
2. 单 namespace 预算仍保持独立生效，不会被 root budget 替代。
3. Rust / Dart 回归覆盖：
   - root budget 触发的跨 namespace 淘汰
   - 共享初始化配置漂移拒绝
   - 缓存关闭路径不受影响

## 当前结论

1. 当前不建议立即实现显式分区策略。
2. 当前推荐先把“每 namespace 独立上限”作为正式契约固定下来。
3. 若后续要继续治理磁盘总量，优先新增 `cacheRootMaxBytes`，不要直接跳到复杂分区表。
