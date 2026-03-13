use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::Semaphore;

/// 并发调度器：控制最大并发数，支持繁忙模式降级
#[derive(Clone)]
pub struct Scheduler {
    semaphore: Arc<Semaphore>,
    max_permits: u16,
    is_busy: Arc<AtomicBool>,
}

impl Scheduler {
    pub fn new(max_in_flight: u16) -> Self {
        Self {
            semaphore: Arc::new(Semaphore::new(max_in_flight as usize)),
            max_permits: max_in_flight,
            is_busy: Arc::new(AtomicBool::new(false)),
        }
    }

    /// 获取执行许可，高优先级（0）不受繁忙模式限制
    pub async fn acquire(&self, priority: u8) -> anyhow::Result<tokio::sync::SemaphorePermit<'_>> {
        // 繁忙模式下，低优先级任务额外等待
        if self.is_busy.load(Ordering::Relaxed) && priority > 0 {
            tokio::time::sleep(std::time::Duration::from_millis(50 * priority as u64)).await;
        }

        let permit = self
            .semaphore
            .acquire()
            .await
            .map_err(|e| anyhow::anyhow!("scheduler closed: {}", e))?;
        Ok(permit)
    }

    pub fn set_busy(&self, busy: bool) {
        self.is_busy.store(busy, Ordering::Relaxed);
    }

    pub fn max_permits(&self) -> u16 {
        self.max_permits
    }
}
