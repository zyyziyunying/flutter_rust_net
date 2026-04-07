# flutter_rust_net namespace 预算治理方案（2026-03-14）

## 目标

在不打乱当前缓存契约的前提下，明确 `cacheMaxNamespaceBytes` 的现状边界、后续治理优先级，以及何时才值得继续扩展为显式分区策略。

## 实施补记（2026-03-16）

1. 阶段 B 的最小实现已落地：
   - Dart `RustEngineInitOptions` / Rust `NetEngineConfig` 新增可选 `cacheRootMaxBytes`
   - `_RustAdapterInitTracker` 已把该字段纳入共享初始化一致性比较
   - `DiskCache` 已按 cache root 实际文件占用执行 root-level prune：计入 body + metadata，并在扫描时清理 root 内残留文件
   - `NetEngine` 初始化 cache 时会先执行一次 root prune，已有超限目录不会等到后续写路径才收敛
   - root budget 关键路径现已串行化，避免 `prune_root()` 与缓存自身 `*.tmp` 写入交错时误删临时文件
   - 启用 root budget 时，`cache_dir` 的“独占专用目录”要求现已升级为显式契约
2. 当前剩余重点不再是“要不要做 root budget”，而是：
   - 在 benchmark / 真机归档里实际使用已接好的 root budget 口径与占用观测
   - 继续评估是否真的需要阶段 C 的显式分区策略

## 当前现状（基于现有代码与回归）

1. Rust `DiskCache` 当前同时维护 `max_namespace_bytes` 与可选 `max_root_bytes`：前者是“每个 namespace 独立上限”，后者仅在启用时才作为 cache root 总上限。
2. Rust 请求缓存默认 namespace 已外置为初始化配置 `cache_response_namespace`；Dart 对应入口是 `RustEngineInitOptions.cacheResponseNamespace`。
3. 同一 Rust engine scope 下，Dart 共享初始化会拒绝 `cacheResponseNamespace`、`cacheMaxNamespaceBytes` 与 `cacheRootMaxBytes` 配置漂移，避免静默沿用旧预算。
4. Rust 回归已确认：不同 namespace 会各自执行 LRU 淘汰，不会跨 namespace 互相驱逐。
5. 这也意味着：若同一 `cache_dir` 下累计存在多个 namespace，cache root 总占用可以高于单个 `cacheMaxNamespaceBytes`。

## 现在不建议直接扩接口的原因

1. 当前主链路一次只绑定一个响应缓存 namespace；现有产品代码还没有“多 namespace 同时活跃并需要统一预算仲裁”的明确契约。
2. 若现在直接引入“按 namespace 配权重 / 配独立上限”的复杂策略，会同时扩大 Dart 配置面、FRB bridge 面和共享初始化漂移比较面，收益不确定。
3. `clear_cache(namespace)`、namespace 隔离和 on-disk 目录语义刚完成一轮收口；此时再放宽成分层或复杂分区，风险高于收益。

## 推荐路线

### 阶段 A：维持现状并补齐文档口径

阶段 A 的基线契约仍然是“每 namespace 独立上限”：

1. 默认行为保持不变：
   - `cacheMaxNamespaceBytes` 继续表示单 namespace 上限。
   - `cacheResponseNamespace` 继续表示请求缓存落盘分区。
2. 当同一 cache root 下出现多个 namespace 时：
   - 允许总占用超过单 namespace 上限。
   - 不承诺跨 namespace 全局淘汰。
3. 阶段 A 不新增 bridge 字段，不修改磁盘格式，不重定义 `clear_cache` 语义。

结论：即使已补 root budget，基线仍先稳定“平面 namespace + 独立 budget”契约，不立即引入显式分区策略。

### 阶段 B：若出现磁盘总量治理诉求，优先加 root budget，而不是先加分区表

本轮已经按最小范围直接进入代码实现阶段；当初建议进入阶段 B 的触发信号仍然成立：

1. 同一 `cache_dir` 下长期保留多个 namespace，导致总磁盘占用不可接受。
2. 真机归档或 benchmark 复盘中，明确发现“单 namespace 预算健康，但 root 总占用失控”。
3. 产品需要在 tenant 切换后保留旧 namespace 一段时间，但又要求总量受控。

这时优先推荐的新增能力是：

1. 新增可选 `cacheRootMaxBytes`，表示整个 cache root 的总预算上限。
2. 保持 `cacheMaxNamespaceBytes` 语义不变，继续作为单 namespace 上限。
3. root budget 触发时，按跨 namespace 的最近访问时间做全局淘汰；单 namespace budget 触发时，仍在 namespace 内部淘汰。
4. 一旦启用 root budget，`cache_dir` 必须是当前组件独占的专用目录；不要把共享目录、业务混合目录或其他组件的落盘目录直接作为 cache root。

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

## 建议的后续顺序

在当前实现基础上，建议按下面顺序推进：

1. 先跑观测归档：
   - benchmark 已支持记录 `cache_dir`、`cacheResponseNamespace`、`cacheMaxNamespaceBytes`
   - root budget 启用时，归档里同步记录 `cacheRootMaxBytes` 与 root 总占用观测
2. 最后才考虑显式分区策略对象：
   - 只在阶段 B 不能满足需求时再做

## 验收标准

### 仅阶段 A（未启用 root budget 时的基线）

1. 文档明确写清：`cacheMaxNamespaceBytes` 是“每 namespace 独立上限”，不是 root 总预算。
2. `p2_status` 的 In Progress / Next 不再把“预算治理方案未成型”作为模糊项。

### 若进入阶段 B

1. root budget 打开后，跨 namespace 总占用不会长期高于 `cacheRootMaxBytes`。
2. 单 namespace 预算仍保持独立生效，不会被 root budget 替代。
3. Rust / Dart 回归覆盖：
   - root budget 触发的跨 namespace 淘汰
   - root budget 对 metadata / 残留文件的实际占用计量
   - 初始化阶段对已有超限目录的收敛
   - root prune 与缓存内部临时文件写入的并发竞争保护
   - 共享初始化配置漂移拒绝
   - 缓存关闭路径不受影响
4. 文档明确写清：启用 `cacheRootMaxBytes` 时，`cache_dir` 是独占目录契约，不支持与其他数据共用同一根目录。

## 当前结论

1. `cacheRootMaxBytes` 已按“cache root 实际文件总占用”口径收口，可作为 root 总预算治理入口。
2. `cacheMaxNamespaceBytes` 仍是“每 namespace 独立上限”的正式契约，没有被 root budget 替代。
3. 启用 root budget 时，`cache_dir` 需视为当前组件独占的专用目录；这是当前实现和文档共同生效的正式契约。
4. 当前仍不建议直接进入显式分区策略；只有阶段 B 明显不够用时，再考虑复杂分区表。
