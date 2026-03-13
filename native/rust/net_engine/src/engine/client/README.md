# client 模块说明

`engine/client` 负责 `NetEngine` 的核心请求与传输能力，当前按职责拆分成多个子模块，减少单文件复杂度。

## 文件划分

- `mod.rs`：模块入口、`NetEngine` 结构体与初始化构造。
- `common.rs`：公共工具方法（header 处理、可取消发送、文件目录准备、token 清理）。
- `request.rs`：普通请求链路（组装请求、缓存命中/回源、响应体内存/文件切换、缓存写回）。
- `transfer.rs`：传输任务链路（异步任务、续传协商、进度事件、文件写入）。
- `lifecycle.rs`：引擎生命周期接口（事件拉取、取消、busy 状态、清缓存、shutdown）。
- `tests.rs`：该模块的单元测试。

## 主要流程（Mermaid）

### request 链路

```mermaid
flowchart TD
    A[request] --> B[调度器获取 permit]
    B --> C[注册 cancel token]
    C --> D[构建 URL/Method/Header/Body]
    D --> E{GET 且启用缓存?}
    E -- 否 --> I[发送请求]
    E -- 是 --> F[lookup 缓存]
    F --> G{缓存新鲜?}
    G -- 是 --> H[直接返回缓存响应]
    G -- 否 --> I[条件请求或普通请求]
    I --> J[读取响应体]
    J --> K{超过阈值/指定文件?}
    K -- 是 --> L[落盘返回]
    K -- 否 --> M[内存返回]
    L --> N[可写回缓存]
    M --> N
    N --> O[清理 cancel token]
```

### transfer 链路

```mermaid
flowchart TD
    A[start_transfer_task] --> B[注册 token 并发 Queued]
    B --> C[后台任务拿 permit]
    C --> D[发 Started]
    D --> E{可续传?}
    E -- 是 --> F[带 Range 发请求并校验]
    E -- 否 --> G[全量请求]
    F --> H{校验通过?}
    H -- 是 --> I[Resume 写入]
    H -- 否 --> G
    G --> J[Overwrite 写入]
    I --> K[流式写文件并发 Progress]
    J --> K
    K --> L{完成/失败/取消}
    L --> M[发 Completed/Failed/Canceled]
    M --> N[清理 token]
```

## 维护约定

- 通用逻辑优先放 `common.rs`，避免 request/transfer 重复实现。
- request 与 transfer 尽量只做各自编排，不互相耦合内部细节。
- 新增测试优先加在 `tests.rs`，保持行为覆盖。
