use std::io::SeekFrom;
use std::time::Instant;

use futures::StreamExt;
use reqwest::header::{HeaderValue, CONTENT_LENGTH, CONTENT_RANGE, RANGE};
use reqwest::{Client, StatusCode};
use tokio::io::{AsyncSeekExt, AsyncWriteExt};
use tokio_util::io::ReaderStream;
use tokio_util::sync::CancellationToken;

use super::{NetEngine, TransferOutcome, TransferWriteMode};
use crate::api::{NetEvent, NetEventKind, TransferTaskSpec};
use crate::engine::error::NetError;
use crate::engine::events::EventBusSender;

impl NetEngine {
    /// 启动下载/上传任务（异步，通过 poll_events 获取进度）
    pub async fn start_transfer_task(&self, spec: TransferTaskSpec) -> anyhow::Result<String> {
        let task_id = spec.task_id.clone();
        let cancel_token = CancellationToken::new();
        {
            let mut tokens = self.cancel_tokens.lock().await;
            if tokens.contains_key(&task_id) {
                return Err(anyhow::anyhow!("transfer task already exists: {task_id}"));
            }
            tokens.insert(task_id.clone(), cancel_token.clone());
        }

        self.event_bus.emit(NetEvent {
            id: task_id.clone(),
            kind: NetEventKind::Queued,
            transferred: 0,
            total: spec.expected_total,
            status_code: None,
            message: None,
            cost_ms: None,
        });

        // 在后台执行，结果通过事件总线回传。
        let client = self.client.clone();
        let event_bus_tx = self.event_bus.clone_sender();
        let scheduler = self.scheduler.clone();
        let connection_limiter = self.connection_limiter.clone();
        let cancel_tokens = self.cancel_tokens.clone();
        let write_timeout_ms = self.config.write_timeout_ms;

        tokio::spawn(async move {
            let _permit = match scheduler.acquire(spec.priority).await {
                Ok(p) => p,
                Err(e) => {
                    event_bus_tx.emit(NetEvent {
                        id: spec.task_id.clone(),
                        kind: NetEventKind::Failed,
                        transferred: 0,
                        total: spec.expected_total,
                        status_code: None,
                        message: Some(e.to_string()),
                        cost_ms: None,
                    });
                    Self::remove_cancel_token(&cancel_tokens, &spec.task_id).await;
                    return;
                }
            };
            let _connection_permit = match connection_limiter.acquire_for_url(&spec.url).await {
                Ok(p) => p,
                Err(e) => {
                    event_bus_tx.emit(NetEvent {
                        id: spec.task_id.clone(),
                        kind: NetEventKind::Failed,
                        transferred: 0,
                        total: spec.expected_total,
                        status_code: None,
                        message: Some(e.to_string()),
                        cost_ms: None,
                    });
                    Self::remove_cancel_token(&cancel_tokens, &spec.task_id).await;
                    return;
                }
            };

            let start = Instant::now();
            event_bus_tx.emit(NetEvent {
                id: spec.task_id.clone(),
                kind: NetEventKind::Started,
                transferred: 0,
                total: spec.expected_total,
                status_code: None,
                message: None,
                cost_ms: None,
            });

            let result = Self::do_transfer(
                &client,
                &spec,
                &cancel_token,
                &event_bus_tx,
                write_timeout_ms,
            )
            .await;
            let cost_ms = start.elapsed().as_millis() as u32;

            match result {
                Ok(outcome) => {
                    event_bus_tx.emit(NetEvent {
                        id: spec.task_id.clone(),
                        kind: NetEventKind::Completed,
                        transferred: outcome.transferred,
                        total: spec.expected_total,
                        status_code: Some(outcome.status_code),
                        message: None,
                        cost_ms: Some(cost_ms),
                    });
                }
                Err(e) => {
                    let kind = if matches!(e, NetError::Canceled(_)) {
                        NetEventKind::Canceled
                    } else {
                        NetEventKind::Failed
                    };
                    let status_code = if let NetError::Http { status, .. } = &e {
                        Some(*status)
                    } else {
                        None
                    };
                    event_bus_tx.emit(NetEvent {
                        id: spec.task_id.clone(),
                        kind,
                        transferred: 0,
                        total: spec.expected_total,
                        status_code,
                        message: Some(e.to_string()),
                        cost_ms: Some(cost_ms),
                    });
                }
            }

            Self::remove_cancel_token(&cancel_tokens, &spec.task_id).await;
        });

        Ok(task_id)
    }

