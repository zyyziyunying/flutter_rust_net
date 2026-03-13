use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use crate::api::NetEvent;

const DEFAULT_EVENT_BUFFER_CAPACITY: usize = 1024;

/// 可 clone 的发送端，供 spawn 出去的任务使用
#[derive(Clone)]
pub struct EventBusSender {
    queue: Arc<Mutex<VecDeque<NetEvent>>>,
    capacity: usize,
}

impl EventBusSender {
    pub fn emit(&self, event: NetEvent) {
        push_with_drop_oldest(&self.queue, self.capacity, event);
    }
}

/// 事件总线：Rust 内部各模块通过 sender 发送事件，Flutter 侧通过 poll_events 消费
pub struct EventBus {
    queue: Arc<Mutex<VecDeque<NetEvent>>>,
    capacity: usize,
}

impl EventBus {
    pub fn new() -> Self {
        Self::with_capacity(DEFAULT_EVENT_BUFFER_CAPACITY)
    }

    fn with_capacity(capacity: usize) -> Self {
        Self {
            queue: Arc::new(Mutex::new(VecDeque::with_capacity(capacity))),
            capacity: capacity.max(1),
        }
    }

    /// 获取可 clone 的发送端
    pub fn clone_sender(&self) -> EventBusSender {
        EventBusSender {
            queue: self.queue.clone(),
            capacity: self.capacity,
        }
    }

    /// 发送事件（非阻塞）
    pub fn emit(&self, event: NetEvent) {
        push_with_drop_oldest(&self.queue, self.capacity, event);
    }

    /// 批量取出事件，最多 limit 条
    pub async fn drain(&self, limit: u32) -> Vec<NetEvent> {
        if limit == 0 {
            return Vec::new();
        }

        let mut events = Vec::with_capacity(limit as usize);
        with_queue(&self.queue, |queue| {
            for _ in 0..limit {
                match queue.pop_front() {
                    Some(event) => events.push(event),
                    None => break,
                }
            }
        });
        events
    }
}

fn push_with_drop_oldest(queue: &Arc<Mutex<VecDeque<NetEvent>>>, capacity: usize, event: NetEvent) {
    with_queue(queue, |events| {
        if events.len() >= capacity {
            events.pop_front();
        }
        events.push_back(event);
    });
}

fn with_queue<T>(
    queue: &Arc<Mutex<VecDeque<NetEvent>>>,
    f: impl FnOnce(&mut VecDeque<NetEvent>) -> T,
) -> T {
    match queue.lock() {
        Ok(mut guard) => f(&mut guard),
        Err(poisoned) => {
            let mut guard = poisoned.into_inner();
            f(&mut guard)
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::api::{NetEvent, NetEventKind};

    use super::EventBus;

    fn mock_event(id: &str) -> NetEvent {
        NetEvent {
            id: id.to_owned(),
            kind: NetEventKind::Progress,
            transferred: 0,
            total: None,
            status_code: None,
            message: None,
            cost_ms: None,
        }
    }

    #[tokio::test]
    async fn drops_oldest_when_buffer_is_full() {
        let bus = EventBus::with_capacity(2);
        bus.emit(mock_event("1"));
        bus.emit(mock_event("2"));
        bus.emit(mock_event("3"));

        let drained = bus.drain(10).await;
        let ids: Vec<String> = drained.into_iter().map(|event| event.id).collect();

        assert_eq!(ids, vec!["2", "3"]);
    }

    #[tokio::test]
    async fn drain_respects_limit() {
        let bus = EventBus::with_capacity(4);
        bus.emit(mock_event("1"));
        bus.emit(mock_event("2"));
        bus.emit(mock_event("3"));

        let drained = bus.drain(2).await;
        let ids: Vec<String> = drained.into_iter().map(|event| event.id).collect();
        assert_eq!(ids, vec!["1", "2"]);

        let remaining = bus.drain(10).await;
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].id, "3");
    }
}
