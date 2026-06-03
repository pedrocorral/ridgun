/// Scheduler — round-robin foundation for green threads

use std::collections::VecDeque;
use crate::greenthread::{GreenThread, ThreadState};

pub const DEFAULT_QUANTUM: u64 = 100;

pub struct Scheduler {
    threads: Vec<GreenThread>,
    running: Option<usize>,
    queue: VecDeque<usize>,
    next_id: usize,
    quantum: u64,
}

impl Scheduler {
    pub fn new() -> Self {
        Scheduler {
            threads: Vec::new(),
            running: None,
            queue: VecDeque::new(),
            next_id: 0,
            quantum: DEFAULT_QUANTUM,
        }
    }

    pub fn with_quantum(quantum: u64) -> Self {
        let mut s = Scheduler::new();
        s.quantum = quantum;
        s
    }

    /// Create a new ready thread and push it onto the queue.
    pub fn spawn(&mut self) -> usize {
        let id = self.next_id;
        self.next_id += 1;
        let mut thread = GreenThread::new(id);
        thread.state = ThreadState::Ready;
        self.threads.push(thread);
        self.queue.push_back(id);
        id
    }

    /// Yield the currently running thread back to the ready queue.
    pub fn yield_thread(&mut self) {
        if let Some(id) = self.running {
            if let Some(thread) = self.threads.get_mut(id) {
                thread.state = ThreadState::Ready;
                self.queue.push_back(id);
            }
            self.running = None;
        }
    }

    /// Block a thread (remove from schedulable sets).
    pub fn block_thread(&mut self, id: usize) {
        if let Some(thread) = self.threads.get_mut(id) {
            thread.state = ThreadState::Blocked;
        }
        if self.running == Some(id) {
            self.running = None;
        }
    }

    /// Unblock a thread, returning it to the ready queue.
    pub fn unblock(&mut self, id: usize) {
        if let Some(thread) = self.threads.get_mut(id) {
            if thread.state == ThreadState::Blocked {
                thread.state = ThreadState::Ready;
                self.queue.push_back(id);
            }
        }
    }

    /// Pick the next thread from the ready queue and mark it running.
    /// Skips any entries left behind by block/kill operations.
    /// Returns the thread ID and a mutable reference to the thread.
    pub fn next_thread(&mut self) -> Option<(usize, &mut GreenThread)> {
        loop {
            let id = match self.queue.pop_front() {
                Some(id) => id,
                None => return None,
            };
            let state = self.threads.get(id).map(|t| t.state);
            match state {
                Some(ThreadState::Ready) => {}
                _ => continue,
            }
            let thread = self.threads.get_mut(id).unwrap();
            thread.state = ThreadState::Running;
            self.running = Some(id);
            return Some((id, thread));
        }
    }

    /// Count threads that are not Dead.
    pub fn active_count(&self) -> usize {
        self.threads.iter()
            .filter(|t| t.state != ThreadState::Dead)
            .count()
    }

    /// Return true when there are no schedulable threads remaining (queue empty).
    pub fn is_done(&self) -> bool {
        let has_ready = self.threads.iter()
            .any(|t| t.state == ThreadState::Ready);
        !has_ready
    }

    /// Mark a thread as dead.
    pub fn kill(&mut self, id: usize) {
        if let Some(thread) = self.threads.get_mut(id) {
            thread.state = ThreadState::Dead;
        }
        if self.running == Some(id) {
            self.running = None;
        }
    }

    /// Get the current state of a thread.
    pub fn get_thread_state(&self, id: usize) -> ThreadState {
        self.threads.get(id).map(|t| t.state).unwrap_or(ThreadState::Dead)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spawn_single() {
        let mut sched = Scheduler::new();
        let id = sched.spawn();
        assert_eq!(id, 0);
        assert_eq!(sched.active_count(), 1);
        assert!(!sched.is_done());
    }

    #[test]
    fn test_spawn_multiple() {
        let mut sched = Scheduler::new();
        let a = sched.spawn();
        let b = sched.spawn();
        let c = sched.spawn();
        assert_eq!(a, 0);
        assert_eq!(b, 1);
        assert_eq!(c, 2);
        assert_eq!(sched.active_count(), 3);
    }

    #[test]
    fn test_round_robin() {
        let mut sched = Scheduler::new();
        sched.spawn();
        sched.spawn();
        sched.spawn();

        let t0 = sched.next_thread().map(|(id, _)| id);
        let t1 = sched.next_thread().map(|(id, _)| id);
        let t2 = sched.next_thread().map(|(id, _)| id);

        assert_eq!(t0, Some(0));
        assert_eq!(t1, Some(1));
        assert_eq!(t2, Some(2));
        assert!(sched.is_done());
    }

    #[test]
    fn test_yield_returns_to_queue() {
        let mut sched = Scheduler::new();
        sched.spawn();
        sched.spawn();

        let first = sched.next_thread().unwrap();
        assert_eq!(first.0, 0);
        sched.yield_thread();

        let second = sched.next_thread().unwrap();
        assert_eq!(second.0, 1);
        sched.yield_thread();

        let resumed = sched.next_thread().unwrap();
        assert_eq!(resumed.0, 0);
    }

    #[test]
    fn test_block_and_unblock() {
        let mut sched = Scheduler::new();
        let a = sched.spawn();
        let b = sched.spawn();

        sched.block_thread(a);
        assert!(!sched.is_done());
        let picked = sched.next_thread().unwrap();
        assert_eq!(picked.0, b);

        sched.yield_thread();
        sched.unblock(a);
        let picked = sched.next_thread().unwrap();
        // b was yielded first, so b is ahead of a in the ready queue
        assert_eq!(picked.0, b);
        let picked2 = sched.next_thread().unwrap();
        assert_eq!(picked2.0, a);
    }

    #[test]
    fn test_kill_ends_thread() {
        let mut sched = Scheduler::new();
        let a = sched.spawn();
        let b = sched.spawn();

        sched.kill(a);
        assert_eq!(sched.active_count(), 1);

        let remaining = sched.next_thread().unwrap();
        assert_eq!(remaining.0, b);
    }

    #[test]
    fn test_default_quantum() {
        let sched = Scheduler::new();
        assert_eq!(sched.quantum, DEFAULT_QUANTUM);
        assert_eq!(DEFAULT_QUANTUM, 100);
    }

    #[test]
    fn test_custom_quantum() {
        let sched = Scheduler::with_quantum(50);
        assert_eq!(sched.quantum, 50);
    }

    #[test]
    fn test_next_thread_returns_none_when_empty() {
        let mut sched = Scheduler::new();
        assert!(sched.next_thread().is_none());
        assert!(sched.is_done());
    }

    #[test]
    fn test_all_dead_is_done() {
        let mut sched = Scheduler::new();
        let a = sched.spawn();
        let b = sched.spawn();

        sched.kill(a);
        sched.kill(b);
        assert!(sched.is_done());
    }
}
