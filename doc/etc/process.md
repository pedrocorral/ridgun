# Ridgun Development Process

Ridgun follows a combined **Spiral + V-Model + OWASP SAMM** development methodology. This document defines how the three frameworks integrate to drive what gets built, how it's verified, and how security is assured.

## Framework Roles

| Framework | Role |
|---|---|
| **Spiral Model** | Drives iteration cadence: what to build, when, and how risk is managed |
| **V-Model** | Drives verification: each design layer has a corresponding test layer |
| **OWASP SAMM** | Drives security assurance as a cross-cutting concern across all spirals |

```
                ┌─────────────────────────────────┐
                │         Spiral Model            │
                │  Plan → Risk → Build → Evaluate │
                │         ╱           ╲            │
                │        ╱             ╲           │
                │  ┌──────────┐  ┌────────────┐   │
                │  │ V-Model  │  │ OWASP SAMM │   │
                │  │ (verify) │  │ (security) │   │
                │  └──────────┘  └────────────┘   │
                └─────────────────────────────────┘
```

---

## Spiral Model — Iteration Plan

Each spiral is a full cycle of **Planning → Risk Analysis → Engineering → Evaluation**. Each spiral produces a testable, working deliverable. Lessons from evaluation feed the next spiral's planning phase.

### Spiral 1 — Core Language

| Phase | Activities |
|---|---|
| **Plan** | Define syntax for variables, types, functions, control flow |
| **Risk** | Parser ambiguities, type system complexity, syntax dead-ends |
| **Build** | Lexer, parser, AST, basic bytecode compiler, minimal stack-machine VM |
| **Evaluate** | Can simple programs (arithmetic, functions, conditionals) compile and run? |

**Deliverable:** `ridgun` compiles and runs basic sequential `.rg` programs.

### Spiral 2 — Parallelism

| Phase | Activities |
|---|---|
| **Plan** | Define spawn, send, recv, channel syntax; scheduler requirements |
| **Risk** | Deadlocks, starvation, scheduler fairness, preemption edge cases |
| **Build** | Green threads, M:N scheduler, mailboxes, channels, reduction counting |
| **Evaluate** | Can programs spawn thousands of threads, exchange messages, and complete? |

**Deliverable:** Parallel programs with message passing work correctly under load.

### Spiral 3 — Interop

| Phase | Activities |
|---|---|
| **Plan** | FFI calling convention, Python bridge API, type marshalling rules |
| **Risk** | GIL contention, memory leaks across FFI boundary, unsafe pointer handling |
| **Build** | FFI layer (libffi/extern C), Python bridge (PyO3), GIL isolation |
| **Evaluate** | Can Ridgun call LibTorch, pandas, SQLite and return correct results? |

**Deliverable:** Ridgun programs call C/C++ and Python libraries.

### Spiral 4 — Standard Library & Tooling

| Phase | Activities |
|---|---|
| **Plan** | Module system, package format, REPL requirements |
| **Risk** | API design lock-in, backward compatibility |
| **Build** | Core modules (io, net, json, parallel), REPL, formatter |
| **Evaluate** | Can real-world programs be written using only the standard library? |

**Deliverable:** Self-sufficient language with tooling for daily use.

### Spiral 5+ — Hardening & AOT (Future)

Further spirals address: AOT compilation via LLVM, cross-compilation, performance profiling, ecosystem growth.

---

## V-Model — Verification Matrix

Each design layer (left side) maps to a validation layer (right side). Tests live in `tst/` mirroring this structure.

```
    DESIGN (descending)                    VALIDATION (ascending)
    ─────────────────                      ─────────────────────

    Requirements Spec          ◄─────►     Acceptance Tests
         │                                       ▲
         ▼                                       │
    Language Design            ◄─────►     Integration Tests
         │                                       ▲
         ▼                                       │
    VM Architecture            ◄─────►     System Tests
         │                                       ▲
         ▼                                       │
    Implementation             ◄─────►     Unit Tests
```

### Test Categories and `tst/` Layout

