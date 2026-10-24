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

2. **Asynchronous Message Sending (`send ... to`) & Synchronous Request-Reply (`ask`)**:
   - `send <msg> to <agent>` (and multi-argument `send <arg1> <arg2> ... to <agent>`, which packs the arguments into a tuple message) SHALL immediately dispatch the message to `<agent>` in the background without blocking the caller, and may be used either as a standalone statement (`send x to ag`) or bound (`_ = send x to ag`).
   - `ask <agent> <msg...>` (Akka prefix style) and `ask <msg...> to <agent>` (Ridgun `to` style) SHALL perform a synchronous request-reply on `<agent>`, returning the typed response `R` directly.

3. **Blocking and Non-Blocking Response Retrieval (`receive from` & `try receive from`)**:
   - `receive from <agent>` SHALL await completion of the oldest in-flight job and return the next response `R` from `<agent>`'s output mailbox in FIFO order.
   - `try receive from <agent>` SHALL poll `<agent>`'s oldest in-flight job or output mailbox without blocking and return `Some r` (`Option R`) if a response is ready or `None` if still running or empty.

4. **Deterministic Lifecycle & Cleanup (`stop` & `agent alive`)**:
   - `stop <agent>` (usable as a standalone statement or expression) SHALL terminate `<agent>`, close its mailboxes, and deterministically release its held state and queued values via `RMM1`/`RMM2`.
   - `agent alive <agent>` SHALL return `True` (`Bool`) while the agent is active and `False` after `stop <agent>`.

5. **Type Representation (`Agent`) & Retirement of `spawn`/`join`, `global ::`, `context ::`, `shared ::`, and `atomic`**:
   - Type signatures SHALL support `Agent` (both unparameterized `Agent` and parameterized `Agent In Out` / `(Agent In Out)`).
   - Legacy unstructured `spawn` and `join` built-ins, as well as global/scoped state constructs (`global ::`, `context ::`, `shared ::`, `atomic`, and user `with <ctx> = <val> do`), SHALL be removed from the language, documentation, harnesses, and books in favor of explicit parameters, `||` / `||map` / `||filter` (for structured dataflow parallelism), and `agent` (for decoupled stateful/service processes).

6. **True Background Concurrent Execution (`b_id 57` `async_spawn`, `b_id 58` `async_poll`, `b_id 59` `async_await`) & Smart Compile-Time Strategy Selection**:
   - Both **stateless (`agent fn`, status `3`)** and **stateful (`agent fn init_state`, status `2`)** agents SHALL dispatch their handlers asynchronously in the background via `b_id 57` (`async_spawn`) immediately when `send ... to ag` is called, returning in ~0 ms without blocking the sender even when the handler sleeps (`sys sleep ms`) or executes heavy CPU work.
   - `try receive from ag` SHALL poll the in-flight background job via `b_id 58` (`async_poll`) without blocking (`None` while running, `Some r` when finished, transitioning stateful agent state `S -> S'` upon harvesting), and `receive from ag` SHALL await completion via `b_id 59` (`async_await` / `FUTEX_WAIT`).
   - Independent `||` DAG waves ($\ge 2$ heavy branches via `"__rg_par_eval__"`) and `||map` / `||filter` consult the static analyzer's 4-tier `RFnSummary` classification to select inline sequential execution vs multicore OS kernel thread execution (`NCallBuiltin 54` / `56`).

## Rationale
- **Orthogonal Concurrency Model**: `||`, `||map`, and `||filter` solve scoped computational fork-join parallelism with compile-time DAG verification, while `agent` solves long-lived, decoupled service concurrency (HTTP/TCP connection handlers, session stores, state machines, actors) with isolated state and typed message queues.
- **Best of Erlang + Akka Typed + Native RMM**: Ridgun agents combine Erlang's true memory isolation and inline `receive from` ergonomics with Akka Typed's compile-time message type safety and Ridgun's zero-GC deterministic `RMM1`/`RMM2` state reclamation.

## Acceptance Criteria
1. **AC-1 (Stateless & Multi-Argument Agents)**: Creating `ag = agent fn`, sending single or multi-argument messages via `send ... to ag`, and collecting results via `receive from ag` returns the exact computed outputs in FIFO order.
2. **AC-2 (Stateful Agents `S M => S` and `S M => S R`)**: Creating `ag = agent fn init_state` preserves and updates isolated state across multiple messages without locks or memory leaks, supporting both `S M => S` (counter) and `S M => S R` (persistent HTTP/session handler returning new state + response).
3. **AC-3 (Non-Blocking `try receive from` and `stop` / `agent alive`)**: `try receive from ag` returns `None` when no response is queued and `Some r` when ready; `stop ag` transitions `agent alive ag` from `True` to `False` and frees the agent's state.
4. **AC-4 (Retirement of `spawn`/`join`)**: `spawn` and `join` are removed from the compiler, harnesses, and all 7 book editions (`docs/book/`).
5. **AC-5 (Smart Compile-Time Strategy Selection & Persistent Worker Pool)**: `compiler.rg` automatically selects lightweight green execution (`StratInlineSequential`) for trivial functions and multicore OS thread execution (`SYS_clone`, `NCallBuiltin 54`/`56`) for heavy/recursive `agent`s, `||` DAG waves, and `||map`/`||filter`, backed by a persistent pre-warmed `SYS_futex` worker thread pool in `x86_64.rg` that reuses spawned OS worker threads across batches without repeated stack teardown.
