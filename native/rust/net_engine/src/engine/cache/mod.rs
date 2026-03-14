//! Disk-backed HTTP response cache.
//!
//! This module is intentionally split by responsibility to keep the public
//! API stable while reducing single-file complexity:
//! - `mod.rs`: public types and high-level cache workflows.
//! - `headers.rs`: header parsing/merge/normalization helpers.
//! - `key.rs`: cache-key construction and URL/header normalization.
//! - `policy.rs`: cache policy decisions (`no-store`, `max-age`, etc.).
//! - `storage.rs`: async file IO and metadata persistence helpers.
//! - `prune.rs`: namespace pruning and eviction logic.
//! - `tests.rs`: behavior-focused tests for the cache module.
//!
//! Keep new code in the most specific submodule first; only keep orchestration
//! in `mod.rs`.

use std::path::{Component, Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Context};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

mod headers;
mod key;
mod policy;
mod prune;
mod storage;

const CACHE_KEY_VERSION: &str = "v1";
const META_SUFFIX: &str = ".meta.json";
const BODY_SUFFIX: &str = ".body.bin";
pub const DEFAULT_CACHE_TTL_SECONDS: u64 = 300;
pub const DEFAULT_CACHE_MAX_NAMESPACE_BYTES: u64 = 64 * 1024 * 1024;

pub const RESPONSE_CACHE_NAMESPACE: &str = "responses";

#[derive(Clone, Debug)]
pub struct DiskCache {
    root_dir: PathBuf,
    default_ttl: Duration,
    max_namespace_bytes: u64,
}

