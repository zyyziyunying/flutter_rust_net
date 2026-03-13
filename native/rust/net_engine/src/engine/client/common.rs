use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use reqwest::header::{HeaderName, HeaderValue};
use reqwest::RequestBuilder;
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

use super::NetEngine;
use crate::engine::error::NetError;

impl NetEngine {
    pub(super) async fn open_output_file(path: &str) -> Result<tokio::fs::File, NetError> {
        // 统一确保父目录存在。
        Self::ensure_parent_dir(path).await?;
        tokio::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(path)
            .await
            .map_err(NetError::Io)
    }

    pub(super) async fn ensure_parent_dir(path: &str) -> Result<(), NetError> {
        // 路径有父目录时才创建。
        if let Some(parent) = Path::new(path).parent() {
            if !parent.as_os_str().is_empty() {
                tokio::fs::create_dir_all(parent)
                    .await
                    .map_err(NetError::Io)?;
            }
        }
        Ok(())
    }

    pub(super) async fn send_with_cancel(
        builder: RequestBuilder,
        cancel_token: &CancellationToken,
        cancel_id: &str,
        timeout: Option<Duration>,
    ) -> Result<reqwest::Response, NetError> {
        // 请求发送与取消信号并发等待。
        let request_future = async move {
            match timeout {
                Some(limit) => match tokio::time::timeout(limit, builder.send()).await {
                    Ok(resp) => resp.map_err(NetError::from_reqwest),
                    Err(_) => Err(NetError::Timeout(format!(
                        "write timeout while sending request after {}ms",
                        limit.as_millis()
                    ))),
                },
                None => builder.send().await.map_err(NetError::from_reqwest),
            }
        };

        tokio::select! {
            resp = request_future => resp,
            _ = cancel_token.cancelled() => Err(NetError::Canceled(cancel_id.to_owned())),
        }
    }

    pub(super) fn apply_headers(
        mut builder: RequestBuilder,
        headers: &[(String, String)],
    ) -> Result<RequestBuilder, NetError> {
        // 逐条校验并附加 header。
        for (name, value) in headers {
            let header_name = HeaderName::from_bytes(name.as_bytes())
                .map_err(|e| NetError::Parse(format!("invalid header name `{name}`: {e}")))?;
            let header_value = HeaderValue::from_str(value)
                .map_err(|e| NetError::Parse(format!("invalid header value for `{name}`: {e}")))?;
            builder = builder.header(header_name, header_value);
        }
        Ok(builder)
    }

    pub(super) async fn remove_cancel_token(
        cancel_tokens: &Arc<Mutex<HashMap<String, CancellationToken>>>,
        id: &str,
    ) {
        // 请求结束后清理 token，避免泄漏。
        let mut tokens = cancel_tokens.lock().await;
        tokens.remove(id);
    }
}
