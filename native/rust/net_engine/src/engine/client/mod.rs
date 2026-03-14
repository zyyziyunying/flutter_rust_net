//! client 模块入口：按职责拆分请求、传输、通用工具与生命周期逻辑。

use std::collections::HashMap;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use reqwest::Client;
use tokio::sync::{Mutex, OwnedSemaphorePermit, Semaphore};
use tokio_util::sync::CancellationToken;

use crate::api::NetEngineConfig;
use crate::engine::cache::{
    normalize_namespace, DiskCache, DEFAULT_CACHE_MAX_NAMESPACE_BYTES, DEFAULT_CACHE_TTL_SECONDS,
    RESPONSE_CACHE_NAMESPACE,
};
use crate::engine::error::NetError;
use crate::engine::events::EventBus;
use crate::engine::scheduler::Scheduler;

mod common; // 共享工具函数（header、取消、文件操作）
mod lifecycle; // 生命周期与状态管理接口
mod request; // 普通请求与缓存逻辑
mod transfer; // 传输任务（下载/续传）逻辑

#[cfg(test)]
mod tests;

/// 核心引擎：持有 HTTP 客户端、调度器、事件总线
pub struct NetEngine {
    config: NetEngineConfig,
    client: Client,
    event_bus: EventBus,
    scheduler: Scheduler,
    connection_limiter: ConnectionLimiter,
    cancel_tokens: Arc<Mutex<HashMap<String, CancellationToken>>>,
    disk_cache: Option<DiskCache>,
    response_cache_namespace: String,
    is_busy: AtomicBool,
}

#[derive(Clone)]
struct ConnectionLimiter {
    global: Arc<Semaphore>,
    per_host_limit: usize,
    per_host: Arc<Mutex<HashMap<String, Arc<Semaphore>>>>,
}

struct ConnectionPermit {
    _global: OwnedSemaphorePermit,
    _per_host: OwnedSemaphorePermit,
}

enum ResponseBodyStorage {
    Inline(Vec<u8>), // 内存返回
    File(String),    // 落盘返回
}

#[derive(Clone, Copy, Debug)]
enum TransferWriteMode {
    Overwrite,   // 全量覆盖写
    Resume(u64), // 从偏移续写
}

struct TransferOutcome {
    transferred: u64,
    status_code: u16,
}

impl NetEngine {
    pub fn new(config: NetEngineConfig) -> anyhow::Result<Self> {
        // 统一在这里创建 HTTP client，避免分散配置。
        let client = Client::builder()
            .connect_timeout(std::time::Duration::from_millis(
                config.connect_timeout_ms as u64,
            ))
            .read_timeout(std::time::Duration::from_millis(
                config.read_timeout_ms as u64,
            ))
            .pool_max_idle_per_host(config.max_connections_per_host as usize)
            .user_agent(&config.user_agent)
            .build()?;

        let scheduler = Scheduler::new(config.max_in_flight_tasks); // 控制并发
        let connection_limiter =
            ConnectionLimiter::new(config.max_connections, config.max_connections_per_host);
        let cache_enabled = !config.cache_dir.trim().is_empty();
        let (disk_cache, response_cache_namespace) = if cache_enabled {
            let response_cache_namespace = normalize_namespace(&config.cache_response_namespace)?;
            let cache_default_ttl_seconds = if config.cache_default_ttl_seconds == 0 {
                DEFAULT_CACHE_TTL_SECONDS
            } else {
                config.cache_default_ttl_seconds as u64
            };
            let cache_max_namespace_bytes = if config.cache_max_namespace_bytes == 0 {
                DEFAULT_CACHE_MAX_NAMESPACE_BYTES
            } else {
                config.cache_max_namespace_bytes as u64
            };
            (
                Some(DiskCache::new_with_policy(
                    &config.cache_dir,
                    std::time::Duration::from_secs(cache_default_ttl_seconds),
                    cache_max_namespace_bytes,
                )?),
                response_cache_namespace,
            )
        } else {
            (None, RESPONSE_CACHE_NAMESPACE.to_owned())
        };

        Ok(Self {
            config,
            client,
            event_bus: EventBus::new(),
            scheduler,
            connection_limiter,
            cancel_tokens: Arc::new(Mutex::new(HashMap::new())),
            disk_cache,
            response_cache_namespace,
            is_busy: AtomicBool::new(false),
        })
    }

    async fn acquire_connection_permit(&self, url: &str) -> Result<ConnectionPermit, NetError> {
        self.connection_limiter.acquire_for_url(url).await
    }

    fn write_timeout_duration(write_timeout_ms: u32) -> Option<std::time::Duration> {
        if write_timeout_ms == 0 {
            None
        } else {
            Some(std::time::Duration::from_millis(write_timeout_ms as u64))
        }
    }
}

impl ConnectionLimiter {
    fn new(max_connections: u16, max_connections_per_host: u16) -> Self {
        let global_limit = usize::from(max_connections.max(1));
        let per_host_limit = usize::from(max_connections_per_host.max(1));
        Self {
            global: Arc::new(Semaphore::new(global_limit)),
            per_host_limit,
            per_host: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    async fn acquire_for_url(&self, url: &str) -> Result<ConnectionPermit, NetError> {
        let host_key = Self::host_key(url)?;
        let global =
            self.global.clone().acquire_owned().await.map_err(|e| {
                NetError::Internal(format!("global connection limiter closed: {e}"))
            })?;

        let per_host_semaphore = self.get_or_create_host_semaphore(&host_key).await;
        let per_host = per_host_semaphore.acquire_owned().await.map_err(|e| {
            NetError::Internal(format!(
                "per-host connection limiter closed for `{host_key}`: {e}"
            ))
        })?;

        Ok(ConnectionPermit {
            _global: global,
            _per_host: per_host,
        })
    }

    async fn get_or_create_host_semaphore(&self, host_key: &str) -> Arc<Semaphore> {
        let mut per_host = self.per_host.lock().await;
        per_host
            .entry(host_key.to_owned())
            .or_insert_with(|| Arc::new(Semaphore::new(self.per_host_limit)))
            .clone()
    }

    fn host_key(url: &str) -> Result<String, NetError> {
        let parsed = reqwest::Url::parse(url)
            .map_err(|e| NetError::Parse(format!("invalid url `{url}`: {e}")))?;
        let host = parsed
            .host_str()
            .ok_or_else(|| NetError::Parse(format!("url `{url}` missing host")))?;
        let port = parsed
            .port_or_known_default()
            .ok_or_else(|| NetError::Parse(format!("url `{url}` missing known port")))?;
        Ok(format!(
            "{}://{}:{port}",
            parsed.scheme(),
            host.to_ascii_lowercase()
        ))
    }
}
