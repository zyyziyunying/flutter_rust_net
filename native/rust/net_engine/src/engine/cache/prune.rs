//! Namespace pruning and LRU-like eviction helpers.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use super::{key, now_millis, DiskCache, BODY_SUFFIX, META_SUFFIX};

#[derive(Clone, Debug)]
struct NamespaceEntry {
    namespace: String,
    key: String,
    meta_path: PathBuf,
    body_path: PathBuf,
    budget_bytes: u64,
    last_access_at_ms: u64,
    expires_at_ms: u64,
    has_validator: bool,
}

impl DiskCache {
    pub(super) async fn prune_namespace(&self, namespace_dir: &Path) -> anyhow::Result<()> {
        let namespace = namespace_dir
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default();
        let (entries, total_bytes) =
            Self::collect_namespace_entries(namespace_dir, namespace).await?;
        self.prune_entries(entries, total_bytes, self.max_namespace_bytes)
            .await
    }

    pub(crate) async fn prune_root(&self) -> anyhow::Result<()> {
        let _root_budget_guard = self.lock_root_budget().await;
        self.prune_root_inner().await
    }

    pub(super) async fn prune_root_inner(&self) -> anyhow::Result<()> {
        let Some(max_root_bytes) = self.max_root_bytes else {
            return Ok(());
        };

        let mut entries = Vec::new();
        let mut total_bytes = 0_u64;

        let mut dir_entries = match tokio::fs::read_dir(&self.root_dir).await {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(error) => return Err(error.into()),
        };

        while let Some(entry) = dir_entries.next_entry().await? {
            let path = entry.path();
            let file_type = entry.file_type().await?;
            if !file_type.is_dir() {
                Self::remove_residual_path(&path).await?;
                continue;
            }
            let namespace = entry.file_name().to_string_lossy().into_owned();
            let (mut namespace_entries, namespace_total_bytes) =
                Self::collect_root_entries(&path, &namespace).await?;
            total_bytes = total_bytes.saturating_add(namespace_total_bytes);
            entries.append(&mut namespace_entries);
        }

        self.prune_entries(entries, total_bytes, max_root_bytes)
            .await
    }

    async fn collect_namespace_entries(
        namespace_dir: &Path,
        namespace: &str,
    ) -> anyhow::Result<(Vec<NamespaceEntry>, u64)> {
        let mut entries = Vec::new();
        let mut total_bytes = 0_u64;
        let now_ms = now_millis();

        let mut dir_entries = match tokio::fs::read_dir(namespace_dir).await {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok((entries, 0)),
            Err(error) => return Err(error.into()),
        };

        while let Some(entry) = dir_entries.next_entry().await? {
            let path = entry.path();
            if !path
                .extension()
                .and_then(|value| value.to_str())
                .map(|value| value.eq_ignore_ascii_case("json"))
                .unwrap_or(false)
            {
                continue;
            }

            let meta = match Self::load_meta(&path).await {
                Ok(meta) => meta,
                Err(_) => {
                    let _ = tokio::fs::remove_file(&path).await;
                    continue;
                }
            };
            let body_path =
                namespace_dir.join(format!("{}{}", key::sanitize_key(&meta.key), BODY_SUFFIX));
            let body_metadata = match tokio::fs::metadata(&body_path).await {
                Ok(metadata) => metadata,
                Err(_) => {
                    let _ = tokio::fs::remove_file(&path).await;
                    continue;
                }
            };

            let entry = NamespaceEntry {
                namespace: namespace.to_owned(),
                key: meta.key,
                meta_path: path,
                body_path,
                budget_bytes: body_metadata.len(),
                last_access_at_ms: meta.last_access_at_ms,
                expires_at_ms: meta.expires_at_ms,
                has_validator: meta.etag.is_some() || meta.last_modified.is_some(),
            };

            if entry.expires_at_ms <= now_ms && !entry.has_validator {
                Self::remove_entry_files(&entry.meta_path, &entry.body_path).await?;
                continue;
            }

            total_bytes = total_bytes.saturating_add(entry.budget_bytes);
            entries.push(entry);
        }

        Ok((entries, total_bytes))
    }

