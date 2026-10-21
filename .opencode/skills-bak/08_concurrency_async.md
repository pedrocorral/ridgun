# Skill: Concurrency & Async Mastery

## 🎯 Objective
Leverage modern hardware capabilities by writing thread-safe, non-blocking code that handles thousands of simultaneous operations without race conditions or deadlocks.

## 🔄 Core Directives
1. **Non-Blocking I/O:** ALWAYS use asynchronous execution (`async/await`, Promises, Coroutines) for network requests, database queries, and filesystem operations.
2. **Immutability First:** Avoid shared mutable state across threads entirely. Pass immutable data structures to concurrent workers to naturally eliminate race conditions.
3. **Concurrency Control:** When shared state is unavoidable, strictly utilize Mutexes, Locks, or Semaphores. Keep the "critical section" as short as possible.
4. **Timeouts & Limits:** NEVER make an external network call without an explicit timeout. When fanning out tasks, implement Worker Pools to bound concurrency and prevent memory exhaustion.

## 🚫 Anti-Patterns to Reject
- Blocking the event loop (heavy synchronous CPU tasks in an async environment).
- Nested locking, which leads to Deadlocks.
- "Fire and forget" async tasks without error handling (unhandled promise rejections).
