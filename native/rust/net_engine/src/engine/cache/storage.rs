//! Async filesystem helpers for cache body/meta persistence.

use std::path::Path;

use anyhow::anyhow;
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

use super::{CacheBodySource, CacheEntryMeta, DiskCache};

impl DiskCache {
    pub(super) async fn persist_body(
        path: &Path,
        body: CacheBodySource<'_>,
    ) -> anyhow::Result<u64> {
        match body {
            CacheBodySource::Bytes(bytes) => {
                let mut file = tokio::fs::File::create(path).await?;
                file.write_all(bytes).await?;
                file.flush().await?;
                Ok(bytes.len() as u64)
            }
            CacheBodySource::FilePath(source_path) => {
                let copied = tokio::fs::copy(source_path, path).await?;
                Ok(copied)
            }
        }
    }

    pub(super) async fn replace_file(from_path: &Path, target_path: &Path) -> anyhow::Result<()> {
        if let Some(parent) = target_path.parent() {
            if !parent.as_os_str().is_empty() {
                tokio::fs::create_dir_all(parent).await?;
            }
        }

        if tokio::fs::metadata(target_path).await.is_ok() {
            tokio::fs::remove_file(target_path).await?;
        }
        tokio::fs::rename(from_path, target_path).await?;
        Ok(())
    }

    pub(super) async fn save_meta(path: &Path, meta: &CacheEntryMeta) -> anyhow::Result<()> {
        let payload = serde_json::to_vec_pretty(meta)?;
        let parent = path
            .parent()
            .ok_or_else(|| anyhow!("cache metadata path has no parent"))?;
        let tmp_path = parent.join(format!(
            "{}.{}.tmp",
            path.file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("meta"),
            Uuid::new_v4()
        ));
        tokio::fs::write(&tmp_path, payload).await?;
        Self::replace_file(&tmp_path, path).await
    }

    pub(super) async fn load_meta(path: &Path) -> anyhow::Result<CacheEntryMeta> {
        let payload = tokio::fs::read(path).await?;
        let meta: CacheEntryMeta = serde_json::from_slice(&payload)?;
        Ok(meta)
    }

    pub(super) async fn remove_entry_files(
        meta_path: &Path,
        body_path: &Path,
    ) -> anyhow::Result<()> {
        if tokio::fs::metadata(meta_path).await.is_ok() {
            tokio::fs::remove_file(meta_path).await?;
        }
        if tokio::fs::metadata(body_path).await.is_ok() {
            tokio::fs::remove_file(body_path).await?;
        }
        Ok(())
    }

    pub(super) async fn clear_dir_contents(root: &Path) -> anyhow::Result<u64> {
        let mut removed_bytes = 0_u64;
        let mut stack = vec![root.to_path_buf()];
        let mut dirs_to_remove = Vec::new();

        while let Some(current_dir) = stack.pop() {
            let mut entries = tokio::fs::read_dir(&current_dir).await?;

            while let Some(entry) = entries.next_entry().await? {
                let entry_path = entry.path();
                let file_type = entry.file_type().await?;
                if file_type.is_dir() {
                    stack.push(entry_path.clone());
                    dirs_to_remove.push(entry_path);
                    continue;
                }

                if file_type.is_file() {
                    let metadata = entry.metadata().await?;
                    removed_bytes = removed_bytes.saturating_add(metadata.len());
                }

                tokio::fs::remove_file(&entry_path).await?;
            }
        }

        dirs_to_remove
            .sort_by(|left, right| right.components().count().cmp(&left.components().count()));

        for dir_path in dirs_to_remove {
            match tokio::fs::remove_dir(&dir_path).await {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => return Err(error.into()),
            }
        }

        Ok(removed_bytes)
    }
}
