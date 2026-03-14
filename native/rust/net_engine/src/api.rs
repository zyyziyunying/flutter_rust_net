use serde::{Deserialize, Serialize};

use crate::engine::cache::RESPONSE_CACHE_NAMESPACE;

// ── 配置 ──

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct NetEngineConfig {
    pub base_url: String,
    pub connect_timeout_ms: u32,
    pub read_timeout_ms: u32,
    pub write_timeout_ms: u32,
    pub max_connections: u16,
    pub max_connections_per_host: u16,
    pub max_in_flight_tasks: u16,
    pub large_body_threshold_kb: u32,
    pub cache_dir: String,
    pub cache_response_namespace: String,
    pub cache_default_ttl_seconds: u32,
    pub cache_max_namespace_bytes: u32,
    pub user_agent: String,
}

impl Default for NetEngineConfig {
    fn default() -> Self {
        Self {
            base_url: String::new(),
            connect_timeout_ms: 10_000,
            read_timeout_ms: 30_000,
            write_timeout_ms: 30_000,
            max_connections: 100,
            max_connections_per_host: 6,
            max_in_flight_tasks: 32,
            large_body_threshold_kb: 256,
            cache_dir: String::new(),
            cache_response_namespace: RESPONSE_CACHE_NAMESPACE.into(),
            cache_default_ttl_seconds: 300,
            cache_max_namespace_bytes: 64 * 1024 * 1024,
            user_agent: "HarryPet/1.0".into(),
        }
    }
}

// ── 请求 ──

#[derive(Clone, Debug)]
pub struct RequestSpec {
    pub request_id: String,
    pub method: String,
    pub path: String,
    pub query: Vec<(String, String)>,
    pub headers: Vec<(String, String)>,
    pub body_bytes: Option<Vec<u8>>,
    pub body_file_path: Option<String>,
    pub expect_large_response: bool,
    pub save_to_file_path: Option<String>,
    pub priority: u8,
}

// ── 响应 ──

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NetErrorKind {
    Timeout,
    Dns,
    Tls,
    Http4xx,
    Http5xx,
    Canceled,
    Parse,
    Io,
    Internal,
}

#[derive(Clone, Debug)]
pub struct ResponseMeta {
    pub request_id: String,
    pub status_code: u16,
    pub headers: Vec<(String, String)>,
    pub body_inline: Option<Vec<u8>>,
    pub body_file_path: Option<String>,
    pub from_cache: bool,
    pub cost_ms: u32,
    pub error_kind: Option<NetErrorKind>,
    pub error: Option<String>,
}

// ── 传输任务 ──

#[derive(Clone, Debug)]
pub struct TransferTaskSpec {
    pub task_id: String,
    pub kind: String,
    pub url: String,
    pub method: String,
    pub headers: Vec<(String, String)>,
    pub local_path: String,
    pub resume_from: Option<u64>,
    pub expected_total: Option<u64>,
    pub priority: u8,
}

// ── 事件 ──

#[derive(Clone, Debug)]
pub enum NetEventKind {
    Queued,
    Started,
    Progress,
    Completed,
    Failed,
    Canceled,
}

#[derive(Clone, Debug)]
pub struct NetEvent {
    pub id: String,
    pub kind: NetEventKind,
    pub transferred: u64,
    pub total: Option<u64>,
    pub status_code: Option<u16>,
    pub message: Option<String>,
    pub cost_ms: Option<u32>,
}

// ── FRB 暴露的顶层函数 ──

use crate::engine::client::NetEngine;
use std::sync::Arc;
use std::sync::OnceLock;
use tokio::sync::Mutex;

static ENGINE: OnceLock<Mutex<Option<Arc<NetEngine>>>> = OnceLock::new();

fn engine_slot() -> &'static Mutex<Option<Arc<NetEngine>>> {
    ENGINE.get_or_init(|| Mutex::new(None))
}

async fn get_engine() -> anyhow::Result<Arc<NetEngine>> {
    let engine = engine_slot().lock().await;
    engine
        .clone()
        .ok_or_else(|| anyhow::anyhow!("NetEngine not initialized, call init_net_engine first"))
}

pub async fn init_net_engine(config: NetEngineConfig) -> anyhow::Result<()> {
    let mut engine_slot = engine_slot().lock().await;
    if engine_slot.is_some() {
        return Err(anyhow::anyhow!("NetEngine already initialized"));
    }

    *engine_slot = Some(Arc::new(NetEngine::new(config)?));
    tracing::info!("NetEngine initialized");
    Ok(())
}

pub async fn request(spec: RequestSpec) -> anyhow::Result<ResponseMeta> {
    get_engine().await?.request(spec).await
}

pub async fn start_transfer_task(spec: TransferTaskSpec) -> anyhow::Result<String> {
    get_engine().await?.start_transfer_task(spec).await
}

pub async fn poll_events(limit: u32) -> anyhow::Result<Vec<NetEvent>> {
    get_engine().await?.poll_events(limit).await
}

pub async fn cancel(id: String) -> anyhow::Result<bool> {
    get_engine().await?.cancel(id).await
}

pub async fn set_network_busy(is_busy: bool) -> anyhow::Result<()> {
    get_engine().await?.set_network_busy(is_busy).await
}

pub async fn clear_cache(namespace: Option<String>) -> anyhow::Result<u64> {
    get_engine().await?.clear_cache(namespace).await
}

pub async fn shutdown_net_engine() -> anyhow::Result<()> {
    let mut engine_slot = engine_slot().lock().await;
    if let Some(engine) = engine_slot.take() {
        engine.shutdown().await?;
    }
    tracing::info!("NetEngine shut down");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{init_net_engine, shutdown_net_engine, NetEngineConfig};
    use std::sync::OnceLock;
    use tokio::sync::Mutex;

    static API_TEST_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    fn api_test_lock() -> &'static Mutex<()> {
        API_TEST_LOCK.get_or_init(|| Mutex::new(()))
    }

    #[tokio::test]
    async fn shutdown_allows_reinitialize_with_new_config() {
        let _guard = api_test_lock().lock().await;
        shutdown_net_engine().await.expect("reset global engine");

        let mut first_config = NetEngineConfig::default();
        first_config.cache_default_ttl_seconds = 12;
        init_net_engine(first_config).await.expect("first init");

        shutdown_net_engine()
            .await
            .expect("shutdown after first init");

        let mut second_config = NetEngineConfig::default();
        second_config.cache_default_ttl_seconds = 30;
        init_net_engine(second_config)
            .await
            .expect("reinitialize after shutdown");

        shutdown_net_engine().await.expect("cleanup global engine");
    }
}
