# Ridgun Parallelism Model

## Philosophy

Parallelism in Ridgun is not a library feature — it is the **execution model**. Every Ridgun program runs inside a parallel scheduler. Even a "sequential" program is a single green thread managed by the scheduler.

The guiding principles:

1. **Spawn is cheap.** Creating a green thread is as lightweight as calling a function. Thousands or millions of concurrent tasks are normal.
2. **Share nothing.** Green threads do not share mutable state. Communication happens through message passing and typed channels.
3. **Fail fast, fail isolated.** A crash in one green thread does not bring down others. Supervisors can monitor and restart failed threads.
4. **The runtime is smarter than the programmer.** The scheduler decides how to map green threads to OS threads. Programmers express *what* to parallelize, not *how*.

## Green Threads

A **green thread** (also called a "process" in Erlang terminology) is Ridgun's unit of concurrent execution. It is:

- **Lightweight**: ~2-4 KB of initial memory (just a stack and a mailbox). Compare to OS threads at ~1-8 MB.
- **Scheduled by the VM**: Not by the OS. The VM multiplexes thousands of green threads onto a small pool of OS threads.
- **Isolated**: Each green thread has its own stack, instruction pointer, and local heap. No shared mutable state.

### Lifecycle

```
  ┌──────────┐   SPAWN    ┌──────────┐
  │          │ ─────────▶ │  READY   │
  │ (parent) │            └────┬─────┘
  └──────────┘                 │
                          scheduled│
                               │
                          ┌────▼─────┐
                 YIELD    │ RUNNING  │◄──────────┐
               ┌─────────▶│          │           │
               │          └────┬─────┘      scheduled
               │               │                 │
               │          RECV │(empty)     ┌────┴─────┐
               │               │            │  READY   │
               │          ┌────▼─────┐      └──────────┘
               │          │ WAITING  │           ▲
               │          │(mailbox) │───────────┘
               │          └──────────┘  message arrives
               │
               │          ┌──────────┐
               └──────────│   DONE   │
                  RETURN  └──────────┘
```

States:
- **READY** — Runnable, waiting to be picked up by a worker thread.
- **RUNNING** — Currently executing on a worker thread.
- **WAITING** — Blocked on a `RECV` (mailbox empty) or `CHAN_RECV` (channel empty). Does **not** block the underlying OS thread.
- **DONE** — Completed execution. Result is available to the parent via `AWAIT`.

## M:N Threading Model

Ridgun uses an **M:N threading model**: M green threads are multiplexed onto N OS threads, where M >> N.

```
┌─────────────────────────────────────────────┐
│               Ridgun VM                     │
│                                             │
│  Green Threads:  T1  T2  T3  T4  T5  ...  │
│                  │   │   │    │   │         │
│                  ▼   ▼   ▼    ▼   ▼         │
│  ┌─────────────────────────────────────┐    │
│  │         Work-Stealing Scheduler     │    │
│  └──────┬──────────┬──────────┬────────┘    │
│         │          │          │              │
└─────────┼──────────┼──────────┼──────────────┘
          ▼          ▼          ▼
    ┌──────────┐┌──────────┐┌──────────┐
    │OS Thread ││OS Thread ││OS Thread │
    │   W0     ││   W1     ││   W2     │
    └──────────┘└──────────┘└──────────┘
          │          │          │
          ▼          ▼          ▼
    ┌──────────────────────────────────┐
    │       Operating System           │
    │       CPU Core 0  Core 1  ...   │
    └──────────────────────────────────┘
```

- **N** (OS thread count) defaults to the number of CPU cores. Configurable at VM startup.
- **M** (green thread count) is unbounded — limited only by available memory.
- Each OS worker thread has a **local run queue** of green threads ready to execute.

## Work-Stealing Scheduler

The scheduler ensures work is evenly distributed and no OS thread sits idle while others are overloaded.

### Algorithm

1. Each worker thread maintains a **double-ended queue (deque)** of runnable green threads.
2. When a worker finishes executing a green thread, it pops the next one from its **own deque** (LIFO for cache locality).
3. If the local deque is **empty**, the worker **steals** from the tail of another worker's deque (FIFO to steal the oldest/largest work units first).
4. If all deques are empty, the worker parks (sleeps) until new work is available.

