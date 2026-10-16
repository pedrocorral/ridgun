/// Scheduler — round-robin and deterministic `--seed` scheduling for green threads.
/// Implements Section 9 of `docs/etc/next_gen_architecture.md` and `docs/etc/parallelism.md`.

use std::collections::VecDeque;
use crate::greenthread::{GreenThread, ThreadState};

pub const DEFAULT_QUANTUM: u64 = 100;

pub struct Scheduler {
    threads: Vec<GreenThread>,
    running: Option<usize>,
    queue: VecDeque<usize>,
    next_id: usize,
    quantum: u64,
    seed_state: Option<u64>,
    logical_clock: u64,
}

impl Scheduler {
    pub fn new() -> Self {
        Scheduler {
            threads: Vec::new(),
            running: None,
            queue: VecDeque::new(),
            next_id: 0,
            quantum: DEFAULT_QUANTUM,
            seed_state: None,
            logical_clock: 0,
        }
    }

    pub fn with_quantum(quantum: u64) -> Self {
        let mut s = Scheduler::new();
        s.quantum = quantum;
        s
    }

    /// Create a deterministic simulation scheduler initialized with `seed` (Section 9).
    pub fn with_seed(seed: u64) -> Self {
        let mut s = Scheduler::new();
        s.seed_state = Some(if seed == 0 { 0x9E37_79B9_7F4A_7C15 } else { seed });
        s
    }

    /// Current logical clock tick count (incremented on every scheduled reduction).
    pub fn logical_clock(&self) -> u64 {
        self.logical_clock
    }

    /// Quantum budget per green thread before cooperative preemption.
    pub fn quantum(&self) -> u64 {
        self.quantum
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

    /// Record one instruction reduction on the running thread; returns `true` if quantum expired.
    pub fn tick_reduction(&mut self) -> bool {
        self.logical_clock += 1;
        if let Some(id) = self.running {
            if let Some(thread) = self.threads.get_mut(id) {
                thread.reduction_count += 1;
                if thread.reduction_count >= self.quantum {
                    thread.reduction_count = 0;
                    return true;
                }
            }
        }
        false
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
    /// In `--seed` mode, uses deterministic xorshift64* selection over ready threads.
    pub fn next_thread(&mut self) -> Option<(usize, &mut GreenThread)> {
        self.queue.retain(|&id| {
            self.threads.get(id).map(|t| t.state == ThreadState::Ready).unwrap_or(false)
        });
        if self.queue.is_empty() {
            return None;
        }
        let chosen_idx = if let Some(ref mut state) = self.seed_state {
            let mut x = *state;
            x ^= x >> 12;
            x ^= x << 25;
            x ^= x >> 27;
            *state = x;
            let rand_val = x.wrapping_mul(0x2545_F491_4F6C_DD1D);
            (rand_val as usize) % self.queue.len()
        } else {
            0
        };
        let id = self.queue.remove(chosen_idx)?;
        let thread = self.threads.get_mut(id)?;
        thread.state = ThreadState::Running;
        self.running = Some(id);
        Some((id, thread))
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

    #[test]
    fn test_deterministic_seed_reproducibility() {
        let run_schedule = |seed: u64| -> Vec<usize> {
            let mut sched = Scheduler::with_seed(seed);
            for _ in 0..4 {
                sched.spawn();
            }
            let mut order = Vec::new();
            for _ in 0..12 {
                let (id, _) = sched.next_thread().unwrap();
                order.push(id);
                sched.yield_thread();
            }
            order
        };
        assert_eq!(run_schedule(918273), run_schedule(918273));
        assert_ne!(run_schedule(918273), run_schedule(42));
    }
}
