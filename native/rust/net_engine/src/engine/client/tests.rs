use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use reqwest::Client;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use uuid::Uuid;

use super::transfer::parse_content_range_start;
use super::{ConnectionLimiter, NetEngine};
use crate::api::{NetEngineConfig, RequestSpec};
use crate::engine::error::NetError;

#[test]
fn parses_content_range_start_value() {
    // 只关心 range 起始偏移。
    assert_eq!(parse_content_range_start("bytes 200-1000/67589"), Some(200));
    assert_eq!(parse_content_range_start("bytes */67589"), None);
    assert_eq!(parse_content_range_start("invalid"), None);
}

#[tokio::test]
async fn header_validation_rejects_invalid_name() {
    let client = Client::new();
    let builder = client.get("http://localhost/");
    let result =
        NetEngine::apply_headers(builder, &[("invalid name".to_owned(), "value".to_owned())]);

    assert!(matches!(result, Err(NetError::Parse(_))));
}

#[tokio::test]
async fn header_validation_rejects_invalid_value() {
    let client = Client::new();
    let builder = client.get("http://localhost/");
    let result =
        NetEngine::apply_headers(builder, &[("x-test".to_owned(), "bad\nvalue".to_owned())]);

    assert!(matches!(result, Err(NetError::Parse(_))));
}

#[tokio::test]
async fn connection_limiter_applies_per_host_limit() {
    let limiter = ConnectionLimiter::new(8, 1);
    let first = limiter
        .acquire_for_url("http://127.0.0.1:18080/a")
        .await
        .expect("acquire first permit");

    let blocked = tokio::time::timeout(
        Duration::from_millis(50),
        limiter.acquire_for_url("http://127.0.0.1:18080/b"),
    )
    .await;
    assert!(blocked.is_err(), "second same-host permit should block");

    drop(first);
    let second = tokio::time::timeout(
        Duration::from_millis(200),
        limiter.acquire_for_url("http://127.0.0.1:18080/b"),
    )
    .await
    .expect("second permit should unblock after release")
    .expect("acquire second permit");
    drop(second);
}

#[tokio::test]
async fn connection_limiter_applies_global_limit() {
    let limiter = ConnectionLimiter::new(1, 8);
    let first = limiter
        .acquire_for_url("http://127.0.0.1:18080/a")
        .await
        .expect("acquire first permit");

    let blocked = tokio::time::timeout(
        Duration::from_millis(50),
        limiter.acquire_for_url("http://127.0.0.1:18081/b"),
    )
    .await;
    assert!(
        blocked.is_err(),
        "second cross-host permit should still block on global cap"
    );

    drop(first);
    let second = tokio::time::timeout(
        Duration::from_millis(200),
        limiter.acquire_for_url("http://127.0.0.1:18081/b"),
    )
    .await
    .expect("global permit should unblock after release")
    .expect("acquire second permit");
    drop(second);
}

#[tokio::test]
async fn clear_cache_removes_all_files_under_root() {
    // namespace=None 时应清空整个缓存根目录内容。
    let cache_dir = create_test_cache_dir_path("clear_all");
    tokio::fs::create_dir_all(cache_dir.join("nested"))
        .await
        .expect("create nested cache dir");
    tokio::fs::write(cache_dir.join("a.bin"), vec![0_u8; 4])
        .await
        .expect("write root cache file");
    tokio::fs::write(cache_dir.join("nested").join("b.bin"), vec![0_u8; 6])
        .await
        .expect("write nested cache file");

    let engine = create_engine_for_cache_dir(&cache_dir);
    let removed = engine.clear_cache(None).await.expect("clear cache");

    assert_eq!(removed, 10);
    assert!(tokio::fs::metadata(cache_dir.join("a.bin")).await.is_err());
    assert!(tokio::fs::metadata(cache_dir.join("nested")).await.is_err());
    assert!(tokio::fs::metadata(&cache_dir).await.is_ok());

    tokio::fs::remove_dir_all(&cache_dir)
        .await
        .expect("remove cache root");
}

