//! Cache module behavior tests.

use std::path::PathBuf;
use std::time::Duration;

use uuid::Uuid;

use super::{normalize_namespace, CacheBodySource, DiskCache, RESPONSE_CACHE_NAMESPACE};

#[tokio::test]
async fn stores_and_reads_fresh_cache_entry() {
    let cache_dir = create_test_cache_dir_path("store_lookup");
    let cache = create_cache(&cache_dir, 1024 * 1024);
    let key = DiskCache::build_cache_key("GET", "https://example.com/a?b=2&a=1", &[], None);
    cache
        .store(
            RESPONSE_CACHE_NAMESPACE,
            &key,
            "GET",
            "https://example.com/a?b=2&a=1",
            200,
            &[
                ("cache-control".to_owned(), "max-age=60".to_owned()),
                ("etag".to_owned(), "\"abc\"".to_owned()),
            ],
            CacheBodySource::Bytes(b"hello"),
        )
        .await
        .expect("store cache");

    let cached = cache
        .lookup(RESPONSE_CACHE_NAMESPACE, &key)
        .await
        .expect("lookup")
        .expect("cache entry");
    let body = tokio::fs::read(&cached.body_path)
        .await
        .expect("read cached body");

    assert!(cached.is_fresh);
    assert_eq!(cached.status_code, 200);
    assert_eq!(cached.etag.as_deref(), Some("\"abc\""));
    assert_eq!(body, b"hello");

    tokio::fs::remove_dir_all(cache_dir)
        .await
        .expect("remove cache dir");
}

#[tokio::test]
async fn stale_entry_with_validator_can_be_revalidated() {
    let cache_dir = create_test_cache_dir_path("revalidate");
    let cache = create_cache(&cache_dir, 1024 * 1024);
    let key = DiskCache::build_cache_key("GET", "https://example.com/a", &[], None);
    cache
        .store(
            RESPONSE_CACHE_NAMESPACE,
            &key,
            "GET",
            "https://example.com/a",
            200,
            &[
                ("cache-control".to_owned(), "max-age=0".to_owned()),
                ("etag".to_owned(), "\"v1\"".to_owned()),
            ],
            CacheBodySource::Bytes(b"body"),
        )
        .await
        .expect("store cache");

    let stale = cache
        .lookup(RESPONSE_CACHE_NAMESPACE, &key)
        .await
        .expect("lookup stale")
        .expect("stale cache");
    assert!(!stale.is_fresh);
    assert_eq!(stale.etag.as_deref(), Some("\"v1\""));

    cache
        .revalidate(
            RESPONSE_CACHE_NAMESPACE,
            &key,
            &[
                ("cache-control".to_owned(), "max-age=120".to_owned()),
                ("etag".to_owned(), "\"v2\"".to_owned()),
            ],
        )
        .await
        .expect("revalidate");

    let refreshed = cache
        .lookup(RESPONSE_CACHE_NAMESPACE, &key)
        .await
        .expect("lookup refreshed")
        .expect("refreshed cache");
    assert!(refreshed.is_fresh);
    assert_eq!(refreshed.etag.as_deref(), Some("\"v2\""));

    tokio::fs::remove_dir_all(cache_dir)
        .await
        .expect("remove cache dir");
}

#[tokio::test]
async fn custom_default_ttl_can_disable_fresh_cache_without_cache_control() {
    let cache_dir = create_test_cache_dir_path("custom_default_ttl");
    let cache = DiskCache::new_with_policy(
        cache_dir.to_string_lossy().as_ref(),
        Duration::ZERO,
        1024 * 1024,
    )
    .expect("create cache");
    let key = DiskCache::build_cache_key("GET", "https://example.com/default-ttl", &[], None);

    cache
        .store(
            RESPONSE_CACHE_NAMESPACE,
            &key,
            "GET",
            "https://example.com/default-ttl",
            200,
            &[],
            CacheBodySource::Bytes(b"body"),
        )
        .await
        .expect("store cache");

    let cached = cache
        .lookup(RESPONSE_CACHE_NAMESPACE, &key)
        .await
        .expect("lookup");

    assert!(cached.is_none());

    tokio::fs::remove_dir_all(cache_dir)
        .await
        .expect("remove cache dir");
}

#[tokio::test]
async fn lru_prunes_oldest_entries_when_namespace_exceeds_budget() {
    let cache_dir = create_test_cache_dir_path("lru");
    let cache = DiskCache::new_for_test(
        cache_dir.to_string_lossy().as_ref(),
        Duration::from_secs(300),
        8,
    )
    .expect("create cache");

    let key_a = DiskCache::build_cache_key("GET", "https://example.com/a", &[], None);
    let key_b = DiskCache::build_cache_key("GET", "https://example.com/b", &[], None);

    cache
        .store(
            RESPONSE_CACHE_NAMESPACE,
            &key_a,
            "GET",
            "https://example.com/a",
            200,
            &[("cache-control".to_owned(), "max-age=120".to_owned())],
            CacheBodySource::Bytes(b"12345"),
        )
        .await
        .expect("store A");
    tokio::time::sleep(Duration::from_millis(4)).await;
    cache
        .store(
            RESPONSE_CACHE_NAMESPACE,
            &key_b,
            "GET",
            "https://example.com/b",
            200,
            &[("cache-control".to_owned(), "max-age=120".to_owned())],
            CacheBodySource::Bytes(b"67890"),
        )
        .await
        .expect("store B");

    let first = cache
        .lookup(RESPONSE_CACHE_NAMESPACE, &key_a)
        .await
        .expect("lookup first");
    let second = cache
        .lookup(RESPONSE_CACHE_NAMESPACE, &key_b)
        .await
        .expect("lookup second");

    assert!(first.is_none());
    assert!(second.is_some());

    tokio::fs::remove_dir_all(cache_dir)
        .await
        .expect("remove cache dir");
}