```
tst/
├── unit/                 # V-Model: Implementation level
│   ├── lexer/            # Token output for known inputs
│   ├── parser/           # AST output for known syntax
│   ├── compiler/         # Bytecode output for known ASTs
│   ├── vm/               # Opcode execution correctness
│   └── gc/               # Garbage collector invariants
│
├── system/               # V-Model: VM Architecture level
│   ├── scheduler/        # Work-stealing fairness, preemption
│   ├── concurrency/      # Deadlock detection, starvation
│   └── memory/           # Heap limits, GC under pressure
│
├── integration/          # V-Model: Language Design level
│   ├── ffi/              # FFI calls to real C libraries
│   ├── python/           # Python bridge with real packages
│   └── interop_parallel/ # FFI + Python under parallel load
│
├── acceptance/           # V-Model: Requirements level
│   ├── programs/         # Full Ridgun programs that must compile + run
│   ├── benchmarks/       # Performance baselines
│   └── regression/       # Previously fixed bugs
│
└── security/             # OWASP SAMM: Security Testing
    ├── fuzzing/          # Fuzz lexer, parser, bytecode loader
    ├── sandbox/          # VM escape attempts
    └── interop_safety/   # Malicious FFI/Python inputs
```

### V-Model Traceability

Every test case links back to a design requirement:

| Design Layer | Question Answered | Test Location |
|---|---|---|
| Requirements | "Does the language solve the intended problems?" | `tst/acceptance/` |
| Language Design | "Do components work together correctly?" | `tst/integration/` |
| VM Architecture | "Does the VM behave correctly under stress?" | `tst/system/` |
| Implementation | "Does each unit produce correct output?" | `tst/unit/` |

---

## OWASP SAMM — Security Practices

OWASP SAMM is applied as a cross-cutting concern across all spirals. The practices below are adapted for a **language runtime** rather than a web application.

### Governance