#[tokio::test]
async fn clear_cache_only_removes_target_namespace() {
    // 指定 namespace 只清理该分区。
    let cache_dir = create_test_cache_dir_path("clear_ns");
    tokio::fs::create_dir_all(cache_dir.join("ns_a"))
        .await
        .expect("create ns_a");
    tokio::fs::create_dir_all(cache_dir.join("ns_b"))
        .await
        .expect("create ns_b");
    tokio::fs::write(cache_dir.join("ns_a").join("a.bin"), vec![0_u8; 3])
        .await
        .expect("write ns_a file");
    tokio::fs::write(cache_dir.join("ns_b").join("b.bin"), vec![0_u8; 5])
        .await
        .expect("write ns_b file");

    let engine = create_engine_for_cache_dir(&cache_dir);
    let removed = engine
        .clear_cache(Some("  ns_a  ".to_owned()))
        .await
        .expect("clear namespace");

    assert_eq!(removed, 3);
    assert!(tokio::fs::metadata(cache_dir.join("ns_a").join("a.bin"))
        .await
        .is_err());
    assert!(tokio::fs::metadata(cache_dir.join("ns_b").join("b.bin"))
        .await
        .is_ok());

    tokio::fs::remove_dir_all(&cache_dir)
        .await
        .expect("remove cache root");
}

#[tokio::test]
async fn clear_cache_rejects_blank_namespace() {
    let cache_dir = create_test_cache_dir_path("clear_blank_ns");
    tokio::fs::create_dir_all(cache_dir.join("ns_a"))
        .await
        .expect("create ns_a");
    tokio::fs::write(cache_dir.join("ns_a").join("a.bin"), vec![0_u8; 3])
        .await
        .expect("write ns_a file");

    let engine = create_engine_for_cache_dir(&cache_dir);
    let result = engine.clear_cache(Some("   ".to_owned())).await;

    assert!(result.is_err());
    assert!(tokio::fs::metadata(cache_dir.join("ns_a").join("a.bin"))
        .await
        .is_ok());

    tokio::fs::remove_dir_all(&cache_dir)
        .await
        .expect("remove cache root");
}

#[tokio::test]
async fn clear_cache_rejects_parent_namespace() {
    // 防止路径穿越。
    let cache_dir = create_test_cache_dir_path("clear_invalid_ns");
    tokio::fs::create_dir_all(&cache_dir)
        .await
        .expect("create cache root");

    let engine = create_engine_for_cache_dir(&cache_dir);
    let result = engine.clear_cache(Some("../outside".to_owned())).await;

    assert!(result.is_err());

    tokio::fs::remove_dir_all(&cache_dir)
        .await
        .expect("remove cache root");
}

#[tokio::test]
async fn request_cache_key_distinguishes_query_parameters() {
    let cache_dir = create_test_cache_dir_path("cache_query");
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test server");
    let base_url = format!("http://{}", listener.local_addr().expect("local addr"));
    let server_hits = Arc::new(AtomicUsize::new(0));
    let server_hits_ref = Arc::clone(&server_hits);
    let server_task = tokio::spawn(async move {
        loop {
            let accept_result =
                tokio::time::timeout(Duration::from_millis(200), listener.accept()).await;
            let Ok(Ok((mut socket, _))) = accept_result else {
                break;
            };

            let mut request_bytes = Vec::new();
            let mut buffer = [0_u8; 1024];
            loop {
                let read = socket.read(&mut buffer).await.expect("read request");
                if read == 0 {
                    break;
                }
                request_bytes.extend_from_slice(&buffer[..read]);
                if request_bytes.windows(4).any(|chunk| chunk == b"\r\n\r\n") {
                    break;
                }
            }

            let request_text = String::from_utf8_lossy(&request_bytes);
            let target = request_text
                .lines()
                .next()
                .and_then(|line| line.split_whitespace().nth(1))
                .unwrap_or("/");
            let body = format!("{{\"target\":\"{target}\"}}");
            server_hits_ref.fetch_add(1, Ordering::SeqCst);
            let response = format!(
                concat!(
                    "HTTP/1.1 200 OK\r\n",
                    "Content-Type: application/json\r\n",
                    "Cache-Control: max-age=60\r\n",
                    "Content-Length: {}\r\n",
                    "Connection: close\r\n\r\n",
                    "{}"
                ),
                body.len(),
                body
            );
            socket
                .write_all(response.as_bytes())
                .await
                .expect("write response");
            socket.shutdown().await.expect("shutdown socket");
        }
    });

    let engine = create_engine_for_base_url_and_cache_dir(&base_url, &cache_dir);
    let first = engine
        .request(build_get_request("query-1", "/cache", vec![("id", "1")]))
        .await
        .expect("first response");
    let second = engine
        .request(build_get_request("query-2", "/cache", vec![("id", "2")]))
        .await
        .expect("second response");
    let third = engine
        .request(build_get_request("query-3", "/cache", vec![("id", "2")]))
        .await
        .expect("third response");

    assert!(!first.from_cache);
    assert_eq!(response_body_text(&first), "{\"target\":\"/cache?id=1\"}");
    assert!(first.error.is_none());

    assert!(!second.from_cache);
    assert_eq!(response_body_text(&second), "{\"target\":\"/cache?id=2\"}");
    assert!(second.error.is_none());

    assert!(third.from_cache);
    assert_eq!(response_body_text(&third), "{\"target\":\"/cache?id=2\"}");
    assert!(third.error.is_none());

    server_task.await.expect("server task");
    assert_eq!(server_hits.load(Ordering::SeqCst), 2);

    tokio::fs::remove_dir_all(&cache_dir)
        .await
        .expect("remove cache root");
}