#[tokio::test]
async fn namespace_byte_budget_is_isolated_per_namespace() {
    let cache_dir = create_test_cache_dir_path("namespace_budget_isolation");
    let cache = DiskCache::new_for_test(
        cache_dir.to_string_lossy().as_ref(),
        Duration::from_secs(300),
        8,
    )
    .expect("create cache");

    cache
        .store(
            "ns_a",
            "k1",
            "GET",
            "https://example.com/ns_a/1",
            200,
            &[("cache-control".to_owned(), "max-age=120".to_owned())],
            CacheBodySource::Bytes(b"12345"),
        )
        .await
        .expect("store ns_a k1");
    tokio::time::sleep(Duration::from_millis(4)).await;
    cache
        .store(
            "ns_a",
            "k2",
            "GET",
            "https://example.com/ns_a/2",
            200,
            &[("cache-control".to_owned(), "max-age=120".to_owned())],
            CacheBodySource::Bytes(b"67890"),
        )
        .await
        .expect("store ns_a k2");

    cache
        .store(
            "ns_b",
            "k3",
            "GET",
            "https://example.com/ns_b/1",
            200,
            &[("cache-control".to_owned(), "max-age=120".to_owned())],
            CacheBodySource::Bytes(b"abcde"),
        )
        .await
        .expect("store ns_b k3");
    tokio::time::sleep(Duration::from_millis(4)).await;
    cache
        .store(
            "ns_b",
            "k4",
            "GET",
            "https://example.com/ns_b/2",
            200,
            &[("cache-control".to_owned(), "max-age=120".to_owned())],
            CacheBodySource::Bytes(b"vwxyz"),
        )
        .await
        .expect("store ns_b k4");

    let ns_a_old = cache.lookup("ns_a", "k1").await.expect("lookup ns_a old");
    let ns_a_new = cache.lookup("ns_a", "k2").await.expect("lookup ns_a new");
    let ns_b_old = cache.lookup("ns_b", "k3").await.expect("lookup ns_b old");
    let ns_b_new = cache.lookup("ns_b", "k4").await.expect("lookup ns_b new");

    assert!(ns_a_old.is_none());
    assert!(ns_a_new.is_some());
    assert!(ns_b_old.is_none());
    assert!(ns_b_new.is_some());

    assert!(tokio::fs::metadata(cache_dir.join("ns_a")).await.is_ok());
    assert!(tokio::fs::metadata(cache_dir.join("ns_b")).await.is_ok());

    tokio::fs::remove_dir_all(cache_dir)
        .await
        .expect("remove cache dir");
}

#[tokio::test]
async fn clear_namespace_rejects_parent_path() {
    let cache_dir = create_test_cache_dir_path("invalid_ns");
    let cache = create_cache(&cache_dir, 1024 * 1024);
    let result = cache.clear(Some("../outside".to_owned())).await;
    assert!(result.is_err());

    tokio::fs::remove_dir_all(cache_dir)
        .await
        .expect("remove cache dir");
}

#[test]
fn normalize_namespace_rejects_path_like_inputs() {
    for namespace in [
        ".",
        "..",
        "./responses",
        "tenant/a",
        "tenant\\a",
        "responses.",
        "tenant_cache..",
        "responses/",
        "\\responses",
    ] {
        assert!(
            normalize_namespace(namespace).is_err(),
            "expected `{namespace}` to be rejected"
        );
    }

    assert_eq!(
        normalize_namespace("  tenant_responses  ").expect("normalize namespace"),
        "tenant_responses"
    );
}

#[tokio::test]
async fn clear_namespace_only_removes_target_namespace_files() {
    let cache_dir = create_test_cache_dir_path("clear_ns");
    let cache = create_cache(&cache_dir, 1024 * 1024);

    cache
        .store(
            "ns_a",
            "k1",
            "GET",
            "https://example.com/a",
            200,
            &[("cache-control".to_owned(), "max-age=60".to_owned())],
            CacheBodySource::Bytes(b"abc"),
        )
        .await
        .expect("store ns_a");
    cache
        .store(
            "ns_b",
            "k2",
            "GET",
            "https://example.com/b",
            200,
            &[("cache-control".to_owned(), "max-age=60".to_owned())],
            CacheBodySource::Bytes(b"xyz12"),
        )
        .await
        .expect("store ns_b");

    let removed = cache
        .clear(Some("ns_a".to_owned()))
        .await
        .expect("clear ns_a");
    assert!(removed >= 3);

    let ns_a_file = cache_dir.join("ns_a").join("k1.body.bin");
    let ns_b_file = cache_dir.join("ns_b").join("k2.body.bin");
    assert!(tokio::fs::metadata(ns_a_file).await.is_err());
    assert!(tokio::fs::metadata(ns_b_file).await.is_ok());

    tokio::fs::remove_dir_all(cache_dir)
        .await
        .expect("remove cache dir");
}

fn create_cache(cache_dir: &PathBuf, max_namespace_bytes: u64) -> DiskCache {
    DiskCache::new_for_test(
        cache_dir.to_string_lossy().as_ref(),
        Duration::from_secs(300),
        max_namespace_bytes,
    )
    .expect("create cache")
}

fn create_test_cache_dir_path(label: &str) -> PathBuf {
    std::env::temp_dir().join(format!("disk_cache_{label}_{}", Uuid::new_v4()))
}