    async fn do_transfer(
        client: &Client,
        spec: &TransferTaskSpec,
        cancel_token: &CancellationToken,
        event_bus: &EventBusSender,
        write_timeout_ms: u32,
    ) -> Result<TransferOutcome, NetError> {
        let transfer_kind = TransferTaskKind::parse(&spec.kind)?;
        let method: reqwest::Method = spec
            .method
            .parse()
            .map_err(|e: http::method::InvalidMethod| NetError::Parse(e.to_string()))?;

        match transfer_kind {
            TransferTaskKind::Download => {
                Self::do_download_transfer(client, spec, method, cancel_token, event_bus).await
            }
            TransferTaskKind::Upload => {
                Self::do_upload_transfer(
                    client,
                    spec,
                    method,
                    cancel_token,
                    event_bus,
                    write_timeout_ms,
                )
                .await
            }
        }
    }

    async fn do_download_transfer(
        client: &Client,
        spec: &TransferTaskSpec,
        method: reqwest::Method,
        cancel_token: &CancellationToken,
        event_bus: &EventBusSender,
    ) -> Result<TransferOutcome, NetError> {
        // 支持续传时先探测可用 offset。
        let resume_from = Self::effective_resume_offset(spec).await;
        let mut response =
            Self::send_transfer_request(client, spec, method.clone(), cancel_token, resume_from)
                .await?;
        let mut write_mode = TransferWriteMode::Overwrite;

        if let Some(offset) = resume_from {
            if Self::is_valid_resume_response(&response, offset) {
                write_mode = TransferWriteMode::Resume(offset);
            } else {
                // 续传协商失败，回退到全量下载。
                tracing::warn!(
                    task_id = %spec.task_id,
                    resume_from = offset,
                    status = %response.status(),
                    "resume validation failed, fallback to full download"
                );
                response =
                    Self::send_transfer_request(client, spec, method, cancel_token, None).await?;
            }
        }

        let status = response.status();
        if !Self::is_transfer_status_allowed(status, write_mode) {
            return Err(NetError::Http {
                status: status.as_u16(),
                message: format!("transfer failed with status {status}"),
            });
        }

        let mut file = Self::open_transfer_target_file(&spec.local_path, write_mode).await?;
        let mut stream = response.bytes_stream();
        let mut transferred = match write_mode {
            TransferWriteMode::Overwrite => 0,
            TransferWriteMode::Resume(offset) => offset,
        };

        while let Some(chunk) = tokio::select! {
            c = stream.next() => c,
            _ = cancel_token.cancelled() => {
                return Err(NetError::Canceled(spec.task_id.clone()));
            }
        } {
            // 每个 chunk 写入后立刻上报进度。
            let chunk = chunk.map_err(NetError::from_reqwest)?;
            file.write_all(&chunk).await.map_err(NetError::Io)?;
            transferred += chunk.len() as u64;

            event_bus.emit(NetEvent {
                id: spec.task_id.clone(),
                kind: NetEventKind::Progress,
                transferred,
                total: spec.expected_total,
                status_code: None,
                message: None,
                cost_ms: None,
            });
        }

        file.flush().await.map_err(NetError::Io)?;
        Ok(TransferOutcome {
            transferred,
            status_code: status.as_u16(),
        })
    }