#[tokio::test]
async fn clear_cache_keeps_materialized_response_files_outside_cache_root() {
    let temp_root = create_test_cache_dir_path("materialized_boundary");
    let cache_dir = temp_root.join("cache");
    tokio::fs::create_dir_all(&cache_dir)
        .await
        .expect("create cache dir");

    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test server");
    let base_url = format!("http://{}", listener.local_addr().expect("local addr"));
    let server_hits = Arc::new(AtomicUsize::new(0));
    let server_hits_ref = Arc::clone(&server_hits);
    let payload = vec![0x41_u8; 64];
    let server_task = tokio::spawn(async move {
        loop {
            let accept_result =
                tokio::time::timeout(Duration::from_millis(200), listener.accept()).await;
            let Ok(Ok((mut socket, _))) = accept_result else {
                break;
            };

            let mut request_bytes = Vec::new();
            let mut buffer = [0_u8; 1024];
            loop {
                let read = socket.read(&mut buffer).await.expect("read request");
                if read == 0 {
                    break;
                }
                request_bytes.extend_from_slice(&buffer[..read]);
                if request_bytes.windows(4).any(|chunk| chunk == b"\r\n\r\n") {
                    break;
                }
            }

            server_hits_ref.fetch_add(1, Ordering::SeqCst);
            let response = format!(
                concat!(
                    "HTTP/1.1 200 OK\r\n",
                    "Content-Type: application/octet-stream\r\n",
                    "Cache-Control: max-age=60\r\n",
                    "Content-Length: {}\r\n",
                    "Connection: close\r\n\r\n"
                ),
                payload.len()
            );
            socket
                .write_all(response.as_bytes())
                .await
                .expect("write response headers");
            socket
                .write_all(&payload)
                .await
                .expect("write response body");
            socket.shutdown().await.expect("shutdown socket");
        }
    });

    let engine = create_engine_for_base_url_and_cache_dir(&base_url, &cache_dir);
    let first = engine
        .request(build_large_get_request("materialized-1", "/cache", vec![]))
        .await
        .expect("first response");
    assert!(!first.from_cache);
    let first_path = PathBuf::from(first.body_file_path.expect("first file body"));
    assert!(!first_path.starts_with(&cache_dir));
    assert!(tokio::fs::metadata(&first_path).await.is_ok());

    tokio::fs::remove_file(&first_path)
        .await
        .expect("remove first materialized file");

    let second = engine
        .request(build_large_get_request("materialized-2", "/cache", vec![]))
        .await
        .expect("second response");
    assert!(second.from_cache);
    let second_path = PathBuf::from(second.body_file_path.expect("second file body"));
    assert!(!second_path.starts_with(&cache_dir));
    assert!(tokio::fs::metadata(&second_path).await.is_ok());

    let removed = engine.clear_cache(None).await.expect("clear cache");
    assert!(removed > 0);
    assert!(tokio::fs::metadata(cache_dir.join("responses"))
        .await
        .is_err());
    assert!(tokio::fs::metadata(&second_path).await.is_ok());

    let third = engine
        .request(build_large_get_request("materialized-3", "/cache", vec![]))
        .await
        .expect("third response");
    assert!(!third.from_cache);
    assert_eq!(server_hits.load(Ordering::SeqCst), 2);

    server_task.await.expect("server task");
    tokio::fs::remove_dir_all(&temp_root)
        .await
        .expect("remove temp root");
}

