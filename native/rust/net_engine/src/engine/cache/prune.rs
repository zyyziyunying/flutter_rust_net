//! Namespace pruning and LRU-like eviction helpers.

use std::path::{Path, PathBuf};

use super::{key, now_millis, DiskCache, BODY_SUFFIX};

#[derive(Clone, Debug)]
struct NamespaceEntry {
    key: String,
    meta_path: PathBuf,
    body_path: PathBuf,
    body_size: u64,
    last_access_at_ms: u64,
    expires_at_ms: u64,
    has_validator: bool,
}

impl DiskCache {
    pub(super) async fn prune_namespace(&self, namespace_dir: &Path) -> anyhow::Result<()> {
        let mut entries = Vec::new();
        let mut total_bytes = 0_u64;
        let now_ms = now_millis();

        let mut dir_entries = match tokio::fs::read_dir(namespace_dir).await {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
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
                key: meta.key,
                meta_path: path,
                body_path,
                body_size: body_metadata.len(),
                last_access_at_ms: meta.last_access_at_ms,
                expires_at_ms: meta.expires_at_ms,
                has_validator: meta.etag.is_some() || meta.last_modified.is_some(),
            };

            if entry.expires_at_ms <= now_ms && !entry.has_validator {
                Self::remove_entry_files(&entry.meta_path, &entry.body_path).await?;
                continue;
            }

            total_bytes = total_bytes.saturating_add(entry.body_size);
            entries.push(entry);
        }

        if total_bytes <= self.max_namespace_bytes {
            return Ok(());
        }

        entries.sort_by(|left, right| {
            left.last_access_at_ms
                .cmp(&right.last_access_at_ms)
                .then_with(|| left.key.cmp(&right.key))
        });

        for entry in entries {
            if total_bytes <= self.max_namespace_bytes {
                break;
            }
            Self::remove_entry_files(&entry.meta_path, &entry.body_path).await?;
            total_bytes = total_bytes.saturating_sub(entry.body_size);
        }

        Ok(())
    }
}
