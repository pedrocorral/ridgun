# Ridgun Development Roadmap

## Phase 1 — Language Frontend

**Goal:** Parse Ridgun source into a well-typed AST.

| Milestone | Description |
|---|---|
| Lexer | Tokenize `.rg` source files (keywords, identifiers, literals, operators) |
| Parser | Recursive descent (or PEG) parser producing an AST |
| Semantic analysis | Type checking, scope resolution, parallelism constraint validation |
| Error reporting | Clear, human-readable compiler errors with source location |
| Test suite | Unit tests for lexer, parser, and semantic analyzer |

**Output:** Given a `.rg` file, produce a validated AST in memory.

---

## Phase 2 — Bytecode Compiler

**Goal:** Compile the AST into Ridgun bytecode.

| Milestone | Description |
|---|---|
| Instruction set | Define all opcodes (stack, arithmetic, control flow, parallelism, interop) |
| Code generation | AST → bytecode emission |
| Constant pool | String/number literal interning and serialization |
| `.rgc` format | Binary file format: header, constants, code segments, debug info |
| Optimization passes | Constant folding, dead code elimination, basic peephole optimizations |
| Test suite | Round-trip tests: source → bytecode → disassembly verification |

**Output:** Given an AST, produce a `.rgc` bytecode file.

---

## Phase 3 — VM Core

**Goal:** Execute bytecodes with full parallel scheduling.

| Milestone | Description |
|---|---|
| Bytecode loader | Read and validate `.rgc` files, populate function tables |
| Stack machine | Execution loop: fetch, decode, dispatch instructions |
| Green threads | Lightweight thread creation (`SPAWN`), per-thread stacks |
| Scheduler | M:N work-stealing scheduler with preemption (reduction counting) |
| Message passing | Mailboxes (`SEND`/`RECV`) and typed channels (`CHAN_*`) |
| Garbage collector | Per-thread generational GC, concurrent shared-heap GC |
| Test suite | Concurrency stress tests, scheduler fairness tests |

**Output:** A working VM that can run compiled Ridgun programs with parallel execution.

---

## Phase 4 — Interop

**Goal:** Enable Ridgun to call external C/C++ and Python libraries.

| Milestone | Description |
|---|---|
| FFI layer | Call C functions via `libffi`, type marshalling, blocking call dispatch |
| Python bridge | Embed CPython via PyO3, `PY_CALL`/`PY_IMPORT` opcodes |
| GIL isolation | Python calls yield green threads, dedicated Python worker thread |
| Type conversion | Bidirectional marshalling between Ridgun, C, and Python types |
| Test suite | FFI tests with real libraries (SQLite, libcurl), Python bridge tests |

**Output:** Ridgun programs can call LibTorch, pandas, OpenCV, etc.

---

## Phase 5 — Standard Library

**Goal:** Provide essential built-in modules.

| Module | Description |
|---|---|
| `io` | File I/O, stdin/stdout, async file operations |
| `net` | TCP/UDP sockets, HTTP client (via FFI to libcurl or native) |
| `json` | JSON parsing and serialization |
| `math` | Mathematical functions and constants |
| `collections` | Advanced data structures (sorted maps, sets, queues) |
| `parallel` | High-level parallel patterns: `par_map`, `par_filter`, `par_reduce` |
| `time` | Clocks, timers, sleep, timeouts |
| `fmt` | String formatting and output |

---

## Phase 6 — Developer Tools

**Goal:** Make Ridgun pleasant to use.

| Tool | Description |
|---|---|
| REPL | Interactive Ridgun shell for experimentation |
| Package manager | Dependency resolution and package registry |
| Formatter | Opinionated code formatter (like `gofmt` / `rustfmt`) |
| LSP server | Language Server Protocol for editor integration |
| Debugger | Step-through debugging with green thread inspection |
| Profiler | Per-thread CPU and memory profiling |

---

## Phase 7 — AOT Native Compilation (Future)

**Goal:** Compile Ridgun directly to native binaries for production deployment.

| Milestone | Description |
|---|---|
| LLVM backend | AST/bytecode → LLVM IR → native machine code |
| Runtime library | Scheduler, GC, FFI as a static library linked into native binaries |
| Cross-compilation | Target multiple architectures (x86_64, aarch64) |

This phase is **deferred** until the language design stabilizes. The bytecode VM remains the primary execution target.

---

## Priority Order

```
Phase 1 ──▶ Phase 2 ──▶ Phase 3 ──▶ Phase 4 ──▶ Phase 5
  │            │            │            │           │
  │            │            │            │           ▼
  │            │            │            │        Phase 6
  │            │            │            │
  │            │            │            │        Phase 7
  │            │            │            │       (future)
  ▼            ▼            ▼            ▼
 Lexer      Bytecode      VM +       FFI +      Stdlib +
 Parser     Compiler      Scheduler  Python     Tooling
```

Each phase produces a testable, self-contained deliverable. Phases are sequential — each depends on the output of the previous one.
