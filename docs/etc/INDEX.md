# docs/etc/ — Architecture, VM, parallelism, and roadmap

| Path | What | Read when |
|---|---|---|
| `architecture.md` | Bytecode VM architecture and `.rgc` format | Working on bytecode compiler, loader, or VM |
| `compiler_optimizations.md` | Compiler Optimization Catalog (`OPT-001`..`OPT-006`) for AST, RMM1/RMM2, `Tensor`, and SHA-256 codegen (`FR-COMP-011`) | Implementing, reviewing, or documenting compiler optimization passes in `compiler.rg` and `x86_64.rg` |
| `cmm_architecture.md` | Compiled Memory Management (CMM) & Conditional CMM (`ptr(a) != ptr(c)`) (`FR-COMP-002`) | Working on compile-time memory management, liveness, or alias-guarded drops |
| `low_level_ridgun_runtime_design.md` | Portable low-level Ridgun runtime kernel design vs symbolic assembly (`TASK-0013`) | Evaluating or implementing freestanding/unboxed Ridgun runtime primitives |
| `next_gen_architecture.md` | Approved v2.0 architectural blueprint (DAGs, Freeze, Regions, Tiering, `--seed`) | Implementing v2.0 VM, memory, or static analysis |
| `parallelism.md` | Green threads, work-stealing scheduler, mailboxes, channels | Working on scheduler, threads, or concurrency |
| `interop.md` | C/C++ FFI and Python bridge specification | Working on FFI or PyO3 interop |
| `process.md` | Spiral + V-Model + OWASP SAMM methodology | Planning verification and security gates |
| `roadmap.md` | High-level development phases and milestones | Reviewing phase ordering |
