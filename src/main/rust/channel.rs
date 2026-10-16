//! Typed Channels with Affine Move Semantics for Mutable Types.
//! Implements Section 5 of `docs/etc/next_gen_architecture.md`.

use std::collections::VecDeque;
use crate::vm::Value;

/// Result of attempting to send a value through a `Channel`.
#[derive(Debug, Clone, PartialEq)]
pub enum SendStatus {
    Sent,
    WouldBlock,
    Closed,
}

/// Result of attempting to receive a value from a `Channel`.
#[derive(Debug, Clone, PartialEq)]
pub enum RecvStatus {
    Received(Value),
    Empty,
    Closed,
}

/// A structured MPMC channel supporting bounded backpressure and affine moves.
#[derive(Debug, Clone)]
pub struct Channel {
    pub id: usize,
    capacity: Option<usize>,
    queue: VecDeque<Value>,
    waiting_receivers: VecDeque<usize>,
    waiting_senders: VecDeque<(usize, Value)>,
    closed: bool,
    moved_transfers: usize,
}

impl Channel {
    /// Create an unbounded `Channel`.
    pub fn unbounded(id: usize) -> Self {
        Channel {
            id,
            capacity: None,
            queue: VecDeque::new(),
            waiting_receivers: VecDeque::new(),
            waiting_senders: VecDeque::new(),
            closed: false,
            moved_transfers: 0,
        }
    }

    /// Create a bounded `Channel` with backpressure capacity `cap`.
    pub fn bounded(id: usize, cap: usize) -> Self {
        Channel {
            id,
            capacity: Some(cap.max(1)),
            queue: VecDeque::new(),
            waiting_receivers: VecDeque::new(),
            waiting_senders: VecDeque::new(),
            closed: false,
            moved_transfers: 0,
        }
    }

    /// Number of buffered messages currently in the channel.
    pub fn buffered_count(&self) -> usize {
        self.queue.len()
    }

    /// Number of zero-copy affine moves of mutable values (`Tensor`) performed.
    pub fn affine_move_count(&self) -> usize {
        self.moved_transfers
    }

    /// Return true if the channel has been closed.
    pub fn is_closed(&self) -> bool {
        self.closed
    }

    /// Send a value through the channel. If a bounded channel is full, records
    /// `sender_tid` in `waiting_senders` and returns `SendStatus::WouldBlock`.
    pub fn send(&mut self, sender_tid: usize, value: Value) -> SendStatus {
        if self.closed {
            return SendStatus::Closed;
        }
        if matches!(value, Value::Tensor(_, _)) {
            self.moved_transfers += 1;
        }
        if let Some(cap) = self.capacity {
            if self.queue.len() >= cap {
                self.waiting_senders.push_back((sender_tid, value));
                return SendStatus::WouldBlock;
            }
        }
        self.queue.push_back(value);
        SendStatus::Sent
    }

    /// Receive a value from the channel. If empty and open, parks `receiver_tid`.
    pub fn recv(&mut self, receiver_tid: usize) -> (RecvStatus, Option<usize>) {
        if let Some(val) = self.queue.pop_front() {
            let unblocked_sender = self.promote_waiting_sender();
            return (RecvStatus::Received(val), unblocked_sender);
        }
        if self.closed {
            return (RecvStatus::Closed, None);
        }
        if !self.waiting_receivers.contains(&receiver_tid) {
            self.waiting_receivers.push_back(receiver_tid);
        }
        (RecvStatus::Empty, None)
    }

    /// Non-blocking receive (`try receive from ch`) returning `Option a`.
    pub fn try_recv(&mut self) -> (Option<Value>, Option<usize>) {
        if let Some(val) = self.queue.pop_front() {
            let unblocked_sender = self.promote_waiting_sender();
            (Some(val), unblocked_sender)
        } else {
            (None, None)
        }
    }

    /// Pop the next waiting receiver thread ID when a new message arrives.
    pub fn pop_waiting_receiver(&mut self) -> Option<usize> {
        self.waiting_receivers.pop_front()
    }

    /// Close the channel and return all waiting receiver thread IDs to wake them.
    pub fn close(&mut self) -> Vec<usize> {
        self.closed = true;
        self.waiting_receivers.drain(..).collect()
    }

    fn promote_waiting_sender(&mut self) -> Option<usize> {
        if let Some((sender_tid, pending_val)) = self.waiting_senders.pop_front() {
            self.queue.push_back(pending_val);
            Some(sender_tid)
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_unbounded_channel_send_recv() {
        let mut ch = Channel::unbounded(0);
        assert_eq!(ch.send(1, Value::Int(10)), SendStatus::Sent);
        assert_eq!(ch.send(1, Value::Int(20)), SendStatus::Sent);
        assert_eq!(ch.buffered_count(), 2);

        let (r1, _) = ch.recv(2);
        let (r2, _) = ch.recv(2);
        assert_eq!(r1, RecvStatus::Received(Value::Int(10)));
        assert_eq!(r2, RecvStatus::Received(Value::Int(20)));
    }

    #[test]
    fn test_bounded_channel_backpressure() {
        let mut ch = Channel::bounded(1, 1);
        assert_eq!(ch.send(10, Value::Int(1)), SendStatus::Sent);
        assert_eq!(ch.send(11, Value::Int(2)), SendStatus::WouldBlock);

        let (first, unblocked) = ch.recv(20);
        assert_eq!(first, RecvStatus::Received(Value::Int(1)));
        assert_eq!(unblocked, Some(11));

        let (second, _) = ch.recv(20);
        assert_eq!(second, RecvStatus::Received(Value::Int(2)));
    }

    #[test]
    fn test_try_recv_and_affine_tensor_move() {
        let mut ch = Channel::unbounded(2);
        assert_eq!(ch.try_recv(), (None, None));

        let tensor = Value::Tensor(vec![2, 2], vec![1.0, 2.0, 3.0, 4.0]);
        assert_eq!(ch.send(1, tensor.clone()), SendStatus::Sent);
        assert_eq!(ch.affine_move_count(), 1);
        assert_eq!(ch.try_recv().0, Some(tensor));
    }
}