    async fn collect_root_entries(
        namespace_dir: &Path,
        namespace: &str,
    ) -> anyhow::Result<(Vec<NamespaceEntry>, u64)> {
        let mut entries = Vec::new();
        let mut total_bytes = 0_u64;
        let now_ms = now_millis();
        let mut files = BTreeMap::new();

        let mut dir_entries = match tokio::fs::read_dir(namespace_dir).await {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok((entries, 0)),
            Err(error) => return Err(error.into()),
        };

        while let Some(entry) = dir_entries.next_entry().await? {
            let path = entry.path();
            let file_type = entry.file_type().await?;
            if file_type.is_dir() {
                Self::remove_residual_dir(&path).await?;
                continue;
            }
            if !file_type.is_file() {
                Self::remove_residual_path(&path).await?;
                continue;
            }

            let metadata = entry.metadata().await?;
            total_bytes = total_bytes.saturating_add(metadata.len());
            files.insert(path, metadata.len());
        }

        let meta_paths = files
            .keys()
            .filter(|path| Self::is_meta_path(path))
            .cloned()
            .collect::<Vec<_>>();

        for meta_path in meta_paths {
            let Some(meta_size) = files.remove(&meta_path) else {
                continue;
            };

            let meta = match Self::load_meta(&meta_path).await {
                Ok(meta) => meta,
                Err(_) => {
                    Self::remove_residual_path(&meta_path).await?;
                    total_bytes = total_bytes.saturating_sub(meta_size);
                    continue;
                }
            };
            let body_path =
                namespace_dir.join(format!("{}{}", key::sanitize_key(&meta.key), BODY_SUFFIX));
            let Some(body_size) = files.remove(&body_path) else {
                Self::remove_residual_path(&meta_path).await?;
                total_bytes = total_bytes.saturating_sub(meta_size);
                continue;
            };

            let entry = NamespaceEntry {
                namespace: namespace.to_owned(),
                key: meta.key,
                meta_path,
                body_path,
                budget_bytes: meta_size.saturating_add(body_size),
                last_access_at_ms: meta.last_access_at_ms,
                expires_at_ms: meta.expires_at_ms,
                has_validator: meta.etag.is_some() || meta.last_modified.is_some(),
            };

            if entry.expires_at_ms <= now_ms && !entry.has_validator {
                Self::remove_entry_files(&entry.meta_path, &entry.body_path).await?;
                total_bytes = total_bytes.saturating_sub(entry.budget_bytes);
                continue;
            }

            entries.push(entry);
        }

        for (residual_path, residual_size) in files {
            Self::remove_residual_path(&residual_path).await?;
            total_bytes = total_bytes.saturating_sub(residual_size);
        }

        Ok((entries, total_bytes))
    }

    fn is_meta_path(path: &Path) -> bool {
        path.file_name()
            .and_then(|value| value.to_str())
            .map(|value| value.ends_with(META_SUFFIX))
            .unwrap_or(false)
    }

    async fn remove_residual_dir(path: &Path) -> anyhow::Result<()> {
        let _ = Self::clear_dir_contents(path).await?;
        match tokio::fs::remove_dir(path).await {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error.into()),
        }
    }

    async fn remove_residual_path(path: &Path) -> anyhow::Result<()> {
        match tokio::fs::remove_file(path).await {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error.into()),
        }
    }

    async fn prune_entries(
        &self,
        mut entries: Vec<NamespaceEntry>,
        mut total_bytes: u64,
        max_bytes: u64,
    ) -> anyhow::Result<()> {
        if total_bytes <= max_bytes {
            return Ok(());
        }

        entries.sort_by(|left, right| {
            left.last_access_at_ms
                .cmp(&right.last_access_at_ms)
                .then_with(|| left.namespace.cmp(&right.namespace))
                .then_with(|| left.key.cmp(&right.key))
        });

        for entry in entries {
            if total_bytes <= max_bytes {
                break;
            }
            Self::remove_entry_files(&entry.meta_path, &entry.body_path).await?;
            total_bytes = total_bytes.saturating_sub(entry.budget_bytes);
        }

        Ok(())
    }
}
