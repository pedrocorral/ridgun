---
id: ADR-0014
title: Threads live in the IR runtime: the runtime owns the worker pool, the PAL gives threads and futexes, shared state is made safe inside the runtime
status: accepted
date: 2026-11-16
supersedes: []
affects: [ADR-0013, ADR-0008, FR-COMP-009, FR-COMP-001, FR-COMP-026, TASK-0096, src/main/runtime/core/agents.ll, src/main/runtime/core/heap.ll, src/main/runtime/core/value.ll, src/main/runtime/pal/linux-x86_64.ll, src/main/ridgun/lib/llvm.ridgun, src/main/ridgun/lib/x86_64.ridgun]
---
# ADR-0014 — Threads in the IR runtime

## Context
ADR-0013 (rule 2) says the IR runtime gets threads from atomics plus a small `clone` in the Linux PAL. Reading both runtimes (2026-11-16) shows what that means in practice:

- The IR runtime is single-threaded. `agents.ll` runs a job when it is spawned; `heap.ll` has one bump pointer and one set of free lists; reference counts are plain `add`/`sub` (`value.ll`, three places); channel operations take no lock.
- The old x86-64 runtime has the threads: a pool of 8 worker slots (state at a fixed address, `futex` to sleep and wake), a sharded allocator (TASK-0024), work for `||map`, `||filter`, `||` waves and agents (FR-COMP-009 AC-5).
- The LLVM backend does part of the work itself in generated helpers: the channel spin lock (`__rg_chan_lock`), the thread-tagged replies (`gettid`), and `__rg_builtin_job_spawn`, which reads the old pool's state at the fixed address 4288300. With the IR runtime that address is not a pool: the helper waits for a free slot forever (the four agent cases time out for this reason).

So threads are split across the runtime and the backends, and the backends know the old runtime's memory. That is the same drift ADR-0013 removes.

## Options considered
1. Keep the thread code in each backend's helpers and give the IR runtime the pool state at the same address. Keeps the duplication; ARM64, Windows and the pure encoder would each repeat it.
2. The runtime owns everything about threads; backends call runtime builtins only. One source, one place to test; the PAL gives the system part.
3. Run every job on the calling thread (what the IR runtime does today). Correct for results, but FR-COMP-009 AC-5 asks for multicore execution.

## Decision
Option 2, in steps. The principles:

1. **The runtime owns the pool and the jobs.** Builtins 57 (spawn), 58 (poll), 59 (await), 96-99 (thread id, tagged send and receive), 51 (receive with timeout) and the channel builtins 1, 32, 33, 35, 50 are complete in the runtime. The backends call them and carry no thread code, no lock and no fixed address. A pool of up to 8 persistent workers starts at the first job; a job started from a worker, or while every slot is busy, runs on the calling thread (what the old runtime does for workers), so no wait can deadlock the pool.
2. **PAL interface (ADR-0008).** `__rg_pal_thread_spawn(entry, arg)` gives a thread (a stack of its own, the thread pointer set), `__rg_pal_thread_id()`, `__rg_pal_futex_wait(address, expected, timeout_ns)`, `__rg_pal_futex_wake(address, count)`, `__rg_pal_yield()`. The Linux PAL implements them with `clone`, `futex`, `sched_yield` and the thread register (`fs` on x86-64). wasm32 answers `-ENOSYS` to spawn: the runtime then runs every job on the calling thread, as today (ADR-0011).
3. **Reference counts are atomic once there is a second thread.** One global flag, set before the first worker starts, picks the form of every count update (`atomicrmw` or plain). Single-thread programs pay one predictable branch. All updates go through two functions, so this is one change.
4. **The allocator is sharded by thread.** Each thread has its own free lists and bump region (thread-local data through the thread register; on a single-thread target it is one set). A block freed by another thread joins the free lists of the freeing thread. Chunks come from the PAL (`mmap`, thread safe). No lock on the fast path.
5. **Channels, jobs and the pool are guarded by locks in the runtime** (spin a few times, then `futex_wait`), with the thread-tagged reply semantics of the contract (`runtime_contract.md` §5.5) unchanged.
6. **Order of work.** (a) The backend stops calling the pool at a fixed address and calls builtin 57: jobs run synchronously on the IR runtime (correct, not parallel): the six cases that wait on agents pass. (b) Thread-safe counts, allocator and channels, with the PAL thread interface, tested by themselves with the flag forced on. (c) The pool: parallel jobs, `||map`, `||filter`. (d) The builtins that need a timeout (51).

## Consequences
- **Tests (each step, run many times to show races):** counts shared by workers (a list read by many threads), allocator stress (allocate, send, free on another thread; sum checked, no growth after a million rounds), channels (several producers and consumers: no item lost, none twice, FIFO per producer), jobs (results in order, nested jobs, a worker that raises an error), the program ends while workers sleep, leak counters (`live`, `freed`) equal at the end, and the timing proposal `perf/parallel_agents_not_slower`.
- **Requirements to update:** FR-COMP-009 (AC-5 names `x86_64.ridgun` as the pool's home: it moves to the runtime), runtime contract §5.5 and §7.
- **Code to update:** `agents.ll`, `heap.ll`, `value.ll`, `pal/linux-x86_64.ll`, `pal/wasm32.ll` (stubs); `llvm.ridgun` loses `__rg_chan_lock*`, `__rg_builtin_gettid`, `__rg_builtin_job_spawn` and the tagged-reply helpers; `x86_64.ridgun` loses the pool and the locks when the encoder moves to the IR runtime.
- **Risk:** the allocator and counts are the hardest part to get right and the hardest to see failing. The flag keeps single-thread programs on the proven plain path, and every step must pass the whole suite with the flag on and off.
