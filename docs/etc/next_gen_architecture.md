# Ridgun Next-Gen Architecture Specification (v2.0)

**Status:** Approved Architectural Blueprint  
**Target Subsystems:** Parser, Typechecker, Static Analyzer, Memory Manager, Bytecode VM, Native Backend (Cranelift/LLVM), Runtime Scheduler, Bare-Metal OS Profile  
**Core Philosophy:** Zero-cost safe parallelism, deterministic lexical region memory without tracing GC, static mutation control without lifetime annotations, AST-driven execution tiering, and seamless scaling from high-level declarative dataflows to bare-metal OS kernels.

---

## Table of Contents

1. [Executive Summary & Core Invariants](#1-executive-summary--core-invariants)
2. [Language & Spec Harmonization (v1.0 Cleanups)](#2-language--spec-harmonization-v10-cleanups)
3. [Implicit Dataflow Parallelism (DAG Scheduling in `where`)](#3-implicit-dataflow-parallelism-dag-scheduling-in-where)
4. [Static Mutation Control: Automatic Freeze on Parallel Share](#4-static-mutation-control-automatic-freeze-on-parallel-share)
5. [Structured Concurrency & Typed Channels (Task vs. Process)](#5-structured-concurrency--typed-channels-task-vs-process)
6. [AST-Driven Execution Tiering (Inline vs. Kernel Worker vs. Green Thread)](#6-ast-driven-execution-tiering-inline-vs-kernel-worker-vs-green-thread)
7. [Region-Based Memory Management (Lexical Arenas without Tracing GC)](#7-region-based-memory-management-lexical-arenas-without-tracing-gc)
8. [Controlled Global & Scoped State](#8-controlled-global--scoped-state)
9. [Deterministic Concurrency & Simulation Mode (`--seed`)](#9-deterministic-concurrency--simulation-mode---seed)
10. [Native Compilation Strategy (AOT/JIT via Cranelift/LLVM)](#10-native-compilation-strategy-aotjit-via-craneliftllvm)
11. [Compile-Time Tensor Shape & Disjoint Slice Verification](#11-compile-time-tensor-shape--disjoint-slice-verification)
12. [Systems & Bare-Metal OS Profile (Ridgun as a SASOS Kernel)](#12-systems--bare-metal-os-profile-ridgun-as-a-sasos-kernel)
13. [Compiler Data Structures & Implementation Roadmap](#13-compiler-data-structures--implementation-roadmap)

---

## 1. Executive Summary & Core Invariants

Ridgun bridges the gap between high-level declarative functional languages (Haskell/ML) and low-level systems languages (Rust/C). While Ridgun v1.0 established natural language operators (`op ::`), equation-based definitions, and bytecode VM execution, **Ridgun v2.0** introduces a cohesive compile-time verification and execution engine built on five foundational invariants:

1. **Zero Manual Synchronization or Lifetimes:** Programmers never write `async`, `await`, `Mutex`, `Arc`, or `'a` lifetime annotations.
2. **Data-Race Freedom by Construction (Automatic Freeze):** Mutable values passed to a single execution branch retain read-write privileges; mutable values shared across $\ge 2$ concurrent branches are automatically downgraded to **Read-Only (Frozen)** at compile time.
3. **AST-Guided Execution Granularity:** The compiler statically analyzes the AST of every parallel branch and classifies it into sequential inlined code, non-yielding OS kernel worker jobs (`pthread` / physical CPU core), lazy stealable tasks, or suspendable Green Threads.
4. **Lexical Region Memory (Zero Tracing GC):** Memory allocated inside a function or operator belongs to its lexical arena. Sub-calls are strictly forbidden from deallocating parent memory. Upon function exit, only the return value escapes (is promoted to the caller's arena); all intermediate allocations are reclaimed in $O(1)$ time by resetting the arena pointer.
5. **Dual-Target Execution (VM + Native Bare-Metal):** Because memory safety and concurrency safety are proven statically in the compiler front-end, Ridgun can execute on its deterministic bytecode VM (with `--seed` simulation) or compile directly to lock-free, zero-copy native machine code capable of running bare-metal operating system kernels.

---

## 2. Language & Spec Harmonization (v1.0 Cleanups)

To ensure deterministic parsing and high accuracy when assisted by LLMs or static tools, the following rules standardize ambiguities between early prototypes and `spec.md`:

1. **Capitalized Built-in Types:** All built-in types are strictly PascalCase (`Int`, `Real`, `Bool`, `Char`, `String`, `Complex`, `Tensor`, `Tensor_GPU`, `Channel`). Lowercase aliases (`int`, `bool`) are deprecated.
2. **Return Type Arrows (`=>` vs. `->`):**
   * `=>` is the standard separator between input parameter types and return types in `fn ::` and `op ::` declarations.
   * `->` is used inside `where` blocks to bind the output of a parallel expression to a local variable (`expr -> var`), and optionally in sequence-transforming operators (`op :: Int Int switch -> Int Int`).
3. **Multi-Value Return Syntax:** Comma-separated types (`=> Res, Res`) denote a tuple of distinct return values, whereas space-separated types (`-> Int Int`) denote an unboxed flat sequence (`seq`).
4. **Record Construction & Field Access:** Product types (`type Conf = host String, port Int`) are constructed positionally (`Conf "localhost" 8080`) and accessed via prefix field projection (`host c`, `port c`).

---

## 3. Implicit Dataflow Parallelism (DAG Scheduling in `where`)

### 3.1 Motivation
Traditional `where` or `||` blocks execute as flat fork-join barriers. However, real-world computations often contain partial data dependencies between sub-tasks. Requiring manual nesting of blocks or explicit futures leads to artificial synchronization bottlenecks.

### 3.2 Static DAG Construction
In Ridgun, every binding inside a `where` block has the canonical form:

```ridgun
<expr> -> <bound_var_pattern>
```

During compilation, the AST analyzer constructs a **Directed Acyclic Graph (DAG)** $G = (V, E)$ for each `where` block:
* **Vertices $V$:** Each statement $s_i$ in the `where` block.
* **Producer Set $P(s_i)$:** All identifiers bound on the right-hand side of `->` in statement $s_i$.
* **Consumer Set $C(s_i)$:** All free identifiers referenced in `<expr>` of statement $s_i$ that are bound within the same `where` block.
* **Directed Edge ($s_i \to s_j \in E$):** Exists iff $P(s_i) \cap C(s_j) \neq \emptyset$.

### 3.3 Execution Semantics & Latch Lowering

```ridgun
fn :: process_order Order => Receipt
      process_order ord = final_receipt
        where
          validate_user ord              -> user          -- Stage 0: Starts at T=0
          verify_inventory ord           -> stock         -- Stage 0: Starts at T=0
          compute_taxes ord              -> tax           -- Stage 0: Starts at T=0
          charge_card user tax           -> payment       -- Stage 1: Waits ONLY for (user, tax)
          reserve_warehouse stock        -> shipment      -- Stage 1: Waits ONLY for (stock)
          issue_receipt payment shipment -> final_receipt -- Stage 2: Waits for (payment, shipment)
```

* **Compile-Time Cycle Detection:** If $G$ contains a cycle (or duplicate binding of the same variable name in a single `where` block), compilation fails with `CyclicWhereDependencyError`.
* **Concurrency Relation ($s_a \parallel s_b$):** Two statements $s_a$ and $s_b$ are concurrently active iff $s_a \neq s_b$, there is no directed path $s_a \leadsto s_b$, and there is no directed path $s_b \leadsto s_a$ in $G$.
* **Wait-Free Atomic Latch Lowering:**
  * Every statement $s_j$ with in-degree $\text{deg}^-(s_j) > 0$ is assigned a stack-allocated atomic countdown counter initialized to $\text{deg}^-(s_j)$.
  * All statements with $\text{deg}^-(s_i) = 0$ are scheduled immediately upon entering the `where` block.
  * When statement $s_i$ completes, it iterates over its outgoing edges $s_i \to s_j$ and performs an atomic `fetch_sub(1, AcqRel)` on $s_j$'s counter.
  * The exact worker thread that decrements $s_j$'s counter to `0` immediately transitions to executing $s_j$ (tail-chaining) or pushes $s_j$ to its local work-stealing deque.

---

## 4. Static Mutation Control: Automatic Freeze on Parallel Share

### 4.1 Core Principle
Ridgun supports both **Immutable Types** (`Int`, `Real`, `Bool`, `Char`, `String`, `[a]`, ADTs) and **Mutable Types** (`Tensor`, `Tensor_GPU`, mutable buffers). To guarantee 100% data-race freedom without requiring `&mut` or lifetime syntax, Ridgun enforces **Automatic Freeze on Parallel Share** at compile time.

### 4.2 Interprocedural Mutation Effect Inference
For every function or operator $f$ with $k$ parameters, the compiler computes a static mutation signature:

$$\text{Effect}(f) = [\mu_1, \mu_2, \dots, \mu_k], \quad \text{where } \mu_i \in \{\text{ReadOnly}, \text{Mutates}\}$$

**Bottom-Up Fixpoint Algorithm:**
1. **Initialization:** Set $\mu_i = \text{ReadOnly}$ for all parameters of all functions in the module.
2. **Direct Mutation Scan:** If the AST body of $f$ contains an in-place write targeting parameter $p_i$ (e.g., `p_i[idx] = expr`) or passes $p_i$ to a mutating intrinsic, set $\mu_i = \text{Mutates}$.
3. **Alias Tracking Within Function:** If a local binding `p_i -> alias` is created inside $f$, any mutation of `alias` marks $p_i$ as $\text{Mutates}$.
4. **Call-Graph Propagation:** If $f$ passes parameter $p_i$ as the $j$-th argument to a function/operator $g$ where $\text{Effect}(g)_j = \text{Mutates}$, set $\text{Effect}(f)_i = \text{Mutates}$.
5. **SCC Convergence:** For recursive or mutually recursive function groups, repeat Step 4 over the Strongly Connected Component until no bits flip (terminates in at most $1 + \sum k_m$ iterations).

### 4.3 Parallel Share Verification Matrix
For any mutable variable $v$ referenced inside a `where` or `||` block, let $U(v)$ be the set of statements that reference $v$:

| Usage Pattern of Mutable Variable $v$ | Compile-Time Rule | Runtime Execution Behavior |
|---|---|---|
| **Single Concurrent User:** No two statements in $U(v)$ satisfy $s_a \parallel s_b$ | **Read-Write Permitted.** A statement may invoke functions on $v$ with $\mu = \text{Mutates}$ or $\mu = \text{ReadOnly}$. | Direct pointer passed. Exclusive ownership guaranteed by DAG ordering or single-branch execution. |
| **Shared Across Concurrent Branches ($s_a \parallel s_b$)** AND every $s \in U(v)$ uses $v$ with $\mu = \text{ReadOnly}$ | **Automatic Freeze (Read-Only Permitted).** $v$ is temporarily frozen into an immutable view for the duration of the parallel block. | All parallel branches receive the same raw memory pointer. Zero copies, zero `Mutex`/`RwLock`. |
| **Shared Across Concurrent Branches ($s_a \parallel s_b$)** AND at least one $s \in U(v)$ uses $v$ with $\mu = \text{Mutates}$ | **Compile-Time Error (`ParallelMutationConflictError`).** Compiler highlights both the mutating branch and the concurrent reading/mutating branch. | Compilation aborted before code generation. |

### 4.4 Example

```ridgun
-- Function that mutates its first parameter in-place
fn :: zero_first_element Tensor => Tensor
      zero_first_element t = t
        where
          0.0 -> t[0, 0]

-- Function that only reads its parameter
fn :: trace_2x2 Tensor => Real
      trace_2x2 t = t[0, 0] + t[1, 1]

-- VALID: Shared across 2 parallel branches, but both are ReadOnly (Automatic Freeze)
op :: dual_read Tensor => Real, Real
      dual_read m = a, b
        where
          trace_2x2 m -> a
          trace_2x2 m -> b

-- COMPILE ERROR: 'm' is shared across parallel branches and 'zero_first_element' mutates 'm'
op :: invalid_share Tensor => Tensor, Real
      invalid_share m = m_out, tr
        where
          zero_first_element m -> m_out
          trace_2x2 m          -> tr
```

---

## 5. Structured Concurrency & Typed Channels (Task vs. Process)

### 5.1 Architectural Separation
* **Task Parallelism (`where` and `||`):** Designed for throughput and dataflow efficiency. Sub-computations run in parallel, bind their output, and join at the block boundary.
* **Interactive Process Concurrency (`Channel a`):** Designed for stateful actors, streaming pipelines, and I/O event loops that communicate while concurrently alive.

### 5.2 Structured Channel Primitives
All concurrent processes in Ridgun are spawned within structured `where` or `||` blocks—guaranteeing that no background process outlives its lexical scope undetected—and interact through typed channels:

```ridgun
type Channel a

fn :: new_channel => Channel a
fn :: new_bounded_channel Int => Channel a

op :: send a through Channel a       => ()
op :: receive from Channel a         => a
op :: try receive from Channel a     => Option a
op :: receive from Channel a timeout Int => Result a TimeoutError
```

### 5.3 Affine Move Semantics on Channel Send
When a thread executes `send val through ch`:
1. **If `val` is an Immutable Type (`Int`, `String`, `[a]`, ADT):**
   * The pointer is sent through the channel (or promoted to the channel's shared region if `val` was allocated in a narrower child region).
   * The sender thread may continue reading `val` freely.
2. **If `val` is a Mutable Type (`Tensor`, `Tensor_GPU`):**
   * Sending `val` performs a **Compile-Time Affine Move**.
   * The variable `val` is marked `Moved` in the sender's lexical scope. Any subsequent read or write of `val` in the sender thread produces a `UseAfterChannelSendError` at compile time.
   * The receiving thread acquires sole mutable ownership of `val` upon `receive from ch -> received_val`.
   * **Result:** Arbitrarily large mutable tensors are streamed between pipeline stages by passing an 8-byte pointer with zero copying and zero synchronization overhead.

---

## 6. AST-Driven Execution Tiering (Inline vs. Kernel Worker vs. Green Thread)

### 6.1 The Fixed OS Worker Pool
Spawning an OS thread (`pthread_create`) takes 20–50 $\mu\text{s}$ and allocates megabytes of kernel stack. Ridgun never calls `pthread_create` during user task execution. Instead, at program boot, the runtime spawns exactly $N$ OS worker threads (`pthreads` pinned to physical CPU cores $0 \dots N-1$).

To decide how each branch of a `where` or `||` block executes on those $N$ workers, the compiler runs a static bottom-up **Cost & Suspension Analysis** over the AST.

### 6.2 Static AST Attributes
Every function, operator, and expression node $e$ is annotated with two compile-time attributes:

1. **Yield Capability (`can_yield(e) -> bool`):**
   * `true` iff $e$ contains a blocking channel operation (`receive`, bounded `send`), blocking I/O, explicit timeout/sleep, or a call to a function $g$ with `can_yield(g) == true`.
   * `false` for all pure computation, pattern matching, list manipulation, and tensor operations.
2. **Computational Weight (`cost(e) -> CostTier`):**
   * `CostTier::Trivial`: Estimated $\le 32$ CPU cycles (scalar arithmetic, boolean logic, ADT construction/field access, sequence masking `s(+ _)`).
   * `CostTier::HeavyCPU`: Tensor contractions (`@`), Hadamard broadcasting ops, external C/C++ FFI calls, or statically known large workloads.
   * `CostTier::DynamicRecursive`: Direct or mutual recursion over dynamically sized lists `[a]` or recursive ADTs (`Tree`).

### 6.3 The 4-Tier Code Generation & Dispatch Strategy

| Tier | Condition (`can_yield`, `cost`) | Codegen & Runtime Execution Strategy | Overhead |
|---|---|---|---|
| **Tier 1: Micro-Task** | `can_yield == false` AND `cost == Trivial` | **Sequential Inlining.** Parallel markers are stripped; expressions are emitted as straight-line instructions in the current CPU register frame. | **0 ns** |
| **Tier 2: Kernel Compute Job** | `can_yield == false` AND `cost == HeavyCPU` | **Direct Kernel Worker Dispatch.** Because the task is proven never to suspend, no Green Thread stack or mailbox is created. Dispatched as a raw function pointer + frame pointer directly to an idle OS `pthread`'s native hardware stack. | **~15–40 ns** |
| **Tier 3: Lazy Stealable Task** | `can_yield == false` AND `cost == DynamicRecursive` | **Lazy Work-Stealing (Cilk-style).** The current worker pushes a 24-byte thief descriptor onto its local Chase-Lev deque and immediately calls the first branch on its own native stack. Only if another physical CPU core becomes idle does it steal the remaining branch from the deque tail. | **~2–5 ns** (uncontended) |
| **Tier 4: Concurrent Process** | `can_yield == true` (any `cost`) | **Full Green Thread.** Allocated with a suspendable continuation frame and mailbox pointer so that blocking on `receive` or I/O parks the task in user-space in ~20 ns and immediately switches the `pthread` to another runnable task. | **~25–60 ns** |

---

## 7. Region-Based Memory Management (Lexical Arenas without Tracing GC)

### 7.1 The Lexical Region Invariant
Ridgun eliminates tracing Garbage Collection (zero Stop-the-World latency spikes) and eliminates atomic reference counting (`Arc`) during parallel reads by binding memory lifetimes to **Lexical Function Regions**:

1. **Function-Scoped Bump Arenas:** Every function/operator invocation has a logical local region $R_{\text{local}}$. Allocations inside the function simply bump a pointer (`cursor += align(size)`), executing in 1–2 CPU instructions.
2. **Strict No-Subcall-Destruction Rule:** A callee or parallel child branch is strictly forbidden from freeing or resetting memory in any ancestor region ($R_{\text{parent}}$). Because structured `where`/`||` blocks guarantee all child tasks complete before the parent function exits, every pointer into $R_{\text{parent}}$ is guaranteed to remain valid for the entire lifetime of all child branches—requiring **zero reference counting and zero locks**.
3. **Single-Instruction Bulk Deallocation:** When a function `f` completes, everything allocated in $R_{\text{local}}$ except the return value is discarded simultaneously in $O(1)$ time by resetting `R_local.cursor = frame_watermark`.

### 7.2 Return Value Placement (RVP) & Escape Promotion
How does the return value survive when $R_{\text{local}}$ is destroyed upon function exit? Ridgun uses a two-level strategy:

1. **Static Return Value Placement (Zero-Copy):**
   * Every function receives an implicit hidden parameter: `out_region: *mut Region` pointing to the caller's region $R_{\text{caller}}$.
   * The compiler's AST Escape Analyzer marks any constructor, string interpolation, list cell, or tensor allocated directly in the return position of `f`.
   * Those final return allocations are constructed **directly inside `out_region` ($R_{\text{caller}}$)** rather than $R_{\text{local}}$. When `f` exits, $R_{\text{local}}$ resets in $O(1)$ with zero copying.
2. **Dynamic Subgraph Promotion (Evacuation Copy):**
   * If a function constructs a large temporary recursive structure in $R_{\text{local}}$ (e.g., building a candidate tree and returning only one branch selected dynamically), the return epilogue runs a fast **Deep Region Evacuation** that copies only the live reachable return value into contiguous memory in `out_region` ($R_{\text{caller}}$) immediately before resetting $R_{\text{local}}$.
   * **Cache Locality Bonus:** Evacuating a recursive list or tree into contiguous bytes in $R_{\text{caller}}$ linearizes pointers in memory, dramatically reducing L1/L2 CPU cache misses in subsequent operations.

### 7.3 Parallel Thread-Local Regions in `where` / `||`
When a `where` block dispatches $k$ branches across multiple OS `pthreads`:
* Each OS `pthread` owns a pre-allocated **Worker Bump Arena** ($R_{\text{worker}[t]}$).
* During branch execution, intermediate allocations happen inside $R_{\text{worker}[t]}$ with **zero cross-thread contention and zero atomic operations**.
* The final value bound by `expr -> res_var` is written/promoted into a dedicated sub-slab of the parent's region $R_{\text{parent}}$ reserved for `res_var`.
* As soon as the branch finishes, $R_{\text{worker}[t]}$ rewinds its watermark in $O(1)$.

### 7.4 Tail-Call Region Ping-Pong (Bounded Memory for Infinite Loops)
In functional languages, loops are expressed via tail recursion. If `loop_fn` calls itself $10^9$ times, waiting for the base case to reset $R_{\text{local}}$ would leak memory.
* **Compiler Tail-Call Transformation:** When `f(args)` makes a tail-recursive call `f(next_args)`, the runtime uses two alternating scratch regions ($R_A$ and $R_B$):
  1. Iteration $i$ allocates temporaries in $R_A$.
  2. `next_args` are evaluated and placed/promoted into the clean region $R_B$.
  3. $R_A$ is reset in $O(1)$ (`R_A.cursor = R_A.start`).
  4. Roles swap ($R_A \leftrightarrow R_B$) and execution jumps to the top of `f`.
* **Guarantee:** Any tail-recursive state machine or server loop runs forever in strictly constant $O(1)$ memory.

---

## 8. Controlled Global & Scoped State

Unrestricted mutable globals (`static mut`) break both data-race freedom and lexical region safety (if a local pointer is stored into a global and the local region resets). Ridgun replaces raw mutable globals with three safe constructs:

### 8.1 Immortal Root Constants (`global ::`)
Evaluated once at startup inside the immortal `R_root` region and permanently marked **Read-Only**:

```ridgun
global :: vocabulary_table => [String]
          vocabulary_table = load_vocab 'vocab.txt'
```

### 8.2 Task-Tree Scoped Contexts (`context ::` and `with`)
Provides ergonomic access to configuration, loggers, database handles, or auth tokens without threading parameters through 20 function signatures:

```ridgun
context :: current_config => Conf

fn :: handle_request Request => Response
      handle_request req =
        connect_to (host current_config) (port current_config) req

fn :: main => ()
      main =
        with current_config = (Conf "127.0.0.1" 8080) do
          serve_all
```

* **Memory & Concurrency Semantics:** The context value lives in the region of the enclosing `with` block. Because child branches in `where`/`||` cannot outlive the `with` block and can only read `current_config` (or shadow it locally for their own subtree using a nested `with`), access is lock-free and region-safe.

### 8.3 Transactional / Atomic Shared State (`shared ::`)
For genuine cross-thread mutable state (e.g., global metrics, shared in-memory caches):

```ridgun
shared :: active_sessions => Int
          active_sessions = 0
```

* **Strict Promotion Barrier:** Updating a `shared ::` variable requires an atomic operator or an `atomic` Software Transactional Memory (STM) block. Any composite value stored into a `shared ::` slot is automatically deep-cloned into the global epoch-managed heap, guaranteeing that no pointer into a lexical function region $R_{\text{local}}$ can ever escape into global state.

---

## 9. Deterministic Concurrency & Simulation Mode (`--seed`)

Because Ridgun controls task scheduling and forbids unsynchronized shared memory mutation, the runtime natively supports **Deterministic Simulation Testing (DST)**:

```bash
ridgun test --seed 4294967291 my_program.rg
```

1. **Seeded Virtual Scheduler:** In `--seed` mode, all work-stealing decisions, DAG tie-breakers, and Green Thread wakeups are governed by a deterministic PRNG (`ChaCha8Rng` initialized with the user seed) over a logical clock.
2. **Deterministic Channel Resolution:** When multiple producers send to the same `Channel a`, the order of message delivery is deterministically resolved by the virtual scheduler rather than OS kernel thread races.
3. **Reproducible Bug Replay:** If an overnight fuzzer runs 100,000 random seeds and discovers a subtle protocol bug on `--seed 918273`, any developer can pass `--seed 918273` to reproduce the exact instruction-by-instruction interleaving deterministically.

---

## 10. Native Compilation Strategy (AOT/JIT via Cranelift/LLVM)

Ridgun is architected so that the bytecode VM and a native machine code compiler share the exact same front-end and middle-end analyses:

```
Ridgun Source (.rg)
   │
   ▼
[1. Lexer & Parser]       ──► Surface AST
   │
   ▼
[2. Type & Shape Checker] ──► HM Type Unification, Tensor Shape Unification
   │
   ▼
[3. Static Analyzer]      ──► Mutation Effect(f), Parallel Freeze Check,
   │                          where-DAG Builder, Escape Analysis, AST Tier (1–4)
   ▼
[4. Ridgun MIR]           ──► Explicit Region Alloc/Reset & Tiered Spawn Ops
   │
   ├───────────────────────────────────┐
   ▼                                   ▼
[5a. Bytecode Emitter]        [5b. Native Codegen (Cranelift / LLVM)]
   │                                   │
   ▼                                   ▼
Ridgun VM (.rgc)              Native Binary (ELF/Mach-O/PE) + libridgun_rt.a
```

### 10.1 Why Native Codegen is Ultra-Fast in Ridgun
In languages like Go or Java, native code is slowed down by **Write Barriers** (for the Garbage Collector) and **Stack Guards** on every function prologue. In Ridgun:
* Because memory is managed via lexical regions, there are **zero GC write barriers**.
* Because parallel mutation conflicts are rejected at compile time, there are **zero runtime lock acquisitions** on data access.
* Tier 1, Tier 2, and Tier 3 tasks compile to bare-metal functions that use the hardware stack pointer (`RSP`) directly, achieving C/Rust execution speed.

---

## 11. Compile-Time Tensor Shape & Disjoint Slice Verification

1. **Compile-Time Einstein Shape Unification:**
   Functions may optionally annotate symbolic dimensions on tensors:

   ```ridgun
   fn :: linear_layer Tensor(b, i) Tensor(o, i) Tensor(o) => Tensor(b, o)
         linear_layer x weight bias = out
           where
             (x_bi @ weight_oi) -> prod
             (prod_bo + bias_o) -> out
   ```

   The typechecker unifies index labels (`b`, `i`, `o`) across `@` and broadcasting operators, catching dimension errors at compile time.

2. **Disjoint Parallel Slice Mutation:**
   When a mutable `Tensor` is indexed by disjoint first-dimension slices across parallel branches of a `where` block:

   ```ridgun
   op :: update_halves Tensor => Tensor
         update_halves m = m
           where
             compute_row_zero m[0] -> m[0]
             compute_row_one  m[1] -> m[1]
   ```

   If the compiler proves index sets $I_1 \cap I_2 = \emptyset$ (e.g., distinct constant indices `[0]` vs. `[1]`, or non-overlapping ranges `0..k` vs. `k..n`), it treats `m[0]` and `m[1]` as disjoint sub-resources and permits parallel in-place mutation without copying.

---

## 12. Systems & Bare-Metal OS Profile (Ridgun as a SASOS Kernel)

Because Ridgun guarantees memory isolation (via Lexical Regions) and concurrency safety (via Static Freeze & Affine Channels) **at compile time**, Ridgun can be used to build a **Single-Address-Space Operating System (SASOS)** where kernel services, device drivers, and user applications execute in a single address space without costly hardware page-table switches (CR3 flushes / Ring 3 $\leftrightarrow$ Ring 0 syscall traps).

To target bare-metal hardware (`ridgun compile --target x86_64-unknown-none --freestanding`), Ridgun includes four systems extensions:

### 12.1 Fixed-Width Primitives & Hardware Layout (`@repr(C)`, `@packed`)
```ridgun
-- Exact-width primitives: U8, U16, U32, U64, Usize, I8, I16, I32, I64
@packed
type IdtEntry = offset_low U16, selector U16, ist U8, flags U8, offset_mid U16, offset_high U32, reserved U32
```

### 12.2 Quota-Bounded Regions (Kernel OOM Immunity)
An OS kernel must never crash when a driver or user process allocates excessive memory. Ridgun supports **Quota-Bounded Regions**:

```ridgun
op :: execute_untrustedApp Payload with region limit 16_MB => Result AppOutput KernelError
```

If the region cursor reaches `start + 16_MB`, the allocation trap unwinds the task immediately, resets the 16 MB region in $O(1)$ time, and returns `Err OutOfMemory` to the kernel caller without affecting any other running process.

### 12.3 Hardware Interrupts (IRQs) as Lock-Free Channels
A minimal (~1,500 LOC) Rust/ASM `no_std` nanokernel initializes the CPU, APIC/GIC, and physical page allocator, and maps hardware interrupts directly into lock-free ring-buffer `Channel` instances:

```ridgun
fn :: nvme_driver (Channel NvmeIrq) => ()
      nvme_driver irq_ch =
        process_completion_queue event
        where
          receive from irq_ch -> event
```

Device drivers become standard, type-safe, region-isolated Ridgun functions.

### 12.4 Audited `hardware ::` Blocks
Operations that inherently bypass compiler guarantees (MMIO volatile register reads/writes, port I/O `inb`/`outb`, inline assembly) are isolated inside explicit `hardware ::` declarations permitted only in ring-0 bootstrap modules.

---

## 13. Compiler Data Structures & Implementation Roadmap

### 13.1 Core Rust Data Structures (`src/main/rust/`)

```rust
/// Static analysis metadata attached to every Function/Operator definition in the AST
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FnStaticSummary {
    /// Per-parameter mutation behavior inferred bottom-up
    pub param_effects: Vec<ParamEffect>,
    /// True if this function or any transitive callee can block/yield (Channel Recv, I/O)
    pub can_yield: bool,
    /// Estimated execution weight for AST tiering
    pub cost_tier: CostTier,
    /// True if return value is freshly constructed and eligible for Return Value Placement
    pub supports_rvp: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParamEffect {
    ReadOnly,
    Mutates,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum CostTier {
    Trivial,          // Tier 1: Inline sequentially
    HeavyCPU,         // Tier 2: Direct OS pthread dispatch (no green thread stack)
    DynamicRecursive, // Tier 3: Lazy work-stealing deque entry
}

/// Execution strategy selected by the compiler for each statement in a `where` or `||` block
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BranchExecStrategy {
    InlineSequential,
    KernelWorkerJob,
    LazyStealableTask,
    FullGreenThread,
}

/// Runtime Lexical Region (Bump Arena)
#[repr(C)]
pub struct Region {
    pub start: *mut u8,
    pub cursor: *mut u8,
    pub limit: *mut u8, // Enforces Quota-Bounded Regions in OS mode
    pub parent: *mut Region,
}
```

### 13.2 Phased Implementation Roadmap

1. **Milestone 1 — Spec Harmonization & Static Freeze Pass (`typechecker.rs`):**
   * Unify type casing (`Int`, `Real`, `Bool`, `String`, `Tensor`).
   * Implement `FnStaticSummary` bottom-up fixpoint inference (`ReadOnly` vs. `Mutates`).
   * Reject concurrent mutations in `where` and `||` blocks with `ParallelMutationConflictError`, while allowing zero-copy concurrent reads (`Automatic Freeze`).
2. **Milestone 2 — `where` Block DAG Compiler & Affine Channels (`compiler.rs`, `vm.rs`):**
   * Build the producer-consumer dependency graph $G = (V, E)$ for `where` blocks.
   * Emit atomic countdown latches for multi-stage DAG execution.
   * Implement `Channel a` with compile-time Affine Move checking for mutable types (`UseAfterChannelSendError`).
3. **Milestone 3 — AST Execution Tiering & Deterministic `--seed` (`analyzer.rs`, `scheduler.rs`):**
   * Compute `can_yield` and `CostTier` on all AST nodes.
   * Route Tier 1 to sequential instructions, Tier 2/3 to `pthread` worker queues, and Tier 4 to suspendable Green Threads.
   * Add `--seed <u64>` flag to `ridgun test` and `ridgun run` for deterministic simulation scheduling.
4. **Milestone 4 — Lexical Region Memory Engine (`memory.rs`, `vm.rs`):**
   * Replace general heap allocation of lists, strings, and ADTs with `Region` bump allocation.
   * Implement Return Value Placement (`out_region`), deep evacuation copy for dynamic subgraphs, and ping-pong tail-call regions.
5. **Milestone 5 — Native Cranelift Backend & Bare-Metal OS Profile (`codegen_cranelift.rs`, `runtime/`):**
   * Lower Ridgun MIR to Cranelift IR linked against `libridgun_rt.a`.
   * Add fixed-width integer types (`U8`–`U64`), `@packed` layout attributes, Quota-Bounded Regions, and `hardware ::` blocks for bare-metal kernel compilation.

