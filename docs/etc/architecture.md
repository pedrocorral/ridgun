# Ridgun VM Architecture

## Overview

Ridgun uses a **bytecode-compiled, VM-executed** architecture. Source code is parsed into an AST, compiled to a compact bytecode format, and executed by a custom virtual machine with a built-in parallel scheduler.

This design provides the best trade-off for a parallelism-first language:
- The VM **owns the scheduler**, enabling fine-grained control over green threads, preemption, and work distribution.
- Bytecode compilation is **fast to iterate on** during language design, unlike targeting native machine code.
- **AOT (ahead-of-time) native compilation** via LLVM can be added later once the language stabilizes, without changing any user-facing semantics.

## Compilation Pipeline

```
                    ┌─────────────────────────────────┐
                    │          Ridgun Source           │
                    │            (.rg files)           │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │       1. LEXER                   │
                    │  Source text → Token stream      │
                    │  (keywords, identifiers,         │
                    │   literals, operators)            │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │       2. PARSER                  │
                    │  Token stream → AST              │
                    │  (recursive descent or PEG)      │
                    │  Produces typed syntax tree      │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │    3. SEMANTIC ANALYSIS          │
                    │  Type checking, scope resolution │
                    │  Parallelism constraint checks   │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │    4. BYTECODE COMPILER          │
                    │  AST → Ridgun bytecode           │
                    │  Optimization passes             │
                    │  Output: .rgc files              │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │       5. RIDGUN VM               │
                    │  Bytecode loader                 │
                    │  Stack machine execution         │
                    │  Parallel scheduler              │
                    │  FFI + Python bridge              │
                    └─────────────────────────────────┘
```

## Bytecode Format

Ridgun bytecode (`.rgc` files) is a compact binary format containing:

| Section | Contents |
|---|---|
| **Header** | Magic bytes, version, checksum |
| **Constant pool** | String literals, numeric constants, function metadata |
| **Code segments** | Instruction sequences per function/closure |
| **Debug info** | Source maps for error reporting (optional, strippable) |

### Instruction Set Categories

The instruction set is organized around six categories:

#### Stack Operations
Basic stack machine operations for value manipulation.
- `PUSH`, `POP`, `DUP`, `SWAP`
- `LOAD_LOCAL`, `STORE_LOCAL`, `LOAD_GLOBAL`, `STORE_GLOBAL`
- `LOAD_CONST` (from constant pool)

#### Arithmetic & Logic
Standard computation instructions.
- `ADD`, `SUB`, `MUL`, `DIV`, `MOD`
- `AND`, `OR`, `NOT`, `XOR`
- `EQ`, `NEQ`, `LT`, `GT`, `LTE`, `GTE`

#### Control Flow
Branching and function calls.
- `JUMP`, `JUMP_IF`, `JUMP_IF_NOT`
- `CALL`, `RETURN`
- `MATCH` (pattern matching dispatch)

#### Parallelism
First-class concurrency primitives — this is where Ridgun's identity lives.
- `SPAWN` — create a new green thread from a closure
- `SEND` — send a message to a green thread's mailbox
- `RECV` — receive a message (blocks the green thread, not the OS thread)
- `YIELD` — voluntary preemption point
- `CHAN_NEW`, `CHAN_SEND`, `CHAN_RECV` — typed channel operations
- `AWAIT` — wait for a green thread to complete and collect its result
- `PAR_MAP` — parallel map over a collection (high-level batch primitive)

#### Memory & Data
Heap allocation and structured data.
- `ALLOC`, `FREE` (managed by GC, not user-exposed)
- `LIST_NEW`, `LIST_PUSH`, `LIST_GET`
- `MAP_NEW`, `MAP_SET`, `MAP_GET`
- `STRUCT_NEW`, `STRUCT_GET`, `STRUCT_SET`

#### Interop
Foreign function and Python bridge calls.
- `FFI_CALL` — call a C/C++ function via FFI
- `PY_CALL` — call a Python function via the embedded CPython bridge
- `PY_IMPORT` — import a Python module

## VM Components

### Stack Machine

The Ridgun VM is a **register-free stack machine**. Each green thread has its own stack. This simplifies the implementation and makes context switching between green threads cheap — the scheduler just switches which stack is active.

```
Green Thread A          Green Thread B          Green Thread C
┌────────────┐         ┌────────────┐         ┌────────────┐
│   Stack    │         │   Stack    │         │   Stack    │
│  ┌──────┐  │         │  ┌──────┐  │         │  ┌──────┐  │
│  │ 42   │  │         │  │"hello│  │         │  │ true │  │
│  │ 3.14 │  │         │  │ 100  │  │         │  │ 0    │  │
│  └──────┘  │         │  └──────┘  │         │  └──────┘  │
│    PC: 47  │         │    PC: 12  │         │    PC: 89  │
│ Status: RUN│         │ Status:WAIT│         │ Status: RUN│
└────────────┘         └────────────┘         └────────────┘
```

### Scheduler

See [parallelism.md](parallelism.md) for the full scheduler design. In summary:

- **M:N model**: many green threads mapped to a pool of OS threads.
- **Work-stealing**: idle OS threads steal runnable green threads from busy threads' queues.
- **Preemption**: reduction counting ensures no single green thread monopolizes a worker.

### Heap & Garbage Collection

- Each green thread has a **thread-local heap** for short-lived allocations.
- A **shared heap** exists for data that crosses thread boundaries (message payloads).
- GC strategy: **generational, per-thread** for local heaps; **concurrent mark-and-sweep** for the shared heap.
- The GC never stops all green threads simultaneously (no global stop-the-world).

### Bytecode Loader

The loader reads `.rgc` files, validates the header and checksum, deserializes the constant pool and code segments, and registers them with the VM's function table. Dynamic loading is supported for hot-reloading during development.

## Rust Implementation

The VM is implemented in Rust. Key crates and design decisions:

| Component | Approach |
|---|---|
| Bytecode execution | Hand-written dispatch loop (computed goto via `match`) |
| Green thread stacks | `Vec<Value>` per thread, pre-allocated pool |
| Scheduler | Crossbeam for work-stealing deques |
| FFI | `libffi` crate or direct `extern "C"` bindings |
| Python bridge | PyO3 for embedding CPython |
| GC | Custom implementation; per-thread nurseries |

### Why Rust?

1. **Memory safety without GC** — The VM manages its own GC for Ridgun values; Rust guarantees the VM code itself is memory-safe.
2. **Fearless concurrency** — Rust's ownership model prevents data races in the scheduler and cross-thread communication.
3. **Performance** — Zero-cost abstractions and no runtime overhead. The VM's hot loop compiles to tight machine code.
4. **Ecosystem** — PyO3, crossbeam, and the LLVM bindings crate are production-grade.

## Future: AOT Native Compilation

Once the language stabilizes, an AOT compiler can target **LLVM IR**, producing native binaries. The runtime (scheduler, GC, FFI) would be linked as a static library. This is the same path taken by:
- Erlang (HiPE)
- Dart (AOT mode)
- GraalVM (native-image)

The bytecode VM remains the primary development target; AOT is an optimization for production deployment.
