# Net Engine - TODO / 待修复点

> 记录时间：2026-02-15  
> 范围：`native/rust/net_engine`

- [x] **请求 header 校验/容错**：已改为显式校验 header name/value，非法输入返回 `NetError::Parse`。  
  位置：`native/rust/net_engine/src/engine/client.rs:289`

- [x] **cancel token 清理**：任务结束和 `cancel()` 现在都会移除 token，避免 map 长期增长。  
  位置：`native/rust/net_engine/src/engine/client.rs:317`、`native/rust/net_engine/src/engine/client.rs:580`

- [x] **断点续传写文件策略**：已实现覆盖写/续传分流，续传校验 `206 + Content-Range`，失败时回退全量下载。
  - 非 resume：`truncate(true)` 覆盖写；
  - resume：打开后 `seek` 到 offset，校验 206/Content-Range，不符合则回退为全量下载。
  位置：`native/rust/net_engine/src/engine/client.rs:398`、`native/rust/net_engine/src/engine/client.rs:546`

- [x] **大响应内存占用**：`request()` 已改为 `bytes_stream()`，支持阈值/显式大响应落盘与流式写入。  
  位置：`native/rust/net_engine/src/engine/client.rs:177`、`native/rust/net_engine/src/engine/client.rs:215`

- [x] **事件总线无界增长**：已改为固定容量 ring buffer，满时丢弃最旧事件（drop oldest）。  
  位置：`native/rust/net_engine/src/engine/events.rs:22`
