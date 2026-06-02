/// Mailbox — FIFO message passing between green threads

use std::collections::VecDeque;
use crate::vm::Value;

pub struct Mailbox {
    queue: VecDeque<Value>,
    owner: Option<usize>,
    senders: Vec<usize>,
}

impl Mailbox {
    pub fn new() -> Self {
        Mailbox {
            queue: VecDeque::new(),
            owner: None,
            senders: Vec::new(),
        }
    }

    /// Send a value into the mailbox.
    pub fn send(&mut self, value: Value) -> bool {
        self.queue.push_back(value);
        true
    }

    /// Receive the oldest value from the mailbox.
    pub fn recv(&mut self) -> Option<Value> {
        self.queue.pop_front()
    }

    /// Check whether the mailbox has no messages.
    pub fn is_empty(&self) -> bool {
        self.queue.is_empty()
    }

    /// Number of messages waiting in the mailbox.
    pub fn len(&self) -> usize {
        self.queue.len()
    }

    /// Set the owner thread (the one that may receive).
    pub fn set_owner(&mut self, thread_id: usize) {
        self.owner = Some(thread_id);
    }

    /// Register a thread that is allowed to send to this mailbox.
    pub fn add_sender(&mut self, thread_id: usize) {
        self.senders.push(thread_id);
    }

    /// Return the owner thread id, if any.
    pub fn get_owner(&self) -> Option<usize> {
        self.owner
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_mailbox_empty() {
        let mailbox = Mailbox::new();
        assert!(mailbox.is_empty());
        assert_eq!(mailbox.len(), 0);
    }

    #[test]
    fn test_send_and_recv() {
        let mut mailbox = Mailbox::new();
        assert!(mailbox.send(Value::Int(42)));
        assert_eq!(mailbox.len(), 1);
        assert_eq!(mailbox.recv(), Some(Value::Int(42)));
        assert!(mailbox.is_empty());
    }

    #[test]
    fn test_fifo_ordering() {
        let mut mailbox = Mailbox::new();
        mailbox.send(Value::Int(1));
        mailbox.send(Value::Int(2));
        mailbox.send(Value::Int(3));

        assert_eq!(mailbox.len(), 3);
        assert_eq!(mailbox.recv(), Some(Value::Int(1)));
        assert_eq!(mailbox.recv(), Some(Value::Int(2)));
        assert_eq!(mailbox.recv(), Some(Value::Int(3)));
        assert!(mailbox.is_empty());
    }

    #[test]
    fn test_recv_empty_returns_none() {
        let mut mailbox = Mailbox::new();
        assert_eq!(mailbox.recv(), None);
    }

    #[test]
    fn test_send_various_value_types() {
        let mut mailbox = Mailbox::new();
        mailbox.send(Value::Str("hello".into()));
        mailbox.send(Value::Bool(true));
        mailbox.send(Value::Unit);
        mailbox.send(Value::List(vec![Value::Int(1), Value::Int(2)]));

        assert_eq!(mailbox.len(), 4);
        assert_eq!(mailbox.recv(), Some(Value::Str("hello".into())));
        assert_eq!(mailbox.recv(), Some(Value::Bool(true)));
        assert_eq!(mailbox.recv(), Some(Value::Unit));
        assert_eq!(mailbox.recv(), Some(Value::List(vec![Value::Int(1), Value::Int(2)])));
    }

    #[test]
    fn test_owner_management() {
        let mut mailbox = Mailbox::new();
        assert_eq!(mailbox.get_owner(), None);
        mailbox.set_owner(5);
        assert_eq!(mailbox.get_owner(), Some(5));
    }

    #[test]
    fn test_sender_registration() {
        let mut mailbox = Mailbox::new();
        mailbox.add_sender(1);
        mailbox.add_sender(2);
        assert_eq!(mailbox.senders.len(), 2);
        assert_eq!(mailbox.senders[0], 1);
        assert_eq!(mailbox.senders[1], 2);
    }

    #[test]
    fn test_partial_recv() {
        let mut mailbox = Mailbox::new();
        mailbox.send(Value::Int(10));
        mailbox.send(Value::Int(20));
        mailbox.send(Value::Int(30));

        let first = mailbox.recv();
        assert_eq!(first, Some(Value::Int(10)));
        assert_eq!(mailbox.len(), 2);
    }
}