    async fn do_upload_transfer(
        client: &Client,
        spec: &TransferTaskSpec,
        method: reqwest::Method,
        cancel_token: &CancellationToken,
        event_bus: &EventBusSender,
        write_timeout_ms: u32,
    ) -> Result<TransferOutcome, NetError> {
        let source_file = tokio::fs::File::open(&spec.local_path)
            .await
            .map_err(NetError::Io)?;
        let source_size = source_file.metadata().await.map_err(NetError::Io)?.len();
        let progress_total = spec.expected_total.or(Some(source_size));

        let mut transferred = 0_u64;
        let task_id = spec.task_id.clone();
        let event_bus = event_bus.clone();
        let upload_stream = ReaderStream::new(source_file).map(move |chunk_result| {
            chunk_result.map(|chunk| {
                transferred += chunk.len() as u64;
                event_bus.emit(NetEvent {
                    id: task_id.clone(),
                    kind: NetEventKind::Progress,
                    transferred,
                    total: progress_total,
                    status_code: None,
                    message: None,
                    cost_ms: None,
                });
                chunk
            })
        });

        let mut builder = client.request(method, &spec.url);
        builder = Self::apply_headers(builder, &spec.headers)?;
        if !spec
            .headers
            .iter()
            .any(|(name, _)| name.eq_ignore_ascii_case(CONTENT_LENGTH.as_str()))
        {
            builder = builder.header(CONTENT_LENGTH, source_size);
        }
        builder = builder.body(reqwest::Body::wrap_stream(upload_stream));

        let write_timeout = Self::write_timeout_duration(write_timeout_ms);
        let response =
            Self::send_with_cancel(builder, cancel_token, &spec.task_id, write_timeout).await?;
        let status = response.status();
        if !status.is_success() {
            return Err(NetError::Http {
                status: status.as_u16(),
                message: format!("transfer failed with status {status}"),
            });
        }

        Ok(TransferOutcome {
            transferred: source_size,
            status_code: status.as_u16(),
        })
    }

    async fn effective_resume_offset(spec: &TransferTaskSpec) -> Option<u64> {
        // resume_from 只有 >0 才有意义。
        let resume_from = spec.resume_from.filter(|offset| *offset > 0)?;
        match tokio::fs::metadata(&spec.local_path).await {
            Ok(metadata) if metadata.len() >= resume_from => Some(resume_from),
            Ok(metadata) => {
                tracing::warn!(
                    task_id = %spec.task_id,
                    resume_from,
                    file_len = metadata.len(),
                    "resume offset exceeds local file length, fallback to full download"
                );
                None
            }
            Err(err) => {
                tracing::warn!(
                    task_id = %spec.task_id,
                    resume_from,
                    error = %err,
                    "resume file missing, fallback to full download"
                );
                None
            }
        }
    }

    async fn send_transfer_request(
        client: &Client,
        spec: &TransferTaskSpec,
        method: reqwest::Method,
        cancel_token: &CancellationToken,
        resume_from: Option<u64>,
    ) -> Result<reqwest::Response, NetError> {
        // 续传时附加 Range 头。
        let mut builder = client.request(method, &spec.url);
        builder = Self::apply_headers(builder, &spec.headers)?;

        if let Some(offset) = resume_from {
            let range_value = HeaderValue::from_str(&format!("bytes={offset}-")).map_err(|e| {
                NetError::Parse(format!(
                    "invalid range header value for task `{}`: {}",
                    spec.task_id, e
                ))
            })?;
            builder = builder.header(RANGE, range_value);
        }

        Self::send_with_cancel(builder, cancel_token, &spec.task_id, None).await
    }

    fn is_transfer_status_allowed(status: StatusCode, write_mode: TransferWriteMode) -> bool {
        // 续传必须是 206，全量下载接受 2xx。
        match write_mode {
            TransferWriteMode::Resume(_) => status == StatusCode::PARTIAL_CONTENT,
            TransferWriteMode::Overwrite => status.is_success(),
        }
    }

    fn is_valid_resume_response(response: &reqwest::Response, expected_offset: u64) -> bool {
        // 校验 Content-Range 起始是否匹配预期偏移。
        if response.status() != StatusCode::PARTIAL_CONTENT {
            return false;
        }

        let Some(content_range) = response.headers().get(CONTENT_RANGE) else {
            return false;
        };

        let Ok(content_range) = content_range.to_str() else {
            return false;
        };

        parse_content_range_start(content_range)
            .map(|start| start == expected_offset)
            .unwrap_or(false)
    }

