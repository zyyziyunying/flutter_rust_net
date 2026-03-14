use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use futures::StreamExt;
use reqwest::header::{HeaderValue, IF_MODIFIED_SINCE, IF_NONE_MATCH};
use reqwest::{RequestBuilder, StatusCode};
use tokio::io::AsyncWriteExt;
use tokio_util::sync::CancellationToken;

use super::{NetEngine, ResponseBodyStorage};
use crate::api::{RequestSpec, ResponseMeta};
use crate::engine::cache::{CacheBodySource, CacheLookup, DiskCache};
use crate::engine::error::NetError;

const MATERIALIZED_RESPONSE_DIR_SUFFIX: &str = "_materialized";
const DEFAULT_MATERIALIZED_RESPONSE_DIR_NAME: &str = "net_engine_materialized";

impl NetEngine {
    /// 同步式请求（等待完成后返回）
    pub async fn request(&self, spec: RequestSpec) -> anyhow::Result<ResponseMeta> {
        // 先拿调度 permit，受全局并发控制。
        let _permit = self.scheduler.acquire(spec.priority).await?;
        let cancel_token = CancellationToken::new();
        {
            let mut tokens = self.cancel_tokens.lock().await;
            tokens.insert(spec.request_id.clone(), cancel_token.clone());
        }

        let start = Instant::now();
        let result = self.do_request(&spec, &cancel_token).await;
        let cost_ms = start.elapsed().as_millis() as u32;

        // 清理 cancel token
        Self::remove_cancel_token(&self.cancel_tokens, &spec.request_id).await;

        match result {
            Ok(mut meta) => {
                meta.cost_ms = cost_ms;
                Ok(meta)
            }
            Err(e) => Ok(ResponseMeta {
                request_id: spec.request_id,
                status_code: match &e {
                    NetError::Http { status, .. } => *status,
                    _ => 0,
                },
                headers: vec![],
                body_inline: None,
                body_file_path: None,
                from_cache: false,
                cost_ms,
                error_kind: Some(e.kind()),
                error: Some(e.to_string()),
            }),
        }
    }

