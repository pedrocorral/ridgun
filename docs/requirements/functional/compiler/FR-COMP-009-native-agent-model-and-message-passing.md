---
id: FR-COMP-009
title: Native Agent Model (`agent`, `send ... to`, `receive from`, `try receive from`, `stop`) and Retirement of Legacy `spawn`/`join`
status: implemented
priority: must
created: 2026-10-22
updated: 2026-10-22
depends_on:
  - FR-COMP-001
  - FR-COMP-002
  - FR-COMP-008
verified_by: []
---
# FR-COMP-009 — Native Agent Model (`agent`, `send ... to`, `receive from`, `try receive from`, `stop`) and Retirement of Legacy `spawn`/`join`

## Statement
The Ridgun language and `ridgunc` / `stable` toolchain SHALL replace legacy unstructured `spawn`/`join` thread primitives with a native, strongly-typed **Agent Model** built directly on standard Ridgun functions (`fn ::` and `op ::`) and deterministic `RMM1`/`RMM2` memory management:

1. **Zero Boilerplate Agent Creation (`agent`)**:
   - Any standard Ridgun function or operator (`fn ::` or `op ::`) MAY be instantiated as an autonomous agent without introducing special declaration headers:
     - **Stateless Agent (`ag = agent fn`)**: Given `fn :: M1 ... Mn => R`, `agent fn` creates an agent with an input mailbox of type `(M1, ..., Mn)` (or `M1` when $n = 1$) and an output mailbox of type `R`.
     - **Stateful Agent (`ag = agent fn init_state`)**: Given a state-transition function `fn :: S M => S` or `fn :: S M => S R` and an initial state `init_state :: S`, `agent fn init_state` creates an isolated stateful agent initialized with `init_state`.
       - When `fn :: S M => S`, each processed message transitions the internal state `s' = fn s msg`, deterministically releases the previous state `s` (`RMM1`/`RMM2`), and enqueues `s'` in the agent's output queue.
       - When `fn :: S M => S R` (a 2-element tuple/sequence return type where the first component is `S` and the second is `R`), each processed message transitions the internal state to `s'`, deterministically releases the previous state `s` (`RMM1`/`RMM2`), and enqueues the response `r :: R` in the agent's output queue.

2. **Asynchronous Message Sending (`send ... to`)**:
   - `send <msg> to <agent>` (and multi-argument `send <arg1> <arg2> ... to <agent>`, which packs the arguments into a tuple message) SHALL enqueue the message in `<agent>`'s input mailbox without blocking the caller, and may be used either as a standalone statement (`send x to ag`) or bound (`_ = send x to ag`).

3. **Blocking and Non-Blocking Response Retrieval (`receive from` & `try receive from`)**:
   - `receive from <agent>` SHALL retrieve and return the next response `R` from `<agent>`'s output mailbox.
   - `try receive from <agent>` SHALL check `<agent>`'s output mailbox without blocking and return `Some r` (`Option R`) if a response is available or `None` if empty.

4. **Deterministic Lifecycle & Cleanup (`stop` & `agent alive`)**:
   - `stop <agent>` (usable as a standalone statement or expression) SHALL terminate `<agent>`, close its mailboxes, and deterministically release its held state and queued values via `RMM1`/`RMM2`.
   - `agent alive <agent>` SHALL return `True` (`Bool`) while the agent is active and `False` after `stop <agent>`.

5. **Type Representation (`Agent`) & Retirement of `spawn`/`join`**:
   - Type signatures SHALL support `Agent` (both unparameterized `Agent` and parameterized `Agent In Out` / `(Agent In Out)`).
   - Legacy unstructured `spawn` and `join` built-ins SHALL be removed from the language, documentation, harnesses, and books in favor of `||` / `||map` / `||filter` (for structured dataflow parallelism) and `agent` (for decoupled stateful/service processes).

6. **Smart Compile-Time Execution Strategy Selection (Green Execution vs Multicore OS Kernel Threads)**:
   - The compiler (`compiler.rg`) SHALL consult the static analyzer's 4-tier `RFnSummary` classification (`StratInlineSequential` / `TierTrivial`, `StratKernelWorkerJob` / `TierHeavyCPU`, `StratLazyStealableTask` / `TierDynamicRecursive`, `StratFullGreenThread`) when lowering `agent`, `||` blocks (`EWhere` and `EParPipe`), and `||map` / `||filter`:
     - **Lightweight Green-Thread Execution (`StratInlineSequential` / `TierTrivial`)**: Shallow, non-recursive functions execute inline as lightweight green steps without paying OS thread creation (`SYS_mmap` + `SYS_clone`) warmup costs.
     - **Multicore OS Kernel Thread Execution (`StratKernelWorkerJob` / `StratLazyStealableTask` / `StratFullGreenThread`)**: Heavy CPU/tensor or recursive functions in `agent fn` (status `3` mailbox batching), independent `||` DAG waves ($\ge 2$ heavy branches via `"__rg_par_eval__"`), and `||map` / `||filter` automatically dispatch across real OS kernel threads (`SYS_clone`, `NCallBuiltin 54` / `56`).

## Rationale
- **Orthogonal Concurrency Model**: `||`, `||map`, and `||filter` solve scoped computational fork-join parallelism with compile-time DAG verification, while `agent` solves long-lived, decoupled service concurrency (HTTP/TCP connection handlers, session stores, state machines, actors) with isolated state and typed message queues.
- **Best of Erlang + Akka Typed + Native RMM**: Ridgun agents combine Erlang's true memory isolation and inline `receive from` ergonomics with Akka Typed's compile-time message type safety and Ridgun's zero-GC deterministic `RMM1`/`RMM2` state reclamation.

## Acceptance Criteria
1. **AC-1 (Stateless & Multi-Argument Agents)**: Creating `ag = agent fn`, sending single or multi-argument messages via `send ... to ag`, and collecting results via `receive from ag` returns the exact computed outputs in FIFO order.
2. **AC-2 (Stateful Agents `S M => S` and `S M => S R`)**: Creating `ag = agent fn init_state` preserves and updates isolated state across multiple messages without locks or memory leaks, supporting both `S M => S` (counter) and `S M => S R` (persistent HTTP/session handler returning new state + response).
3. **AC-3 (Non-Blocking `try receive from` and `stop` / `agent alive`)**: `try receive from ag` returns `None` when no response is queued and `Some r` when ready; `stop ag` transitions `agent alive ag` from `True` to `False` and frees the agent's state.
4. **AC-4 (Retirement of `spawn`/`join`)**: `spawn` and `join` are removed from the compiler, harnesses, and all 7 book editions (`docs/book/`).
5. **AC-5 (Smart Compile-Time Strategy Selection & Persistent Worker Pool)**: `compiler.rg` automatically selects lightweight green execution (`StratInlineSequential`) for trivial functions and multicore OS thread execution (`SYS_clone`, `NCallBuiltin 54`/`56`) for heavy/recursive `agent`s, `||` DAG waves, and `||map`/`||filter`, backed by a persistent pre-warmed `SYS_futex` worker thread pool in `x86_64.rg` that reuses spawned OS worker threads across batches without repeated stack teardown.