| Practice | Application |
|---|---|
| **Strategy & Metrics** | Define security goals: memory safety, isolation guarantees, zero VM escapes |
| **Policy & Compliance** | Document what Ridgun guarantees (and doesn't) about safety |
| **Education & Guidance** | Security guidelines for contributors touching VM, FFI, or GC code |

### Design

| Practice | Application |
|---|---|
| **Threat Assessment** | Model threats: malicious `.rg` code, crafted bytecode, FFI abuse, Python injection |
| **Security Requirements** | Green thread isolation, no shared mutable state, bounds-checked stack access |
| **Security Architecture** | Rust's ownership for VM internals, sandboxed FFI, GIL-isolated Python bridge |

### Implementation

| Practice | Application |
|---|---|
| **Secure Build** | Reproducible builds, dependency pinning (`Cargo.lock`), SBOM generation |
| **Secure Coding** | No `unsafe` Rust except in reviewed, audited FFI boundary code |
| **Dependency Management** | Audit crates (PyO3, crossbeam, libffi) for known vulnerabilities |

### Verification

| Practice | Application |
|---|---|
| **Architecture Assessment** | Review scheduler and GC designs for race conditions |
| **Security Testing** | Fuzz parser + bytecode loader (`tst/security/fuzzing/`), VM escape tests |
| **Requirements-driven Testing** | Verify isolation guarantees hold under adversarial workloads |

### Operations

| Practice | Application |
|---|---|
| **Vulnerability Management** | CVE monitoring for Rust crates, CPython, linked C libraries |
| **Incident Management** | Process for handling reported VM vulnerabilities |
| **Environment Hardening** | Recommended deployment: seccomp profiles, capability dropping for Ridgun processes |

### SAMM Maturity Progression

Security maturity grows with each spiral:

| Spiral | SAMM Focus |
|---|---|
| **Spiral 1** (Core) | Secure coding in Rust, basic threat model, fuzz the parser |
| **Spiral 2** (Parallelism) | Verify thread isolation, audit scheduler for races, stress test GC |
| **Spiral 3** (Interop) | FFI boundary review, Python bridge sandboxing, `unsafe` audit |
| **Spiral 4** (Stdlib) | Dependency audit, SBOM, secure defaults in I/O and network modules |

---

## Code Review vs Secure Code Review

Code review and secure code review are different in essence but serve complementary purposes in the SDLC. Both are **mandatory gates** in the Ridgun development process, applied at different stages and with different objectives.

### Code Review

The primary objective is to identify bugs, enhance code quality, and ensure alignment with coding standards.

| Focus Area | What to Check |
|---|---|
| **Correctness** | Does the code produce the right output? Are edge cases handled? |
| **Efficiency** | Are there unnecessary allocations, redundant computations, or O(n²) traps? |
| **Readability** | Is the code self-documenting? Are names meaningful? Is complexity justified? |
| **Maintainability** | Can this be modified without ripple effects? Is it properly modular? |
| **Consistency** | Does it follow established patterns in the codebase? |

Applied to Ridgun components:

| Component | Code Review Focus |
|---|---|
| Lexer / Parser | Correct tokenization, complete grammar coverage, meaningful error messages |
| Bytecode compiler | Correct opcode emission, constant pool integrity, optimization correctness |
| VM execution loop | Instruction dispatch correctness, stack invariants, GC trigger points |
| Scheduler | Fairness properties, queue invariant maintenance, preemption correctness |
| Standard library | API ergonomics, documentation completeness, consistent error handling |

Code reviews can be performed **manually by developers** or **automated** via linting tools (Clippy for Rust, custom Ridgun lints for `.rg` code).

### Secure Code Review

The objective is to identify and mitigate **security vulnerabilities** within the codebase. This requires a deeper understanding of security principles and threat models.

| Focus Area | What to Check |
|---|---|
| **Memory safety** | Buffer overflows, use-after-free, double-free (especially in `unsafe` Rust blocks) |
| **Injection** | Can user input reach FFI calls or Python `eval` unsanitized? |
| **Isolation** | Can a green thread access another thread's stack or heap? |
| **Authentication / Authorization** | Does the FFI layer validate library paths? Can arbitrary `.so` files be loaded? |
| **Data handling** | Are secrets (API keys) in Ridgun programs protected from cross-thread leakage? |
| **Concurrency** | TOCTOU races, atomicity violations, lock ordering in scheduler internals |

Applied to Ridgun components:

| Component | Secure Code Review Focus |
|---|---|
| VM stack machine | Stack bounds checking, heap boundary enforcement, no out-of-bounds reads |
| FFI layer | Pointer validation, buffer length verification, no unchecked `unsafe` casts |
| Python bridge | GIL state integrity, no Python code injection via string interpolation |
| Bytecode loader | Malformed `.rgc` rejection, checksum verification, no arbitrary code execution |
| GC | No dangling references after collection, shared heap concurrent access safety |
| Scheduler | No thread ID spoofing, mailbox access control, no cross-thread stack access |

Secure code reviews leverage both **manual inspection** and **automated SAST tools** (e.g., `cargo audit`, `cargo clippy` with security lints, custom fuzzers in `tst/security/`).

### When Each Applies

```
Feature Branch
     │
     ▼
 Code Review          ← Every PR: quality, correctness, readability
     │
     │ (passes)
     ▼
 Secure Code Review   ← PRs touching: VM, FFI, Python bridge, GC,
     │                   bytecode loader, scheduler, unsafe blocks
     │ (passes)
     ▼
 Merge to main
```

**Code Review** is required for **every** change. **Secure Code Review** is required for changes touching security-sensitive components (VM internals, FFI boundary, Python bridge, GC, bytecode loader) or any code containing `unsafe` blocks. Both must pass before merge.

---

## Combined Process per Spiral

Each spiral follows this sequence:

```
 1. PLAN
    ├── Define features for this spiral
    ├── Update threat model (SAMM: Threat Assessment)
    └── Define V-Model test requirements for each layer

 2. RISK ANALYSIS
    ├── Identify technical risks (Spiral: Risk)
    ├── Identify security risks (SAMM: Security Requirements)
    └── Prioritize: mitigate highest risks first

 3. BUILD
    ├── Implement features
    ├── Write unit + system tests (V-Model: bottom-up)
    ├── Apply secure coding practices (SAMM: Secure Coding)
    ├── Code Review: quality, correctness, readability
    ├── Secure Code Review: vulnerabilities in VM/FFI/GC/scheduler
    └── Audit dependencies (SAMM: Dependency Management)

 4. EVALUATE
    ├── Run full test suite (V-Model: all layers)
    ├── Run security tests (SAMM: Security Testing)
    ├── Performance benchmarks
    └── Retrospective: feed lessons into next spiral's Plan
```