#[tokio::test]
async fn blank_cache_dir_disables_default_materialized_response_directory() {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test server");
    let base_url = format!("http://{}", listener.local_addr().expect("local addr"));
    let payload = vec![0x42_u8; 64];
    let server_task = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.expect("accept request");

        let mut request_bytes = Vec::new();
        let mut buffer = [0_u8; 1024];
        loop {
            let read = socket.read(&mut buffer).await.expect("read request");
            if read == 0 {
                break;
            }
            request_bytes.extend_from_slice(&buffer[..read]);
            if request_bytes.windows(4).any(|chunk| chunk == b"\r\n\r\n") {
                break;
            }
        }

        let response = format!(
            concat!(
                "HTTP/1.1 200 OK\r\n",
                "Content-Type: application/octet-stream\r\n",
                "Content-Length: {}\r\n",
                "Connection: close\r\n\r\n"
            ),
            payload.len()
        );
        socket
            .write_all(response.as_bytes())
            .await
            .expect("write response headers");
        socket
            .write_all(&payload)
            .await
            .expect("write response body");
        socket.shutdown().await.expect("shutdown socket");
    });

    let mut config = NetEngineConfig::default();
    config.base_url = base_url;
    config.cache_dir = "   ".to_owned();
    let engine = NetEngine::new(config).expect("create net engine");

    let response = engine
        .request(build_large_get_request("blank-cache-dir", "/download", vec![]))
        .await
        .expect("request response");

    assert!(!response.from_cache);
    assert_eq!(
        response.body_file_path.as_deref(),
        Some("blank-cache-dir.bin")
    );
    assert!(tokio::fs::metadata("blank-cache-dir.bin").await.is_ok());

    server_task.await.expect("server task");
    tokio::fs::remove_file("blank-cache-dir.bin")
        .await
        .expect("remove materialized response");
}

#[tokio::test]
async fn request_cache_uses_configured_response_namespace() {
    let cache_dir = create_test_cache_dir_path("custom_namespace");
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test server");
    let base_url = format!("http://{}", listener.local_addr().expect("local addr"));
    let server_hits = Arc::new(AtomicUsize::new(0));
    let server_hits_ref = Arc::clone(&server_hits);
    let server_task = tokio::spawn(async move {
        loop {
            let accept_result =
                tokio::time::timeout(Duration::from_millis(200), listener.accept()).await;
            let Ok(Ok((mut socket, _))) = accept_result else {
                break;
            };

            let mut request_bytes = Vec::new();
            let mut buffer = [0_u8; 1024];
            loop {
                let read = socket.read(&mut buffer).await.expect("read request");
                if read == 0 {
                    break;
                }
                request_bytes.extend_from_slice(&buffer[..read]);
                if request_bytes.windows(4).any(|chunk| chunk == b"\r\n\r\n") {
                    break;
                }
            }

            server_hits_ref.fetch_add(1, Ordering::SeqCst);
            let body = "{\"ok\":true}";
            let response = format!(
                concat!(
                    "HTTP/1.1 200 OK\r\n",
                    "Content-Type: application/json\r\n",
                    "Cache-Control: max-age=60\r\n",
                    "Content-Length: {}\r\n",
                    "Connection: close\r\n\r\n",
                    "{}"
                ),
                body.len(),
                body
            );
            socket
                .write_all(response.as_bytes())
                .await
                .expect("write response");
            socket.shutdown().await.expect("shutdown socket");
        }
    });

    let engine = create_engine_for_base_url_and_cache_dir_with_namespace(
        &base_url,
        &cache_dir,
        "tenant_responses",
    );
    let first = engine
        .request(build_get_request("custom-ns-1", "/cache", vec![]))
        .await
        .expect("first response");
    let second = engine
        .request(build_get_request("custom-ns-2", "/cache", vec![]))
        .await
        .expect("second response");

    assert!(!first.from_cache);
    assert!(second.from_cache);
    assert_eq!(server_hits.load(Ordering::SeqCst), 1);
    assert!(tokio::fs::metadata(cache_dir.join("tenant_responses"))
        .await
        .is_ok());
    assert!(tokio::fs::metadata(cache_dir.join("responses"))
        .await
        .is_err());

    server_task.await.expect("server task");
    tokio::fs::remove_dir_all(&cache_dir)
        .await
        .expect("remove cache root");
}