#[derive(Clone, Debug)]
pub enum CacheBodySource<'a> {
    Bytes(&'a [u8]),
    FilePath(&'a Path),
}

#[derive(Clone, Debug)]
pub struct CacheLookup {
    pub key: String,
    pub status_code: u16,
    pub headers: Vec<(String, String)>,
    pub body_path: PathBuf,
    pub body_size: u64,
    pub etag: Option<String>,
    pub last_modified: Option<String>,
    pub is_fresh: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct CacheEntryMeta {
    schema_version: String,
    key: String,
    method: String,
    url: String,
    status_code: u16,
    response_headers: Vec<(String, String)>,
    etag: Option<String>,
    last_modified: Option<String>,
    created_at_ms: u64,
    updated_at_ms: u64,
    last_access_at_ms: u64,
    expires_at_ms: u64,
    body_size: u64,
}

impl DiskCache {
    pub fn new(cache_dir: &str) -> anyhow::Result<Self> {
        Self::new_with_policy(
            cache_dir,
            Duration::from_secs(DEFAULT_CACHE_TTL_SECONDS),
            DEFAULT_CACHE_MAX_NAMESPACE_BYTES,
        )
    }

    pub fn new_with_policy(
        cache_dir: &str,
        default_ttl: Duration,
        max_namespace_bytes: u64,
    ) -> anyhow::Result<Self> {
        Self::with_limits(cache_dir, default_ttl, max_namespace_bytes)
    }

    pub fn build_cache_key(
        method: &str,
        url: &str,
        headers: &[(String, String)],
        body: Option<&[u8]>,
    ) -> String {
        key::build_cache_key(method, url, headers, body)
    }

    pub fn request_disables_cache(headers: &[(String, String)]) -> bool {
        policy::request_disables_cache(headers)
    }

    pub async fn lookup(&self, namespace: &str, key: &str) -> anyhow::Result<Option<CacheLookup>> {
        let (meta_path, body_path) = self.entry_paths(namespace, key)?;
        let mut meta = match Self::load_meta(&meta_path).await {
            Ok(meta) => meta,
            Err(error) => {
                if error.downcast_ref::<std::io::Error>().map(|e| e.kind())
                    == Some(std::io::ErrorKind::NotFound)
                {
                    return Ok(None);
                }
                // Corrupted metadata should not block requests. Clean it up and treat as miss.
                let _ = tokio::fs::remove_file(&meta_path).await;
                return Ok(None);
            }
        };

        let body_metadata = match tokio::fs::metadata(&body_path).await {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                let _ = tokio::fs::remove_file(&meta_path).await;
                return Ok(None);
            }
            Err(error) => return Err(error.into()),
        };

        let now_ms = now_millis();
        let is_fresh = meta.expires_at_ms > now_ms;
        if !is_fresh && meta.etag.is_none() && meta.last_modified.is_none() {
            Self::remove_entry_files(&meta_path, &body_path).await?;
            return Ok(None);
        }

        meta.last_access_at_ms = now_ms;
        meta.body_size = body_metadata.len();
        Self::save_meta(&meta_path, &meta).await?;

        Ok(Some(CacheLookup {
            key: meta.key,
            status_code: meta.status_code,
            headers: meta.response_headers,
            body_path,
            body_size: body_metadata.len(),
            etag: meta.etag,
            last_modified: meta.last_modified,
            is_fresh,
        }))
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn store(
        &self,
        namespace: &str,
        key: &str,
        method: &str,
        url: &str,
        status_code: u16,
        headers: &[(String, String)],
        body: CacheBodySource<'_>,
    ) -> anyhow::Result<()> {
        let method = method.trim().to_ascii_uppercase();
        if method != "GET" || status_code != 200 || policy::response_has_no_store(headers) {
            let (meta_path, body_path) = self.entry_paths(namespace, key)?;
            Self::remove_entry_files(&meta_path, &body_path).await?;
            return Ok(());
        }

        let namespace_dir = self.namespace_dir(namespace)?;
        tokio::fs::create_dir_all(&namespace_dir)
            .await
            .context("create cache namespace dir")?;

        let safe_key = key::sanitize_key(key);
        let (meta_path, body_path) = self.entry_paths(namespace, key)?;
        let tmp_body_path = namespace_dir.join(format!("{}.{}.tmp", safe_key, Uuid::new_v4()));
        let body_size = Self::persist_body(&tmp_body_path, body).await?;
        Self::replace_file(&tmp_body_path, &body_path).await?;

        let now_ms = now_millis();
        let ttl = self.resolve_ttl(headers);
        let existing = Self::load_meta(&meta_path).await.ok();
        let meta = CacheEntryMeta {
            schema_version: CACHE_KEY_VERSION.to_owned(),
            key: key.to_owned(),
            method,
            url: key::normalize_url(url),
            status_code,
            response_headers: headers::normalize_headers_for_storage(headers),
            etag: headers::first_header_value(headers, "etag").map(ToOwned::to_owned),
            last_modified: headers::first_header_value(headers, "last-modified")
                .map(ToOwned::to_owned),
            created_at_ms: existing.map(|item| item.created_at_ms).unwrap_or(now_ms),
            updated_at_ms: now_ms,
            last_access_at_ms: now_ms,
            expires_at_ms: now_ms.saturating_add(ttl.as_millis() as u64),
            body_size,
        };

        Self::save_meta(&meta_path, &meta).await?;
        self.prune_namespace(&namespace_dir).await
    }

    pub async fn revalidate(
        &self,
        namespace: &str,
        key: &str,
        revalidate_headers: &[(String, String)],
    ) -> anyhow::Result<()> {
        let namespace_dir = self.namespace_dir(namespace)?;
        let (meta_path, body_path) = self.entry_paths(namespace, key)?;
        let mut meta = match Self::load_meta(&meta_path).await {
            Ok(meta) => meta,
            Err(error) => {
                if error.downcast_ref::<std::io::Error>().map(|e| e.kind())
                    == Some(std::io::ErrorKind::NotFound)
                {
                    return Ok(());
                }
                return Err(error);
            }
        };

        if tokio::fs::metadata(&body_path).await.is_err() {
            Self::remove_entry_files(&meta_path, &body_path).await?;
            return Ok(());
        }

        let merged_headers = headers::merge_headers(&meta.response_headers, revalidate_headers);
        let now_ms = now_millis();
        meta.response_headers = merged_headers.clone();
        meta.etag = headers::first_header_value(&merged_headers, "etag")
            .map(ToOwned::to_owned)
            .or(meta.etag);
        meta.last_modified = headers::first_header_value(&merged_headers, "last-modified")
            .map(ToOwned::to_owned)
            .or(meta.last_modified);
        meta.updated_at_ms = now_ms;
        meta.last_access_at_ms = now_ms;
        meta.expires_at_ms =
            now_ms.saturating_add(self.resolve_ttl(&merged_headers).as_millis() as u64);

        Self::save_meta(&meta_path, &meta).await?;
        self.prune_namespace(&namespace_dir).await
    }

    pub async fn clear(&self, namespace: Option<String>) -> anyhow::Result<u64> {
        let target = match namespace {
            Some(namespace) => self.namespace_dir(&namespace)?,
            None => self.root_dir.clone(),
        };

        let metadata = match tokio::fs::metadata(&target).await {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(0),
            Err(error) => return Err(error.into()),
        };

        if metadata.is_file() {
            let file_size = metadata.len();
            tokio::fs::remove_file(&target).await?;
            return Ok(file_size);
        }

        if !metadata.is_dir() {
            return Ok(0);
        }

        Self::clear_dir_contents(&target).await
    }

    #[cfg(test)]
    fn new_for_test(
        cache_dir: &str,
        default_ttl: Duration,
        max_namespace_bytes: u64,
    ) -> anyhow::Result<Self> {
        Self::with_limits(cache_dir, default_ttl, max_namespace_bytes)
    }

    fn with_limits(
        cache_dir: &str,
        default_ttl: Duration,
        max_namespace_bytes: u64,
    ) -> anyhow::Result<Self> {
        let cache_dir = cache_dir.trim();
        if cache_dir.is_empty() {
            return Err(anyhow!("cache dir is empty"));
        }

        let root_dir = PathBuf::from(cache_dir);
        std::fs::create_dir_all(&root_dir).context("create cache root dir")?;

        Ok(Self {
            root_dir,
            default_ttl,
            max_namespace_bytes,
        })
    }

    fn resolve_ttl(&self, headers: &[(String, String)]) -> Duration {
        policy::resolve_ttl(headers, self.default_ttl)
    }

    fn namespace_dir(&self, namespace: &str) -> anyhow::Result<PathBuf> {
        let namespace = normalize_namespace(namespace)?;
        Ok(self.root_dir.join(namespace))
    }

    fn entry_paths(&self, namespace: &str, key: &str) -> anyhow::Result<(PathBuf, PathBuf)> {
        let namespace_dir = self.namespace_dir(namespace)?;
        let key = key::sanitize_key(key);
        Ok((
            namespace_dir.join(format!("{key}{META_SUFFIX}")),
            namespace_dir.join(format!("{key}{BODY_SUFFIX}")),
        ))
    }
}

pub fn normalize_namespace(namespace: &str) -> anyhow::Result<String> {
    let trimmed = namespace.trim();
    if trimmed.is_empty() {
        return Err(anyhow!("cache namespace is empty"));
    }

    if trimmed.contains(['/', '\\']) {
        return Err(anyhow!("invalid cache namespace"));
    }

    // Reject Windows directory aliases such as `responses.` that collapse to
    // the same on-disk entry as `responses`.
    if trimmed.ends_with('.') {
        return Err(anyhow!("invalid cache namespace"));
    }

    let mut components = Path::new(trimmed).components();
    match (components.next(), components.next()) {
        (Some(Component::Normal(_)), None) => Ok(trimmed.to_owned()),
        _ => Err(anyhow!("invalid cache namespace")),
    }
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[cfg(test)]
mod tests;
