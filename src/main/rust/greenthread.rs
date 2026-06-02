/// Green thread primitives — lightweight VM-level threads

use crate::vm::{Value, CallFrame};

// ── Thread states ──────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ThreadState {
    Ready,
    Running,
    Blocked,
    Suspended,
    Dead,
}

// ── Green thread ───────────────────────────────────────────

pub struct GreenThread {
    pub id: usize,
    pub state: ThreadState,
    pub stack: Vec<Value>,
    pub call_stack: Vec<CallFrame>,
    pub reduction_count: u64,
}

impl GreenThread {
    pub fn new(id: usize) -> Self {
        GreenThread {
            id,
            state: ThreadState::Ready,
            stack: Vec::new(),
            call_stack: Vec::new(),
            reduction_count: 0,
        }
    }

    /// Suspend the thread, giving ownership of captured state back to caller.
    pub fn suspend(&mut self) -> (Vec<Value>, Vec<CallFrame>) {
        let stack = std::mem::take(&mut self.stack);
        let call_stack = std::mem::take(&mut self.call_stack);
        self.state = ThreadState::Suspended;
        (stack, call_stack)
    }

    /// Restore state into a suspended thread.
    pub fn restore(&mut self, stack: Vec<Value>, call_stack: Vec<CallFrame>) {
        self.stack = stack;
        self.call_stack = call_stack;
        self.state = ThreadState::Ready;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_thread() {
        let thread = GreenThread::new(0);
        assert_eq!(thread.id, 0);
        assert_eq!(thread.state, ThreadState::Ready);
        assert!(thread.stack.is_empty());
        assert!(thread.call_stack.is_empty());
        assert_eq!(thread.reduction_count, 0);
    }

    #[test]
    fn test_suspend_thread() {
        let mut thread = GreenThread::new(1);
        thread.stack.push(Value::Int(42));
        thread.state = ThreadState::Running;

        let (stack, _call_stack) = thread.suspend();
        assert_eq!(thread.state, ThreadState::Suspended);
        assert!(thread.stack.is_empty());
        assert_eq!(stack, vec![Value::Int(42)]);
    }

    #[test]
    fn test_restore_thread() {
        let mut thread = GreenThread::new(2);
        let stack = vec![Value::Int(1), Value::Int(2), Value::Int(3)];
        let call_stack = Vec::new();

        thread.restore(stack, call_stack);
        assert_eq!(thread.state, ThreadState::Ready);
        assert_eq!(thread.stack.len(), 3);
        assert_eq!(thread.stack[0], Value::Int(1));
        assert_eq!(thread.stack[1], Value::Int(2));
        assert_eq!(thread.stack[2], Value::Int(3));
    }

    #[test]
    fn test_suspend_restore_roundtrip() {
        let mut thread = GreenThread::new(3);
        thread.stack.push(Value::Str("hello".into()));
        thread.stack.push(Value::Bool(true));
        thread.state = ThreadState::Running;

        let (stack, call_stack) = thread.suspend();
        assert_eq!(thread.state, ThreadState::Suspended);

        thread.restore(stack, call_stack);
        assert_eq!(thread.state, ThreadState::Ready);
        assert_eq!(thread.stack.len(), 2);
        assert_eq!(thread.stack[0], Value::Str("hello".into()));
        assert_eq!(thread.stack[1], Value::Bool(true));
    }

    #[test]
    fn test_thread_states_distinct() {
        let s1 = ThreadState::Ready;
        let s2 = ThreadState::Running;
        let s3 = ThreadState::Blocked;
        let s4 = ThreadState::Suspended;
        let s5 = ThreadState::Dead;
        assert_ne!(s1, s2);
        assert_ne!(s2, s3);
        assert_ne!(s3, s4);
        assert_ne!(s4, s5);
        assert_ne!(s1, s5);
    }
}
