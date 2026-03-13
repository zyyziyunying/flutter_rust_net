use std::sync::atomic::Ordering;

use super::NetEngine;
use crate::api::NetEvent;

impl NetEngine {
    pub async fn poll_events(&self, limit: u32) -> anyhow::Result<Vec<NetEvent>> {
        // 拉取并清空事件队列中的前 N 条。
        Ok(self.event_bus.drain(limit).await)
    }

    pub async fn cancel(&self, id: String) -> anyhow::Result<bool> {
        // 从 token 表中移除后再触发取消。
        let token = {
            let mut tokens = self.cancel_tokens.lock().await;
            tokens.remove(&id)
        };
        if let Some(token) = token {
            token.cancel();
            Ok(true)
        } else {
            Ok(false)
        }
    }

    pub async fn set_network_busy(&self, is_busy: bool) -> anyhow::Result<()> {
        // busy 状态会透传给调度器做限流。
        self.is_busy.store(is_busy, Ordering::Relaxed);
        self.scheduler.set_busy(is_busy);
        Ok(())
    }

    pub async fn clear_cache(&self, namespace: Option<String>) -> anyhow::Result<u64> {
        // 没有磁盘缓存配置时直接返回 0。
        let Some(cache) = self.disk_cache.as_ref() else {
            return Ok(0);
        };

        let namespace = namespace.and_then(|raw| {
            let trimmed = raw.trim().to_owned();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed)
            }
        });

        cache.clear(namespace).await
    }

    pub async fn shutdown(&self) -> anyhow::Result<()> {
        // 取消所有进行中的任务并清空 token 表。
        let mut tokens = self.cancel_tokens.lock().await;
        for token in tokens.values() {
            token.cancel();
        }
        tokens.clear();
        Ok(())
    }
}