```
Worker 0 deque:    [T1, T2, T3]  ← pop from here (LIFO)
Worker 1 deque:    [T4]
Worker 2 deque:    []             ← empty! steal from Worker 0's tail

After steal:
Worker 0 deque:    [T2, T3]
Worker 1 deque:    [T4]
Worker 2 deque:    [T1]           ← stole T1
```

### Preemption

Green threads are **cooperatively preempted** using a **reduction counter**:

1. Each green thread starts with a budget of N reductions (e.g., 4000).
2. Every bytecode instruction decrements the counter by 1.
3. When the counter reaches 0, the green thread **yields** and is placed back in the run queue.
4. The worker picks up the next green thread.

This ensures no single green thread can starve others, even in tight loops. It mirrors the BEAM VM's approach and avoids the complexity of signal-based OS preemption.

Additional yield points:
- `RECV` on an empty mailbox → thread moves to WAITING.
- `CHAN_RECV` on an empty channel → thread moves to WAITING.
- `PY_CALL` → thread yields while Python executes (GIL-bound work doesn't block the scheduler).
- `FFI_CALL` with blocking semantics → executed on a dedicated I/O thread pool.

## Communication Primitives

### Message Passing (Mailboxes)

Every green thread has a **mailbox** — an unbounded FIFO queue of messages. Any thread can send a message to any other thread's mailbox.

```
Thread A                    Thread B
   │                           │
   │  SEND(B, {hello, 42})     │
   │ ─────────────────────────▶│
   │                           │ RECV → {hello, 42}
   │                           │
```

- `SEND` is **non-blocking** — it enqueues the message and returns immediately.
- `RECV` **blocks the green thread** (not the OS thread) until a message arrives.
- Messages are **copied** (deep clone) to maintain isolation. For large data, use channels with ownership transfer.

### Typed Channels

For structured producer-consumer communication, Ridgun provides **typed channels**:

```
┌──────────┐    channel: Chan<i64>    ┌──────────┐
│Producer A│ ──── CHAN_SEND(42) ─────▶│Consumer  │
│Producer B│ ──── CHAN_SEND(99) ─────▶│          │
└──────────┘                          └──────────┘
```

- Channels can be **bounded** (back-pressure) or **unbounded**.
- Bounded channels cause `CHAN_SEND` to block when full — natural flow control.
- Multiple producers and consumers are supported (MPMC).
- Closing a channel signals all waiting consumers.

## Supervision (Fault Tolerance)

Inspired by Erlang's OTP supervisor trees, Ridgun supports **supervision** — a parent thread can monitor its children and react to failures.

Strategies:
- **one-for-one**: If a child crashes, only that child is restarted.
- **one-for-all**: If any child crashes, all children are restarted.
- **rest-for-one**: If a child crashes, that child and all children spawned after it are restarted.

This makes Ridgun programs **self-healing** by default. Crashes are expected and managed, not fatal.

## Comparison with Existing Models

| Feature | Ridgun | Erlang/BEAM | Go | Rust (Tokio) |
|---|---|---|---|---|
| Lightweight threads | Green threads | Processes | Goroutines | Tasks |
| Scheduling | Work-stealing | Reduction counting | Work-stealing | Work-stealing |
| Communication | Mailboxes + Channels | Mailboxes | Channels | Channels |
| Preemption | Reduction counting | Reduction counting | Cooperative + sysmon | Cooperative |
| Supervision | Yes (built-in) | Yes (OTP) | No (manual) | No (manual) |
| Shared state | Forbidden | Forbidden | Allowed (mutex) | Allowed (Arc+Mutex) |
| GC per thread | Yes | Yes | Global GC | No GC |

Ridgun takes the strongest elements of each:
- **Erlang's** isolation, mailboxes, supervision, and per-thread GC.
- **Go's** work-stealing scheduler and channel semantics.
- **Rust's** FFI capabilities and memory-efficient runtime.