    async fn open_transfer_target_file(
        path: &str,
        write_mode: TransferWriteMode,
    ) -> Result<tokio::fs::File, NetError> {
        // Overwrite 清空文件；Resume 截断并 seek 到偏移。
        Self::ensure_parent_dir(path).await?;

        let mut options = tokio::fs::OpenOptions::new();
        options.create(true).write(true);
        if matches!(write_mode, TransferWriteMode::Overwrite) {
            options.truncate(true);
        }

        let mut file = options.open(path).await.map_err(NetError::Io)?;
        if let TransferWriteMode::Resume(offset) = write_mode {
            file.set_len(offset).await.map_err(NetError::Io)?;
            file.seek(SeekFrom::Start(offset))
                .await
                .map_err(NetError::Io)?;
        }
        Ok(file)
    }
}

pub(super) fn parse_content_range_start(content_range: &str) -> Option<u64> {
    // 示例: bytes 200-1000/67589
    let range = content_range.trim().strip_prefix("bytes ")?;
    let (start_end, _) = range.split_once('/')?;
    let (start, _) = start_end.split_once('-')?;
    start.parse().ok()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TransferTaskKind {
    Download,
    Upload,
}

impl TransferTaskKind {
    fn parse(raw: &str) -> Result<Self, NetError> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "download" => Ok(Self::Download),
            "upload" => Ok(Self::Upload),
            _ => Err(NetError::Parse(format!(
                "unsupported transfer kind `{}`",
                raw
            ))),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::path::{Path, PathBuf};
    use std::time::Duration;

    use reqwest::Client;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;
    use tokio_util::sync::CancellationToken;
    use uuid::Uuid;

    use super::{NetEngine, TransferTaskKind};
    use crate::api::{NetEngineConfig, NetEventKind, TransferTaskSpec};
    use crate::engine::error::NetError;
    use crate::engine::events::EventBus;

    #[test]
    fn parses_transfer_task_kind() {
        assert_eq!(
            TransferTaskKind::parse("download").expect("parse download"),
            TransferTaskKind::Download
        );
        assert_eq!(
            TransferTaskKind::parse("UPLOAD").expect("parse upload"),
            TransferTaskKind::Upload
        );
        assert!(matches!(
            TransferTaskKind::parse("sync"),
            Err(NetError::Parse(_))
        ));
    }

    #[tokio::test]
    async fn start_transfer_task_rejects_duplicate_task_ids() {
        let (url, server_handle) =
            spawn_download_server_with_delay("200 OK", b"ok", Duration::from_millis(200)).await;
        let target_path = create_temp_file_path("duplicate_download");
        let engine = NetEngine::new(NetEngineConfig::default()).expect("create net engine");
        let spec = build_download_spec("duplicate-task", &url, &target_path);

        let task_id = engine
            .start_transfer_task(spec.clone())
            .await
            .expect("start first transfer task");
        let error = engine
            .start_transfer_task(spec)
            .await
            .expect_err("duplicate task id should be rejected");

        assert_eq!(task_id, "duplicate-task");
        assert!(error
            .to_string()
            .contains("transfer task already exists: duplicate-task"));

        engine.shutdown().await.expect("shutdown engine");
        server_handle
            .await
            .expect("download server task should join");
        let _ = tokio::fs::remove_file(&target_path).await;
    }

    #[tokio::test]
    async fn upload_transfer_reports_progress_and_success() {
        let (url, server_handle) = spawn_upload_server("201 Created").await;
        let payload = vec![0x3F_u8; 4096];
        let source_path = create_temp_file_path("upload_success");
        tokio::fs::write(&source_path, &payload)
            .await
            .expect("write upload source");

        let event_bus = EventBus::new();
        let spec = build_upload_spec(&url, &source_path);
        let outcome = NetEngine::do_transfer(
            &Client::new(),
            &spec,
            &CancellationToken::new(),
            &event_bus.clone_sender(),
            30_000,
        )
        .await
        .expect("upload should succeed");

        let uploaded_body = server_handle.await.expect("upload server task should join");
        assert_eq!(uploaded_body, payload);
        assert_eq!(outcome.transferred, payload.len() as u64);
        assert_eq!(outcome.status_code, 201);

        let events = event_bus.drain(32).await;
        let progress: Vec<_> = events
            .into_iter()
            .filter(|event| matches!(event.kind, NetEventKind::Progress))
            .collect();
        assert!(!progress.is_empty());
        assert_eq!(progress.last().expect("has progress").transferred, 4096);
        assert_eq!(
            progress.last().expect("has progress").total,
            Some(payload.len() as u64)
        );

        tokio::fs::remove_file(&source_path)
            .await
            .expect("cleanup upload source");
    }

    #[tokio::test]
    async fn upload_transfer_returns_io_when_source_file_missing() {
        let missing_path = create_temp_file_path("upload_missing");
        let event_bus = EventBus::new();
        let spec = build_upload_spec("http://127.0.0.1:18080/upload", &missing_path);

        let result = NetEngine::do_transfer(
            &Client::new(),
            &spec,
            &CancellationToken::new(),
            &event_bus.clone_sender(),
            30_000,
        )
        .await;

        assert!(matches!(result, Err(NetError::Io(_))));
    }

    #[tokio::test]
    async fn upload_transfer_returns_http_error_on_non_2xx() {
        let (url, server_handle) = spawn_upload_server("503 Service Unavailable").await;
        let source_path = create_temp_file_path("upload_http_error");
        tokio::fs::write(&source_path, vec![0x7B_u8; 256])
            .await
            .expect("write upload source");
        let event_bus = EventBus::new();
        let spec = build_upload_spec(&url, &source_path);

        let result = NetEngine::do_transfer(
            &Client::new(),
            &spec,
            &CancellationToken::new(),
            &event_bus.clone_sender(),
            30_000,
        )
        .await;

        assert!(matches!(result, Err(NetError::Http { status: 503, .. })));
        server_handle.await.expect("upload server task should join");

        tokio::fs::remove_file(&source_path)
            .await
            .expect("cleanup upload source");
    }

    #[tokio::test]
    async fn upload_transfer_honors_cancel_signal() {
        let source_path = create_temp_file_path("upload_canceled");
        tokio::fs::write(&source_path, vec![0x1_u8; 1024])
            .await
            .expect("write upload source");
        let event_bus = EventBus::new();
        let spec = build_upload_spec("http://127.0.0.1:18080/upload", &source_path);
        let cancel_token = CancellationToken::new();
        cancel_token.cancel();

        let result = NetEngine::do_transfer(
            &Client::new(),
            &spec,
            &cancel_token,
            &event_bus.clone_sender(),
            30_000,
        )
        .await;

        assert!(matches!(result, Err(NetError::Canceled(_))));
        tokio::fs::remove_file(&source_path)
            .await
            .expect("cleanup upload source");
    }

    #[tokio::test]
    async fn upload_transfer_honors_write_timeout() {
        let (url, server_handle) =
            spawn_upload_server_with_delay("201 Created", Duration::from_millis(200)).await;
        let source_path = create_temp_file_path("upload_write_timeout");
        tokio::fs::write(&source_path, vec![0x2_u8; 256])
            .await
            .expect("write upload source");
        let event_bus = EventBus::new();
        let spec = build_upload_spec(&url, &source_path);

        let result = NetEngine::do_transfer(
            &Client::new(),
            &spec,
            &CancellationToken::new(),
            &event_bus.clone_sender(),
            20,
        )
        .await;

        assert!(matches!(result, Err(NetError::Timeout(_))));
        server_handle.await.expect("upload server task should join");
        tokio::fs::remove_file(&source_path)
            .await
            .expect("cleanup upload source");
    }

    fn build_upload_spec(url: &str, local_path: &Path) -> TransferTaskSpec {
        TransferTaskSpec {
            task_id: format!("upload_{}", Uuid::new_v4()),
            kind: "upload".to_owned(),
            url: url.to_owned(),
            method: "POST".to_owned(),
            headers: vec![("x-test".to_owned(), "upload".to_owned())],
            local_path: local_path.to_string_lossy().into_owned(),
            resume_from: None,
            expected_total: None,
            priority: 0,
        }
    }

    fn build_download_spec(task_id: &str, url: &str, local_path: &Path) -> TransferTaskSpec {
        TransferTaskSpec {
            task_id: task_id.to_owned(),
            kind: "download".to_owned(),
            url: url.to_owned(),
            method: "GET".to_owned(),
            headers: vec![],
            local_path: local_path.to_string_lossy().into_owned(),
            resume_from: None,
            expected_total: None,
            priority: 0,
        }
    }

    fn create_temp_file_path(label: &str) -> PathBuf {
        std::env::temp_dir().join(format!("net_engine_transfer_{label}_{}", Uuid::new_v4()))
    }

    async fn spawn_upload_server(status_line: &str) -> (String, tokio::task::JoinHandle<Vec<u8>>) {
        spawn_upload_server_with_delay(status_line, Duration::from_millis(0)).await
    }

    async fn spawn_upload_server_with_delay(
        status_line: &str,
        response_delay: Duration,
    ) -> (String, tokio::task::JoinHandle<Vec<u8>>) {
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind upload server");
        let addr = listener.local_addr().expect("server local addr");
        let response =
            format!("HTTP/1.1 {status_line}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");

        let handle = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.expect("accept upload connection");
            let mut request = Vec::new();
            let mut buf = [0_u8; 2048];
            let header_end = loop {
                let read = stream.read(&mut buf).await.expect("read request bytes");
                assert!(read > 0, "connection closed before request headers");
                request.extend_from_slice(&buf[..read]);
                if let Some(index) = find_header_end(&request) {
                    break index;
                }
            };

            let headers_raw = String::from_utf8_lossy(&request[..header_end]).to_string();
            let content_length = parse_content_length(&headers_raw).unwrap_or(0);
            let mut body = request[(header_end + 4)..].to_vec();
            while body.len() < content_length {
                let read = stream.read(&mut buf).await.expect("read request body");
                if read == 0 {
                    break;
                }
                body.extend_from_slice(&buf[..read]);
            }

            tokio::time::sleep(response_delay).await;
            stream
                .write_all(response.as_bytes())
                .await
                .expect("write response");
            body
        });

        (format!("http://{addr}/upload"), handle)
    }

    async fn spawn_download_server_with_delay(
        status_line: &str,
        body: &[u8],
        response_delay: Duration,
    ) -> (String, tokio::task::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind download server");
        let addr = listener.local_addr().expect("server local addr");
        let status_line = status_line.to_owned();
        let body = body.to_vec();

        let handle = tokio::spawn(async move {
            let accept_result =
                tokio::time::timeout(Duration::from_secs(1), listener.accept()).await;
            let Ok(Ok((mut stream, _))) = accept_result else {
                return;
            };
            let mut request = Vec::new();
            let mut buf = [0_u8; 2048];
            loop {
                let read = stream.read(&mut buf).await.expect("read request bytes");
                if read == 0 {
                    // The duplicate-id regression only cares that the second start is rejected.
                    // During shutdown, the first transfer may be canceled before headers finish sending.
                    return;
                }
                request.extend_from_slice(&buf[..read]);
                if find_header_end(&request).is_some() {
                    break;
                }
            }

            tokio::time::sleep(response_delay).await;
            let response = format!(
                "HTTP/1.1 {status_line}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                body.len()
            );
            let _ = stream.write_all(response.as_bytes()).await;
            let _ = stream.write_all(&body).await;
        });

        (format!("http://{addr}/download"), handle)
    }

    fn find_header_end(payload: &[u8]) -> Option<usize> {
        payload.windows(4).position(|window| window == b"\r\n\r\n")
    }

    fn parse_content_length(headers_raw: &str) -> Option<usize> {
        for line in headers_raw.lines() {
            if let Some((name, value)) = line.split_once(':') {
                if name.trim().eq_ignore_ascii_case("content-length") {
                    return value.trim().parse::<usize>().ok();
                }
            }
        }
        None
    }
}