#[test]
fn net_engine_rejects_invalid_configured_response_cache_namespace() {
    let cache_dir = create_test_cache_dir_path("invalid_response_namespace");
    for namespace in ["../outside", "./responses", "tenant/a", "tenant\\a"] {
        let mut config = NetEngineConfig::default();
        config.cache_dir = cache_dir.to_string_lossy().into_owned();
        config.cache_response_namespace = namespace.to_owned();

        let result = NetEngine::new(config);

        assert!(result.is_err(), "expected `{namespace}` to be rejected");
    }

    let _ = std::fs::remove_dir_all(&cache_dir);
}

#[test]
fn net_engine_allows_invalid_response_cache_namespace_when_cache_disabled() {
    for namespace in [
        "",
        "   ",
        "../outside",
        "./responses",
        "tenant/a",
        "tenant\\a",
    ] {
        let mut config = NetEngineConfig::default();
        config.cache_dir = String::new();
        config.cache_response_namespace = namespace.to_owned();

        let result = NetEngine::new(config);

        assert!(
            result.is_ok(),
            "expected `{namespace}` to be ignored when cache is disabled"
        );
    }
}

fn create_engine_for_cache_dir(cache_dir: &Path) -> NetEngine {
    // 用临时目录构建最小可用引擎。
    let mut config = NetEngineConfig::default();
    config.cache_dir = cache_dir.to_string_lossy().into_owned();
    NetEngine::new(config).expect("create net engine")
}

fn create_engine_for_base_url_and_cache_dir(base_url: &str, cache_dir: &Path) -> NetEngine {
    let mut config = NetEngineConfig::default();
    config.base_url = base_url.to_owned();
    config.cache_dir = cache_dir.to_string_lossy().into_owned();
    NetEngine::new(config).expect("create net engine")
}

fn create_engine_for_base_url_and_cache_dir_with_namespace(
    base_url: &str,
    cache_dir: &Path,
    cache_response_namespace: &str,
) -> NetEngine {
    let mut config = NetEngineConfig::default();
    config.base_url = base_url.to_owned();
    config.cache_dir = cache_dir.to_string_lossy().into_owned();
    config.cache_response_namespace = cache_response_namespace.to_owned();
    NetEngine::new(config).expect("create net engine")
}

fn build_get_request(request_id: &str, path: &str, query: Vec<(&str, &str)>) -> RequestSpec {
    RequestSpec {
        request_id: request_id.to_owned(),
        method: "GET".to_owned(),
        path: path.to_owned(),
        query: query
            .into_iter()
            .map(|(key, value)| (key.to_owned(), value.to_owned()))
            .collect(),
        headers: vec![],
        body_bytes: None,
        body_file_path: None,
        expect_large_response: false,
        save_to_file_path: None,
        priority: 1,
    }
}

fn build_large_get_request(request_id: &str, path: &str, query: Vec<(&str, &str)>) -> RequestSpec {
    let mut spec = build_get_request(request_id, path, query);
    spec.expect_large_response = true;
    spec
}

fn response_body_text(response: &crate::api::ResponseMeta) -> String {
    String::from_utf8(response.body_inline.clone().expect("inline body")).expect("utf8 body")
}

fn create_test_cache_dir_path(label: &str) -> PathBuf {
    // 随机目录避免测试互相污染。
    std::env::temp_dir().join(format!("net_engine_{label}_{}", Uuid::new_v4()))
}