    async fn do_request(
        &self,
        spec: &RequestSpec,
        cancel_token: &CancellationToken,
    ) -> Result<ResponseMeta, NetError> {
        // path 支持相对路径，自动拼接 base_url。
        let url = if spec.path.starts_with("http") {
            spec.path.clone()
        } else {
            format!(
                "{}{}",
                self.config.base_url.trim_end_matches('/'),
                spec.path
            )
        };

        let method: reqwest::Method = spec
            .method
            .parse()
            .map_err(|e: http::method::InvalidMethod| NetError::Parse(e.to_string()))?;
        let _connection_permit = self.acquire_connection_permit(&url).await?;
        let request_url_for_cache = Self::url_with_query(&url, &spec.query);
        let response_cache_namespace = self.response_cache_namespace.as_str();

        let mut builder = self.client.request(method.clone(), &url); // 构建请求

        // query params
        if !spec.query.is_empty() {
            builder = builder.query(&spec.query);
        }

        builder = Self::apply_headers(builder, &spec.headers)?;
        let mut cache_key: Option<String> = None;
        let mut stale_cache_entry: Option<CacheLookup> = None;
        if let Some(cache) = self.disk_cache.as_ref() {
            // 仅 GET 且未禁用缓存时参与缓存流程。
            if method == reqwest::Method::GET && !DiskCache::request_disables_cache(&spec.headers) {
                let key = DiskCache::build_cache_key(
                    method.as_str(),
                    &request_url_for_cache,
                    &spec.headers,
                    spec.body_bytes.as_deref(),
                );

                if let Some(cached) = cache
                    .lookup(response_cache_namespace, &key)
                    .await
                    .map_err(|error| NetError::Internal(error.to_string()))?
                {
                    // 命中新鲜缓存直接返回。
                    if cached.is_fresh {
                        return self.materialize_cached_response(spec, cached).await;
                    }
                    // 命中过期缓存则走条件请求。
                    builder = Self::apply_conditional_cache_headers(builder, &cached)?;
                    stale_cache_entry = Some(cached);
                }

                cache_key = Some(key);
            }
        }

        // body：支持内存字节或文件读取。
        if let Some(ref body) = spec.body_bytes {
            builder = builder.body(body.clone());
        } else if let Some(ref body_path) = spec.body_file_path {
            let body = tokio::fs::read(body_path).await.map_err(NetError::Io)?;
            builder = builder.body(body);
        }

        // 发送请求，支持取消
        let write_timeout = Self::request_write_timeout(spec, self.config.write_timeout_ms);
        let response =
            Self::send_with_cancel(builder, cancel_token, &spec.request_id, write_timeout).await?;

        let status_code = response.status().as_u16();
        let headers: Vec<(String, String)> = response
            .headers()
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("").to_string()))
            .collect();
        if status_code == StatusCode::NOT_MODIFIED.as_u16() {
            // 304 时回放旧缓存内容并刷新元信息。
            if let Some(cached) = stale_cache_entry {
                if let Some(cache) = self.disk_cache.as_ref() {
                    if let Err(error) = cache
                        .revalidate(response_cache_namespace, &cached.key, &headers)
                        .await
                    {
                        tracing::warn!(
                            request_id = %spec.request_id,
                            error = %error,
                            "cache revalidate failed"
                        );
                    }
                }
                return self.materialize_cached_response(spec, cached).await;
            }
        }

        let threshold = self.config.large_body_threshold_kb as usize * 1024; // 内存/落盘阈值

        let body_storage = self
            .read_response_body(response, spec, cancel_token, threshold)
            .await?;

        self.maybe_store_response_cache(
            spec,
            method.as_str(),
            &request_url_for_cache,
            status_code,
            &headers,
            cache_key.as_deref(),
            &body_storage,
        )
        .await;

        match body_storage {
            ResponseBodyStorage::File(path) => Ok(ResponseMeta {
                request_id: spec.request_id.clone(),
                status_code,
                headers,
                body_inline: None,
                body_file_path: Some(path),
                from_cache: false,
                cost_ms: 0,
                error_kind: None,
                error: None,
            }),
            ResponseBodyStorage::Inline(body) => Ok(ResponseMeta {
                request_id: spec.request_id.clone(),
                status_code,
                headers,
                body_inline: Some(body),
                body_file_path: None,
                from_cache: false,
                cost_ms: 0,
                error_kind: None,
                error: None,
            }),
        }
    }

    async fn read_response_body(
        &self,
        response: reqwest::Response,
        spec: &RequestSpec,
        cancel_token: &CancellationToken,
        threshold: usize,
    ) -> Result<ResponseBodyStorage, NetError> {
        // 根据请求参数和 content-length 决定是否直接落盘。
        let should_stream_to_file =
            Self::should_stream_to_file(spec, response.content_length(), threshold);
        let mut stream = response.bytes_stream();
        let mut inline_body = Vec::new();
        let mut file_state: Option<(String, tokio::fs::File)> = None;

        if should_stream_to_file {
            let path = self.response_output_path(spec);
            let file = Self::open_output_file(&path).await?;
            file_state = Some((path, file));
        }

        while let Some(chunk) = tokio::select! {
            c = stream.next() => c,
            _ = cancel_token.cancelled() => {
                return Err(NetError::Canceled(spec.request_id.clone()));
            }
        } {
            let chunk = chunk.map_err(NetError::from_reqwest)?;

            if let Some((_, file)) = file_state.as_mut() {
                // 已进入落盘模式就持续写文件。
                file.write_all(&chunk).await.map_err(NetError::Io)?;
                continue;
            }

            if inline_body.len().saturating_add(chunk.len()) >= threshold {
                // 达到阈值后从内存切到文件并迁移已有数据。
                let path = self.response_output_path(spec);
                let mut file = Self::open_output_file(&path).await?;
                if !inline_body.is_empty() {
                    file.write_all(&inline_body).await.map_err(NetError::Io)?;
                    inline_body.clear();
                }
                file.write_all(&chunk).await.map_err(NetError::Io)?;
                file_state = Some((path, file));
            } else {
                inline_body.extend_from_slice(&chunk);
            }
        }

        if let Some((path, mut file)) = file_state {
            file.flush().await.map_err(NetError::Io)?;
            Ok(ResponseBodyStorage::File(path))
        } else {
            Ok(ResponseBodyStorage::Inline(inline_body))
        }
    }

    fn should_stream_to_file(
        spec: &RequestSpec,
        content_length: Option<u64>,
        threshold: usize,
    ) -> bool {
        // 显式大响应或指定目标文件时，强制落盘。
        if spec.expect_large_response || spec.save_to_file_path.is_some() {
            return true;
        }

        content_length
            .map(|len| len as usize >= threshold)
            .unwrap_or(false)
    }

    fn response_output_path(&self, spec: &RequestSpec) -> String {
        // save_to_file_path 优先，否则默认用 request_id 命名。
        if let Some(path) = &spec.save_to_file_path {
            return path.clone();
        }

        if self.config.cache_dir.trim().is_empty() {
            format!("{}.bin", spec.request_id)
        } else {
            self.default_materialized_response_dir()
                .join(format!("{}.bin", spec.request_id))
                .to_string_lossy()
                .into_owned()
        }
    }

    fn default_materialized_response_dir(&self) -> PathBuf {
        let cache_dir = Path::new(&self.config.cache_dir);
        if let Some(file_name) = cache_dir.file_name() {
            let mut sibling_name = file_name.to_os_string();
            sibling_name.push(MATERIALIZED_RESPONSE_DIR_SUFFIX);
            return cache_dir.with_file_name(sibling_name);
        }
        cache_dir.join(DEFAULT_MATERIALIZED_RESPONSE_DIR_NAME)
    }

    fn url_with_query(url: &str, query: &[(String, String)]) -> String {
        if query.is_empty() {
            return url.to_owned();
        }

        let Ok(mut parsed) = reqwest::Url::parse(url) else {
            return url.to_owned();
        };
        parsed.query_pairs_mut().extend_pairs(
            query
                .iter()
                .map(|(key, value)| (key.as_str(), value.as_str())),
        );
        parsed.to_string()
    }

    fn request_write_timeout(spec: &RequestSpec, write_timeout_ms: u32) -> Option<Duration> {
        if spec.body_bytes.is_none() && spec.body_file_path.is_none() {
            return None;
        }
        Self::write_timeout_duration(write_timeout_ms)
    }

    async fn materialize_cached_response(
        &self,
        spec: &RequestSpec,
        cached: CacheLookup,
    ) -> Result<ResponseMeta, NetError> {
        // 读取缓存时沿用相同阈值策略，保证输出行为一致。
        let threshold = self.config.large_body_threshold_kb as usize * 1024;
        let should_use_file = Self::should_stream_to_file(spec, Some(cached.body_size), threshold);

        if should_use_file {
            let output_path = self.response_output_path(spec);
            Self::ensure_parent_dir(&output_path).await?;
            tokio::fs::copy(&cached.body_path, &output_path)
                .await
                .map_err(NetError::Io)?;
            return Ok(ResponseMeta {
                request_id: spec.request_id.clone(),
                status_code: cached.status_code,
                headers: cached.headers,
                body_inline: None,
                body_file_path: Some(output_path),
                from_cache: true,
                cost_ms: 0,
                error_kind: None,
                error: None,
            });
        }

        let body = tokio::fs::read(&cached.body_path)
            .await
            .map_err(NetError::Io)?;
        Ok(ResponseMeta {
            request_id: spec.request_id.clone(),
            status_code: cached.status_code,
            headers: cached.headers,
            body_inline: Some(body),
            body_file_path: None,
            from_cache: true,
            cost_ms: 0,
            error_kind: None,
            error: None,
        })
    }

    fn apply_conditional_cache_headers(
        mut builder: RequestBuilder,
        cached: &CacheLookup,
    ) -> Result<RequestBuilder, NetError> {
        // 基于缓存元信息追加条件请求头。
        if let Some(etag) = cached.etag.as_deref() {
            let value = HeaderValue::from_str(etag).map_err(|e| {
                NetError::Parse(format!(
                    "invalid if-none-match value for cache key `{}`: {e}",
                    cached.key
                ))
            })?;
            builder = builder.header(IF_NONE_MATCH, value);
        }

        if let Some(last_modified) = cached.last_modified.as_deref() {
            let value = HeaderValue::from_str(last_modified).map_err(|e| {
                NetError::Parse(format!(
                    "invalid if-modified-since value for cache key `{}`: {e}",
                    cached.key
                ))
            })?;
            builder = builder.header(IF_MODIFIED_SINCE, value);
        }

        Ok(builder)
    }

    async fn maybe_store_response_cache(
        &self,
        spec: &RequestSpec,
        method: &str,
        url: &str,
        status_code: u16,
        headers: &[(String, String)],
        cache_key: Option<&str>,
        body_storage: &ResponseBodyStorage,
    ) {
        // 非 GET、非 200、显式禁用缓存时都跳过存储。
        let Some(cache) = self.disk_cache.as_ref() else {
            return;
        };
        let Some(key) = cache_key else {
            return;
        };
        if !method.eq_ignore_ascii_case("GET") {
            return;
        }
        if status_code != StatusCode::OK.as_u16() {
            return;
        }
        if DiskCache::request_disables_cache(&spec.headers) {
            return;
        }

        let body = match body_storage {
            ResponseBodyStorage::Inline(bytes) => CacheBodySource::Bytes(bytes),
            ResponseBodyStorage::File(path) => CacheBodySource::FilePath(Path::new(path)),
        };

        if let Err(error) = cache
            .store(
                &self.response_cache_namespace,
                key,
                method,
                url,
                status_code,
                headers,
                body,
            )
            .await
        {
            tracing::warn!(
                request_id = %spec.request_id,
                cache_key = %key,
                error = %error,
                "cache store failed"
            );
        }
    }
}
